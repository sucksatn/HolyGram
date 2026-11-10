// @HolygramBot: Pro shop for everyone, plus an admin panel for ADMIN_IDS.
//
// Telegram and Crypto Pay are reached through injected functions so the whole flow runs in tests:
//   tg(method, params)     -> Bot API result (throws on errors the caller cares about)
//   crypto(method, params) -> Crypto Pay API result, or null when Crypto Pay isn't configured
import {
  FOREVER, MONTH_SECONDS, PLANS, SWITCHABLE_FEATURES,
  formatDeviceCode, formatExpiry, formatUsd, grant, isActive, normalizeDeviceCode, parseDuration,
  planById, planDiscount, revoke,
} from "./core.js";

const CRYPTO_ASSETS = "USDT,TON,BTC,ETH,LTC,BNB,TRX,USDC";
const DEVICE_PATTERN = /HG-?[0-9A-Z]{4}-?[0-9A-Z]{4}-?[0-9A-Z]{4}/i;

function isRussian(user) {
  const code = (user?.language_code || "ru").toLowerCase();
  return ["ru", "uk", "be", "kk", "uz"].some((prefix) => code.startsWith(prefix));
}

function userLabel(user) {
  if (!user) return "?";
  const name = [user.first_name, user.last_name].filter(Boolean).join(" ");
  return user.username ? `@${user.username} (${name}, id ${user.id})` : `${name} (id ${user.id})`;
}

const button = (text, data) => ({ text, callback_data: data });
const urlButton = (text, url) => ({ text, url });
const keyboard = (rows) => ({ inline_keyboard: rows.filter((row) => row.length > 0) });

