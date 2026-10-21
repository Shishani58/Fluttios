## SimFlutDock 1.0.7

Native Flutter controls beside Simulator / Device Hub. English and Russian UI.
Нативная панель управления Flutter рядом с Simulator / Device Hub. Русский и английский интерфейс.

### Changes / Изменения

- Run the same Flutter project on multiple devices at once. Switching devices selects that device's session for Run, Hot Reload, Hot Restart, Stop, and logs, while other sessions keep running.
- Added a device picker to logs and kept app data and permission actions scoped to the selected device.
- Improved automatic update installation, cancellation, and recovery, Flutter process cleanup, and log memory limits.
- Split UI and tests into focused files and added CI checks for SwiftPM and Xcode builds.

- Один Flutter-проект можно запускать на нескольких устройствах одновременно. Переключение устройства выбирает его сессию для Run, Hot Reload, Hot Restart, Stop и логов; остальные сессии продолжают работать.
- В окно логов добавлен выбор устройства. Действия с данными и разрешениями приложения относятся к выбранному устройству.
- Улучшены автоматическая установка обновлений, отмена и восстановление после ошибок, завершение процессов Flutter и ограничения памяти журналов.
- UI и тесты разделены на отдельные файлы, добавлены CI-проверки SwiftPM и Xcode.

### Download / Скачать

Download **SimFlutDock-1.0.7.dmg** below. Universal app for **Apple Silicon and Intel**, **macOS 14+**. Open the DMG, drag **SimFlutDock.app** to **Applications**, then launch the installed copy. Flutter SDK and full Xcode are required to run projects.

Скачайте **SimFlutDock-1.0.7.dmg** ниже. Универсальное приложение для **Apple Silicon и Intel**, **macOS 14+**. Откройте DMG, перетащите **SimFlutDock.app** в **Applications** и запускайте установленную копию. Для запуска проектов нужны Flutter SDK и полный Xcode.

### Signing / Подпись

This build uses an **ad-hoc signature** and is **not notarized by Apple**. macOS may block the first launch. It contains no personal developer certificate. Review [Apple's guidance](https://support.apple.com/en-us/102445) before opening software that macOS cannot verify.

Сборка имеет **ad-hoc подпись**, **без notarization Apple**. macOS может заблокировать первое открытие. Личный сертификат разработчика не включён. Перед запуском ознакомьтесь с [инструкцией Apple](https://support.apple.com/ru-ru/102445).

The `.sha256` file provides a checksum. / Файл `.sha256` содержит контрольную сумму.

For features and source build instructions, see the bilingual README. / Функции и сборка из исходного кода описаны в README на двух языках.
