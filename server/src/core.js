// HolyGram Pro subscription logic, independent of Cloudflare so it can be tested with Node.
//
// A subscription belongs to one iPhone, identified by a device code the app generates and keeps in
// the device-only keychain. On that iPhone Pro works in every account; logging the same Telegram
// account in on another device does not carry Pro over.

export const FOREVER = -1;

const DAY = 86400;

// Crockford base32 without I, L, O, U: easy to read out and type.
const CODE_ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";
const CODE_LENGTH = 12;

/** "hg-7k2f-9xqm-p4td", "HG7K2F9XQMP4TD" -> "HG7K2F9XQMP4TD"; anything else -> null. */
export function normalizeDeviceCode(text) {
  if (!text) return null;
  let value = String(text).toUpperCase().replace(/[\s-]/g, "");
  if (value.startsWith("HG")) value = value.slice(2);
  value = value.replace(/O/g, "0").replace(/[IL]/g, "1");
  if (value.length !== CODE_LENGTH) return null;
  for (const c of value) if (!CODE_ALPHABET.includes(c)) return null;
  return "HG" + value;
}

/** "HG7K2F9XQMP4TD" -> "HG-7K2F-9XQM-P4TD" */
export function formatDeviceCode(code) {
  const body = code.slice(2);
  return `HG-${body.slice(0, 4)}-${body.slice(4, 8)}-${body.slice(8)}`;
}

/** Parses "30d", "12m", "1y", "2w", "forever" into seconds (or FOREVER). */
export function parseDuration(text) {
  if (!text) return null;
  const value = text.trim().toLowerCase();
  if (value === "forever" || value === "навсегда" || value === "inf") return FOREVER;
  const match = /^(\d{1,4})\s*(d|д|w|н|m|м|y|г)?$/.exec(value);
  if (!match) return null;
  const amount = Number(match[1]);
  if (amount <= 0) return null;
  const unit = match[2] || "d";
  const days = { d: 1, "д": 1, w: 7, "н": 7, m: 30, "м": 30, y: 365, "г": 365 }[unit];
  return amount * days * DAY;
}

export function formatExpiry(expiresAt, now) {
  if (expiresAt === FOREVER) return "навсегда";
  if (!expiresAt || expiresAt <= now) return "нет подписки";
  const date = new Date(expiresAt * 1000).toISOString().slice(0, 10);
  const days = Math.ceil((expiresAt - now) / DAY);
  return `до ${date} (осталось ${days} дн.)`;
}

export function isActive(expiresAt, now) {
  return expiresAt === FOREVER || (typeof expiresAt === "number" && expiresAt > now);
}

/**
 * Storage interface (Workers KV in production, a Map in tests):
 *   get(deviceCode) -> {device, expiresAt, note, grantedBy, requestedBy, updatedAt} | null
 *   put(record)
 *   remove(deviceCode)
 *   listActive(now, limit) -> records
 *   counts(now) -> {active, forever, total}
 *   getDisabledFeatures() / setDisabledFeatures(list)
 */

/** Extends from the current expiry when it is still running, otherwise from now. */
export async function grant(storage, { device, seconds, note, grantedBy, now }) {
  const current = await storage.get(device);
  let expiresAt;
  if (seconds === FOREVER || current?.expiresAt === FOREVER) {
    expiresAt = FOREVER;
  } else {
    const base = current && current.expiresAt > now ? current.expiresAt : now;
    expiresAt = base + seconds;
  }
  const record = {
    device,
    expiresAt,
    note: note || current?.note || null,
    grantedBy,
    requestedBy: current?.requestedBy || null,
    updatedAt: now,
  };
  await storage.put(record);
  return record;
}

/** Ends the subscription but keeps the record (who asked for it, notes). Returns false when nothing was active. */
export async function revoke(storage, { device, now }) {
  const current = await storage.get(device);
  if (!current || !isActive(current.expiresAt, now)) return false;
  await storage.put({ ...current, expiresAt: 0, updatedAt: now });
  return true;
}

// ---------- signed status ----------

function toBase64(bytes) {
  let binary = "";
  for (const b of new Uint8Array(bytes)) binary += String.fromCharCode(b);
  return btoa(binary);
}

function fromBase64(text) {
  const binary = atob(text.trim());
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

export async function importSigningKey(pkcs8Base64) {
  return crypto.subtle.importKey("pkcs8", fromBase64(pkcs8Base64), { name: "Ed25519" }, false, ["sign"]);
}

/**
 * The app verifies `sig` over the exact `payload` bytes with the embedded public key.
 * payload = "holygram-pro-v2|<deviceCode>|<expiresAt>|<issuedAt>"
 * expiresAt: -1 forever, 0 not subscribed, otherwise unix seconds.
 * The app trusts a status for at most 3 days after issuedAt, so a revoke takes effect.
 */
export async function signedStatus(key, { device, expiresAt, now }) {
  const effective = isActive(expiresAt, now) ? expiresAt : 0;
  const payload = `holygram-pro-v2|${device}|${effective}|${now}`;
  const signature = await crypto.subtle.sign({ name: "Ed25519" }, key, new TextEncoder().encode(payload));
  return { payload, sig: toBase64(signature) };
}

// ---------- remote feature switches ----------

/** Features that can be switched off for every user at once, e.g. on a request from Telegram. */
export const SWITCHABLE_FEATURES = {
  ghost: "режим призрака (в сети, прочтение, печатает, истории)",
  selfdestruct: "сохранение исчезающих медиа",
  deleted: "сохранение удалённых сообщений",
  edits: "история правок",
};

/** payload = "holygram-flags-v1|<comma-separated disabled features>|<issuedAt>" */
export async function signedFlags(key, { disabled, now }) {
  const list = [...disabled].filter((f) => f in SWITCHABLE_FEATURES).sort().join(",");
  const payload = `holygram-flags-v1|${list}|${now}`;
  const signature = await crypto.subtle.sign({ name: "Ed25519" }, key, new TextEncoder().encode(payload));
  return { payload, sig: toBase64(signature) };
}

// ---------- plans ----------

/** Monthly price $2.50; longer plans are cheaper per month. Stars are priced near the USD amount. */
export const PLANS = [
  { id: "1m", months: 1, usd: 2.5, stars: 190 },
  { id: "3m", months: 3, usd: 6.99, stars: 530 },
  { id: "6m", months: 6, usd: 12.49, stars: 950 },
  { id: "12m", months: 12, usd: 21.99, stars: 1670 },
];

export const MONTH_SECONDS = 30 * DAY;

export function planById(id) {
  return PLANS.find((p) => p.id === id) || null;
}

/** Discount against paying $2.50 every month, in whole percent. */
export function planDiscount(plan) {
  const full = PLANS[0].usd * plan.months;
  return Math.round((1 - plan.usd / full) * 100);
}

export function formatUsd(value) {
  return `$${value.toFixed(2)}`;
}
