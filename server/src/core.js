// HolyGram Pro subscription logic, independent of Cloudflare so it can be tested with Node.

export const FOREVER = -1;

const DAY = 86400;

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
 * Storage interface (D1 in production, a Map in tests):
 *   get(userId) -> {userId, expiresAt, note, grantedBy, updatedAt} | null
 *   put(record)
 *   remove(userId)
 *   listActive(now, limit) -> records
 *   counts(now) -> {active, forever, total}
 */

/** Extends from the current expiry when it is still running, otherwise from now. */
export async function grant(storage, { userId, seconds, note, grantedBy, now }) {
  const current = await storage.get(userId);
  let expiresAt;
  if (seconds === FOREVER || current?.expiresAt === FOREVER) {
    expiresAt = FOREVER;
  } else {
    const base = current && current.expiresAt > now ? current.expiresAt : now;
    expiresAt = base + seconds;
  }
  const record = { userId, expiresAt, note: note || current?.note || null, grantedBy, updatedAt: now };
  await storage.put(record);
  return record;
}

export async function revoke(storage, { userId }) {
  const current = await storage.get(userId);
  if (!current) return false;
  await storage.remove(userId);
  return true;
}

// ---------- signed status ----------

function toBase64(bytes) {
  let binary = "";
  for (const b of new Uint8Array(bytes)) binary += String.fromCharCode(b);
  return btoa(binary);
}

function fromBase64(text) {
  const binary = atob(text);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

export async function importSigningKey(pkcs8Base64) {
  return crypto.subtle.importKey("pkcs8", fromBase64(pkcs8Base64), { name: "Ed25519" }, false, ["sign"]);
}

/**
 * The app verifies `sig` over the exact `payload` bytes with the embedded public key.
 * payload = "holygram-pro-v1|<userId>|<expiresAt>|<issuedAt>"
 * expiresAt: -1 forever, 0 not subscribed, otherwise unix seconds.
 * The app trusts a status for at most 3 days after issuedAt, so a revoke takes effect.
 */
export async function signedStatus(key, { userId, expiresAt, now }) {
  const effective = isActive(expiresAt, now) ? expiresAt : 0;
  const payload = `holygram-pro-v1|${userId}|${effective}|${now}`;
  const signature = await crypto.subtle.sign({ name: "Ed25519" }, key, new TextEncoder().encode(payload));
  return { payload, sig: toBase64(signature) };
}

// ---------- bot commands ----------

const HELP = [
  "Команды администратора:",
  "/grant <user_id> <срок> [заметка] — выдать или продлить Pro. Срок: 7d, 30d, 3m, 1y, forever",
  "/revoke <user_id> — забрать Pro",
  "/info <user_id> — статус подписки",
  "/list [N] — активные подписки",
  "/stats — сколько подписчиков",
  "",
  "Вместо user_id можно ответить командой на пересланное сообщение пользователя.",
  "Свой ID пользователь видит в HolyGram: Настройки → HolyGram Pro.",
].join("\n");

function forwardedUserId(message) {
  const origin = message?.reply_to_message?.forward_origin;
  if (origin?.type === "user" && origin.sender_user?.id) return origin.sender_user.id;
  const legacy = message?.reply_to_message?.forward_from;
  if (legacy?.id) return legacy.id;
  return null;
}

/** Returns the reply text for a message, or null to stay silent. */
export async function handleCommand(storage, { message, adminIds, now }) {
  const text = (message?.text || "").trim();
  const fromId = message?.from?.id;
  if (!text.startsWith("/") || !fromId) return null;

  const [rawCommand, ...args] = text.split(/\s+/);
  const command = rawCommand.split("@")[0].toLowerCase();
  const isAdmin = adminIds.includes(fromId);

  if (!isAdmin) {
    if (command === "/start" || command === "/id" || command === "/status") {
      const record = await storage.get(fromId);
      return [
        "HolyGram Pro",
        `Ваш ID: ${fromId}`,
        `Подписка: ${formatExpiry(record?.expiresAt, now)}`,
        "",
        "Чтобы оформить или продлить Pro, напишите администратору.",
      ].join("\n");
    }
    return null;
  }

  const replyTarget = forwardedUserId(message);
  const takeUserId = () => {
    if (replyTarget) return replyTarget;
    const value = Number(args.shift());
    return Number.isSafeInteger(value) && value > 0 ? value : null;
  };

  switch (command) {
    case "/start":
    case "/help":
      return HELP;
    case "/grant": {
      const userId = takeUserId();
      const seconds = parseDuration(args.shift());
      if (!userId || seconds === null) return "Формат: /grant <user_id> <срок> [заметка]\nСрок: 7d, 30d, 3m, 1y, forever";
      const record = await grant(storage, { userId, seconds, note: args.join(" ") || null, grantedBy: fromId, now });
      return `✅ Pro для ${userId}: ${formatExpiry(record.expiresAt, now)}`;
    }
    case "/revoke": {
      const userId = takeUserId();
      if (!userId) return "Формат: /revoke <user_id>";
      return (await revoke(storage, { userId })) ? `🚫 Pro у ${userId} отозван` : `У ${userId} нет подписки`;
    }
    case "/info": {
      const userId = takeUserId();
      if (!userId) return "Формат: /info <user_id>";
      const record = await storage.get(userId);
      if (!record) return `${userId}: нет подписки`;
      return [
        `${userId}: ${formatExpiry(record.expiresAt, now)}`,
        record.note ? `Заметка: ${record.note}` : null,
        `Изменено: ${new Date(record.updatedAt * 1000).toISOString().slice(0, 16).replace("T", " ")} UTC`,
      ].filter(Boolean).join("\n");
    }
    case "/list": {
      const limit = Math.min(Math.max(Number(args[0]) || 50, 1), 200);
      const records = await storage.listActive(now, limit);
      if (records.length === 0) return "Активных подписок нет";
      return records.map((r) => `${r.userId} — ${formatExpiry(r.expiresAt, now)}${r.note ? ` · ${r.note}` : ""}`).join("\n");
    }
    case "/stats": {
      const c = await storage.counts(now);
      return `Активных: ${c.active} (навсегда: ${c.forever})\nВсего записей: ${c.total}`;
    }
    default:
      return "Неизвестная команда. /help — список команд";
  }
}
