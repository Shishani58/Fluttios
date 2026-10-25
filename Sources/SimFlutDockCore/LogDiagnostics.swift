import Foundation

public enum LogDiagnostics {
    /// Flutter exceptions often arrive on stdout; retain their stack and details in the error filter.
    public static func errorEntryIDs(in entries: [LogEntry]) -> Set<UUID> {
        var result = Set<UUID>()
        var inException = false
        for entry in entries {
            let value = entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = value.lowercased()
            let exceptionHeader = value.hasPrefix("══╡ EXCEPTION")
            if exceptionHeader { inException = true }
            if entry.isError || inException || lower.contains("unhandled exception")
                || lower.contains("error:") || lower.contains("exception:")
                || value.range(of: #"^#\d+\s"#, options: .regularExpression) != nil
            {
                result.insert(entry.id)
            }
            if inException && value.hasPrefix("════") && !exceptionHeader { inException = false }
        }
        return result
    }

    public static func filtered(_ entries: [LogEntry], query: String, errorsOnly: Bool) -> [LogEntry] {
        let errors = errorsOnly ? errorEntryIDs(in: entries) : []
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return entries.filter {
            (!errorsOnly || errors.contains($0.id))
                && (query.isEmpty || $0.text.localizedCaseInsensitiveContains(query))
        }
    }

    /// Copy the latest error and bounded context, independent of the current search filter.
    public static func reportEntries(_ entries: [LogEntry]) -> [LogEntry] {
        let errors = errorEntryIDs(in: entries)
        guard let index = entries.lastIndex(where: { errors.contains($0.id) }) else { return Array(entries.suffix(80)) }
        if let header = entries[...index].lastIndex(where: {
            $0.text.hasPrefix("══╡ EXCEPTION") || $0.text.lowercased().hasPrefix("unhandled exception")
        }),
            header == index || entries[header].text.hasPrefix("══╡ EXCEPTION")
                || entries[index].text.range(of: #"^#\d+\s"#, options: .regularExpression) != nil,
            !entries[header..<index].contains(where: {
                $0.text.hasPrefix("════") && !$0.text.hasPrefix("══╡ EXCEPTION")
            }),
            !entries[header].text.lowercased().hasPrefix("unhandled exception")
                || unbrokenStack(in: entries, from: header, through: index)
        {
            let lower = max(0, header - 5)
            let upper = min(entries.count, index + 21)
            if upper - lower <= 80 { return Array(entries[lower..<upper]) }
            // A long stack must not displace the exception headline from a bounded report.
            let headEnd = min(upper, header + 15)
            return Array(entries[lower..<headEnd]) + Array(entries[max(headEnd, upper - 60)..<upper])
        }
        return Array(entries[max(0, index - 40)..<min(entries.count, index + 21)])
    }

    private static func unbrokenStack(in entries: [LogEntry], from header: Int, through end: Int) -> Bool {
        var started = false
        for entry in entries[header...end].dropFirst() {
            let value = entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if value.range(of: #"^#\d+\s"#, options: .regularExpression) != nil {
                started = true
            } else if started && !value.isEmpty {
                return false
            }
        }
        return true
    }
}

public struct LogSourceLocation: Equatable {
    public let file: URL
    public let line: Int
    public let column: Int
    public let range: NSRange
    private static let referencePattern = try! NSRegularExpression(
        pattern:
            #"(?:package:[^\s():]+|file:///[^\s():]+|/[^\s():]+|(?:lib|test|integration_test)/[^\s():]+)\.dart:(\d+)(?::(\d+))?"#
    )

    /// Only local Dart source references become clickable. Log text never becomes a shell command.
    public static func locations(in text: String, projectPath: String, packageRoots: [String: URL]) -> [Self] {
        return referencePattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard let range = Range(match.range, in: text), let lineRange = Range(match.range(at: 1), in: text),
                let line = Int(text[lineRange]), line > 0
            else { return nil }
            let reference = String(text[range]).components(separatedBy: ".dart:")[0] + ".dart"
            let column = Range(match.range(at: 2), in: text).flatMap { Int(text[$0]) } ?? 1
            let file: URL
            if reference.hasPrefix("package:") {
                let parts = reference.dropFirst(8).split(separator: "/", maxSplits: 1)
                guard parts.count == 2, let root = packageRoots[String(parts[0])] else { return nil }
                file = root.appendingPathComponent(String(parts[1]))
            } else if reference.hasPrefix("file:") {
                guard let url = URL(string: reference), url.isFileURL else { return nil }
                file = url
            } else {
                file =
                    reference.hasPrefix("/")
                    ? URL(fileURLWithPath: reference)
                    : URL(fileURLWithPath: projectPath).appendingPathComponent(reference)
            }
            let resolved = file.standardizedFileURL.resolvingSymlinksInPath()
            let roots = [URL(fileURLWithPath: projectPath)] + Array(packageRoots.values)
            guard column > 0,
                roots.contains(where: {
                    resolved.path.hasPrefix($0.standardizedFileURL.resolvingSymlinksInPath().path + "/")
                })
            else { return nil }
            return Self(file: resolved, line: line, column: column, range: match.range)
        }
    }

    public static func packageRoots(projectPath: String) -> [String: URL] {
        let config = URL(fileURLWithPath: projectPath).appendingPathComponent(".dart_tool/package_config.json")
        guard let data = try? Data(contentsOf: config),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let packages = json["packages"] as? [[String: Any]]
        else { return [:] }
        var roots: [String: URL] = [:]
        for package in packages {
            guard let name = package["name"] as? String, let root = package["rootUri"] as? String,
                let rootURL = URL(string: root, relativeTo: config)?.absoluteURL, rootURL.isFileURL,
                let library = URL(string: package["packageUri"] as? String ?? "lib/", relativeTo: rootURL)?.absoluteURL,
                library.isFileURL
            else { continue }
            roots[name] = library
        }
        return roots
    }
}
