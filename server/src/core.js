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

// ---------- bot commands ----------

const HELP = [
  "Команды администратора:",
  "/grant <код> <срок> [заметка] — выдать или продлить Pro. Срок: 7d, 30d, 3m, 1y, forever",
  "/revoke <код> — забрать Pro",
  "/info <код> — статус подписки",
  "/list [N] — активные подписки",
  "/stats — сколько подписчиков",
  "/disable <функция> — выключить функцию у всех (ghost, selfdestruct, deleted, edits, all)",
  "/enable <функция> — включить обратно",
  "/flags — что сейчас выключено",
  "",
  "Код — это код устройства вида HG-XXXX-XXXX-XXXX из HolyGram (Настройки → HolyGram → HolyGram Pro).",
  "Когда пользователь нажимает «Получить HolyGram Pro», вам приходит запрос с кодом: ответьте на него, например, /grant 30d — код подставится сам.",
].join("\n");

function userLabel(user) {
  if (!user) return "?";
  const name = [user.first_name, user.last_name].filter(Boolean).join(" ");
  return user.username ? `@${user.username} (${name}, id ${user.id})` : `${name} (id ${user.id})`;
}

/** The device code in the message an admin replied to (a request notification or any text with a code). */
function repliedDeviceCode(message) {
  const text = message?.reply_to_message?.text || "";
  const match = /HG-?[0-9A-Z]{4}-?[0-9A-Z]{4}-?[0-9A-Z]{4}/i.exec(text);
  return match ? normalizeDeviceCode(match[0]) : null;
}

/**
 * Returns the messages to send: [{chatId, text}]. Empty when the bot should stay silent.
 * Admin requests are answered in the admin's chat; a user's Pro request also notifies every admin.
 */
