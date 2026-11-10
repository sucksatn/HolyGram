import test from "node:test";
import assert from "node:assert/strict";
import { FOREVER, grant, revoke, handleCommand, parseDuration, signedStatus, importSigningKey } from "../src/core.js";

function memoryStorage() {
  const map = new Map();
  return {
    async get(id) { return map.get(id) ?? null; },
    async put(r) { map.set(r.userId, { ...r }); },
    async remove(id) { map.delete(id); },
    async listActive(now, limit) { return [...map.values()].filter((r) => r.expiresAt === -1 || r.expiresAt > now).slice(0, limit); },
    async counts(now) {
      const all = [...map.values()];
      return { total: all.length, active: all.filter((r) => r.expiresAt === -1 || r.expiresAt > now).length, forever: all.filter((r) => r.expiresAt === -1).length };
    },
  };
}

const NOW = 1_800_000_000;
const ADMIN = 111;

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
  let r = await grant(s, { userId: 5, seconds: 10 * 86400, grantedBy: ADMIN, now: NOW });
  assert.equal(r.expiresAt, NOW + 10 * 86400);
  r = await grant(s, { userId: 5, seconds: 5 * 86400, grantedBy: ADMIN, now: NOW + 86400 });
  assert.equal(r.expiresAt, NOW + 15 * 86400);
  r = await grant(s, { userId: 5, seconds: 86400, grantedBy: ADMIN, now: NOW + 100 * 86400 });
  assert.equal(r.expiresAt, NOW + 101 * 86400);
  r = await grant(s, { userId: 5, seconds: FOREVER, grantedBy: ADMIN, now: NOW });
  assert.equal(r.expiresAt, FOREVER);
  r = await grant(s, { userId: 5, seconds: 86400, grantedBy: ADMIN, now: NOW });
  assert.equal(r.expiresAt, FOREVER, "a timed grant never shortens a forever subscription");
  assert.equal(await revoke(s, { userId: 5 }), true);
  assert.equal(await s.get(5), null);
});

test("only admins can manage subscriptions", async () => {
  const s = memoryStorage();
  const reply = await handleCommand(s, { message: { text: "/grant 42 30d", from: { id: 999 } }, adminIds: [ADMIN], now: NOW });
  assert.equal(reply, null);
  assert.equal(await s.get(42), null);
  const own = await handleCommand(s, { message: { text: "/start", from: { id: 999 } }, adminIds: [ADMIN], now: NOW });
  assert.match(own, /Ваш ID: 999/);
});

test("admin commands", async () => {
  const s = memoryStorage();
  const cmd = (text, extra = {}) => handleCommand(s, { message: { text, from: { id: ADMIN }, ...extra }, adminIds: [ADMIN], now: NOW });
  assert.match(await cmd("/grant 42 30d friend"), /Pro для 42/);
  assert.match(await cmd("/info 42"), /осталось 30 дн/);
  assert.match(await cmd("/list"), /42 — до/);
  assert.match(await cmd("/stats"), /Активных: 1/);
  assert.match(await cmd("/grant 43 forever", {}), /навсегда/);
  assert.match(await cmd("/grant 30d", { reply_to_message: { forward_origin: { type: "user", sender_user: { id: 77 } } } }), /Pro для 77/);
  assert.match(await cmd("/revoke 42"), /отозван/);
  assert.match(await cmd("/grant x"), /Формат/);
});

test("signed status verifies with the public key and hides expired subscriptions", async () => {
  const { privateKey, publicKey } = await crypto.subtle.generateKey({ name: "Ed25519" }, true, ["sign", "verify"]);
  const pkcs8 = Buffer.from(await crypto.subtle.exportKey("pkcs8", privateKey)).toString("base64");
  const key = await importSigningKey(pkcs8);
  const active = await signedStatus(key, { userId: 42, expiresAt: NOW + 10, now: NOW });
  assert.equal(active.payload, `holygram-pro-v1|42|${NOW + 10}|${NOW}`);
  const ok = await crypto.subtle.verify({ name: "Ed25519" }, publicKey, Buffer.from(active.sig, "base64"), new TextEncoder().encode(active.payload));
  assert.equal(ok, true);
  const expired = await signedStatus(key, { userId: 42, expiresAt: NOW - 10, now: NOW });
  assert.equal(expired.payload, `holygram-pro-v1|42|0|${NOW}`);
});
