// Cloudflare Worker entry point: status API for the app and the admin bot webhook.
import { handleCommand, importSigningKey, normalizeDeviceCode, signedFlags, signedStatus } from "./core.js";

// Workers KV: "dev:<device code>" -> subscription record, "flags:disabled" -> comma list.
// Reads are cheap; writes happen only from admin bot commands.
function kvStorage(kv) {
  const subKey = (device) => `dev:${device}`;
  async function allRecords() {
    const records = [];
    let cursor;
    do {
      const page = await kv.list({ prefix: "dev:", cursor });
      for (const { name } of page.keys) {
        const record = await kv.get(name, "json");
        if (record) records.push(record);
      }
      cursor = page.list_complete ? undefined : page.cursor;
    } while (cursor);
    return records;
  }
  const isActive = (r, now) => r.expiresAt === -1 || r.expiresAt > now;
  return {
    async get(device) {
      return await kv.get(subKey(device), "json");
    },
    async put(record) {
      await kv.put(subKey(record.device), JSON.stringify(record));
    },
    async remove(device) {
      await kv.delete(subKey(device));
    },
    async listActive(now, limit) {
      return (await allRecords())
        .filter((r) => isActive(r, now))
        .sort((a, b) => b.updatedAt - a.updatedAt)
        .slice(0, limit);
    },
    async getDisabledFeatures() {
      const value = await kv.get("flags:disabled");
      return value ? value.split(",").filter(Boolean) : [];
    },
    async setDisabledFeatures(list) {
      await kv.put("flags:disabled", list.join(","));
    },
    async counts(now) {
      const all = await allRecords();
      return {
        total: all.length,
        active: all.filter((r) => isActive(r, now)).length,
        forever: all.filter((r) => r.expiresAt === -1).length,
      };
    },
  };
}

function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json", "cache-control": "no-store" },
  });
}

async function sendMessage(token, chatId, text) {
  await fetch(`https://api.telegram.org/bot${token}/sendMessage`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ chat_id: chatId, text, disable_web_page_preview: true }),
  });
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const now = Math.floor(Date.now() / 1000);
    const storage = kvStorage(env.SUBS);

    if (request.method === "GET" && url.pathname === "/v1/status") {
      const device = normalizeDeviceCode(url.searchParams.get("device"));
      if (!device) return json({ error: "bad device" }, 400);
      const record = await storage.get(device);
      const key = await importSigningKey(env.SIGNING_KEY);
      return json(await signedStatus(key, { device, expiresAt: record?.expiresAt ?? 0, now }));
    }

    if (request.method === "GET" && url.pathname === "/v1/flags") {
      const key = await importSigningKey(env.SIGNING_KEY);
      return json(await signedFlags(key, { disabled: await storage.getDisabledFeatures(), now }));
    }

    if (request.method === "POST" && url.pathname === `/bot/${env.WEBHOOK_SECRET}`) {
      // Telegram also sends the secret in this header when the webhook is set with secret_token.
      if (request.headers.get("x-telegram-bot-api-secret-token") !== env.WEBHOOK_SECRET) {
        return new Response("forbidden", { status: 403 });
      }
      const update = await request.json();
      const message = update.message;
      if (message?.chat?.type === "private") {
        const adminIds = String(env.ADMIN_IDS || "").split(",").map((s) => Number(s.trim())).filter(Boolean);
        const outgoing = await handleCommand(storage, { message, adminIds, now });
        for (const { chatId, text } of outgoing) {
          await sendMessage(env.BOT_TOKEN, chatId, text);
        }
      }
      return new Response("ok");
    }

    if (url.pathname === "/") return new Response("HolyGram Pro");
    return new Response("not found", { status: 404 });
  },
};
