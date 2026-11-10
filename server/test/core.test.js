import test from "node:test";
import assert from "node:assert/strict";
import {
  FOREVER, MONTH_SECONDS, PLANS, grant, revoke, parseDuration, signedStatus, signedFlags, importSigningKey,
  normalizeDeviceCode, formatDeviceCode, planDiscount,
} from "../src/core.js";
import { createBot } from "../src/bot.js";
import { verifyCryptoPaySignature } from "../src/worker.js";

function memoryStorage() {
  const devices = new Map();
  const users = new Map();
  const states = new Map();
  const payments = new Map();
  let disabled = [];
  const active = (r, now) => r.expiresAt === -1 || r.expiresAt > now;
  return {
    devices, payments,
    async get(device) { return devices.get(device) ?? null; },
    async put(r) { devices.set(r.device, { ...r }); },
    async remove(device) { devices.delete(device); },
    async listActive(now, limit) { return [...devices.values()].filter((r) => active(r, now)).slice(0, limit); },
    async counts(now) {
      const all = [...devices.values()];
      return { total: all.length, active: all.filter((r) => active(r, now)).length, forever: all.filter((r) => r.expiresAt === -1).length };
    },
    async getUserDevice(id) { return users.get(id) ?? null; },
    async setUserDevice(id, device) { users.set(id, device); },
    async getState(id) { return states.get(id) ?? null; },
    async setState(id, state) { if (state) states.set(id, state); else states.delete(id); },
    async addPayment(id, record) { if (payments.has(id)) return false; payments.set(id, { id, ...record }); return true; },
    async listPayments() { return [...payments.values()]; },
    async getDisabledFeatures() { return disabled; },
    async setDisabledFeatures(list) { disabled = list; },
  };
}

const NOW = 1_800_000_000;
const ADMIN = 111;
const USER = 999;
const CODE = "HG7K2F9XQMP4TD";

function harness({ withCrypto = true } = {}) {
  const storage = memoryStorage();
  const calls = [];
  let nextMessageId = 100;
  const tg = async (method, params) => {
    calls.push({ method, params });
    return method === "sendMessage" ? { message_id: nextMessageId++ } : true;
  };
  const cryptoCalls = [];
  const crypto = withCrypto ? async (method, params) => {
    cryptoCalls.push({ method, params });
    return { invoice_id: 77, bot_invoice_url: "https://t.me/CryptoBot?start=IVabc" };
  } : null;
  const bot = createBot({ storage, tg, crypto, adminIds: [ADMIN], now: NOW, botUsername: "HolygramBot" });
  const user = (id) => ({ id, username: id === ADMIN ? "owner" : "buyer", first_name: "Name", language_code: "ru" });
  const send = (from, text, extra = {}) => bot.handleUpdate({ message: { message_id: 1, from: user(from), chat: { id: from, type: "private" }, text, ...extra } });
  const press = (from, data) => bot.handleUpdate({ callback_query: { id: "cb", from: user(from), data, message: { message_id: 50, chat: { id: from } } } });
  const sent = () => calls.filter((c) => c.method === "sendMessage" || c.method === "editMessageText");
  const last = () => sent().at(-1).params;
  const buttons = (params) => (params.reply_markup?.inline_keyboard || []).flat();
  return { storage, calls, cryptoCalls, bot, send, press, sent, last, buttons, user };
}

test("device codes", () => {
  assert.equal(normalizeDeviceCode("hg-7k2f-9xqm-p4td"), CODE);
  assert.equal(normalizeDeviceCode("7K2F 9XQM P4TD"), CODE);
  assert.equal(normalizeDeviceCode("HG-7K2F-9XQM-P4TO"), "HG7K2F9XQMP4T0", "O reads as 0");
  assert.equal(normalizeDeviceCode("HG-7K2F-9XQM"), null);
  assert.equal(normalizeDeviceCode(undefined), null);
  assert.equal(formatDeviceCode(CODE), "HG-7K2F-9XQM-P4TD");
});

test("durations and plans", () => {
  assert.equal(parseDuration("30d"), 30 * 86400);
  assert.equal(parseDuration("1y"), 365 * 86400);
  assert.equal(parseDuration("forever"), FOREVER);
  assert.equal(parseDuration("abc"), null);
  assert.deepEqual(PLANS.map((p) => p.usd), [2.5, 6.99, 12.49, 21.99]);
  assert.deepEqual(PLANS.map(planDiscount), [0, 7, 17, 27]);
  for (let i = 1; i < PLANS.length; i++) {
    assert.ok(PLANS[i].usd / PLANS[i].months < PLANS[i - 1].usd / PLANS[i - 1].months, "longer plans are cheaper per month");
    assert.ok(PLANS[i].stars / PLANS[i].months < PLANS[i - 1].stars / PLANS[i - 1].months);
  }
});

