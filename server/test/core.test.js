import test from "node:test";
import assert from "node:assert/strict";
import {
  FOREVER, grant, revoke, handleCommand, parseDuration, signedStatus, signedFlags, importSigningKey,
  normalizeDeviceCode, formatDeviceCode,
} from "../src/core.js";

function memoryStorage() {
  const map = new Map();
  let disabled = [];
  const active = (r, now) => r.expiresAt === -1 || r.expiresAt > now;
  return {
    async getDisabledFeatures() { return disabled; },
    async setDisabledFeatures(list) { disabled = list; },
    async get(device) { return map.get(device) ?? null; },
    async put(r) { map.set(r.device, { ...r }); },
    async remove(device) { map.delete(device); },
    async listActive(now, limit) { return [...map.values()].filter((r) => active(r, now)).slice(0, limit); },
    async counts(now) {
      const all = [...map.values()];
      return { total: all.length, active: all.filter((r) => active(r, now)).length, forever: all.filter((r) => r.expiresAt === -1).length };
    },
  };
}

const NOW = 1_800_000_000;
const ADMIN = 111;
const USER = 999;
const CODE = "HG7K2F9XQMP4TD";

const msg = (text, from, extra = {}) => ({ text, from: { id: from, username: "someone", first_name: "Some" }, chat: { id: from }, ...extra });
const texts = (out) => out.map((m) => m.text).join("\n---\n");

test("device codes", () => {
  assert.equal(normalizeDeviceCode("hg-7k2f-9xqm-p4td"), CODE);
  assert.equal(normalizeDeviceCode("HG7K2F9XQMP4TD"), CODE);
  assert.equal(normalizeDeviceCode("7K2F 9XQM P4TD"), CODE);
  assert.equal(normalizeDeviceCode("HG-7K2F-9XQM-P4TO"), "HG7K2F9XQMP4T0", "O reads as 0");
  assert.equal(normalizeDeviceCode("HG-7K2F-9XQM"), null);
  assert.equal(normalizeDeviceCode("HG-7K2F-9XQM-P4T!"), null);
  assert.equal(normalizeDeviceCode(undefined), null);
  assert.equal(formatDeviceCode(CODE), "HG-7K2F-9XQM-P4TD");
});

test("durations", () => {
  assert.equal(parseDuration("30d"), 30 * 86400);
  assert.equal(parseDuration("3m"), 90 * 86400);
  assert.equal(parseDuration("1y"), 365 * 86400);
  assert.equal(parseDuration("7"), 7 * 86400);
  assert.equal(parseDuration("forever"), FOREVER);
  assert.equal(parseDuration("0d"), null);
  assert.equal(parseDuration("abc"), null);
});

test("grant extends a running subscription and starts fresh after expiry", async () => {
  const s = memoryStorage();
  let r = await grant(s, { device: CODE, seconds: 10 * 86400, grantedBy: ADMIN, now: NOW });
  assert.equal(r.expiresAt, NOW + 10 * 86400);
  r = await grant(s, { device: CODE, seconds: 5 * 86400, grantedBy: ADMIN, now: NOW + 86400 });
  assert.equal(r.expiresAt, NOW + 15 * 86400);
  r = await grant(s, { device: CODE, seconds: 86400, grantedBy: ADMIN, now: NOW + 100 * 86400 });
  assert.equal(r.expiresAt, NOW + 101 * 86400);
  r = await grant(s, { device: CODE, seconds: FOREVER, grantedBy: ADMIN, now: NOW });
  assert.equal(r.expiresAt, FOREVER);
  r = await grant(s, { device: CODE, seconds: 86400, grantedBy: ADMIN, now: NOW });
  assert.equal(r.expiresAt, FOREVER, "a timed grant never shortens a forever subscription");
  assert.equal(await revoke(s, { device: CODE, now: NOW }), true);
  assert.equal((await s.get(CODE)).expiresAt, 0);
  assert.equal(await revoke(s, { device: CODE, now: NOW }), false);
});

