# HolyGram Pro — сервер подписок и бот-админка

Cloudflare Worker + Workers KV. Бесплатно: 100 000 запросов и 100 000 чтений KV в день.

Рабочий сервер: https://holygram-pro.holygram.workers.dev, бот: @HolygramBot.

- `GET /v1/status?user_id=…` — приложение спрашивает статус Pro. Ответ подписан ключом Ed25519, приложение проверяет подпись встроенным публичным ключом, так что ответ нельзя подделать прокси или правкой настроек.
- `POST /bot/<WEBHOOK_SECRET>` — webhook Telegram-бота. Команды управления подписками принимаются только от `ADMIN_IDS`.

## Команды бота

| Команда | Что делает |
|---|---|
| `/grant <user_id> <срок> [заметка]` | Выдать или продлить Pro. Срок: `7d`, `30d`, `3m`, `1y`, `forever` |
| `/revoke <user_id>` | Забрать Pro |
| `/info <user_id>` | Статус подписки |
| `/list [N]` | Активные подписки |
| `/stats` | Сколько подписчиков |
| `/disable <функция>` | Выключить функцию у **всех** пользователей: `ghost`, `selfdestruct`, `deleted`, `edits` или `all` |
| `/enable <функция>` | Включить обратно |
| `/flags` | Что сейчас выключено |

`/disable` — аварийный выключатель. Если Telegram потребует убрать режим призрака или сохранение исчезающих медиа (по их правилам на исправление даётся 10 дней), выполните `/disable ghost` и `/disable selfdestruct`: функции пропадут у всех при следующей проверке (до 6 часов или при открытии настроек HolyGram), без обновления в App Store.

Вместо `user_id` можно переслать боту сообщение пользователя и ответить на него `/grant 30d`. Свой ID пользователь видит в HolyGram: Настройки → HolyGram Pro. Обычные пользователи на `/start` получают свой ID и статус подписки.

Продление складывается: если подписка ещё идёт, срок добавляется к её концу. После отзыва приложение перестаёт считать подписку активной в течение 3 дней (столько живёт подписанный ответ без связи с сервером).

## Установка (один раз, ~15 минут, нужен компьютер с Node.js 20+)

1. **Бот.** В Telegram откройте @BotFather → `/newbot`, сохраните токен.
2. **Свой ID.** Напишите @userinfobot — он пришлёт ваш числовой ID (это и есть `ADMIN_IDS`).
3. **Cloudflare.** Зарегистрируйтесь на https://dash.cloudflare.com (бесплатно).
4. В папке `server`:
   ```sh
   npx wrangler login
   npx wrangler kv namespace create SUBS        # вставьте id в wrangler.toml
   node tools/genkey.mjs                        # выдаст SIGNING_KEY и публичный ключ
   npx wrangler secret put SIGNING_KEY          # вставьте SIGNING_KEY
   npx wrangler secret put BOT_TOKEN            # токен от BotFather
   npx wrangler secret put ADMIN_IDS            # ваш ID (несколько — через запятую)
   npx wrangler secret put WEBHOOK_SECRET       # любая длинная случайная строка
   npx wrangler deploy                          # покажет адрес вида https://holygram-pro.<имя>.workers.dev
   ```
5. **Подключите бота к серверу** (подставьте токен, адрес и WEBHOOK_SECRET):
   ```
   https://api.telegram.org/bot<BOT_TOKEN>/setWebhook?url=https://holygram-pro.<имя>.workers.dev/bot/<WEBHOOK_SECRET>&secret_token=<WEBHOOK_SECRET>
   ```
   Откройте ссылку в браузере — должно быть `"ok":true`.
6. **Пришлите разработчику приложения** адрес сервера и **публичный** ключ (вторая строка из `genkey`). Их можно показывать кому угодно. `SIGNING_KEY`, токен бота и `WEBHOOK_SECRET` никому не передавайте.

## Тесты

```sh
npm test
```