test("grant extends, forever stays forever, revoke ends", async () => {
  const s = memoryStorage();
  let r = await grant(s, { device: CODE, seconds: 10 * 86400, grantedBy: ADMIN, now: NOW });
  assert.equal(r.expiresAt, NOW + 10 * 86400);
  r = await grant(s, { device: CODE, seconds: 5 * 86400, grantedBy: ADMIN, now: NOW + 86400 });
  assert.equal(r.expiresAt, NOW + 15 * 86400);
  r = await grant(s, { device: CODE, seconds: FOREVER, grantedBy: ADMIN, now: NOW });
  r = await grant(s, { device: CODE, seconds: 86400, grantedBy: ADMIN, now: NOW });
  assert.equal(r.expiresAt, FOREVER);
  assert.equal(await revoke(s, { device: CODE, now: NOW }), true);
  assert.equal(await revoke(s, { device: CODE, now: NOW }), false);
});

test("a user opens the bot from the app and sees the shop, not the admin panel", async () => {
  const h = harness();
  await h.send(USER, `/start ${CODE}`);
  const menu = h.last();
  assert.match(menu.text, /HG-7K2F-9XQM-P4TD/);
  assert.match(menu.text, /Режим призрака/);
  const labels = h.buttons(menu).map((b) => b.text);
  assert.ok(labels.includes("💎 Купить Pro"));
  assert.ok(!labels.some((l) => l.includes("Админ")), "no admin panel for users");

  await h.press(USER, "buy");
  const plans = h.buttons(h.last()).map((b) => b.text);
  assert.deepEqual(plans.slice(0, 4), ["1 мес. — $2.50", "3 мес. — $6.99 · −7%", "6 мес. — $12.49 · −17%", "12 мес. — $21.99 · −27%"]);

  await h.press(USER, "admin");
  await h.press(USER, `g:${CODE}:f`);
  assert.equal(await h.storage.get(CODE).then((r) => r.expiresAt), 0, "users can't press admin buttons");
});

test("paying with Stars grants the plan once and tells buyer and admin", async () => {
  const h = harness();
  await h.send(USER, `/start ${CODE}`);
  await h.press(USER, "plan:3m");
  assert.ok(h.buttons(h.last()).some((b) => b.callback_data === "pay:stars:3m"));
  await h.press(USER, "pay:stars:3m");
  const invoice = h.calls.find((c) => c.method === "sendInvoice").params;
  assert.equal(invoice.currency, "XTR");
  assert.equal(invoice.prices[0].amount, 530);

  await h.bot.handleUpdate({ pre_checkout_query: { id: "pc", from: h.user(USER), currency: "XTR", total_amount: 530, invoice_payload: invoice.payload } });
  assert.deepEqual(h.calls.at(-1), { method: "answerPreCheckoutQuery", params: { pre_checkout_query_id: "pc", ok: true } });
  await h.bot.handleUpdate({ pre_checkout_query: { id: "pc2", from: h.user(USER), currency: "XTR", total_amount: 1, invoice_payload: invoice.payload } });
  assert.equal(h.calls.at(-1).params.ok, false, "a wrong amount is refused");

  const paid = { successful_payment: { currency: "XTR", total_amount: 530, invoice_payload: invoice.payload, telegram_payment_charge_id: "ch1" } };
  await h.send(USER, "", paid);
  await h.send(USER, "", paid);
  assert.equal((await h.storage.get(CODE)).expiresAt, NOW + 3 * MONTH_SECONDS, "a repeated update doesn't grant twice");
  const texts = h.sent().map((c) => `${c.params.chat_id}: ${c.params.text}`).join("\n");
  assert.match(texts, new RegExp(`${USER}: ✅ Оплата получена`));
  assert.match(texts, new RegExp(`${ADMIN}: 💰 Оплата 530 ⭐`));
});

test("paying with CryptoBot", async () => {
  const h = harness();
  await h.send(USER, `/start ${CODE}`);
  await h.press(USER, "pay:crypto:12m");
  const created = h.cryptoCalls[0].params;
  assert.equal(created.amount, "21.99");
  assert.equal(created.fiat, "USD");
  assert.ok(h.buttons(h.last()).some((b) => b.url === "https://t.me/CryptoBot?start=IVabc"));
  await h.bot.handleCryptoPaid({ invoice_id: 77, status: "paid", payload: created.payload, paid_amount: "21.99", paid_asset: "USDT" });
  await h.bot.handleCryptoPaid({ invoice_id: 77, status: "paid", payload: created.payload });
  assert.equal((await h.storage.get(CODE)).expiresAt, NOW + 12 * MONTH_SECONDS);
  assert.equal(h.storage.payments.size, 1);
});