export async function handleCommand(storage, { message, adminIds, now }) {
  const text = (message?.text || "").trim();
  const from = message?.from;
  const chatId = message?.chat?.id ?? from?.id;
  if (!text.startsWith("/") || !from?.id) return [];

  const [rawCommand, ...args] = text.split(/\s+/);
  const command = rawCommand.split("@")[0].toLowerCase();
  const isAdmin = adminIds.includes(from.id);
  const reply = (t) => [{ chatId, text: t }];

  // "Get HolyGram Pro" in the app opens t.me/<bot>?start=<device code>.
  const startCode = command === "/start" ? normalizeDeviceCode(args[0]) : null;

  if (!isAdmin || startCode) {
    if (command !== "/start" && command !== "/status") return [];
    if (!startCode) {
      return reply([
        "HolyGram Pro",
        "",
        "Pro привязывается к iPhone. Чтобы оформить или продлить подписку, откройте HolyGram → Настройки → HolyGram → «Получить HolyGram Pro»: бот получит код вашего устройства.",
      ].join("\n"));
    }
    const record = await storage.get(startCode);
    if (record && !isActive(record.expiresAt, now)) {
      await storage.put({ ...record, requestedBy: from.id });
    } else if (!record) {
      await storage.put({ device: startCode, expiresAt: 0, note: null, grantedBy: null, requestedBy: from.id, updatedAt: now });
    }
    const status = formatExpiry(record?.expiresAt, now);
    const messages = reply([
      "HolyGram Pro",
      `Устройство: ${formatDeviceCode(startCode)}`,
      `Подписка: ${status}`,
      "",
      isActive(record?.expiresAt, now)
        ? "Чтобы продлить, просто подождите — администратор получил ваш запрос."
        : "Запрос отправлен администратору. Pro появится в HolyGram в течение нескольких минут после оплаты (или откройте настройки HolyGram, чтобы проверить сразу).",
    ].join("\n"));
    for (const adminId of adminIds) {
      if (adminId === from.id) continue;
      messages.push({
        chatId: adminId,
        text: [
          "🔔 Запрос HolyGram Pro",
          `От: ${userLabel(from)}`,
          `Устройство: ${formatDeviceCode(startCode)}`,
          `Сейчас: ${status}`,
          "",
          "Ответьте на это сообщение: /grant 30d (или 3m, 1y, forever)",
        ].join("\n"),
      });
    }
    return messages;
  }

  const fromReply = repliedDeviceCode(message);
  const takeDevice = () => {
    if (fromReply) return fromReply;
    return normalizeDeviceCode(args.shift());
  };

  switch (command) {
    case "/start":
    case "/help":
      return reply(HELP);
    case "/grant": {
      const device = takeDevice();
      const seconds = parseDuration(args.shift());
      if (!device || seconds === null) return reply("Формат: /grant <код устройства> <срок> [заметка]\nСрок: 7d, 30d, 3m, 1y, forever\nИли ответьте на запрос: /grant 30d");
      const record = await grant(storage, { device, seconds, note: args.join(" ") || null, grantedBy: from.id, now });
      const messages = reply(`✅ Pro для ${formatDeviceCode(device)}: ${formatExpiry(record.expiresAt, now)}`);
      if (record.requestedBy && record.requestedBy !== from.id) {
        messages.push({ chatId: record.requestedBy, text: `✅ HolyGram Pro активирован: ${formatExpiry(record.expiresAt, now)}.\nОткройте HolyGram → Настройки → HolyGram, чтобы применить сразу.` });
      }
      return messages;
    }
    case "/revoke": {
      const device = takeDevice();
      if (!device) return reply("Формат: /revoke <код устройства>");
      return reply((await revoke(storage, { device, now })) ? `🚫 Pro у ${formatDeviceCode(device)} отозван` : `У ${formatDeviceCode(device)} нет подписки`);
    }
    case "/info": {
      const device = takeDevice();
      if (!device) return reply("Формат: /info <код устройства>");
      const record = await storage.get(device);
      if (!record) return reply(`${formatDeviceCode(device)}: нет подписки`);
      return reply([
        `${formatDeviceCode(device)}: ${formatExpiry(record.expiresAt, now)}`,
        record.note ? `Заметка: ${record.note}` : null,
        record.requestedBy ? `Запрашивал: id ${record.requestedBy}` : null,
        `Изменено: ${new Date(record.updatedAt * 1000).toISOString().slice(0, 16).replace("T", " ")} UTC`,
      ].filter(Boolean).join("\n"));
    }
    case "/list": {
      const limit = Math.min(Math.max(Number(args[0]) || 50, 1), 200);
      const records = await storage.listActive(now, limit);
      if (records.length === 0) return reply("Активных подписок нет");
      return reply(records.map((r) => `${formatDeviceCode(r.device)} — ${formatExpiry(r.expiresAt, now)}${r.note ? ` · ${r.note}` : ""}`).join("\n"));
    }
    case "/disable":
    case "/enable": {
      const name = (args[0] || "").toLowerCase();
      const names = name === "all" ? Object.keys(SWITCHABLE_FEATURES) : [name];
      if (!names.every((n) => n in SWITCHABLE_FEATURES)) {
        return reply(`Формат: ${command} <функция>\nФункции: ${Object.keys(SWITCHABLE_FEATURES).join(", ")}, all`);
      }
      const disabled = new Set(await storage.getDisabledFeatures());
      for (const n of names) {
        if (command === "/disable") disabled.add(n); else disabled.delete(n);
      }
      await storage.setDisabledFeatures([...disabled]);
      const verb = command === "/disable" ? "⛔️ Выключено" : "✅ Включено";
      return reply(`${verb} у всех пользователей: ${names.join(", ")}\nПриложения применят это при следующей проверке (до 6 часов или при открытии настроек HolyGram).`);
    }
    case "/flags": {
      const disabled = await storage.getDisabledFeatures();
      return reply(Object.entries(SWITCHABLE_FEATURES)
        .map(([n, title]) => `${disabled.includes(n) ? "⛔️" : "✅"} ${n} — ${title}`)
        .join("\n"));
    }
    case "/stats": {
      const c = await storage.counts(now);
      return reply(`Активных: ${c.active} (навсегда: ${c.forever})\nВсего устройств: ${c.total}`);
    }
    default:
      return reply("Неизвестная команда. /help — список команд");
  }
}
