# Security / Безопасность

Please do not post credentials, project logs, private application screenshots or signing material in public issues. For a sensitive report, use GitHub's private vulnerability reporting if enabled; otherwise contact the repository owner through an existing private channel.

Не публикуйте ключи, логи проектов, скриншоты закрытых приложений и материалы подписи в открытых issues. Для конфиденциального сообщения используйте приватный отчёт об уязвимости GitHub, если он включён, либо существующий личный канал связи с владельцем репозитория.

## Local data / Локальные данные

SimFlutDock stores project paths, device selections and saved deep links in `~/Library/Application Support/Fluttios/projects.json`; UI preferences are stored in macOS UserDefaults. Session logs live in memory and can contain output from your application. The app contains no telemetry or analytics uploader. Flutter, Xcode, your project and Apple's notarization service can make their own network requests.

Update checks contact this repository's public GitHub Releases and download release metadata, checksums, and installers. Automatic checks can be disabled in Settings. The updater does not upload project paths, source code, or session logs.

SimFlutDock хранит пути проектов, выбранные устройства и ссылки в `~/Library/Application Support/Fluttios/projects.json`; настройки интерфейса — в UserDefaults macOS. Логи сессий хранятся в памяти и могут содержать вывод вашего приложения. В SimFlutDock нет отправки телеметрии или аналитики. Flutter, Xcode, ваш проект и сервис notarization Apple могут выполнять собственные сетевые запросы.

Проверка обновлений обращается к публичным GitHub Releases этого репозитория и скачивает метаданные, контрольные суммы и установщики. Автоматическую проверку можно отключить в настройках. Обновление не отправляет пути проектов, исходный код или логи сессий.

This developer utility is not sandboxed. It executes Flutter/Xcode tools and uses Accessibility for simulator window attachment. Undocumented window notification symbols have a public Accessibility fallback. Review any Flutter project before running it.

Утилита работает без sandbox, запускает инструменты Flutter/Xcode и использует Accessibility для привязки к окнам. Для недокументированных уведомлений окон предусмотрен fallback на публичный Accessibility. Проверяйте Flutter-проект перед запуском.

## Local MCP control / Локальное управление MCP

The running app accepts session-control requests over a Unix socket in `~/Library/Application Support/Fluttios/mcp`, a directory with mode 0700. The socket has mode 0600 and accepts peers with the same effective user ID. Programs running as that user can discover saved projects/devices, start the saved project configuration on an explicit device, rerun/reload/restart/stop a session, dispatch deep links, and capture the visible iOS Simulator or Android screen. Project startup and links may trigger project-defined network or data operations. Connecting an AI client shares requested metadata, logs and screenshots with that client. Screenshots are bounded JPEG images with private temporary local files, removed when their retry records are evicted. The app does not publish a network listener; launching requires an explicit launch/rerun tool call. MCP cannot add projects, change saved configurations, choose an arbitrary screenshot output path or execute arbitrary shell commands. See [the MCP guide](docs/mcp.md) for client permissions and retry behavior.

Работающее приложение принимает команды через Unix socket в закрытом каталоге `~/Library/Application Support/Fluttios/mcp`. Доступ ограничен текущим пользователем macOS. Подключённый ИИ-клиент получает запрошенные сведения о сохранённых проектах, устройствах, логи и скриншоты видимого экрана iOS Simulator/Android. Он может явно запускать сохранённую конфигурацию на выбранном устройстве, выполнять Rerun, Reload, Restart и Stop, открывать deep links. Запуск проекта и ссылки могут вызывать сетевые запросы и изменения данных приложения. Скриншоты хранятся во временных закрытых JPEG-файлах, удаляемых при вытеснении записи повторного запроса. Учитывайте это при выборе клиента и разрешений инструментов. Приложение не открывает сетевой сервер; запуск требует явной команды. MCP не добавляет проекты, не меняет конфигурации, не принимает произвольный путь скриншота и не выполняет произвольные shell-команды.

## Publication / Публикация

Only the six documented images in `docs/images` are approved for publication. They render production SwiftUI views with fictional projects/devices, without project execution. Local reports, logs, drafts, builds, workspace state, environment files and signing keys are excluded by `.gitignore`. Review staged files and images before each release; an ignore rule does not remove files already committed.

Для публикации отобраны только шесть изображений из `docs/images`: реальные SwiftUI-представления с вымышленными проектами/устройствами, без запуска проектов. Локальные отчёты, логи, черновики, сборки, состояние рабочего места, env-файлы и ключи подписи исключены через `.gitignore`. Перед каждым релизом проверяйте подготовленные файлы и изображения: ignore-правило не удаляет уже закоммиченные файлы.
