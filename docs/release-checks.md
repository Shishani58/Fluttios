# Fluttios 1.0.0 — release checks / Проверки релиза

Date / Дата: 2026-10-07.

| Check / Проверка | Result / Результат |
| :--- | :--- |
| SwiftPM suite | 74 tests: 73 passed, 1 opt-in integration skipped, 0 failures. / 73 успешно, 1 интеграционный пропущен, 0 ошибок. |
| Renamed fictional device fixture | All 4 WindowIdentityTests passed again. / Повторно прошли 4 теста идентификации окон. |
| NSPanel presentation harness | 10 checks passed. / 10 проверок успешно. |
| Release packaging | Universal arm64 + x86_64 app and helper built; strict signature verification passed. / Универсальная сборка app/helper и проверка подписей успешны. |
| Version | App and helper: 1.0.0, build 1; VERSION and UI fallback match. / Версии совпадают с VERSION и интерфейсом. |
| Property lists | App, helper and Xcode project lint passed. / Проверки plist и проекта Xcode успешны. |
| Documentation | Local links and all six screenshot references resolve. / Локальные ссылки и шесть снимков доступны. |
| Publication privacy | Credential-pattern and private-path/name scan of the publication set found no remaining matches. Previous Git history contained only LICENSE. / В отобранных файлах не осталось совпадений ключей, личных путей и названий рабочих проектов; прежняя история содержала только LICENSE. |
| Screenshots | Production SwiftUI views rendered in isolation with fictional projects and devices. Visually reviewed; no private application screens. / Представления SwiftUI отрендерены изолированно с вымышленными проектами и устройствами; просмотрены вручную. |

Local logs, verification notes, draft screenshots, workspace state and built/signing artifacts were excluded from Git. A real working-project name in a test fixture was replaced with a demo name. This was a scoped pattern and visual review, not a guarantee that future changes cannot introduce sensitive data.

Локальные логи, старые отчёты, черновые снимки, состояние рабочего места, сборки и материалы подписи исключены из Git. Название рабочего проекта в тестовых данных заменено демонстрационным. Проверка охватывала отобранные файлы и изображения и не гарантирует отсутствие утечек в будущих изменениях.

Real Flutter Run/Reload/Restart flows, physical devices, Intel execution, macOS 14 execution and Apple notarization were not repeated for this documentation/version release. No notarized binary is published. The screenshot fixture does not run Flutter projects or alter the user's project archive.

В этом релизе документации/версии повторно не проверялись реальные Run/Reload/Restart Flutter, физические устройства, запуск на Intel/macOS 14 и notarization Apple. Нотарифицированный бинарный файл не публикуется. Демонстрационные снимки не запускают проекты и не меняют архив проектов пользователя.

## DMG download / Скачивание DMG

Universal DMG packaging was added after the 1.0.0 source tag. GitHub Actions checked that application source/build metadata match the tag, checked out the tag, passed tests, built the universal app/helper with ad-hoc signing, and published the DMG and SHA-256 checksum to the 1.0.0 release. No private developer certificate is included.

Упаковка DMG добавлена после исходного тега 1.0.0. GitHub Actions проверил совпадение кода/метаданных с тегом, переключился на тег, выполнил тесты, собрал универсальные app/helper с ad-hoc подписью и опубликовал DMG с SHA-256 в релизе 1.0.0. Личный сертификат разработчика не включён.

The local image mounted successfully, contained only the app, Applications symlink, license and installation instructions, and passed signature/architecture/checksum checks. Public DMG and checksum downloads were verified after publication.

Локальный образ успешно смонтирован: внутри только приложение, ссылка Applications, лицензия и инструкция. Проверены подписи, обе архитектуры и контрольная сумма. После публикации проверено скачивание публичного DMG и файла SHA-256.

[Release / Релиз](https://github.com/Shishani58/Fluttios/releases/tag/v1.0.0) · [Build / Сборка](https://github.com/Shishani58/Fluttios/actions/runs/37549380690)
