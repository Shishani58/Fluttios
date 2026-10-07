import Foundation

/// Persisted UI preference. Automatic follows the first system language, with English as fallback.
public enum AppLanguage: String, CaseIterable, Identifiable {
    case automatic, english = "en", russian = "ru"
    public var id: Self { self }
    public var title: String {
        switch self {
        case .automatic: return L10n.text("Automatic")
        case .english: return "English"
        case .russian: return "Русский"
        }
    }
    public func resolvedLanguage(preferredLanguages: [String]) -> AppLanguage {
        guard self == .automatic else { return self }
        let first = preferredLanguages.first?.lowercased().replacingOccurrences(of: "_", with: "-")
        return first == "ru" || first?.hasPrefix("ru-") == true ? .russian : .english
    }
}

public enum L10n {
    public static let preferenceKey = "appLanguage"
    public static let didChange = Notification.Name("Fluttios.languageDidChange")
    public static var language: AppLanguage {
        get { preference(in: .standard) }
        set {
            savePreference(newValue, in: .standard)
            NotificationCenter.default.post(name: didChange, object: nil)
        }
    }
    public static func preference(in defaults: UserDefaults) -> AppLanguage {
        AppLanguage(rawValue: defaults.string(forKey: preferenceKey) ?? "") ?? .automatic
    }
    public static func savePreference(_ language: AppLanguage, in defaults: UserDefaults) {
        defaults.set(language.rawValue, forKey: preferenceKey)
    }
    public static var resolvedLanguage: AppLanguage {
        language.resolvedLanguage(preferredLanguages: Locale.preferredLanguages)
    }
    public static var locale: Locale { Locale(identifier: resolvedLanguage.rawValue) }

