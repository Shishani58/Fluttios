import AppKit
import SimFlutDockCore
import SwiftUI

struct LogsView: View {
    @ObservedObject var model: AppModel
    @State private var query = ""
    @State private var errorsOnly = false
    @State private var followLogs = true
    @AppStorage("logSourceEditor") private var editor = "default"

    private var entries: [LogEntry] { model.selectedSession?.logs ?? [] }
    private var visibleEntries: [LogEntry] {
        LogDiagnostics.filtered(entries, query: query, errorsOnly: errorsOnly)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                ProjectMenu(model: model)
                DeviceMenu(model: model)
                Spacer()
                Button(L10n.text("Copy")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(
                        model.selectedSession?.logs.map { $0.text }.joined(separator: "\n") ?? "", forType: .string)
                }
                .disabled(entries.isEmpty)
                Button(L10n.text("Error report"), action: copyReport)
                    .help(L10n.text("Copy error report"))
                    .accessibilityLabel(L10n.text("Copy error report"))
                    .disabled(entries.isEmpty)
                Button(L10n.text("Clear")) { model.selectedSession?.clearLogs() }
            }.padding()
            Divider()
            HStack {
                TextField(L10n.text("Search logs"), text: $query)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel(L10n.text("Search logs"))
                Toggle(L10n.text("Errors only"), isOn: $errorsOnly)
                    .toggleStyle(.checkbox)
                    .fixedSize()
                Button {
                    followLogs.toggle()
                } label: {
                    Label(
                        L10n.text(followLogs ? "Pause scrolling" : "Resume scrolling"),
                        systemImage: followLogs ? "pause" : "play")
                }
                .labelStyle(.iconOnly)
                .help(L10n.text(followLogs ? "Pause scrolling" : "Resume scrolling"))
                Picker(L10n.text("Open source in"), selection: $editor) {
                    Text(L10n.text("Default editor")).tag("default")
                    if NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.microsoft.VSCode") != nil {
                        Text("VS Code").tag("vscode")
                    }
                    if NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.todesktop.230313mzl4w4u92")
                        != nil
                    {
                        Text("Cursor").tag("cursor")
                    }
                }
                .labelsHidden()
                .help(L10n.text("Open source in"))
                .frame(width: 190)
            }.padding(.horizontal).padding(.vertical, 8)
            Divider()
            if visibleEntries.isEmpty {
                ContentUnavailableView(
                    L10n.text(entries.isEmpty ? "No logs yet" : "No matching logs"),
                    systemImage: "text.alignleft")
            } else {
                LogConsole(
                    entries: visibleEntries, sessionID: model.selectedSession?.id,
                    followLogs: followLogs,
                    projectPath: model.selectedSession?.launchProject?.path ?? model.store.selected?.path,
                    editor: editor)
            }
            Text(L10n.text("Up to 2000 entries per session • quitting the app requires a new Run")).font(.caption)
                .foregroundStyle(.secondary).padding(8)
        }.frame(minWidth: 700, minHeight: 400)
            .onChange(of: model.selectedSession?.id) { _, _ in followLogs = true }
    }

    private func copyReport() {
        guard let session = model.selectedSession else { return }
        let project = session.launchProject ?? model.store.selected
        let configuration = project?.launch
        let device = session.device
        // Arguments may contain credentials (--dart-define); copying a report never includes their values.
        let report = [
            "SimFlutDock error report",
            "Project: \(project?.name ?? "—")",
            "Device: \(device?.name ?? "—") • \(device?.targetPlatform ?? "—") • \(device?.runtime ?? "—")",
            "Flutter: \(session.flutterVersion ?? L10n.text("Unknown"))",
            "Mode: \(configuration?.mode.title ?? "—")",
            "Entrypoint: \(configuration?.entrypoint ?? "—")",
            "Flavor: \(configuration?.scheme ?? "—") • \(configuration?.buildConfiguration ?? "—")",
            "Additional arguments: \(configuration?.arguments.count ?? 0) (values omitted)",
            "State: \(session.state.rawValue)", "", "Recent error and context:",
            LogDiagnostics.reportEntries(session.logs).map(\.text).joined(separator: "\n"),
        ].joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
    }
}

// AppKit owns selection and text layout, avoiding flipped selectable Text layers
// inside SwiftUI's lazy scrolling container.
struct LogConsole: NSViewRepresentable {
    let entries: [LogEntry]
    let sessionID: UUID?
    var followLogs = true
    var projectPath: String?
    var editor = "default"

