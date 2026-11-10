// Cloudflare Worker entry point: status API for the app, the Telegram bot webhook and the
// Crypto Pay (@CryptoBot) payment webhook.
import { createBot } from "./bot.js";
import { importSigningKey, normalizeDeviceCode, signedFlags, signedStatus } from "./core.js";

// Workers KV keys:
//   dev:<device code>  subscription record
//   user:<telegram id> device code the user last opened the bot with
//   state:<telegram id> admin input state (expires after an hour)
//   pay:<payment id>   payment record (also makes payments idempotent)
//   flags:disabled     comma-separated remotely disabled features
export function kvStorage(kv) {
  async function listValues(prefix) {
    const values = [];
    let cursor;
    do {
      const page = await kv.list({ prefix, cursor });
      for (const { name } of page.keys) {
        const value = await kv.get(name, "json");
        if (value) values.push(value);
      }
      cursor = page.list_complete ? undefined : page.cursor;
    } while (cursor);
    return values;
  }
  const isActive = (r, now) => r.expiresAt === -1 || r.expiresAt > now;
  return {
    async get(device) {
      return await kv.get(`dev:${device}`, "json");
    },
    async put(record) {
      await kv.put(`dev:${record.device}`, JSON.stringify(record));
    },
    async remove(device) {
      await kv.delete(`dev:${device}`);
    },
    async listActive(now, limit) {
      return (await listValues("dev:"))
        .filter((r) => isActive(r, now))
        .sort((a, b) => b.updatedAt - a.updatedAt)
        .slice(0, limit);
    },
    async counts(now) {
      const all = await listValues("dev:");
      return {
        total: all.length,
        active: all.filter((r) => isActive(r, now)).length,
        forever: all.filter((r) => r.expiresAt === -1).length,
      };
    },
    async getUserDevice(userId) {
      return await kv.get(`user:${userId}`);
    },
    async setUserDevice(userId, device) {
      await kv.put(`user:${userId}`, device);
    },
    async getState(userId) {
      return await kv.get(`state:${userId}`);
    },
    async setState(userId, state) {
      if (state) {
        await kv.put(`state:${userId}`, state, { expirationTtl: 3600 });
      } else {
        await kv.delete(`state:${userId}`);
      }
    },
    async addPayment(id, record) {
      if (await kv.get(`pay:${id}`)) return false;
      await kv.put(`pay:${id}`, JSON.stringify({ id, ...record }));
      return true;
    },
    async listPayments() {
      return await listValues("pay:");
    },
    async getDisabledFeatures() {
      const value = await kv.get("flags:disabled");
      return value ? value.split(",").filter(Boolean) : [];
    },
    async setDisabledFeatures(list) {
      await kv.put("flags:disabled", list.join(","));
    },
  };
}

function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json", "cache-control": "no-store" },
  });
}

function telegramClient(token) {
  return async (method, params) => {
    const response = await fetch(`https://api.telegram.org/bot${token}/${method}`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(params),
    });
    const body = await response.json();
    if (!body.ok) throw new Error(`${method}: ${body.description}`);
    return body.result;
  };
}

function cryptoPayClient(token) {
  if (!token) return null;
  return async (method, params) => {
    const response = await fetch(`https://pay.crypt.bot/api/${method}`, {
      method: "POST",
      headers: { "content-type": "application/json", "crypto-pay-api-token": token },
      body: JSON.stringify(params),
    });
    const body = await response.json();
    if (!body.ok) throw new Error(`${method}: ${JSON.stringify(body.error)}`);
    return body.result;
  };
}

/** Crypto Pay signs the raw body: HMAC-SHA256 with SHA256(token) as the key, hex. */
export async function verifyCryptoPaySignature(token, rawBody, signatureHex) {
  if (!token || !signatureHex) return false;
  const secret = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(token));
  const key = await crypto.subtle.importKey("raw", secret, { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const mac = new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(rawBody)));
  const expected = [...mac].map((b) => b.toString(16).padStart(2, "0")).join("");
  if (expected.length !== signatureHex.length) return false;
  let diff = 0;
  for (let i = 0; i < expected.length; i++) diff |= expected.charCodeAt(i) ^ signatureHex.charCodeAt(i);
  return diff === 0;
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const now = Math.floor(Date.now() / 1000);
    const storage = kvStorage(env.SUBS);
    const makeBot = () => createBot({
      storage,
      tg: telegramClient(env.BOT_TOKEN),
      crypto: cryptoPayClient(env.CRYPTO_PAY_TOKEN),
      adminIds: String(env.ADMIN_IDS || "").split(",").map((s) => Number(s.trim())).filter(Boolean),
      now,
      botUsername: env.BOT_USERNAME || "HolygramBot",
    });

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
      try {
        await makeBot().handleUpdate(update);
      } catch (error) {
        console.error("bot update failed", error);
      }
      return new Response("ok");
    }

    // Crypto Pay webhook. The path is public; every update is checked against Crypto Pay's HMAC signature.
    if (request.method === "POST" && url.pathname === "/v1/cryptopay") {
      const raw = await request.text();
      const valid = await verifyCryptoPaySignature(env.CRYPTO_PAY_TOKEN, raw, request.headers.get("crypto-pay-api-signature"));
      if (!valid) return new Response("forbidden", { status: 403 });
      const update = JSON.parse(raw);
      if (update.update_type === "invoice_paid") {
        await makeBot().handleCryptoPaid(update.payload);
      }
      return new Response("ok");
    }

    if (url.pathname === "/") return new Response("HolyGram Pro");
    return new Response("not found", { status: 404 });
  },
};
