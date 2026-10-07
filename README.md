<div align="center">
  <img src="Resources/AppIcon.png" width="96" alt="Fluttios">
  <h1>Fluttios</h1>
  <p>Управляйте Flutter прямо рядом с симулятором.</p>
  <p><a href="README.en.md">English</a> · <a href="CHANGELOG.md">История изменений</a> · <a href="LICENSE">MIT</a></p>
  <img src="docs/images/panel.png" width="630" alt="Панель Fluttios с кнопками Run, Reload, Restart и Stop">
</div>

Нативная утилита macOS: запускайте Flutter-проекты, делайте Hot Reload и читайте логи без перехода в Terminal или IDE.

## Установка

[**Скачать Fluttios 1.0.1 (.dmg)**](https://github.com/Shishani58/Fluttios/releases/download/v1.0.1/Fluttios-1.0.1.dmg)

Нужны **macOS 14+**, **Flutter SDK** и полный **Xcode**. Поддерживаются Apple Silicon и Intel. Откройте DMG и перетащите приложение в **Applications**.

Сборка не нотарифицирована Apple; при блокировке первого запуска следуйте [инструкции Apple](https://support.apple.com/ru-ru/102445).

## Главное

- **Run, Hot Reload, Hot Restart и Stop** — отдельная сессия для каждого проекта.
- Панель рядом с **Simulator / Device Hub** или в свободном положении.
- Выбор устройств и режимов запуска, поддержка **FVM**.
- Логи, сохранённые deep links, быстрый доступ к папкам проекта и приложения.
- Русский и английский интерфейс, светлая и тёмная темы.

## Быстрый старт

1. Откройте Fluttios → иконка в строке меню → **Настройки → Проекты → Открыть проект**. Выберите папку с `pubspec.yaml`.
2. Выберите устройство и нажмите **Run**. После изменения Dart-кода используйте **Reload**, для сброса состояния — **Restart**.
3. Для привязки панели разрешите Fluttios в **Настройках системы → Конфиденциальность и безопасность → Универсальный доступ**.

Hot Reload и Hot Restart работают в Debug. После изменения нативного кода или плагинов используйте **Stop → Run**.

## Сборка из исходников

```bash
git clone https://github.com/Shishani58/Fluttios.git
cd Fluttios
./scripts/build-app.sh
open dist/Fluttios.app
```

Для сборки DMG: `./scripts/build-dmg.sh`.
