// Cloudflare Worker entry point: status API for the app and the admin bot webhook.
import { handleCommand, importSigningKey, signedFlags, signedStatus } from "./core.js";

function d1Storage(db) {
  const row = (r) => r && { userId: r.user_id, expiresAt: r.expires_at, note: r.note, grantedBy: r.granted_by, updatedAt: r.updated_at };
  return {
    async get(userId) {
      return row(await db.prepare("SELECT * FROM subscriptions WHERE user_id = ?").bind(userId).first());
    },
    async put(r) {
      await db.prepare(
        "INSERT INTO subscriptions (user_id, expires_at, note, granted_by, updated_at) VALUES (?, ?, ?, ?, ?) " +
        "ON CONFLICT(user_id) DO UPDATE SET expires_at = excluded.expires_at, note = excluded.note, granted_by = excluded.granted_by, updated_at = excluded.updated_at"
      ).bind(r.userId, r.expiresAt, r.note, r.grantedBy, r.updatedAt).run();
    },
    async remove(userId) {
      await db.prepare("DELETE FROM subscriptions WHERE user_id = ?").bind(userId).run();
    },
    async listActive(now, limit) {
      const { results } = await db.prepare(
        "SELECT * FROM subscriptions WHERE expires_at = -1 OR expires_at > ? ORDER BY updated_at DESC LIMIT ?"
      ).bind(now, limit).all();
      return results.map(row);
    },
    async getDisabledFeatures() {
      const r = await db.prepare("SELECT value FROM settings WHERE key = 'disabled_features'").first();
      return r?.value ? r.value.split(",").filter(Boolean) : [];
    },
    async setDisabledFeatures(list) {
      await db.prepare("INSERT INTO settings (key, value) VALUES ('disabled_features', ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value")
        .bind(list.join(",")).run();
    },
    async counts(now) {
      const r = await db.prepare(
        "SELECT COUNT(*) AS total, SUM(CASE WHEN expires_at = -1 OR expires_at > ? THEN 1 ELSE 0 END) AS active, SUM(CASE WHEN expires_at = -1 THEN 1 ELSE 0 END) AS forever FROM subscriptions"
      ).bind(now).first();
      return { total: r.total || 0, active: r.active || 0, forever: r.forever || 0 };
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
    const storage = d1Storage(env.DB);

    if (request.method === "GET" && url.pathname === "/v1/status") {
      const userId = Number(url.searchParams.get("user_id"));
      if (!Number.isSafeInteger(userId) || userId <= 0) return json({ error: "bad user_id" }, 400);
      const record = await storage.get(userId);
      const key = await importSigningKey(env.SIGNING_KEY);
      return json(await signedStatus(key, { userId, expiresAt: record?.expiresAt ?? 0, now }));
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
        const reply = await handleCommand(storage, { message, adminIds, now });
        if (reply) await sendMessage(env.BOT_TOKEN, message.chat.id, reply);
      }
      return new Response("ok");
    }

    if (url.pathname === "/") return new Response("HolyGram Pro");
    return new Response("not found", { status: 404 });
  },
};
