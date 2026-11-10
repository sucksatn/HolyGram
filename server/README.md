# HolyGram Pro — сервер подписок и бот-админка

Cloudflare Worker + база D1. На обычной нагрузке бесплатно (лимит Cloudflare — 100 000 запросов в день).

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

Вместо `user_id` можно переслать боту сообщение пользователя и ответить на него `/grant 30d`. Свой ID пользователь видит в HolyGram: Настройки → HolyGram Pro. Обычные пользователи на `/start` получают свой ID и статус подписки.

Продление складывается: если подписка ещё идёт, срок добавляется к её концу. После отзыва приложение перестаёт считать подписку активной в течение 3 дней (столько живёт подписанный ответ без связи с сервером).

## Установка (один раз, ~15 минут, нужен компьютер с Node.js 20+)

1. **Бот.** В Telegram откройте @BotFather → `/newbot`, сохраните токен.
2. **Свой ID.** Напишите @userinfobot — он пришлёт ваш числовой ID (это и есть `ADMIN_IDS`).
3. **Cloudflare.** Зарегистрируйтесь на https://dash.cloudflare.com (бесплатно).
4. В папке `server`:
   ```sh
   npx wrangler login
   npx wrangler d1 create holygram-pro          # вставьте database_id в wrangler.toml
   npx wrangler d1 execute holygram-pro --remote --file=schema.sql
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
