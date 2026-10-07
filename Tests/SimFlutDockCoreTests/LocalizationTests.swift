import XCTest
@testable import SimFlutDockCore

final class LocalizationTests: XCTestCase {
    func testAutomaticUsesSystemLanguageAndEnglishFallback() {
        for language in ["ru", "ru-RU", "ru_BY"] {
            XCTAssertEqual(AppLanguage.automatic.resolvedLanguage(preferredLanguages: [language, "en"]), .russian)
        }
        for languages in [["en-US"], ["fr-FR", "ru"], ["ja"], []] {
            XCTAssertEqual(AppLanguage.automatic.resolvedLanguage(preferredLanguages: languages), .english)
        }
        XCTAssertEqual(AppLanguage.english.resolvedLanguage(preferredLanguages: ["ru"]), .english)
        XCTAssertEqual(AppLanguage.russian.resolvedLanguage(preferredLanguages: ["en"]), .russian)
    }

    func testPreferenceDefaultsAndPersistsAllChoices() {
        let suite = "SimFlutDock.LocalizationTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(L10n.preference(in: defaults), .automatic)
        for language in AppLanguage.allCases {
            L10n.savePreference(language, in: defaults)
            XCTAssertEqual(L10n.preference(in: UserDefaults(suiteName: suite)!), language)
        }
        defaults.set("unknown", forKey: L10n.preferenceKey)
        XCTAssertEqual(L10n.preference(in: defaults), .automatic)
    }

    func testFormattedTranslationsPreserveValuesWithoutInterpretingThem() {
        let key = "Could not start {0}: {1}"
        let values = ["iPhone {1}", "Error 42"]
        XCTAssertEqual(L10n.translate(key, arguments: values, language: .english), "Could not start iPhone {1}: Error 42")
        XCTAssertEqual(L10n.translate(key, arguments: values, language: .russian), "Не удалось запустить iPhone {1}: Error 42")
        XCTAssertEqual(L10n.translate("External tool output", language: .russian), "External tool output")
    }

    func testCatalogueHasMatchingPlaceholdersAndEnglishKeys() throws {
        let regex = try NSRegularExpression(pattern: #"\{[0-9]+\}"#)
        func tokens(_ value: String) -> [String] {
            regex.matches(in: value, range: NSRange(value.startIndex..., in: value))
                .map { String(value[Range($0.range, in: value)!]) }.sorted()
        }
        for (english, russian) in L10n.russian {
            XCTAssertEqual(tokens(english), tokens(russian), english)
            XCTAssertNil(english.range(of: "[А-Яа-яЁё]", options: .regularExpression), english)
            XCTAssertFalse(english.contains(#"\n"#), english)
        }
    }

    @MainActor func testAlreadyDisplayedNoticesFollowLanguageChanges() {
        let previous = UserDefaults.standard.object(forKey: L10n.preferenceKey)
        defer {
            if let previous { UserDefaults.standard.set(previous, forKey: L10n.preferenceKey) }
            else { UserDefaults.standard.removeObject(forKey: L10n.preferenceKey) }
        }
        L10n.language = .english
        XCTAssertEqual(L10n.display("Не удалось запустить iPhone: Error 42"), "Could not start iPhone: Error 42")
        XCTAssertEqual(L10n.display("Сборка в Xcode"), "Building in Xcode")
        L10n.language = .russian
        XCTAssertEqual(L10n.display("Could not start iPhone: Error 42"), "Не удалось запустить iPhone: Error 42")
        XCTAssertEqual(L10n.display("Building in Xcode"), "Сборка в Xcode")
        XCTAssertEqual(L10n.display("Raw Flutter output"), "Raw Flutter output")
    }

    func testDeviceStateIsIndependentOfUILanguage() throws {
        let json = Data(#"[{"id":"SIM","name":"iPhone","targetPlatform":"ios","emulator":true},{"id":"PHONE","name":"iPhone","targetPlatform":"ios","emulator":false}]"#.utf8)
        XCTAssertEqual(try SimulatorDevice.flutterDevices(from: json).map(\.state), ["Booted", "Available"])
    }
}
