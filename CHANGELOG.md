# Changelog / История изменений

## [1.0.10] — 2026-10-25

- Added log search, error filtering, pause/resume scrolling, source links, and diagnostic report copying.
  Добавлены поиск и фильтр ошибок в логах, пауза прокрутки, переход к исходникам и копирование диагностического отчёта.
- Added one-click DevTools access for the selected running Flutter session.
  Добавлена кнопка открытия DevTools выбранной работающей Flutter-сессии.
- Extended local MCP control with project/device discovery, launch, Rerun, deep links, and screenshots.
  Локальное управление MCP расширено списками проектов/устройств, запуском, Rerun, deep links и скриншотами.

- Added Rerun for the selected active session and a Play icon with a small repeat arrow.
  Добавлены Rerun выбранной активной сессии и иконка Play с маленькой круговой стрелкой.

## [1.0.9] — 2026-10-24

- Added local MCP tools for existing Flutter sessions: list, state, logs, Hot Reload, Hot Restart, and Stop.
  Добавлены локальные MCP-инструменты для запущенных Flutter-сессий: список, состояние, логи, Hot Reload, Hot Restart и Stop.
- Commands target an explicit session and launch; retries use request IDs to prevent duplicate execution.
  Команды адресованы конкретной сессии и запуску; идентификаторы запросов защищают от повторного выполнения.

## [1.0.8] — 2026-10-24

- Allow Debug, Profile, and Release on Android devices and emulators, and select the next launch mode during an active session.
  Debug, Profile и Release доступны для Android-устройств и эмуляторов; режим следующего запуска можно выбрать во время работающей сессии.
- Cache the device list between launches, refresh it in the background, and verify cached devices before starting a session.
  Список устройств сохраняется между запусками, обновляется в фоне и проверяется перед запуском сессии.
- Show device discovery immediately after Run, with Android build/install progress and specific installation failure messages.
  После Run сразу отображается поиск устройства, затем этапы сборки и установки Android и конкретные причины отказа установки.

## [1.0.5] — 2026-10-16

- Redesigned settings and device picker, with grouped controls and a panel placement preview.
  Обновлены настройки и выбор устройств: сгруппированные элементы управления и предпросмотр расположения панели.
- Device discovery refreshes when the picker opens and waits for an ongoing scan.
  Список устройств обновляется при открытии выбора и дожидается текущего поиска.
- Added optional hide/show for the unbound panel from the menu bar; right-click or Control-click opens settings.
  Добавлено скрытие и показ непривязанной панели из строки меню; правое нажатие или Control-click открывает настройки.

## [1.0.4] — 2026-10-12

- Added automatic and manual update checks with DMG size and SHA-256 verification.
  Добавлены автоматическая и ручная проверка обновлений с проверкой размера DMG и SHA-256.

## [1.0.3] — 2026-10-12

- Keep Hot Reload and Hot Restart visible on narrow panels by reducing button widths and spacing.
  Hot Reload и Hot Restart остаются на узкой панели: уменьшаются ширина кнопок и интервалы вместо скрытия действий в меню.

## [1.0.2] — 2026-10-07

- Renamed Fluttios to **SimFlutDock** across the app, build targets, Xcode project and release downloads.
  Fluttios переименован в **SimFlutDock**: интерфейс, сборка, проект Xcode и загрузки релиза.
- Existing projects and preferences are preserved using the original app identifiers and storage paths.
  Сохранённые проекты и настройки доступны через прежние идентификаторы и пути хранения.

## [1.0.1] — 2026-10-07

- Manual panel attachment now works independently of the selected Flutter device.
  Ручная привязка панели работает независимо от выбранного устройства Flutter.
- Centered the panel settings icon and updated panel position controls.
  Исправлено положение иконки настроек и обновлены элементы управления положением панели.
- Shortened both READMEs to installation, key features and quick start.
  README на двух языках сокращены до установки, основных функций и быстрого старта.

## [1.0.0] — 2026-10-07

First public release of Fluttios. / Первый публичный релиз Fluttios.

- Native macOS panel with automatic Simulator / Device Hub window attachment and floating mode.
  Нативная панель macOS с привязкой к Simulator / Device Hub и свободным положением.
- Independent Flutter sessions, Run, Hot Reload, Hot Restart, Stop, progress and per-project logs.
  Независимые Flutter-сессии, запуск, перезагрузка, перезапуск, остановка, этапы и логи проекта.
- Saved projects, SDK/FVM discovery, device search, pinned simulators and launch modes.
  Сохранённые проекты, поиск SDK/FVM, поиск устройств, закрепление симуляторов и режимы запуска.
- Saved deep links, project/data folders and per-app simulator permission reset.
  Сохранённые ссылки, папки проекта/данных и сброс разрешений приложения в симуляторе.
- English/Russian UI, automatic launch helper, light/dark appearance and visible app version.
  Английский/русский интерфейс, помощник автозапуска, светлая/тёмная темы и версия в настройках.
- Bilingual documentation and screenshots with fictional demo data.
  Документация на двух языках и скриншоты с вымышленными данными.

- Universal DMG download, SHA-256 checksum and automated GitHub release packaging.
  Универсальный DMG, контрольная сумма SHA-256 и автоматическая упаковка релиза на GitHub.

[1.0.0]: https://github.com/Shishani58/Fluttios/tree/v1.0.0

[1.0.1]: https://github.com/Shishani58/Fluttios/tree/v1.0.1

[1.0.2]: https://github.com/Shishani58/Fluttios/tree/v1.0.2

[1.0.3]: https://github.com/Shishani58/Fluttios/tree/v1.0.3

[1.0.4]: https://github.com/Shishani58/Fluttios/tree/v1.0.4

[1.0.5]: https://github.com/Shishani58/Fluttios/tree/v1.0.5

[1.0.8]: https://github.com/Shishani58/Fluttios/tree/v1.0.8

[1.0.9]: https://github.com/Shishani58/Fluttios/tree/v1.0.9

[1.0.10]: https://github.com/Shishani58/Fluttios/tree/v1.0.10