    /// Numbered placeholders keep values out of translation keys and allow translators to reorder them.
    public static func text(_ key: String, _ arguments: String...) -> String {
        translate(key, arguments: arguments, language: resolvedLanguage)
    }
    public static func translate(_ key: String, arguments: [String] = [], language: AppLanguage) -> String {
        let template = language == .russian ? russian[key] ?? key : key
        // Replace tokens in the template in one pass; inserted values are never interpreted as tokens.
        let pieces = template.components(separatedBy: "{")
        return pieces.dropFirst().reduce(pieces[0]) { result, piece in
            guard let close = piece.firstIndex(of: "}"),
                  let index = Int(piece[..<close]), arguments.indices.contains(index) else {
                return result + "{" + piece
            }
            return result + arguments[index] + piece[piece.index(after: close)...]
        }
    }
    /// Existing app-generated notices update when the preference changes. External tool output is preserved.
    public static func display(_ value: String) -> String {
        let target = resolvedLanguage
        if let translation = russian[value] { return target == .russian ? translation : value }
        if let key = russian.first(where: { $0.value == value })?.key { return target == .russian ? value : key }
        for entry in formattedNotices {
            let source = target == .russian ? entry.english : entry.russian
            let range = NSRange(value.startIndex..., in: value)
            guard let match = source.firstMatch(in: value, range: range) else { continue }
            let arguments = (1..<match.numberOfRanges).map { index in
                Range(match.range(at: index), in: value).map { String(value[$0]) } ?? ""
            }
            return translate(entry.key, arguments: arguments, language: target)
        }
        return value
    }
    private static let formattedNotices: [(key: String, english: NSRegularExpression, russian: NSRegularExpression)] = {
        func pattern(_ template: String) -> NSRegularExpression {
            let tokens = try! NSRegularExpression(pattern: #"\{[0-9]+\}"#)
            let range = NSRange(template.startIndex..., in: template)
            var pattern = "^", end = template.startIndex
            for match in tokens.matches(in: template, range: range) {
                let token = Range(match.range, in: template)!
                pattern += NSRegularExpression.escapedPattern(for: String(template[end..<token.lowerBound])) + "(.*?)"
                end = token.upperBound
            }
            pattern += NSRegularExpression.escapedPattern(for: String(template[end...])) + "$"
            return try! NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators)
        }
        return russian.filter { $0.key.contains("{0}") }.sorted { $0.key < $1.key }.map {
            (key: $0.key, english: pattern($0.key), russian: pattern($0.value))
        }
    }()
    static let russian: [String: String] = [
        "Clear Saved Projects…": "Очистить сохранённые проекты…",
        "Clear Saved Projects": "Очистить сохранённые проекты",
        "Clear all saved projects? Project files and app data will remain on disk.": "Очистить все сохранённые проекты? Файлы проектов и данные приложений останутся на диске.",
        "Stop running sessions before clearing saved projects.": "Остановите работающие сессии перед очисткой сохранённых проектов.",
        "Remove saved project {0}": "Убрать сохранённый проект {0}",
        "Change location for {0}": "Изменить расположение проекта {0}",
        "Checking project": "Проверка проекта",
        "Building in Xcode": "Сборка в Xcode",
        "Installing and launching": "Установка и запуск",
        "Building and launching app": "Сборка и запуск приложения",
        "Flutter did not finish launching within 10 minutes. Stop the session and check the logs.": "Flutter не завершил запуск за 10 минут. Остановите сессию и проверьте логи.",
        "Lost connection to Dart VM: {0}. Use Stop and Run.": "Соединение с Dart VM потеряно: {0}. Выполните Stop и Run.",
        "Could not connect the Dart console: {0}. Use Stop and Run.": "Не удалось подключить консоль Dart: {0}. Выполните Stop и Run.",
        "Connecting Dart console": "Подключение консоли Dart",
        "The app disconnected. Stop the remaining process or use Run after it exits.": "Приложение отключилось. Остановите оставшийся процесс или повторите Run после его завершения.",
        "Flutter could not update the app.": "Flutter не смог обновить приложение.",
        "Hot restart completed.": "Hot restart завершён.",
        "Hot reload completed.": "Hot reload завершён.",
        "Stopping app": "Остановка приложения",
        "Flutter did not exit normally; terminating the process owned by this session.": "Flutter не завершился штатно; завершаем принадлежащий сессии процесс.",
        "Flutter exited (code {0}). Check the logs and press Run.": "Flutter завершился (код {0}). Проверьте логи и нажмите Run.",
        "Process exited: {0}.": "Процесс завершён: {0}.",
        "Tool exited with code {0}.": "Инструмент завершился с кодом {0}.",
        "Flutter SDK not found. Select the SDK folder in settings. For FVM, select the project's .fvm/flutter_sdk or an installed SDK version.": "Flutter SDK не найден. Выберите папку SDK в настройках. Для FVM выберите .fvm/flutter_sdk проекта или установленную версию SDK.",
        "Full Xcode installation not found. Install and open Xcode, accept the license, and install an iOS Simulator runtime.": "Полный Xcode не найден. Установите Xcode, откройте его, примите лицензию и установите iOS Simulator runtime.",
        "Simulator / Device Hub not found in the selected Xcode.": "Simulator / Device Hub не найден в выбранном Xcode.",
        "Select a running iOS Simulator in project settings.": "Выберите запущенный iOS Simulator в настройках проекта.",
        "Could not determine the app's bundle identifier.": "Не удалось определить bundle identifier приложения.",
        "Unknown simulator action.": "Неизвестное действие симулятора.",
        "Simulators: ": "Симуляторы: ",
        "Devices": "Устройства",
        "Flutter devices: ": "Устройства Flutter: ",
        "Install the full version of Xcode.": "Установите полный Xcode.",
        "The project's simulator is unavailable. Select an iOS Simulator in project settings.": "Симулятор проекта недоступен. Выберите iOS Simulator в настройках проекта.",
        "Data folder unavailable. Install the app on the selected simulator using Run.": "Папка данных недоступна. Установите приложение на выбранный симулятор через Run.",
        "Xcode did not return project settings.": "Xcode не вернул настройки проекта.",
        "Could not determine a unique bundle identifier. Check the scheme and Xcode configuration in project settings.": "Не удалось однозначно определить bundle identifier. Проверьте схему и конфигурацию Xcode в настройках проекта.",
        "Could not read the project list: {0}. File preserved: {1}": "Не удалось прочитать список проектов: {0}. Файл сохранён: {1}",
        "Select a Flutter project containing pubspec.yaml.": "Выберите Flutter-проект с pubspec.yaml.",
        "Specify an entrypoint, scheme, and {0} or {1}-flavor configuration.": "Укажите entrypoint, схему и конфигурацию {0} или {1}-flavor.",
        "{0} is unavailable on this simulator. Choose Debug or a physical device.": "{0} недоступен на этом симуляторе. Выберите Debug или физическое устройство.",
        "The app sets the launch mode, device, entrypoint, and flavor. Remove conflicting arguments.": "Режим запуска, устройство, entrypoint и flavor задаются приложением. Удалите конфликтующие аргументы.",
        "Enter a complete URL with a scheme, such as myapp://profile or https://example.com/profile.": "Укажите полную ссылку со схемой, например myapp://profile или https://example.com/profile.",
        "Running": "Запущено",
        "Available": "Доступно",
        "Ready": "Готово",
        "Starting simulator": "Запуск симулятора",
        "Building": "Сборка",
        "Stopping": "Остановка",
        "Error": "Ошибка",
        "Disconnected": "Потеря соединения",
        "Timed out: {0}. See the logs for details.": "Истекло время ожидания: {0}. Подробности в логах.",
        "The Flutter process exited. Press Run to start again.": "Процесс Flutter завершился. Нажмите Run для нового запуска.",
        "Below": "Снизу",
        "Above": "Сверху",
        "Left": "Слева",
        "Right": "Справа",
        "Flutter returned an unsupported Dart VM address.": "Flutter вернул неподдерживаемый адрес Dart VM.",
        "Dart VM did not return the main isolate.": "Dart VM не вернула основной isolate.",
        "Checking Flutter SDK": "Проверка Flutter SDK",
        "Checking SDK: {0}": "Проверка SDK: {0}",
        "Reading Xcode settings": "Чтение настроек Xcode",
        "Preparing project": "Подготовка проекта",
        "another project": "другой проект",
        "{0} is already using {1} on {2}. Select another device in the panel.": "{0} уже использует {1} на {2}. Выберите другое устройство на панели.",
        "Preparing device launch": "Подготовка запуска на устройстве",
        "Could not bring the app to the foreground: {0}": "Не удалось вывести приложение на передний план: {0}",
        "Helper enabled": "Помощник включён",
        "Allow the helper in System Settings → General → Login Items": "Разрешите помощник в Настройках системы → Основные → Объекты входа",
        "Helper not found. Open the built SimFlutDock.app from /Applications.": "Помощник не найден. Запустите собранный SimFlutDock.app из /Applications.",
        "Automatic launch disabled": "Автоматический запуск выключен",
        "Could not start {0}: {1}": "Не удалось запустить {0}: {1}",
        "Open Project": "Открыть проект",
        "Select a Flutter project folder.": "Выберите папку Flutter-проекта.",
        "Select the Flutter SDK (the folder containing bin/flutter). For FVM, select .fvm/flutter_sdk or a specific version folder.": "Выберите Flutter SDK (папка с bin/flutter). Для FVM: .fvm/flutter_sdk или папку конкретной версии.",
        "Wait for the simulator action to finish before pressing Run.": "Дождитесь завершения действия симулятора перед Run.",
        "The saved device is unavailable. Refresh the list and select a device in the panel. For iPhone / iPad, check the connection, trust this Mac, and enable Developer Mode.": "Сохранённое устройство недоступно. Обновите список и выберите устройство на панели. Для iPhone / iPad проверьте подключение, доверие к Mac и режим разработчика.",
        "Select a connected iPhone / iPad, or install an iOS Simulator in Xcode and refresh the device list in the panel.": "Выберите подключённый iPhone / iPad или установите iOS Simulator в Xcode и обновите список устройств на панели.",
        "Could not open the project folder. Check its location in settings.": "Не удалось открыть папку проекта. Проверьте его расположение в настройках.",
        "Select an iOS Simulator for this project in settings.": "Выберите iOS Simulator для этого проекта в настройках.",
        "Press Stop for this app before resetting permissions.": "Нажмите Stop для этого приложения перед сбросом разрешений.",
        "Wait for the Flutter operation to finish, then try again.": "Дождитесь завершения операции Flutter и повторите действие.",
        "Data folder opened in Finder.": "Папка данных открыта в Finder.",
        "Press Stop for the app on this simulator before resetting permissions.": "Нажмите Stop для приложения на этом симуляторе перед сбросом разрешений.",
        "Permissions reset. The app will request access again when needed.": "Разрешения сброшены. Приложение снова запросит доступ при следующем обращении.",
        "Link opened on {0}.": "Ссылка открыта на {0}.",
        "Flutter and Xcode are available.\n{0}\n{1}": "Flutter и Xcode доступны.\n{0}\n{1}",
        "Device • detached from Simulator": "Устройство • без привязки к Simulator",
        "Free Position": "Свободное положение",
        "Select a Simulator window in the settings menu": "Выберите окно Simulator в меню настроек",
        "macOS has not granted Accessibility access to this copy of SimFlutDock": "macOS не подтверждает Accessibility для этой копии SimFlutDock",
        "Device window not found • select a window in the settings menu": "Окно устройства не найдено • выберите окно в меню настроек",
        "Waiting for Simulator / Device Hub windows": "Ожидание окон Simulator / Device Hub",
        "Simulator / Device Hub is not running": "Simulator / Device Hub не запущен",
        "{0}: AXWindows={1}, found {2}, with coordinates {3}": "{0}: AXWindows={1}, найдено {2}, с координатами {3}",
        "{0} — select a project. Running sessions are preserved.": "{0} — выбрать проект. Работающие сессии сохраняются.",
        "Flutter project selection": "Выбор Flutter-проекта",
        "No project selected": "Проект не выбран",
        "Projects": "Проекты",
        "Close": "Закрыть",
        "Close project picker": "Закрыть выбор проекта",
        "Search projects or folders": "Поиск проекта или папки",
        "Clear search": "Очистить поиск",
        "Recent Projects": "Недавние проекты",
        "Open a Flutter Project": "Откройте Flutter-проект",
        "No matches": "Нет совпадений",
        "Select a folder containing pubspec.yaml.": "Выберите папку с pubspec.yaml.",
        "Try another name or path.": "Попробуйте другое название или путь.",
        "Switching projects preserves running sessions.": "Переключение проекта сохраняет работающие сессии.",
        "Open Another Project…": "Открыть другой проект…",
        "Projects and Settings…": "Проекты и настройки…",
        "No device selected": "Устройство не выбрано",
        "Device unavailable": "Устройство недоступно",
        "Not running": "Не запущен",
        "Main Dart isolate memory. Excludes the Flutter engine, graphics, and other isolates.": "Память основного Dart isolate. Не включает Flutter engine, графику и остальные isolate.",
        "Selected": "Выбран",
        "Not selected": "Не выбран",
        ", main Dart isolate memory: ": ", память основного Dart isolate: ",
        "Project Folder": "Папка проекта",
        "Open project folder for {0}": "Открыть папку проекта {0}",
        "Data": "Данные",
        "Open app data on the simulator": "Открыть данные приложения на симуляторе",
        "Open app data for {0}": "Открыть данные приложения {0}",
        "Press Stop before resetting permissions": "Перед сбросом разрешений нажмите Stop",
        "Reset app permissions": "Сбросить разрешения приложения",
        "Reset app permissions for {0}": "Сбросить разрешения приложения {0}",
        "Action in progress…": "Выполняется действие…",
        "Select device and launch mode": "Выбрать устройство и режим запуска",
        "Device and launch mode": "Устройство и режим запуска",
        "Device and Launch": "Устройство и запуск",
        "Close device picker": "Закрыть выбор устройства",
        "Launch Mode": "Режим запуска",
        "Only Debug is available on simulators.": "Для симулятора доступен только Debug.",
        "Debug — debugging · Profile — performance · Release — production": "Debug — отладка · Profile — замеры · Release — релиз",
        "Search devices or OS versions": "Поиск устройства или версии ОС",
        "Pinned": "Закреплённые",
        "iOS Simulators": "Симуляторы iOS",
        "Other Devices": "Другие устройства",
        "Starting…": "Запуск…",
        "Searching for devices…": "Поиск устройств…",
        "No devices found": "Устройства не найдены",
        "Getting the list from Xcode and Flutter.": "Получаем список из Xcode и Flutter.",
        "Refresh the list and check the connection.": "Обновите список и проверьте подключение.",
        "Try another name or OS version.": "Попробуйте другое название или версию ОС.",
        "The saved device is unavailable. Select another one.": "Сохранённое устройство недоступно. Выберите другое.",
        "Press Stop to change the device or mode.": "Чтобы изменить устройство или режим, нажмите Stop.",
        "Open a Flutter project first.": "Сначала откройте Flutter-проект.",
        "The panel works independently for this device.": "Для этого устройства панель работает отдельно.",
        "Automatic": "Автоматически",
        "Select a running simulator when pressing Run": "Выбрать запущенный симулятор при Run",
        "Refreshing…": "Обновление…",
        "Refresh": "Обновить",
        "Device discovery error": "Ошибка поиска",
        "Shut down": "Выключен",
        "Starting {0}": "Запуск {0}",
        "Start simulator {0}": "Запустить симулятор {0}",
        "Unpin {0}": "Открепить {0}",
        "Pin {0}": "Закрепить {0}",
        "Run — start a new {0} session on the selected device": "Run — новый запуск в {0} на выбранном устройстве",
        "Hot Reload — preserve Dart state": "Hot Reload — сохранить состояние Dart",
        "Hot Restart — reset Dart state. After native code changes, use Stop and Run.": "Hot Restart — сбросить состояние Dart. После изменений нативного кода используйте Stop и Run.",
        "Stop — stop only the selected session": "Stop — остановить только выбранную сессию",
        "Drag the panel using the space between buttons": "Перетащите панель за свободное место между кнопками",
        "Show logs for the selected project": "Показать логи выбранного проекта",
        "Show Error…": "Показать ошибку…",
        "Settings…": "Настройки…",
        "Reset Position": "Сбросить положение",
        "Attach to Simulator Window": "Привязать к окну Simulator",
        "No open Simulator windows": "Нет открытых окон Simulator",
        "Allow access in SimFlutDock settings": "Разрешите доступ в настройках SimFlutDock",
        "Refresh Attachment": "Обновить привязку",
        "Panel Position": "Положение панели",
        "Quit SimFlutDock": "Завершить SimFlutDock",
        "Panel settings and menu": "Настройки и меню панели",
        "Could not complete the action": "Не удалось выполнить действие",
        "Open Logs…": "Открыть логи…",
        "Working…": "Выполняется…",
        "Operation in progress; exact percentage unavailable": "Операция выполняется; точный процент недоступен",
        "Version": "Версия",
        "Build": "Сборка",
        "General": "Общие",
        "Tools": "Инструменты",
        "Panel": "Панель",
        "Show Panel": "Показать панель",
        "Open Project…": "Открыть проект…",
        "Save Error": "Ошибка сохранения",
        "Retry Saving with Backup": "Повторить сохранение с резервной копией",
        "Previous file preserved: ": "Старый файл сохранён: ",
        "Saving restored.": "Сохранение восстановлено.",
        "Dismiss message": "Закрыть сообщение",
        "Settings are saved automatically": "Настройки сохраняются автоматически",
        "Select a folder containing pubspec.yaml. The app starts only after you press Run.": "Выберите папку с pubspec.yaml. Запуск начинается только после нажатия Run.",
        "Saved Projects": "Сохранённые проекты",
        "Project and Simulator": "Проект и симулятор",
        "Project": "Проект",
        "Select a project": "Выберите проект",
        "Project for simulator tools": "Проект для инструментов симулятора",
        "Device": "Устройство",
        "Add a Flutter project in Projects to use simulator tools.": "Добавьте Flutter-проект в разделе «Проекты», чтобы использовать инструменты симулятора.",
        "Default SDK": "SDK по умолчанию",
        "Default Flutter SDK": "Flutter SDK по умолчанию",
        "Choose…": "Выбрать…",
        "Used when the project has no SDK configured. Searches Homebrew, standard SDK folders, and the project's .fvm/flutter_sdk.": "Используется, если у проекта не указан свой SDK. Поиск включает Homebrew, обычные папки SDK и .fvm/flutter_sdk проекта.",
        "Development Environment": "Окружение разработки",
        "Flutter and Xcode": "Flutter и Xcode",
        "Checking…": "Проверка…",
        "Check": "Проверить",
        "Xcode is selected from system settings or an installed app. Finder uses its own PATH.": "Xcode выбирается из настроек системы или установленного приложения. Finder использует свой PATH.",
        "Panel Placement": "Расположение панели",
        "Simulator Side": "Сторона Simulator",
        "Side of the Simulator window": "Сторона окна Simulator",
        "For this device, the panel works independently of Simulator.": "Для этого устройства панель работает отдельно от Simulator.",
        "Turn off Free Position to choose an attachment side.": "Выключите свободное положение, чтобы выбрать сторону привязки.",
        "If there is not enough room on the selected side, the panel appears on the opposite side.": "Если с выбранной стороны не хватает места, панель появится с другой стороны окна.",
        "Simulator Window Access": "Доступ к окнам Simulator",
        "Accessibility": "Универсальный доступ",
        "Allowed": "Разрешён",
        "Permission required": "Требуется разрешение",
        "Enable SimFlutDock in System Settings → Privacy & Security → Accessibility. Access is detected automatically.": "Включите SimFlutDock в Настройках системы → Конфиденциальность и безопасность → Универсальный доступ. Разрешение подхватится автоматически.",
        "Allow Access…": "Разрешить доступ…",
        "Check Permission": "Проверить разрешение",
        "You can select a window manually in the panel menu: ⚙ → Panel Position → Attach to Simulator Window.": "Окно можно выбрать вручную в меню панели ⚙ → Положение панели → Привязать к окну Simulator.",
        "Automatic Launch": "Автозапуск",
        "Launch with Simulator": "Запускать вместе с Simulator",
        "Background Helper": "Фоновый помощник",
        "macOS Settings": "Настройки macOS",
        "Open Login Items…": "Открыть «Объекты входа»…",
        "Saved Links": "Сохранённые ссылки",
        "Save links to screens and test scenarios for this project.": "Сохраните ссылки на экраны и тестовые сценарии этого проекта.",
        "Open": "Открыть",
        "Open link {0}": "Открыть ссылку {0}",
        "Edit link {0}": "Изменить ссылку {0}",
        "Edit link": "Изменить ссылку",
        "Delete link {0}": "Удалить ссылку {0}",
        "Delete link": "Удалить ссылку",
        "Link name": "Название ссылки",
        "myapp://profile or https://example.com/profile": "myapp://profile или https://example.com/profile",
        "Link URL": "URL ссылки",
        "Cancel": "Отмена",
        "Save": "Сохранить",
        "Add Link…": "Добавить ссылку…",
        "Links open in the selected iOS Simulator. The app must support the URL scheme or Universal Link; web links may open in Safari.": "Ссылки открываются в выбранном iOS Simulator. Приложение должно поддерживать соответствующую схему или Universal Link; веб-ссылка может открыться в Safari.",
        "Select a running iOS Simulator to perform actions. You can save links without a running device.": "Для действий выберите запущенный iOS Simulator. Ссылки можно сохранять без запущенного устройства.",
        "Enter a link name.": "Укажите название ссылки.",
        "Launch": "Запуск",
        "Device and Mode": "Устройство и режим",
        "Logs…": "Логи…",
        "Project Options": "Параметры проекта",
        "Name": "Название",
        "Project name": "Название проекта",
        "Project Flutter SDK": "Flutter SDK проекта",
        "Automatic / FVM": "Автоматически / FVM",
        "Changes are saved automatically.": "Изменения сохраняются автоматически.",
        "Press Stop to change launch options. Switching projects preserves the session.": "Параметры запуска можно изменить после Stop. Переключение проекта сохраняет сессию.",
        "Folders": "Папки",
        "App Data": "Данные приложения",
        "Folder unavailable. Choose a new location or remove the entry.": "Папка недоступна. Укажите новое расположение или уберите запись.",
        "Change Location…": "Изменить расположение…",
        "Remove from List": "Убрать из списка",
        "Remove this project from the list? Files will remain on disk.": "Убрать проект из списка? Файлы останутся на диске.",
        "Remove": "Убрать",
        "Copy": "Копировать",
        "Clear": "Очистить",
        "Up to 2000 entries per project • quitting the app requires a new Run": "До 2000 записей на проект • полное завершение приложения требует нового Run",
        "SimFlutDock — show simulator or panel": "SimFlutDock — показать симулятор или панель",
        "SimFlutDock — Projects and Settings": "SimFlutDock — проекты и настройки",
        "SimFlutDock — Logs": "SimFlutDock — логи",
        "Stop Flutter sessions and quit?": "Остановить Flutter-сессии и выйти?",
        "Running projects will be stopped. Press Run again the next time you open SimFlutDock.": "Работающие проекты будут остановлены. При следующем открытии потребуется Run.",
        "Stop All and Quit": "Остановить все и выйти",
        "Unavailable": "Недоступно",
        "Language": "Язык",
        "Use System Language": "Как в системе",
        "Follows the system language. English is used for unsupported languages.": "Язык определяется по системе. Для неподдерживаемых языков используется английский.",
    ]
}