test("a user's request from the app reaches the admin, and the grant reaches the user", async () => {
  const s = memoryStorage();
  const out = await handleCommand(s, { message: msg(`/start ${CODE}`, USER), adminIds: [ADMIN], now: NOW });
  assert.equal(out.length, 2);
  assert.equal(out[0].chatId, USER);
  assert.match(out[0].text, /HG-7K2F-9XQM-P4TD/);
  assert.equal(out[1].chatId, ADMIN);
  assert.match(out[1].text, /Запрос HolyGram Pro[\s\S]*@someone[\s\S]*HG-7K2F-9XQM-P4TD/);

  // The admin answers the notification with "/grant 30d"; the code comes from the replied message.
  const granted = await handleCommand(s, { message: msg("/grant 30d", ADMIN, { reply_to_message: { text: out[1].text } }), adminIds: [ADMIN], now: NOW });
  assert.match(texts(granted), /Pro для HG-7K2F-9XQM-P4TD: до/);
  assert.equal(granted[1].chatId, USER, "the user hears about the activation");
  assert.equal((await s.get(CODE)).expiresAt, NOW + 30 * 86400);
});

test("non-admins can't manage subscriptions", async () => {
  const s = memoryStorage();
  assert.deepEqual(await handleCommand(s, { message: msg(`/grant ${CODE} 30d`, USER), adminIds: [ADMIN], now: NOW }), []);
  assert.deepEqual(await handleCommand(s, { message: msg("/disable ghost", USER), adminIds: [ADMIN], now: NOW }), []);
  assert.equal(await s.get(CODE), null);
  assert.match(texts(await handleCommand(s, { message: msg("/start", USER), adminIds: [ADMIN], now: NOW })), /привязывается к iPhone/);
});

test("admin commands", async () => {
  const s = memoryStorage();
  const cmd = async (text) => texts(await handleCommand(s, { message: msg(text, ADMIN), adminIds: [ADMIN], now: NOW }));
  assert.match(await cmd(`/grant ${CODE} 30d friend`), /Pro для HG-7K2F-9XQM-P4TD/);
  assert.match(await cmd("/info hg-7k2f-9xqm-p4td"), /осталось 30 дн[\s\S]*friend/);
  assert.match(await cmd("/list"), /HG-7K2F-9XQM-P4TD — до/);
  assert.match(await cmd("/stats"), /Активных: 1/);
  assert.match(await cmd("/grant HG-AAAA-BBBB-CCCC forever"), /навсегда/);
  assert.match(await cmd(`/revoke ${CODE}`), /отозван/);
  assert.match(await cmd("/grant x"), /Формат/);
  assert.match(await cmd("/help"), /\/grant <код>/);
});

test("signed status verifies with the public key and hides expired subscriptions", async () => {
  const { privateKey, publicKey } = await crypto.subtle.generateKey({ name: "Ed25519" }, true, ["sign", "verify"]);
  const key = await importSigningKey(Buffer.from(await crypto.subtle.exportKey("pkcs8", privateKey)).toString("base64") + "\n");
  const active = await signedStatus(key, { device: CODE, expiresAt: NOW + 10, now: NOW });
  assert.equal(active.payload, `holygram-pro-v2|${CODE}|${NOW + 10}|${NOW}`);
  const ok = await crypto.subtle.verify({ name: "Ed25519" }, publicKey, Buffer.from(active.sig, "base64"), new TextEncoder().encode(active.payload));
  assert.equal(ok, true);
  const expired = await signedStatus(key, { device: CODE, expiresAt: NOW - 10, now: NOW });
  assert.equal(expired.payload, `holygram-pro-v2|${CODE}|0|${NOW}`);
});

test("remote feature switches", async () => {
  const s = memoryStorage();
  const cmd = async (text) => texts(await handleCommand(s, { message: msg(text, ADMIN), adminIds: [ADMIN], now: NOW }));
  assert.match(await cmd("/disable ghost"), /Выключено/);
  assert.deepEqual(await s.getDisabledFeatures(), ["ghost"]);
  assert.match(await cmd("/flags"), /⛔️ ghost/);
  assert.match(await cmd("/disable all"), /selfdestruct/);
  assert.match(await cmd("/enable all"), /Включено/);
  assert.deepEqual(await s.getDisabledFeatures(), []);
  assert.match(await cmd("/disable nope"), /Формат/);

  const { privateKey } = await crypto.subtle.generateKey({ name: "Ed25519" }, true, ["sign", "verify"]);
  const key = await importSigningKey(Buffer.from(await crypto.subtle.exportKey("pkcs8", privateKey)).toString("base64"));
  const flags = await signedFlags(key, { disabled: ["selfdestruct", "ghost", "bogus"], now: NOW });
  assert.equal(flags.payload, `holygram-flags-v1|ghost,selfdestruct|${NOW}`);
});