test("without Crypto Pay configured only Stars is offered", async () => {
  const h = harness({ withCrypto: false });
  await h.send(USER, `/start ${CODE}`);
  await h.press(USER, "plan:1m");
  const data = h.buttons(h.last()).map((b) => b.callback_data);
  assert.ok(data.includes("pay:stars:1m"));
  assert.ok(!data.includes("pay:crypto:1m"));
});

test("a user without a device code is told how to get one, and can send it as text", async () => {
  const h = harness();
  await h.send(USER, "/start");
  assert.match(h.last().text, /Получить HolyGram Pro/);
  assert.equal(h.buttons(h.last()).length, 0);
  await h.send(USER, "мой код hg-7k2f-9xqm-p4td");
  assert.match(h.last().text, /HG-7K2F-9XQM-P4TD/);
});

test("admin panel: buttons, grant by code, flags", async () => {
  const h = harness();
  await h.send(ADMIN, "/start");
  assert.ok(h.buttons(h.last()).some((b) => b.callback_data === "admin"), "the admin sees the panel button");
  await h.press(ADMIN, "admin");
  assert.match(h.last().text, /Админ-панель/);

  await h.press(ADMIN, "a:grant");
  await h.send(ADMIN, "HG-7K2F-9XQM-P4TD");
  assert.ok(h.buttons(h.last()).some((b) => b.callback_data === `g:${CODE}:30`));
  await h.press(ADMIN, `g:${CODE}:30`);
  assert.equal((await h.storage.get(CODE)).expiresAt, NOW + 30 * 86400);
  await h.press(ADMIN, `g:${CODE}:f`);
  assert.equal((await h.storage.get(CODE)).expiresAt, FOREVER);
  await h.press(ADMIN, `r:${CODE}`);
  assert.equal((await h.storage.get(CODE)).expiresAt, 0);

  await h.send(ADMIN, `/grant ${CODE} 1y vip`);
  assert.equal((await h.storage.get(CODE)).expiresAt, NOW + 365 * 86400);

  await h.press(ADMIN, "a:flags");
  await h.press(ADMIN, "f:ghost");
  assert.deepEqual(await h.storage.getDisabledFeatures(), ["ghost"]);
  assert.match(h.buttons(h.last()).map((b) => b.text).join(), /⛔️ режим призрака/);
  await h.press(ADMIN, "f:ghost");
  assert.deepEqual(await h.storage.getDisabledFeatures(), []);

  await h.press(ADMIN, "a:sales");
  assert.match(h.last().text, /Продаж пока нет/);
});

test("a manual grant tells the user who asked for it", async () => {
  const h = harness();
  await h.send(USER, `/start ${CODE}`);
  await h.send(ADMIN, `/grant ${CODE} 30d`);
  assert.ok(h.sent().some((c) => c.params.chat_id === USER && /Pro активирован/.test(c.params.text)));
});

test("signed status and flags verify with the public key", async () => {
  const { privateKey, publicKey } = await crypto.subtle.generateKey({ name: "Ed25519" }, true, ["sign", "verify"]);
  const key = await importSigningKey(Buffer.from(await crypto.subtle.exportKey("pkcs8", privateKey)).toString("base64") + "\n");
  const status = await signedStatus(key, { device: CODE, expiresAt: NOW + 10, now: NOW });
  assert.equal(status.payload, `holygram-pro-v2|${CODE}|${NOW + 10}|${NOW}`);
  assert.equal(await crypto.subtle.verify({ name: "Ed25519" }, publicKey, Buffer.from(status.sig, "base64"), new TextEncoder().encode(status.payload)), true);
  assert.equal((await signedStatus(key, { device: CODE, expiresAt: NOW - 10, now: NOW })).payload, `holygram-pro-v2|${CODE}|0|${NOW}`);
  assert.equal((await signedFlags(key, { disabled: ["selfdestruct", "ghost", "bogus"], now: NOW })).payload, `holygram-flags-v1|ghost,selfdestruct|${NOW}`);
});

test("Crypto Pay webhook signature", async () => {
  const token = "12345:AAA";
  const body = JSON.stringify({ update_type: "invoice_paid", payload: {} });
  const secret = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(token));
  const key = await crypto.subtle.importKey("raw", secret, { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const sig = Buffer.from(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(body))).toString("hex");
  assert.equal(await verifyCryptoPaySignature(token, body, sig), true);
  assert.equal(await verifyCryptoPaySignature(token, body + " ", sig), false);
  assert.equal(await verifyCryptoPaySignature(token, body, null), false);
  assert.equal(await verifyCryptoPaySignature(undefined, body, sig), false);
});
