# HolyGram

Неофициальный клиент Telegram для iOS (основа — [Swiftgram](https://github.com/Swiftgram/Telegram-iOS), форк официального Telegram-iOS). Android-версия — второстепенная.

## Сборка iOS

Сборка идёт в GitHub Actions (`.github/workflows/ios.yml`) на macOS 27 + Xcode 27.1.

1. Получите `api_id` и `api_hash` на https://my.telegram.org/apps
2. Добавьте их в **Settings → Secrets and variables → Actions** как `API_ID` и `API_HASH`.
3. **Actions → HolyGram iOS → Run workflow.**
4. Готовый неподписанный `.ipa` появится в **Releases** (и в артефактах запуска).

## Установка на iPhone

`.ipa` не подписан. Установите его через [Sideloadly](https://sideloadly.io) или [AltStore](https://altstore.io) — они подпишут приложение вашим Apple ID. С бесплатным Apple ID подпись действует 7 дней.

## Лицензия

GPL v2, как у Telegram-iOS и Swiftgram. При публичном распространении исходный код должен оставаться открытым.