export function createBot({ storage, tg, crypto, adminIds, now, botUsername }) {
  const isAdmin = (userId) => adminIds.includes(userId);

  async function show(chatId, messageId, text, markup) {
    const params = { chat_id: chatId, text, reply_markup: markup, disable_web_page_preview: true };
    if (messageId) {
      try {
        await tg("editMessageText", { ...params, message_id: messageId });
        return;
      } catch (error) {
        if (String(error?.message || error).includes("not modified")) return;
      }
    }
    await tg("sendMessage", params);
  }

  async function notifyAdmins(text, markup) {
    for (const adminId of adminIds) {
      try {
        await tg("sendMessage", { chat_id: adminId, text, reply_markup: markup });
      } catch {
        // An admin who never started the bot can't receive messages.
      }
    }
  }

  // ---------- user screens ----------

  function featuresText(ru) {
    return ru
      ? "Что даёт Pro:\n👻 Режим призрака\n🗑 Сохранение удалённых сообщений\n✏️ История правок\n🚫 Без рекламы в каналах\n🎥 Режим стримера, размытие и другое"
      : "What Pro gives you:\n👻 Ghost mode\n🗑 Deleted messages kept\n✏️ Edit history\n🚫 No ads in channels\n🎥 Streamer mode, blur and more";
  }

  async function mainMenu(user, chatId, messageId) {
    const ru = isRussian(user);
    const device = await storage.getUserDevice(user.id);
    const rows = [];
    let text;
    if (device) {
      const record = await storage.get(device);
      const active = isActive(record?.expiresAt, now);
      text = [
        "💎 HolyGram Pro",
        "",
        `${ru ? "Устройство" : "Device"}: ${formatDeviceCode(device)}`,
        `${ru ? "Подписка" : "Subscription"}: ${active ? (ru ? "✅ " : "✅ ") + formatExpiry(record.expiresAt, now) : (ru ? "нет" : "none")}`,
        "",
        featuresText(ru),
        "",
        ru ? "Pro привязан к iPhone и работает во всех аккаунтах на нём." : "Pro belongs to the iPhone and works in all of its accounts.",
      ].join("\n");
      if (record?.expiresAt !== FOREVER) {
        rows.push([button(active ? (ru ? "💎 Продлить Pro" : "💎 Extend Pro") : (ru ? "💎 Купить Pro" : "💎 Buy Pro"), "buy")]);
      }
      rows.push([button(ru ? "🔄 Обновить" : "🔄 Refresh", "menu")]);
    } else {
      text = [
        "💎 HolyGram Pro",
        "",
        featuresText(ru),
        "",
        ru
          ? "Чтобы купить Pro, откройте HolyGram → Настройки → HolyGram → «Получить HolyGram Pro»: бот узнает код вашего iPhone.\n\nИли пришлите код устройства сообщением (HG-XXXX-XXXX-XXXX)."
          : "To buy Pro, open HolyGram → Settings → HolyGram → “Get HolyGram Pro” so the bot learns your iPhone's code.\n\nOr send the device code as a message (HG-XXXX-XXXX-XXXX).",
      ].join("\n");
    }
    if (isAdmin(user.id)) {
      rows.push([button("🛠 Админ-панель", "admin")]);
    }
    await show(chatId, messageId, text, keyboard(rows));
  }

  async function plansMenu(user, chatId, messageId) {
    const ru = isRussian(user);
    const device = await storage.getUserDevice(user.id);
    if (!device) return mainMenu(user, chatId, messageId);
    const rows = PLANS.map((plan) => {
      const discount = planDiscount(plan);
      const label = ru ? `${plan.months} мес. — ${formatUsd(plan.usd)}` : `${plan.months} mo — ${formatUsd(plan.usd)}`;
      return [button(discount > 0 ? `${label} · −${discount}%` : label, `plan:${plan.id}`)];
    });
    rows.push([button(ru ? "◀️ Назад" : "◀️ Back", "menu")]);
    const best = PLANS[PLANS.length - 1];
    const text = [
      ru ? "💎 Выберите срок HolyGram Pro" : "💎 Choose a HolyGram Pro plan",
      "",
      `${ru ? "Устройство" : "Device"}: ${formatDeviceCode(device)}`,
      "",
      ru
        ? `Чем дольше срок, тем дешевле месяц: за год — ${formatUsd(best.usd / best.months)} в месяц вместо ${formatUsd(PLANS[0].usd)}.`
        : `Longer plans cost less per month: a year is ${formatUsd(best.usd / best.months)}/mo instead of ${formatUsd(PLANS[0].usd)}.`,
      ru ? "Если подписка уже есть, срок добавится к ней." : "If you already have Pro, the time is added on top.",
    ].join("\n");
    await show(chatId, messageId, text, keyboard(rows));
  }

  async function methodMenu(user, chatId, messageId, plan) {
    const ru = isRussian(user);
    const device = await storage.getUserDevice(user.id);
    if (!device) return mainMenu(user, chatId, messageId);
    const rows = [[button(`⭐ Telegram Stars — ${plan.stars} ⭐`, `pay:stars:${plan.id}`)]];
    if (crypto) {
      rows.push([button(ru ? `🪙 Криптовалюта (CryptoBot) — ${formatUsd(plan.usd)}` : `🪙 Crypto (CryptoBot) — ${formatUsd(plan.usd)}`, `pay:crypto:${plan.id}`)]);
    }
    rows.push([button(ru ? "◀️ Назад" : "◀️ Back", "buy")]);
    const text = [
      ru ? `💎 HolyGram Pro на ${plan.months} мес. — ${formatUsd(plan.usd)}` : `💎 HolyGram Pro for ${plan.months} mo — ${formatUsd(plan.usd)}`,
      `${ru ? "Устройство" : "Device"}: ${formatDeviceCode(device)}`,
      "",
      ru ? "Выберите способ оплаты:" : "Choose how to pay:",
      ru ? "⭐ Stars — картой, Apple Pay или Google Pay прямо в Telegram" : "⭐ Stars — card, Apple Pay or Google Pay inside Telegram",
      crypto ? (ru ? "🪙 CryptoBot — USDT, TON, BTC и другие" : "🪙 CryptoBot — USDT, TON, BTC and more") : null,
    ].filter((line) => line !== null).join("\n");
    await show(chatId, messageId, text, keyboard(rows));
  }

  async function sendStarsInvoice(user, chatId, plan) {
    const ru = isRussian(user);
    const device = await storage.getUserDevice(user.id);
    if (!device) return mainMenu(user, chatId, null);
    await tg("sendInvoice", {
      chat_id: chatId,
      title: ru ? `HolyGram Pro — ${plan.months} мес.` : `HolyGram Pro — ${plan.months} mo`,
      description: ru
        ? `Подписка для iPhone ${formatDeviceCode(device)}. Активируется сразу после оплаты.`
        : `Subscription for iPhone ${formatDeviceCode(device)}. Activates right after payment.`,
      payload: JSON.stringify({ d: device, p: plan.id }),
      currency: "XTR",
      prices: [{ label: `HolyGram Pro ${plan.months}m`, amount: plan.stars }],
      provider_token: "",
    });
  }

  async function sendCryptoInvoice(user, chatId, messageId, plan) {
    const ru = isRussian(user);
    const device = await storage.getUserDevice(user.id);
    if (!device || !crypto) return mainMenu(user, chatId, messageId);
    const invoice = await crypto("createInvoice", {
      currency_type: "fiat",
      fiat: "USD",
      amount: plan.usd.toFixed(2),
      accepted_assets: CRYPTO_ASSETS,
      description: `HolyGram Pro — ${plan.months} mo, ${formatDeviceCode(device)}`,
      payload: JSON.stringify({ d: device, p: plan.id, u: user.id, c: chatId }),
      paid_btn_name: "openBot",
      paid_btn_url: `https://t.me/${botUsername}`,
      allow_comments: false,
      allow_anonymous: false,
      expires_in: 3600,
    });
    const url = invoice?.bot_invoice_url || invoice?.mini_app_invoice_url || invoice?.pay_url;
    if (!url) {
      await show(chatId, messageId, ru ? "Не удалось создать счёт, попробуйте позже." : "Couldn't create the invoice, try again later.", keyboard([[button(ru ? "◀️ Назад" : "◀️ Back", "buy")]]));
      return;
    }
    await show(chatId, messageId, [
      ru ? `🪙 Счёт на ${formatUsd(plan.usd)} создан` : `🪙 Invoice for ${formatUsd(plan.usd)} created`,
      "",
      ru ? "Оплатите его в @CryptoBot в течение часа. Pro активируется автоматически, сообщение придёт сюда." : "Pay it in @CryptoBot within an hour. Pro activates automatically and you'll get a message here.",
    ].join("\n"), keyboard([[urlButton(ru ? `🪙 Оплатить ${formatUsd(plan.usd)}` : `🪙 Pay ${formatUsd(plan.usd)}`, url)], [button(ru ? "◀️ Назад" : "◀️ Back", `plan:${plan.id}`)]]));
  }

  /** Grants a paid plan once per payment id and tells the buyer and the admins. */
  async function completePayment({ paymentId, device, plan, buyer, buyerChatId, method, amountText }) {
    const isNew = await storage.addPayment(paymentId, { device, plan: plan.id, method, amount: amountText, buyer: buyer?.id ?? null, at: now });
    if (!isNew) return;
    const record = await grant(storage, { device, seconds: plan.months * MONTH_SECONDS, note: null, grantedBy: `${method}:${paymentId}`, now });
    const ru = buyer ? isRussian(buyer) : true;
    if (buyerChatId) {
      await tg("sendMessage", {
        chat_id: buyerChatId,
        text: ru
          ? `✅ Оплата получена! HolyGram Pro активен ${formatExpiry(record.expiresAt, now)}.\n\nОткройте HolyGram → Настройки → HolyGram, чтобы Pro включился сразу.`
          : `✅ Payment received! HolyGram Pro is active (${formatExpiry(record.expiresAt, now)}).\n\nOpen HolyGram → Settings → HolyGram to turn it on right away.`,
        reply_markup: keyboard([[button(ru ? "💎 Моя подписка" : "💎 My subscription", "menu")]]),
      });
    }
    await notifyAdmins([
      `💰 Оплата ${amountText} (${method === "stars" ? "Stars" : "CryptoBot"})`,
      `${plan.months} мес. · ${formatDeviceCode(device)}`,
      `От: ${buyer ? userLabel(buyer) : "?"}`,
      `Pro: ${formatExpiry(record.expiresAt, now)}`,
    ].join("\n"));
  }

  // ---------- admin screens ----------

  async function adminPanel(chatId, messageId) {
    const counts = await storage.counts(now);
    const payments = await storage.listPayments();
    const usd = payments.filter((p) => p.method === "crypto").reduce((sum, p) => sum + (planById(p.plan)?.usd || 0), 0);
    const stars = payments.filter((p) => p.method === "stars").reduce((sum, p) => sum + (planById(p.plan)?.stars || 0), 0);
    await show(chatId, messageId, [
      "🛠 Админ-панель HolyGram Pro",
      "",
      `Активных подписок: ${counts.active} (навсегда: ${counts.forever})`,
      `Оплат: ${payments.length} — ${formatUsd(usd)} в крипте и ${stars} ⭐`,
    ].join("\n"), keyboard([
      [button("➕ Выдать Pro", "a:grant"), button("📋 Подписки", "a:list")],
      [button("💰 Продажи", "a:sales"), button("🎚 Функции", "a:flags")],
      [button("◀️ Меню", "menu")],
    ]));
  }

  async function deviceCard(chatId, messageId, device, notice) {
    const record = await storage.get(device);
    await show(chatId, messageId, [
      notice || null,
      `📱 ${formatDeviceCode(device)}`,
      `Подписка: ${formatExpiry(record?.expiresAt, now)}`,
      record?.note ? `Заметка: ${record.note}` : null,
      record?.requestedBy ? `Покупатель/запрос: id ${record.requestedBy}` : null,
    ].filter(Boolean).join("\n"), keyboard([
      [button("+1 мес", `g:${device}:30`), button("+3 мес", `g:${device}:90`), button("+1 год", `g:${device}:365`)],
      [button("♾ Навсегда", `g:${device}:f`), button("🚫 Отозвать", `r:${device}`)],
      [button("◀️ Админ-панель", "admin")],
    ]));
  }

  async function adminList(chatId, messageId) {
    const records = await storage.listActive(now, 40);
    const text = records.length === 0
      ? "Активных подписок нет"
      : "📋 Активные подписки\n\n" + records.map((r) => `${formatDeviceCode(r.device)} — ${formatExpiry(r.expiresAt, now)}${r.note ? ` · ${r.note}` : ""}`).join("\n");
    await show(chatId, messageId, text, keyboard([[button("◀️ Админ-панель", "admin")]]));
  }

  async function adminSales(chatId, messageId) {
    const payments = (await storage.listPayments()).sort((a, b) => b.at - a.at);
    const lines = payments.slice(0, 20).map((p) => {
      const date = new Date(p.at * 1000).toISOString().slice(0, 10);
      return `${date} · ${p.amount} · ${planById(p.plan)?.months ?? "?"} мес · ${formatDeviceCode(p.device)}`;
    });
    await show(chatId, messageId, payments.length === 0 ? "Продаж пока нет" : "💰 Последние продажи\n\n" + lines.join("\n"), keyboard([[button("◀️ Админ-панель", "admin")]]));
  }

  async function adminFlags(chatId, messageId) {
    const disabled = await storage.getDisabledFeatures();
    const rows = Object.entries(SWITCHABLE_FEATURES).map(([name, title]) => [
      button(`${disabled.includes(name) ? "⛔️" : "✅"} ${title}`, `f:${name}`),
    ]);
    rows.push([button("◀️ Админ-панель", "admin")]);
    await show(chatId, messageId, [
      "🎚 Функции у всех пользователей",
      "",
      "Нажмите, чтобы выключить или включить. Приложения применят изменения в течение 6 часов или при открытии настроек HolyGram.",
    ].join("\n"), keyboard(rows));
  }

  // ---------- updates ----------

  async function handleMessage(message) {
    const user = message.from;
    const chatId = message.chat.id;
    const text = (message.text || "").trim();

    if (message.successful_payment) {
      const payment = message.successful_payment;
      let info;
      try {
        info = JSON.parse(payment.invoice_payload);
      } catch {
        return;
      }
      const plan = planById(info.p);
      const device = normalizeDeviceCode(info.d);
      if (!plan || !device) return;
      await completePayment({
        paymentId: `stars:${payment.telegram_payment_charge_id}`,
        device, plan, buyer: user, buyerChatId: chatId, method: "stars", amountText: `${payment.total_amount} ⭐`,
      });
      return;
    }

    const [rawCommand, ...args] = text.split(/\s+/);
    const command = rawCommand.startsWith("/") ? rawCommand.split("@")[0].toLowerCase() : null;
    const admin = isAdmin(user.id);

    if (command === "/start") {
      const device = normalizeDeviceCode(args[0]);
      if (device) {
        await storage.setUserDevice(user.id, device);
        const record = await storage.get(device);
        if (!record) {
          await storage.put({ device, expiresAt: 0, note: null, grantedBy: null, requestedBy: user.id, updatedAt: now });
        } else if (!record.requestedBy) {
          await storage.put({ ...record, requestedBy: user.id });
        }
      }
      await storage.setState(user.id, null);
      return mainMenu(user, chatId, null);
    }

    if (admin) {
      const state = await storage.getState(user.id);
      const replyCode = DEVICE_PATTERN.exec(message.reply_to_message?.text || "")?.[0];
      switch (command) {
        case "/admin":
          await storage.setState(user.id, null);
          return adminPanel(chatId, null);
        case "/grant": {
          const device = normalizeDeviceCode(replyCode) || normalizeDeviceCode(args.shift());
          const seconds = parseDuration(args.shift());
          if (!device || seconds === null) {
            return tg("sendMessage", { chat_id: chatId, text: "Формат: /grant <код> <срок> [заметка]\nСрок: 7d, 30d, 3m, 1y, forever" });
          }
          const record = await grant(storage, { device, seconds, note: args.join(" ") || null, grantedBy: user.id, now });
          await notifyBuyer(record);
          return deviceCard(chatId, null, device, `✅ Выдано: ${formatExpiry(record.expiresAt, now)}`);
        }
        case "/revoke":
        case "/info": {
          const device = normalizeDeviceCode(replyCode) || normalizeDeviceCode(args[0]);
          if (!device) return tg("sendMessage", { chat_id: chatId, text: `Формат: ${command} <код устройства>` });
          if (command === "/revoke") {
            const done = await revoke(storage, { device, now });
            return deviceCard(chatId, null, device, done ? "🚫 Pro отозван" : "Подписки не было");
          }
          return deviceCard(chatId, null, device);
        }
        default:
          break;
      }
      // A device code sent as text opens its card (also after "➕ Выдать Pro").
      const typed = normalizeDeviceCode(DEVICE_PATTERN.exec(text)?.[0]);
      if (typed && (state === "grant_code" || !command)) {
        await storage.setState(user.id, null);
        return deviceCard(chatId, null, typed);
      }
      if (state === "grant_code") {
        return tg("sendMessage", { chat_id: chatId, text: "Это не код устройства. Пришлите код вида HG-XXXX-XXXX-XXXX или нажмите /admin." });
      }
    } else {
      const typed = normalizeDeviceCode(DEVICE_PATTERN.exec(text)?.[0]);
      if (typed) {
        await storage.setUserDevice(user.id, typed);
        return mainMenu(user, chatId, null);
      }
    }

    return mainMenu(user, chatId, null);
  }

  async function notifyBuyer(record) {
    if (!record.requestedBy || isAdmin(record.requestedBy)) return;
    try {
      await tg("sendMessage", {
        chat_id: record.requestedBy,
        text: `✅ HolyGram Pro активирован: ${formatExpiry(record.expiresAt, now)}.\nОткройте HolyGram → Настройки → HolyGram, чтобы применить сразу.`,
      });
    } catch {
      // The user may have blocked the bot.
    }
  }

  async function handleCallback(query) {
    const user = query.from;
    const chatId = query.message?.chat?.id ?? user.id;
    const messageId = query.message?.message_id ?? null;
    const data = query.data || "";
    await tg("answerCallbackQuery", { callback_query_id: query.id }).catch(() => {});

    if (data === "menu") return mainMenu(user, chatId, messageId);
    if (data === "buy") return plansMenu(user, chatId, messageId);
    if (data.startsWith("plan:")) {
      const plan = planById(data.slice(5));
      return plan ? methodMenu(user, chatId, messageId, plan) : plansMenu(user, chatId, messageId);
    }
    if (data.startsWith("pay:")) {
      const [, method, planId] = data.split(":");
      const plan = planById(planId);
      if (!plan) return plansMenu(user, chatId, messageId);
      if (method === "stars") return sendStarsInvoice(user, chatId, plan);
      if (method === "crypto") return sendCryptoInvoice(user, chatId, messageId, plan);
      return;
    }

    if (!isAdmin(user.id)) return;

    if (data === "admin") {
      await storage.setState(user.id, null);
      return adminPanel(chatId, messageId);
    }
    if (data === "a:grant") {
      await storage.setState(user.id, "grant_code");
      return show(chatId, messageId, "➕ Выдать Pro\n\nПришлите код устройства (HG-XXXX-XXXX-XXXX). Пользователь видит его в HolyGram: Настройки → HolyGram → HolyGram Pro.", keyboard([[button("◀️ Отмена", "admin")]]));
    }
    if (data === "a:list") return adminList(chatId, messageId);
    if (data === "a:sales") return adminSales(chatId, messageId);
    if (data === "a:flags") return adminFlags(chatId, messageId);
    if (data.startsWith("f:")) {
      const name = data.slice(2);
      if (name in SWITCHABLE_FEATURES) {
        const disabled = new Set(await storage.getDisabledFeatures());
        if (disabled.has(name)) disabled.delete(name); else disabled.add(name);
        await storage.setDisabledFeatures([...disabled]);
      }
      return adminFlags(chatId, messageId);
    }
    if (data.startsWith("g:")) {
      const [, code, amount] = data.split(":");
      const device = normalizeDeviceCode(code);
      if (!device) return;
      const seconds = amount === "f" ? FOREVER : Number(amount) * 86400;
      const record = await grant(storage, { device, seconds, note: null, grantedBy: user.id, now });
      await notifyBuyer(record);
      return deviceCard(chatId, messageId, device, `✅ Выдано: ${formatExpiry(record.expiresAt, now)}`);
    }
    if (data.startsWith("r:")) {
      const device = normalizeDeviceCode(data.slice(2));
      if (!device) return;
      const done = await revoke(storage, { device, now });
      return deviceCard(chatId, messageId, device, done ? "🚫 Pro отозван" : "Подписки не было");
    }
  }

  async function handlePreCheckout(query) {
    let ok = false;
    try {
      const info = JSON.parse(query.invoice_payload);
      const plan = planById(info.p);
      ok = Boolean(plan && normalizeDeviceCode(info.d) && query.currency === "XTR" && query.total_amount === plan.stars);
    } catch {
      ok = false;
    }
    await tg("answerPreCheckoutQuery", ok
      ? { pre_checkout_query_id: query.id, ok: true }
      : { pre_checkout_query_id: query.id, ok: false, error_message: "Invoice is out of date, please start again." });
  }

  return {
    async handleUpdate(update) {
      if (update.pre_checkout_query) return handlePreCheckout(update.pre_checkout_query);
      if (update.callback_query) return handleCallback(update.callback_query);
      const message = update.message;
      if (message?.from && message.chat?.type === "private") return handleMessage(message);
    },

    /** Crypto Pay webhook "invoice_paid". */
    async handleCryptoPaid(invoice) {
      if (invoice?.status !== "paid") return;
      let info;
      try {
        info = JSON.parse(invoice.payload);
      } catch {
        return;
      }
      const plan = planById(info.p);
      const device = normalizeDeviceCode(info.d);
      if (!plan || !device) return;
      const paid = invoice.paid_amount && invoice.paid_asset ? `${invoice.paid_amount} ${invoice.paid_asset}` : formatUsd(plan.usd);
      await completePayment({
        paymentId: `crypto:${invoice.invoice_id}`,
        device, plan,
        buyer: info.u ? { id: info.u, language_code: "ru" } : null,
        buyerChatId: info.c || info.u || null,
        method: "crypto",
        amountText: `${formatUsd(plan.usd)} (${paid})`,
      });
    },
  };
}
