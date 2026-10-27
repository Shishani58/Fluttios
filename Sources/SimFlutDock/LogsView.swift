import AppKit
import SimFlutDockCore
import SwiftUI

struct LogsView: View {
    @ObservedObject var model: AppModel
    @State private var query = ""
    @State private var errorsOnly = false
    @State private var followLogs = true
    @FocusState private var searchFocused: Bool
    @AppStorage("logSourceEditor") private var editor = "default"

    private var entries: [LogEntry] { model.selectedSession?.logs ?? [] }
    private var visibleEntries: [LogEntry] {
        LogDiagnostics.filtered(entries, query: query, errorsOnly: errorsOnly)
    }

    var body: some View {
        let filtered = visibleEntries
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                ProjectMenu(model: model)
                    .frame(maxWidth: 180, alignment: .leading)
                DeviceMenu(model: model)
                    .frame(maxWidth: 260, alignment: .leading)
                Spacer(minLength: 0)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(
                        model.selectedSession?.logs.map { $0.text }.joined(separator: "\n") ?? "", forType: .string)
                } label: {
                    Label(L10n.text("Copy all logs"), systemImage: "doc.on.doc")
                }
                .labelStyle(.iconOnly)
                .help(L10n.text("Copy all logs"))
                .disabled(entries.isEmpty)
                Button(action: copyReport) {
                    Label(L10n.text("Error report"), systemImage: "doc.badge.ellipsis")
                }
                    .labelStyle(.iconOnly)
                    .help(L10n.text("Copy error report"))
                    .accessibilityLabel(L10n.text("Copy error report"))
                    .disabled(entries.isEmpty)
                Button { model.selectedSession?.clearLogs() } label: {
                    Label(L10n.text("Clear"), systemImage: "trash")
                }
                .labelStyle(.iconOnly)
                .help(L10n.text("Clear"))
                .disabled(entries.isEmpty)
            }
            .controlSize(.regular)
            .padding(12)
            .fixedSize(horizontal: false, vertical: true)
            Divider()
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
                    TextField(L10n.text("Search logs"), text: $query)
                        .textFieldStyle(.plain)
                        .accessibilityLabel(L10n.text("Search logs"))
                        .focused($searchFocused)
                    if !query.isEmpty {
                        Button { query = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(L10n.text("Clear search"))
                    }
                }
                .padding(.horizontal, 8).padding(.vertical, 6)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(
                    searchFocused ? Color.accentColor : Color.primary.opacity(0.12),
                    lineWidth: searchFocused ? 2 : 1))
                Toggle(L10n.text("Errors only"), isOn: $errorsOnly)
                    .toggleStyle(.checkbox)
                    .fixedSize()
                Toggle(isOn: $followLogs) {
                    Label(L10n.text("Autoscroll"), systemImage: "arrow.down.to.line")
                }
                .toggleStyle(.button)
                .fixedSize()
                .help(L10n.text(followLogs ? "Pause scrolling" : "Resume scrolling"))
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .fixedSize(horizontal: false, vertical: true)
            Divider()
            Group {
                if filtered.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: entries.isEmpty ? "text.alignleft" : "magnifyingglass")
                            .font(.system(size: 28)).foregroundStyle(.secondary).accessibilityHidden(true)
                        Text(L10n.text(entries.isEmpty ? "No logs yet" : "No matching logs"))
                            .font(.headline)
                        Text(L10n.text(entries.isEmpty
                            ? "Logs will appear here after you press Run in the panel."
                            : "Try another search or turn off the error filter."))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        if !entries.isEmpty {
                            Button(L10n.text("Reset filters")) {
                                query = ""
                                errorsOnly = false
                            }
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    LogConsole(
                        entries: filtered, sessionID: model.selectedSession?.id,
                        followLogs: followLogs,
                        projectPath: model.selectedSession?.launchProject?.path ?? model.store.selected?.path,
                        editor: editor)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))
            Divider()
            HStack(spacing: 8) {
                Text(L10n.text("{0} of {1} entries", "\(filtered.count)", "\(entries.count)"))
                    .monospacedDigit()
                Image(systemName: "info.circle")
                    .help(L10n.text("Up to 2000 entries per session • quitting the app requires a new Run"))
                    .accessibilityLabel(L10n.text("Up to 2000 entries per session • quitting the app requires a new Run"))
                Spacer(minLength: 12)
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
                .fixedSize()
                .help(L10n.text("Open source in"))
            }
            .font(.caption).foregroundStyle(.secondary)
            .controlSize(.small)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(minWidth: 700, minHeight: 400)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: model.selectedSession?.id) { _, _ in followLogs = true }
        .background {
            Button("") { searchFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .hidden().accessibilityHidden(true)
        }
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
        let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 2
        paragraph.paragraphSpacing = 6
        paragraph.headIndent = ("00:00:00  " as NSString).size(withAttributes: [.font: font]).width
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
            let message = entry.text as NSString
            let lineBreak = message.range(of: "\n")
            if lineBreak.location != NSNotFound {
                let continuation = paragraph.mutableCopy() as! NSMutableParagraphStyle
                continuation.firstLineHeadIndent = paragraph.headIndent
                let offset = NSMaxRange(lineBreak)
                output.addAttribute(
                    .paragraphStyle, value: continuation,
                    range: NSRange(location: start + offset, length: message.length - offset))
            }
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
