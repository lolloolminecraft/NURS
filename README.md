# NURS

Универсальный проект для автоматических уведомлений. Первый модуль — отслеживание подтверждённого публичного jailbreak для PS4 firmware 14.00.

## Архитектура
- GitHub Actions выполняет проверку публичных GitHub Releases каждый час и поддерживает файл `docs/status.json`.
- Найденное по ключевым словам не равно подтверждённому jailbreak: оно получает статус `candidate` и **не отправляется** в WhatsApp.
- Отдельная проверка первоисточников должна установить `state: released` с подтверждённой инструкцией, ссылкой на скачивание и, если существует, актуальным видео. После этого GitHub Actions попробует отправить сообщение через WhatsApp Cloud API.
- В `docs/index.html` доступна информация о подтверждённом релизе, дате обнаружения и времени запроса в Meta.

## Первый запуск
1. Для бесплатного GitHub Pages на GitHub Free откройте `Settings → General → Danger Zone → Change repository visibility → Public`. Код не содержит токенов, но перед публикацией проверьте репозиторий.
2. Откройте `Settings → Pages → Build and deployment → Source → GitHub Actions`.
3. Откройте `Actions → NURS Release Watch → Run workflow` для первой проверки.
4. Для уведомлений откройте `Settings → Secrets and variables → Actions → New repository secret` и установите `WHATSAPP_TOKEN`, `WHATSAPP_PHONE_ID`, `WHATSAPP_TO`. Никогда не помещайте токен в код или открытые сообщения.
5. В WhatsApp Manager создайте и дождитесь одобрения utility-шаблона `nurs_ps4_release` на русском языке. Текст должен иметь три переменные в порядке: ссылка на скачивание, ссылка на страницу релиза/инструкции, дата и время обнаружения (UTC).
6. При необходимости создайте Variables: `WHATSAPP_TEMPLATE` = `nurs_ps4_release`, `WHATSAPP_TEMPLATE_LANG` = `ru`, `META_GRAPH_VERSION` = версия Graph API, поддерживаемая Meta, `NURS_SITE_URL` = опубликованная страница GitHub Pages.
7. Проверьте тестовое сообщение `hello_world` в Meta API Setup. Для долгосрочной работы временный токен необходимо заменить на системный токен.

## Ограничения
GitHub-сканер проверяет только репозитории в `config.json`, а не весь интернет. Он не может достоверно подтвердить работоспособность релиза без независимой проверки. Автоматическое изменение статуса на `released` делает только внешняя доверенная проверка. Инструкции и видео не выдумываются.

`submitted_at` означает принятие отправки WhatsApp API, **не подтверждённую доставку**; для статуса доставки нужен webhook. Meta может взимать плату за производственные уведомления. GitHub Actions по расписанию может запускаться с задержкой.

## Тестирование
```bash
python -m unittest discover -s tests
python monitor.py
```
