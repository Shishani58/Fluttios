## SimFlutDock 1.0.6

Native Flutter controls beside Simulator / Device Hub. English and Russian UI.
Нативная панель управления Flutter рядом с Simulator / Device Hub. Русский и английский интерфейс.

### Changes / Изменения

- Fixed a black screen when launching Flutter apps that create background isolates, including Drift database workers. SimFlutDock now resumes newly created isolates paused at startup.
- Preserved breakpoint pauses and prevented duplicate resume requests. Added regression tests for startup and hot restart.

- Исправлен чёрный экран при запуске Flutter-приложений с фоновыми isolate, включая базы данных Drift. SimFlutDock теперь снимает стартовую паузу и с новых isolate.
- Сохранены паузы на точках останова, исключены повторные запросы resume. Добавлены регрессионные тесты запуска и hot restart.

### Download / Скачать

Download **SimFlutDock-1.0.6.dmg** below. Universal app for **Apple Silicon and Intel**, **macOS 14+**. Open the DMG, drag **SimFlutDock.app** to **Applications**, then launch the installed copy. Flutter SDK and full Xcode are required to run projects.

Скачайте **SimFlutDock-1.0.6.dmg** ниже. Универсальное приложение для **Apple Silicon и Intel**, **macOS 14+**. Откройте DMG, перетащите **SimFlutDock.app** в **Applications** и запускайте установленную копию. Для запуска проектов нужны Flutter SDK и полный Xcode.

### Signing / Подпись

This build uses an **ad-hoc signature** and is **not notarized by Apple**. macOS may block the first launch. It contains no personal developer certificate. Review [Apple's guidance](https://support.apple.com/en-us/102445) before opening software that macOS cannot verify.

Сборка имеет **ad-hoc подпись**, **без notarization Apple**. macOS может заблокировать первое открытие. Личный сертификат разработчика не включён. Перед запуском ознакомьтесь с [инструкцией Apple](https://support.apple.com/ru-ru/102445).

The `.sha256` file provides a checksum. / Файл `.sha256` содержит контрольную сумму.

For features and source build instructions, see the bilingual README. / Функции и сборка из исходного кода описаны в README на двух языках.