    final class Coordinator: NSObject, NSTextViewDelegate {
        var entryIDs: [UUID] = []
        var sessionID: UUID?
        var following = true
        var editor = "default"
        var locations: [String: LogSourceLocation] = [:]
        var packagePath: String?
        var packageModified: Date?
        var packageRoots: [String: URL] = [:]
        var sourceLocations: [UUID: [LogSourceLocation]] = [:]
        let timestamp: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss"
            return formatter
        }()

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            guard let key = link as? String, let location = locations[key] else { return true }
            if !["vscode", "cursor"].contains(editor) {
                NSWorkspace.shared.open(location.file)
            } else {
                var components = URLComponents()
                components.scheme = editor
                components.host = "file"
                components.path = location.file.path + ":\(location.line):\(location.column)"
                if let url = components.url { NSWorkspace.shared.open(url) }
            }
            return true
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        let text = NSTextView(frame: scroll.contentView.bounds)
        text.isEditable = false
        text.isSelectable = true
        text.isRichText = false
        text.delegate = context.coordinator
        text.setAccessibilityLabel(L10n.text("Logs"))
        text.drawsBackground = false
        text.textContainerInset = NSSize(width: 16, height: 16)
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]
        text.textContainer?.widthTracksTextView = true
        text.textContainer?.containerSize = NSSize(width: scroll.contentSize.width, height: .greatestFiniteMagnitude)
        scroll.documentView = text
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let text = scroll.documentView as? NSTextView else { return }
        let coordinator = context.coordinator
        let ids = entries.map(\.id)
        let changedSession = coordinator.sessionID != sessionID
        coordinator.editor = editor
        let resumed = followLogs && !coordinator.following
        coordinator.following = followLogs
        let packageModified = projectPath.flatMap {
            try? URL(fileURLWithPath: $0).appendingPathComponent(".dart_tool/package_config.json")
                .resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        }
        let changedPackages = coordinator.packagePath != projectPath || coordinator.packageModified != packageModified
        guard changedSession || coordinator.entryIDs != ids || resumed || changedPackages else { return }
        let visible = scroll.contentView.bounds
        let followEnd =
            followLogs
            && (resumed || changedSession || coordinator.entryIDs.isEmpty
                || visible.maxY >= text.bounds.maxY - 24)
        let selection = text.selectedRange()
        let output = NSMutableAttributedString(string: "")
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let paragraph = NSMutableParagraphStyle()
        paragraph.paragraphSpacing = 4
        if changedSession || changedPackages {
            coordinator.sourceLocations.removeAll()
            coordinator.packageModified = packageModified
            coordinator.packagePath = projectPath
            coordinator.packageRoots = projectPath.map { LogSourceLocation.packageRoots(projectPath: $0) } ?? [:]
        }
        coordinator.locations.removeAll()
        let retainedIDs = Set(ids)
        coordinator.sourceLocations = coordinator.sourceLocations.filter { retainedIDs.contains($0.key) }
        for entry in entries {
            output.append(
                NSAttributedString(
                    string: coordinator.timestamp.string(from: entry.date) + "  ",
                    attributes: [
                        .font: font, .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: paragraph,
                    ]))
            let start = output.length
            output.append(
                NSAttributedString(
                    string: entry.text + "\n",
                    attributes: [
                        .font: font, .foregroundColor: entry.isError ? NSColor.systemRed : NSColor.labelColor,
                        .paragraphStyle: paragraph,
                    ]))
            if let projectPath {
                let locations =
                    coordinator.sourceLocations[entry.id]
                    ?? LogSourceLocation.locations(
                        in: entry.text, projectPath: projectPath, packageRoots: coordinator.packageRoots)
                coordinator.sourceLocations[entry.id] = locations
                for location in locations {
                    let key = UUID().uuidString
                    coordinator.locations[key] = location
                    output.addAttributes(
                        [.link: key],
                        range: NSRange(
                            location: start + location.range.location,
                            length: location.range.length))
                }
            }
        }
        text.textStorage?.setAttributedString(output)
        coordinator.entryIDs = ids
        coordinator.sessionID = sessionID
        if followEnd {
            text.scrollRangeToVisible(NSRange(location: output.length, length: 0))
        } else {
            // Preserve a selection while new lines arrive during inspection.
            if selection.location <= output.length {
                text.setSelectedRange(
                    NSRange(
                        location: selection.location, length: min(selection.length, output.length - selection.location))
                )
            }
            scroll.contentView.scroll(to: visible.origin)
            scroll.reflectScrolledClipView(scroll.contentView)
        }
    }
}
