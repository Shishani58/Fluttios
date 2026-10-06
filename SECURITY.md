# Security / Безопасность

Please do not post credentials, project logs, private application screenshots or signing material in public issues. For a sensitive report, use GitHub's private vulnerability reporting if enabled; otherwise contact the repository owner through an existing private channel.

Не публикуйте ключи, логи проектов, скриншоты закрытых приложений и материалы подписи в открытых issues. Для конфиденциального сообщения используйте приватный отчёт об уязвимости GitHub, если он включён, либо существующий личный канал связи с владельцем репозитория.

## Local data / Локальные данные

Fluttios stores project paths, device selections and saved deep links in `~/Library/Application Support/Fluttios/projects.json`; UI preferences are stored in macOS UserDefaults. Session logs live in memory and can contain output from your application. The app contains no telemetry or analytics uploader. Flutter, Xcode, your project and Apple's notarization service can make their own network requests.

Fluttios хранит пути проектов, выбранные устройства и ссылки в `~/Library/Application Support/Fluttios/projects.json`; настройки интерфейса — в UserDefaults macOS. Логи сессий хранятся в памяти и могут содержать вывод вашего приложения. В Fluttios нет отправки телеметрии или аналитики. Flutter, Xcode, ваш проект и сервис notarization Apple могут выполнять собственные сетевые запросы.

This developer utility is not sandboxed. It executes Flutter/Xcode tools and uses Accessibility for simulator window attachment. Undocumented window notification symbols have a public Accessibility fallback. Review any Flutter project before running it.

Утилита работает без sandbox, запускает инструменты Flutter/Xcode и использует Accessibility для привязки к окнам. Для недокументированных уведомлений окон предусмотрен fallback на публичный Accessibility. Проверяйте Flutter-проект перед запуском.

## Publication / Публикация

Only the six documented images in `docs/images` are approved for publication. They render production SwiftUI views with fictional projects/devices, without project execution. Local reports, logs, drafts, builds, workspace state, environment files and signing keys are excluded by `.gitignore`. Review staged files and images before each release; an ignore rule does not remove files already committed.

Для публикации отобраны только шесть изображений из `docs/images`: реальные SwiftUI-представления с вымышленными проектами/устройствами, без запуска проектов. Локальные отчёты, логи, черновики, сборки, состояние рабочего места, env-файлы и ключи подписи исключены через `.gitignore`. Перед каждым релизом проверяйте подготовленные файлы и изображения: ignore-правило не удаляет уже закоммиченные файлы.
