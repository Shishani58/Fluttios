import Foundation
import Combine

@MainActor public final class ProjectStore: ObservableObject {
    private struct Archive: Codable { var projects: [Project]; var selectedID: UUID? }
    @Published public private(set) var projects: [Project] = []
    @Published public var selectedID: UUID? { didSet { persist() } }
    @Published public private(set) var persistenceError: String?
    private let file: URL
    public var selected: Project? { projects.first { $0.id == selectedID } }
    public init(file: URL? = nil) {
        self.file = file ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Fluttios/projects.json")
        if FileManager.default.fileExists(atPath: self.file.path) {
            do {
                let archive = try JSONDecoder().decode(Archive.self, from: Data(contentsOf: self.file))
                projects = archive.projects; selectedID = archive.selectedID
            } catch { persistenceError = L10n.text("Could not read the project list: {0}. File preserved: {1}", "\(error.localizedDescription)", "\(self.file.path)") }
        }
    }
    nonisolated public static func validate(_ url: URL) throws {
        let spec = url.appendingPathComponent("pubspec.yaml")
        guard let text = try? String(contentsOf: spec), text.range(of: #"(?m)^\s+sdk:\s*flutter\s*(?:#.*)?$"#, options: .regularExpression) != nil else {
            throw FluttiosError.message(L10n.text("Select a Flutter project containing pubspec.yaml."))
        }
    }
    @discardableResult public func open(_ url: URL, replacing id: UUID? = nil) throws -> Project {
        let url = url.resolvingSymlinksInPath().standardizedFileURL
        try Self.validate(url)
        if let existing = projects.first(where: { $0.path == url.path && $0.id != id }) {
            select(existing.id); return existing
        }
        if let id, let index = projects.firstIndex(where: { $0.id == id }) {
            projects[index].path = url.path; projects[index].lastOpened = Date(); selectedID = id
            persist(); return projects[index]
        }
        let spec = try String(contentsOf: url.appendingPathComponent("pubspec.yaml"))
        let nameLine = spec.split(separator: "\n").first { $0.hasPrefix("name:") }
        let name = nameLine.map { String($0.dropFirst(5)).trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\"", with: "").replacingOccurrences(of: "\u{27}", with: "") } ?? url.lastPathComponent
        let project = Project(name: name, path: url.path)
        projects.append(project); selectedID = project.id; persist(); return project
    }
    public func select(_ id: UUID) {
        if let index = projects.firstIndex(where: { $0.id == id }) { projects[index].lastOpened = Date() }
        selectedID = id; persist()
    }
    public func update(_ project: Project) {
        guard let index = projects.firstIndex(where: { $0.id == project.id }) else { return }
        projects[index] = project; persist()
    }
    public func remove(_ id: UUID) {
        projects.removeAll { $0.id == id }
        if selectedID == id { selectedID = projects.first?.id }
        persist()
    }
    public func clearSavedProjects() {
        projects.removeAll()
        // Assigning selectedID persists the empty archive once.
        selectedID = nil
    }
    @discardableResult public func recoverPersistence() throws -> URL? {
        var backup: URL?
        if FileManager.default.fileExists(atPath: file.path) {
            let copy = file.appendingPathExtension("backup-" + UUID().uuidString)
            try FileManager.default.copyItem(at: file, to: copy); backup = copy
        }
        persistenceError = nil; persist()
        if let persistenceError { throw FluttiosError.message(persistenceError) }
        return backup
    }
    public func label(_ project: Project) -> String {
        projects.filter { $0.name == project.name }.count > 1 ? "\(project.name) — \((project.path as NSString).abbreviatingWithTildeInPath)" : project.name
    }
    private func persist() {
        // Never overwrite an unreadable archive without an explicit recovery by the user.
        guard persistenceError == nil else { return }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(Archive(projects: projects, selectedID: selectedID)).write(to: file, options: .atomic)
        } catch { persistenceError = error.localizedDescription }
    }
}
