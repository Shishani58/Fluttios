<div align="center">
  <img src="Resources/AppIcon.png" width="96" alt="SimFlutDock">
  <h1>SimFlutDock</h1>
  <p>Управляйте Flutter прямо рядом с симулятором.</p>
  <p><a href="README.en.md">English</a> · <a href="CHANGELOG.md">История изменений</a> · <a href="LICENSE">MIT</a></p>
  <img src="docs/images/panel.png" width="630" alt="Панель SimFlutDock с кнопками Run, Reload, Restart и Stop">
</div>

Нативная утилита macOS: запускайте Flutter-проекты, делайте Hot Reload и читайте логи без перехода в Terminal или IDE.

## Установка

[**Скачать SimFlutDock 1.0.9 (.dmg)**](https://github.com/Shishani58/Fluttios/releases/download/v1.0.9/SimFlutDock-1.0.9.dmg)

Нужны **macOS 14+**, **Flutter SDK** и полный **Xcode**. Поддерживаются Apple Silicon и Intel. Откройте DMG и перетащите приложение в **Applications**.

Сборка не нотарифицирована Apple; при блокировке первого запуска следуйте [инструкции Apple](https://support.apple.com/ru-ru/102445).

### Обновления

Обновляйтесь через **Настройки → Общие → Обновления приложения**. Перед установкой приложение проверяет SHA-256 и подпись. Работающие Flutter-сессии останавливаются с подтверждением.

## Главное

- **Run, Hot Reload, Hot Restart и Stop** — отдельная сессия для каждой пары «проект + устройство». Переключение устройства меняет управляемую сессию, сохраняя остальные запуски.
- Панель рядом с **Simulator / Device Hub** или в свободном положении.
- Выбор устройств и режимов запуска, поддержка **FVM**.
- Логи, сохранённые deep links, быстрый доступ к папкам проекта и приложения.
- Русский и английский интерфейс, светлая и тёмная темы.

## Быстрый старт

1. Откройте SimFlutDock → иконка в строке меню → **Настройки → Проекты → Открыть проект**. Выберите папку с `pubspec.yaml`.
2. Выберите устройство и нажмите **Run**. После изменения Dart-кода используйте **Reload**, для сброса состояния — **Restart**.
3. Для привязки панели разрешите SimFlutDock в **Настройках системы → Конфиденциальность и безопасность → Универсальный доступ**.

Hot Reload и Hot Restart работают в Debug. После изменения нативного кода или плагинов используйте **Stop → Run**.

### Управление через ИИ (MCP)

Список сессий, состояние, логи, **Hot Reload**, **Hot Restart** и **Stop** доступны ИИ-клиентам. Откройте SimFlutDock и запустите Flutter-сессию, затем подключите Codex (нужен Python 3):

```bash
codex mcp add fluttios -- python3 /Applications/SimFlutDock.app/Contents/Resources/fluttios-mcp.py
```

В конфигурации сервера Codex задайте `tool_timeout_sec = 120`. [Другие клиенты и описание инструментов](docs/mcp.md).

## Сборка из исходников

```bash
git clone https://github.com/Shishani58/Fluttios.git
cd Fluttios
APP_OUTPUT=/Applications/SimFlutDock.app ./scripts/build-app.sh
open /Applications/SimFlutDock.app
```

Команда обновляет одну установленную копию в Applications. Для отдельной сборки без установки используйте `./scripts/build-app.sh`; результат в `dist` не нужно устанавливать повторно. Для сборки DMG: `./scripts/build-dmg.sh`.

Проверки, структура исходников и интеграционные тесты описаны в [Contributing](CONTRIBUTING.md).
