import SwiftUI
import AppKit
import FluttiosCore

private enum PickerMetrics {
    static let width: CGFloat = 360
}

private extension LaunchMode {
    var symbol: String {
        switch self {
        case .debug: return "ladybug"
        case .profile: return "gauge.with.dots.needle.50percent"
        case .release: return "shippingbox"
        }
    }
}

private extension SimulatorDevice {
    var symbol: String {
        switch targetPlatform {
        case "ios": return name.localizedCaseInsensitiveContains("ipad") ? "ipad" : "iphone"
        case "android": return "smartphone"
        case "darwin", "windows", "linux": return "desktopcomputer"
        case let platform where platform.hasPrefix("web"): return "globe"
        default: return "display"
        }
    }
}

struct ProjectMenu: View {
    @ObservedObject var model: AppModel
    var compact = false
    @State private var showingPicker = false

    var body: some View {
        Button { showingPicker.toggle() } label: {
            HStack(spacing: 4) {
                model.projectImage(model.store.selected)
                    .resizable().scaledToFit()
                    .frame(width: compact ? 17 : 16, height: compact ? 17 : 16)
                    .clipShape(RoundedRectangle(cornerRadius: compact ? 4 : 3, style: .continuous))
                    .accessibilityHidden(true)
                if !compact {
                    Text(model.store.selected.map { model.store.label($0) } ?? L10n.text("Open Project"))
                        .lineLimit(1).truncationMode(.tail)
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary).accessibilityHidden(true)
                }
            }.frame(maxWidth: compact ? nil : 180, alignment: .leading)
                .frame(width: compact ? PanelMetrics.controlSize : nil, height: compact ? PanelMetrics.controlHeight : nil)
                .modifier(PanelControlSurface(active: compact, pressed: showingPicker, bordered: compact))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingPicker, arrowEdge: .bottom) {
            ProjectPicker(model: model) { showingPicker = false }
        }
        .help(L10n.text("{0} — select a project. Running sessions are preserved.", "\(model.store.selected.map { model.store.label($0) } ?? L10n.text("Open Project"))"))
        .accessibilityLabel(L10n.text("Flutter project selection"))
        .accessibilityValue(model.store.selected.map { model.store.label($0) } ?? L10n.text("No project selected"))
    }
}

private struct ProjectPicker: View {
    @ObservedObject var model: AppModel
    let close: () -> Void
    @State private var search = ""

    private var projects: [Project] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.store.projects.filter {
            query.isEmpty || "\($0.name) \($0.path)".localizedCaseInsensitiveContains(query)
        }.sorted { $0.lastOpened > $1.lastOpened }
    }

    private var projectListHeight: CGFloat {
        let showsResult = projects.contains { $0.id == model.simulatorToolProjectID }
        let extra: CGFloat = !showsResult ? 0 : (model.simulatorToolBusy ? 30 : (model.simulatorToolResult == nil ? 0 : 80))
        return min(CGFloat(projects.count) * 58 - 2 + extra, 288)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(L10n.text("Projects")).font(.system(size: 13, weight: .semibold))
                Spacer()
                Button(action: close) { Image(systemName: "xmark") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .keyboardShortcut(.cancelAction).help(L10n.text("Close"))
                    .accessibilityLabel(L10n.text("Close project picker"))
            }.padding(.bottom, 8)

            if !model.store.projects.isEmpty {
                if model.store.projects.count > 5 {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
                        TextField(L10n.text("Search projects or folders"), text: $search).textFieldStyle(.plain)
                        if !search.isEmpty {
                            Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                                .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel(L10n.text("Clear search"))
                        }
                    }
                    .padding(8).background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 7))
                    .padding(.bottom, 8)
                }

                HStack {
                    Text(L10n.text("Recent Projects"))
                    Spacer()
                    Text("\(projects.count)").monospacedDigit()
                }
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                .padding(.horizontal, 8).padding(.bottom, 4)
            }

            if projects.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: model.store.projects.isEmpty ? "folder" : "magnifyingglass")
                        .font(.system(size: 24)).foregroundStyle(.secondary).accessibilityHidden(true)
                    Text(model.store.projects.isEmpty ? L10n.text("Open a Flutter Project") : L10n.text("No matches"))
                        .font(.system(size: 13, weight: .medium))
                    Text(model.store.projects.isEmpty ? L10n.text("Select a folder containing pubspec.yaml.") : L10n.text("Try another name or path."))
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity).padding(.vertical, 28)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(projects) { project in
                            ProjectChoiceRow(model: model, project: project) {
                                close()
                                model.select(project)
                            }
                        }
                    }
                }.frame(height: projectListHeight)
            }

            Text(L10n.text("Switching projects preserves running sessions."))
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
            Divider().padding(.vertical, 8)
            VStack(spacing: 4) {
                footerAction(L10n.text("Open Another Project…"), symbol: "folder.badge.plus") {
                    close()
                    model.openProject()
                }
                footerAction(L10n.text("Projects and Settings…"), symbol: "gearshape") {
                    close()
                    model.showSettings()
                }
            }
        }
        .padding(12).frame(width: PickerMetrics.width)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func footerAction(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol).frame(width: 24).foregroundStyle(.secondary).accessibilityHidden(true)
                Text(title).font(.system(size: 12, weight: .medium))
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary).accessibilityHidden(true)
            }.padding(8).modifier(PanelControlSurface())
        }.buttonStyle(.plain)
    }
}

private struct ProjectChoiceRow: View {
    @ObservedObject var model: AppModel
    let project: Project
    let action: () -> Void
    @State private var hovered = false
    @State private var heapBytes: Int64?

    private var selected: Bool { model.store.selectedID == project.id }
    private var state: SessionState { model.manager.sessions[project.id]?.state ?? .ready }
    private var device: SimulatorDevice? {
        model.manager.sessions[project.id]?.device ?? model.simulators.devices.first { $0.id == project.deviceID }
    }
    private var deviceTitle: String {
        device?.name ?? (project.deviceID == nil ? L10n.text("No device selected") : L10n.text("Device unavailable"))
    }
    private var statusTitle: String {
        switch state {
        case .running: return L10n.text("Running")
        case .ready: return L10n.text("Not running")
        default: return state.title
        }
    }
    private var isRunning: Bool { [.running, .reloading, .restarting].contains(state) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Button(action: action) {
                    HStack(spacing: 8) {
                        model.projectImage(project).resizable().scaledToFit()
                            .frame(width: 26, height: 26).clipShape(RoundedRectangle(cornerRadius: 5))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(project.name).font(.system(size: 12, weight: selected ? .semibold : .medium))
                                .lineLimit(1).truncationMode(.middle)
                            HStack(spacing: 5) {
                                Circle().fill(isRunning ? Color.green : Color.secondary.opacity(0.45))
                                    .frame(width: 6, height: 6).accessibilityHidden(true)
                                Label(deviceTitle, systemImage: device?.symbol ?? "display")
                                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        Spacer(minLength: 0)
                    }.frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("\(project.path) — \(statusTitle) — \(deviceTitle)")
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(project.name), \(statusTitle), \(deviceTitle)")
                .accessibilityValue((selected ? L10n.text("Selected") : L10n.text("Not selected")) + (heapBytes.map { L10n.text(", main Dart isolate memory: ") + ByteCountFormatter.string(fromByteCount: $0, countStyle: .memory) } ?? ""))
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 4) {
                        Button { model.openProjectFolder(project) } label: {
                            Image(systemName: "folder").frame(width: 20, height: 20)
                        }.help(L10n.text("Project Folder") + " — " + project.path)
                            .accessibilityLabel(L10n.text("Open project folder for {0}", "\(project.name)"))
                        Button { model.openProjectDataFolder(project.id) } label: {
                            Image(systemName: "externaldrive").frame(width: 20, height: 20)
                        }.help(L10n.text("Open app data on the simulator"))
                            .accessibilityLabel(L10n.text("Open app data for {0}", "\(project.name)"))
                            .disabled(model.simulatorToolBusy)
                        Button { model.resetProjectPermissions(project.id) } label: {
                            Image(systemName: "lock.rotation").frame(width: 20, height: 20)
                        }.help(model.manager.sessions[project.id]?.hasWork == true ? L10n.text("Press Stop before resetting permissions") : L10n.text("Reset app permissions"))
                            .accessibilityLabel(L10n.text("Reset app permissions for {0}", "\(project.name)"))
                            .disabled(model.simulatorToolBusy || model.manager.sessions[project.id]?.hasWork == true)
                    }.font(.system(size: 11)).buttonStyle(.borderless).controlSize(.small)
                    if let heapBytes, state == .running {
                        Text("Dart \(ByteCountFormatter.string(fromByteCount: heapBytes, countStyle: .memory))")
                            .font(.system(size: 10)).monospacedDigit().foregroundStyle(.secondary)
                            .help(L10n.text("Main Dart isolate memory. Excludes the Flutter engine, graphics, and other isolates."))
                    } else if state == .running {
                        Text(model.manager.sessions[project.id]?.launchProject?.launch.mode.title ?? project.launch.mode.title)
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
                Image(systemName: "checkmark").font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.accentColor).opacity(selected ? 1 : 0).frame(width: 12).accessibilityHidden(true)
            }.padding(8)
            if model.simulatorToolProjectID == project.id {
                if model.simulatorToolBusy {
                    HStack(spacing: 6) { ProgressView().controlSize(.mini); Text(L10n.text("Action in progress…")) }
                        .font(.system(size: 11)).padding(.horizontal, 8).padding(.bottom, 8)
                } else if let result = model.simulatorToolResult {
                    Text(L10n.display(result)).font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                        .padding(.horizontal, 8).padding(.bottom, 8)
                }
            }
        }
        .background(selected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(hovered ? 0.05 : 0), in: RoundedRectangle(cornerRadius: 8))
        .onHover { hovered = $0 }
        .task(id: state) {
            heapBytes = nil
            guard state == .running else { return }
            while !Task.isCancelled {
                let value = await model.manager.sessions[project.id]?.mainIsolateHeapBytes()
                guard !Task.isCancelled else { return }
                heapBytes = value
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
            }
        }
    }
}

private enum PanelMetrics {
    static let controlSize: CGFloat = 36
    static let controlHeight: CGFloat = 34
    static let rowHeight: CGFloat = 48
    static let groupSpacing: CGFloat = 8
    static let inset: CGFloat = 7
    static let logsColor = Color(red: 0.88, green: 0.52, blue: 0.49)
    static let iconSize: CGFloat = 14
}

private struct PanelIcon: View {
    let symbol: String
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: PanelMetrics.iconSize, weight: .medium))
            .imageScale(.medium)
            .frame(width: 18, height: 18)
            .accessibilityHidden(true)
    }
}

private struct PanelSettingsIcon: View {
    let hasError: Bool
    private static let settings = coloredSymbol("gearshape", color: NSColor(red: 0.42, green: 0.70, blue: 0.95, alpha: 1))
    private static let error = coloredSymbol("exclamationmark.triangle", color: .systemOrange)

    var body: some View {
        Image(nsImage: hasError ? Self.error : Self.settings)
            .renderingMode(.original)
            .frame(width: 18, height: 18)
            .accessibilityHidden(true)
    }

    // Native macOS menus otherwise turn SF Symbols into monochrome template images.
    private static func coloredSymbol(_ name: String, color: NSColor) -> NSImage {
        let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)!
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: PanelMetrics.iconSize, weight: .medium))!
        let size = symbol.size
        return NSImage(size: size, flipped: false) { rect in
            symbol.draw(in: rect)
            color.setFill()
            rect.fill(using: .sourceAtop)
            return true
        }
    }
}

private struct PanelControlSurface: ViewModifier {
    var active = true
    var pressed = false
    var bordered = false
    @Environment(\.isEnabled) private var enabled
    @State private var hovered = false

    func body(content: Content) -> some View {
        content
            .background {
                if active {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.primary.opacity(enabled && (hovered || pressed) ? 0.10 : (bordered ? 0.055 : 0)))
                        .overlay {
                            if bordered {
                                RoundedRectangle(cornerRadius: 7)
                                    .strokeBorder(Color.primary.opacity(0.11), lineWidth: 0.5)
                            }
                        }
                }
            }
            .contentShape(Rectangle())
            .onHover { hovered = $0 }
    }
}

struct PanelButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PanelButtonContent(configuration: configuration)
    }
    private struct PanelButtonContent: View {
        let configuration: ButtonStyle.Configuration
        @Environment(\.isEnabled) private var enabled
        var body: some View {
            configuration.label
                .font(.system(size: PanelMetrics.iconSize, weight: .medium))
                .frame(width: PanelMetrics.controlSize, height: PanelMetrics.controlHeight)
                .modifier(PanelControlSurface(pressed: configuration.isPressed, bordered: true))
                .opacity(enabled ? 1 : 0.35)
        }
    }
}

struct DeviceMenu: View {
    @ObservedObject var model: AppModel
    var compact = false
    @State private var showingPicker = false

    var body: some View {
        Button { showingPicker.toggle() } label: {
            HStack(spacing: 4) {
                if compact {
                    PanelIcon(symbol: model.selectedDevice?.symbol ?? "iphone")
                } else {
                    Image(systemName: model.selectedDevice?.symbol ?? "iphone")
                        .frame(width: 14).accessibilityHidden(true)
                }
                if !compact {
                    Text("\(model.launchMode.title) · \(model.selectedDevice?.name ?? (model.store.selected?.deviceID != nil ? L10n.text("Unavailable") : L10n.text("Automatic")))")
                        .lineLimit(1).truncationMode(.middle)
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary).accessibilityHidden(true)
                }
            }.frame(maxWidth: compact ? nil : 300, alignment: .leading)
                .frame(width: compact ? PanelMetrics.controlSize : nil, height: compact ? PanelMetrics.controlHeight : nil)
                .modifier(PanelControlSurface(active: compact, pressed: showingPicker, bordered: compact))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingPicker, arrowEdge: .bottom) {
            DevicePicker(model: model) { showingPicker = false }
        }
        .help(L10n.text("Select device and launch mode"))
        .accessibilityLabel(L10n.text("Device and launch mode"))
        .accessibilityValue("\(model.launchMode.title), \(model.selectedDevice?.name ?? (model.store.selected?.deviceID != nil ? L10n.text("Unavailable") : L10n.text("Automatic")))")
    }
}

private struct DevicePicker: View {
    @ObservedObject var model: AppModel
    let close: () -> Void
    @State private var search = ""

    private var canEdit: Bool { model.store.selected != nil && model.selectedSession?.hasWork != true }
    private var devices: [SimulatorDevice] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.simulators.devices.filter {
            query.isEmpty || "\($0.name) \($0.runtime ?? "")".localizedCaseInsensitiveContains(query)
        }.sorted {
            if ($0.state == "Booted") != ($1.state == "Booted") { return $0.state == "Booted" }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(L10n.text("Device and Launch")).font(.system(size: 16, weight: .semibold))
                Spacer()
                Button(action: close) { Image(systemName: "xmark") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .keyboardShortcut(.cancelAction).help(L10n.text("Close"))
                    .accessibilityLabel(L10n.text("Close device picker"))
            }.padding(.bottom, 16)

            Text(L10n.text("Launch Mode")).font(.system(size: 12, weight: .semibold)).padding(.bottom, 8)
            HStack(spacing: 8) {
                ForEach(LaunchMode.allCases, id: \.self) { mode in
                    Button { model.chooseLaunchMode(mode) } label: {
                        Label(mode.title, systemImage: mode.symbol)
                            .font(.system(size: 12, weight: .medium))
                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                            .foregroundStyle(model.launchMode == mode ? Color.accentColor : Color.primary)
                            .background(model.launchMode == mode ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canEdit || !mode.supports(model.selectedDevice))
                    .accessibilityValue(model.launchMode == mode ? L10n.text("Selected") : L10n.text("Not selected"))
                }
            }
            Text(model.selectedDevice == nil || model.selectedDevice?.isEmulator == true
                 ? L10n.text("Only Debug is available on simulators.")
                 : L10n.text("Debug — debugging · Profile — performance · Release — production"))
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 8)

            Divider().padding(.vertical, 16)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
                TextField(L10n.text("Search devices or OS versions"), text: $search).textFieldStyle(.plain)
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel(L10n.text("Clear search"))
                }
            }
            .padding(10).background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 7))
            .padding(.bottom, 8)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(0..<3, id: \.self) { section in
                        let group = devices.filter { device in
                            let pinned = model.pinnedSimulatorIDs.contains(device.id)
                            switch section {
                            case 0: return device.isIOSSimulator && pinned
                            case 1: return device.isIOSSimulator && !pinned
                            default: return !device.isIOSSimulator
                            }
                        }
                        if !group.isEmpty {
                            HStack {
                                Text(section == 0 ? L10n.text("Pinned") : (section == 1 ? L10n.text("iOS Simulators") : L10n.text("Other Devices")))
                                Spacer()
                                Text("\(group.count)").monospacedDigit()
                            }
                            .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                            .padding(.horizontal, 10).padding(.top, 12).padding(.bottom, 4)
                            ForEach(group) { device in
                                DeviceChoiceRow(symbol: device.symbol, title: device.name, detail: runtimeTitle(device),
                                                selected: model.store.selected?.deviceID == device.id,
                                                status: model.bootingSimulatorIDs.contains(device.id) ? L10n.text("Starting…") : statusTitle(device),
                                                active: device.state == "Booted",
                                                canSelect: canEdit,
                                                pinned: device.isIOSSimulator ? model.pinnedSimulatorIDs.contains(device.id) : nil,
                                                booting: model.bootingSimulatorIDs.contains(device.id),
                                                pin: device.isIOSSimulator ? { model.toggleSimulatorPin(device) } : nil,
                                                boot: device.isIOSSimulator && device.isAvailable && device.state == "Shutdown" ? { model.bootSimulator(device) } : nil) {
                                    model.chooseDevice(device)
                                }
                            }
                        }
                    }
                    if devices.isEmpty {
                        VStack(spacing: 6) {
                            Text(model.simulators.refreshing ? L10n.text("Searching for devices…") : (search.isEmpty ? L10n.text("No devices found") : L10n.text("No matches"))).fontWeight(.medium)
                            Text(model.simulators.refreshing ? L10n.text("Getting the list from Xcode and Flutter.") : (search.isEmpty ? L10n.text("Refresh the list and check the connection.") : L10n.text("Try another name or OS version.")))
                                .font(.system(size: 12)).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity).padding(.vertical, 32)
                    }
                }
                .padding(.bottom, 8)
            }
            .frame(height: 340)

            Divider().padding(.vertical, 12)
            if let error = model.simulatorBootError {
                notice(error, symbol: "exclamationmark.triangle")
            }
            if !model.simulators.refreshing, let id = model.store.selected?.deviceID, !model.simulators.devices.contains(where: { $0.id == id }) {
                notice(L10n.text("The saved device is unavailable. Select another one."), symbol: "exclamationmark.triangle")
            }
            if model.selectedSession?.hasWork == true {
                notice(L10n.text("Press Stop to change the device or mode."), symbol: "lock")
            } else if model.store.selected == nil {
                notice(L10n.text("Open a Flutter project first."), symbol: "folder")
            }
            if model.standaloneTarget {
                notice(L10n.text("The panel works independently for this device."), symbol: "macwindow")
            }
            HStack {
                Button { model.chooseDevice(nil) } label: {
                    Label(L10n.text("Automatic"), systemImage: model.store.selected?.deviceID == nil ? "checkmark" : "sparkles")
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(model.store.selected?.deviceID == nil ? Color.accentColor : Color.primary)
                }
                .disabled(!canEdit)
                .help(L10n.text("Select a running simulator when pressing Run"))
                .accessibilityValue(model.store.selected?.deviceID == nil ? L10n.text("Selected") : L10n.text("Not selected"))
                Button { Task { await model.refreshDevices() } } label: {
                    Label(model.simulators.refreshing ? L10n.text("Refreshing…") : L10n.text("Refresh"), systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }.disabled(model.simulators.refreshing)
            }.buttonStyle(.bordered).controlSize(.small)
            if model.simulators.error != nil {
                Button { model.message = model.simulators.error } label: {
                    Label(L10n.text("Device discovery error"), systemImage: "exclamationmark.triangle")
                }.foregroundStyle(.orange).controlSize(.small).padding(.top, 8)
            }
        }
        .padding(20).frame(width: PickerMetrics.width)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func notice(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol).font(.system(size: 11)).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true).padding(.bottom, 10)
    }

    private func runtimeTitle(_ device: SimulatorDevice) -> String {
        let runtime = device.runtime ?? device.targetPlatform
        // simctl runtime identifiers arrive as “iOS 26 5”.
        if device.isIOSSimulator, runtime.hasPrefix("iOS ") {
            return "iOS " + runtime.dropFirst(4).replacingOccurrences(of: " ", with: ".")
        }
        return runtime
    }

    private func statusTitle(_ device: SimulatorDevice) -> String {
        switch device.state {
        case "Booted": return L10n.text("Running")
        case "Shutdown": return L10n.text("Shut down")
        case "Available": return L10n.text("Available")
        default: return device.state
        }
    }
}

private struct DeviceChoiceRow: View {
    let symbol: String
    let title: String
    let detail: String
    let selected: Bool
    let status: String?
    let active: Bool
    var canSelect = true
    var pinned: Bool? = nil
    var booting = false
    var pin: (() -> Void)? = nil
    var boot: (() -> Void)? = nil
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 6) {
            Button(action: action) {
                HStack(spacing: 10) {
                    Image(systemName: symbol).font(.system(size: 18))
                        .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                        .frame(width: 24).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title).font(.system(size: 13, weight: selected ? .semibold : .medium))
                            .lineLimit(2).multilineTextAlignment(.leading)
                        Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
                            .lineLimit(2).multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 8)
                    if let status {
                        HStack(spacing: 4) {
                            if active { Circle().fill(.green).frame(width: 5, height: 5).accessibilityHidden(true) }
                            Text(status)
                        }.font(.system(size: 10, weight: active ? .medium : .regular))
                            .foregroundStyle(active ? Color.primary : Color.secondary).fixedSize()
                    }
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.accentColor).opacity(selected ? 1 : 0)
                        .frame(width: 12).accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain).disabled(!canSelect)
            .help("\(title) — \(detail)\(status.map { " — " + $0 } ?? "")")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(title), \(detail)\(status.map { ", " + $0 } ?? "")")
            .accessibilityValue(selected ? L10n.text("Selected") : L10n.text("Not selected"))

            if pinned != nil {
                Group {
                    if booting {
                        ProgressView().controlSize(.small).accessibilityLabel(L10n.text("Starting {0}", "\(title)"))
                    } else if let boot {
                        Button(action: boot) { Image(systemName: "play.fill") }
                            .buttonStyle(.borderless).foregroundStyle(Color.accentColor)
                            .help(L10n.text("Start simulator {0}", "\(title)"))
                            .accessibilityLabel(L10n.text("Start simulator {0}", "\(title)"))
                    } else {
                        Color.clear.accessibilityHidden(true)
                    }
                }.frame(width: 28, height: 28)
                if let pin {
                    Button(action: pin) { Image(systemName: pinned == true ? "pin.fill" : "pin") }
                        .buttonStyle(.borderless)
                        .foregroundStyle(pinned == true ? Color.accentColor : Color.secondary)
                        .frame(width: 28, height: 28)
                        .help(pinned == true ? L10n.text("Unpin {0}", "\(title)") : L10n.text("Pin {0}", "\(title)"))
                        .accessibilityLabel(pinned == true ? L10n.text("Unpin {0}", "\(title)") : L10n.text("Pin {0}", "\(title)"))
                }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .background(selected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(hovered ? 0.05 : 0), in: RoundedRectangle(cornerRadius: 8))
        .onHover { hovered = $0 }
    }
}

struct SessionButtons: View {
    @ObservedObject var model: AppModel
    var compact = false
    var essentialsOnly = false
    var body: some View {
        Group {
            if compact {
                buttons.labelStyle(.iconOnly).buttonStyle(PanelButtonStyle())
            } else {
                buttons.buttonStyle(.bordered).controlSize(.small)
            }
        }
        .disabled(model.manager.shuttingDown || (model.store.selectedID.map { model.manager.foregroundIDs.contains($0) } ?? false))
    }
    @ViewBuilder
    private func sessionIcon(_ symbol: String, regular: String) -> some View {
        if compact {
            PanelIcon(symbol: symbol)
        } else {
            Image(systemName: regular)
        }
    }
    private var buttons: some View {
        Group {
            Button { model.run() } label: { Label { Text("Run") } icon: { sessionIcon("play", regular: "play.fill") }.foregroundStyle(.green) }
                .disabled(model.selectedSession.map { !$0.canRun } ?? false)
                .help(L10n.text("Run — start a new {0} session on the selected device", "\(model.launchMode.title)"))
            if !essentialsOnly {
            Button { model.restart(full: false) } label: { Label { Text("Hot Reload") } icon: { sessionIcon("bolt", regular: "bolt.fill") }.foregroundStyle(.orange) }
                .disabled(!(model.selectedSession?.canRestart ?? false))
                .help(L10n.text("Hot Reload — preserve Dart state"))
            Button { model.restart(full: true) } label: { Label { Text("Hot Restart") } icon: { sessionIcon("arrow.clockwise", regular: "arrow.clockwise") }.foregroundStyle(.green) }
                .disabled(!(model.selectedSession?.canRestart ?? false))
                .help(L10n.text("Hot Restart — reset Dart state. After native code changes, use Stop and Run."))
            }
            Button { model.selectedSession?.stop() } label: { Label { Text("Stop") } icon: { sessionIcon("stop", regular: "stop.fill") }.foregroundStyle(.red) }
                .disabled(!(model.selectedSession?.canStop ?? false))
                .help(L10n.text("Stop — stop only the selected session"))
        }
    }
}

struct PanelDragHandle: NSViewRepresentable {
    let model: AppModel
    func makeNSView(context: Context) -> DragView {
        let view = DragView(); view.drag = model.dragPanel; return view
    }
    func updateNSView(_ view: DragView, context: Context) { view.drag = model.dragPanel }
    final class DragView: NSView {
        var drag: (NSEvent) -> Void = { _ in }
        override var mouseDownCanMoveWindow: Bool { false }
        override func mouseDown(with event: NSEvent) { drag(event) }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    }
}

struct PanelView: View {
    @ObservedObject var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingError = false
    private var hasError: Bool { model.message != nil || model.selectedSession?.error != nil }
    private var busy: Bool {
        model.selectedSession?.state.isBusy ?? false
    }
    private var hubBackground: Color {
        colorScheme == .dark ? Color(red: 32 / 255, green: 38 / 255, blue: 36 / 255) : Color(nsColor: .windowBackgroundColor)
    }
    private var panelLayout: AnyLayout {
        model.verticalPanel ? AnyLayout(VStackLayout(spacing: PanelMetrics.groupSpacing)) : AnyLayout(HStackLayout(spacing: PanelMetrics.groupSpacing))
    }
    private var compactActions: Bool { !model.verticalPanel && model.panelWidth < 380 }
    private var blockSeparator: some View {
        Group {
        if model.verticalPanel {
            VStack(spacing: 0) {
                PanelDragHandle(model: model).frame(height: 11)
                Rectangle().fill(Color.primary.opacity(0.22)).frame(width: 18, height: 1).accessibilityHidden(true)
                PanelDragHandle(model: model).frame(height: 12)
            }.frame(width: PanelMetrics.controlSize, height: 24)
        } else {
        HStack(spacing: 0) {
            PanelDragHandle(model: model).frame(minWidth: 6, maxWidth: .infinity)
            Rectangle().fill(Color.primary.opacity(0.22)).frame(width: 1, height: 18)
                .accessibilityHidden(true)
            PanelDragHandle(model: model).frame(minWidth: 6, maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
        .frame(height: PanelMetrics.rowHeight)
        }
        }
        .help(L10n.text("Drag the panel using the space between buttons"))
    }
    var body: some View {
        VStack(spacing: 0) {
        let layout = model.verticalPanel ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))
        layout {
            panelLayout {
                ProjectMenu(model: model, compact: true)
                DeviceMenu(model: model, compact: true)
            }
            blockSeparator
            panelLayout {
                SessionButtons(model: model, compact: true, essentialsOnly: compactActions)
            }
            blockSeparator
            panelLayout {
            Button { model.showLogs() } label: {
                PanelIcon(symbol: "doc.text").foregroundStyle(PanelMetrics.logsColor)
            }
            .buttonStyle(PanelButtonStyle())
            .accessibilityLabel(L10n.text("Show logs for the selected project"))
            .help(L10n.text("Show logs for the selected project"))
            Menu {
                if compactActions {
                    Button { model.restart(full: false) } label: { Label("Hot Reload", systemImage: "bolt") }
                        .disabled(!(model.selectedSession?.canRestart ?? false))
                    Button { model.restart(full: true) } label: { Label("Hot Restart", systemImage: "arrow.clockwise") }
                        .disabled(!(model.selectedSession?.canRestart ?? false))
                    Divider()
                }
                if hasError {
                    Button { showingError = true } label: { Label(L10n.text("Show Error…"), systemImage: "exclamationmark.triangle") }
                    Divider()
                }
                Button { model.showSettings() } label: { Label(L10n.text("Settings…"), systemImage: "gearshape") }
                Menu {
                    Toggle(L10n.text("Free Position"), isOn: $model.freePanel)
                    Button(L10n.text("Reset Position")) { model.resetPanel() }
                    Menu(L10n.text("Attach to Simulator Window")) {
                        if model.tracker.windows.isEmpty { Text(model.tracker.trusted ? L10n.text("No open Simulator windows") : L10n.text("Allow access in Fluttios settings")) }
                        ForEach(model.tracker.windows) { window in
                            Button("\(window.title) (\(Int(window.frame.minX)), \(Int(window.frame.minY)))") { model.bindWindow(window.id) }
                        }
                    }
                    Divider()
                    Button(L10n.text("Refresh Attachment")) { model.tracker.refresh() }
                } label: { Label(L10n.text("Panel Position"), systemImage: "rectangle.3.group") }
                Divider()
                Button { model.quitApp() } label: { Label(L10n.text("Quit Fluttios"), systemImage: "power") }
            } label: {
                Color.clear.frame(width: 18, height: 18)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden)
            .frame(width: PanelMetrics.controlSize, height: PanelMetrics.controlHeight)
            // AppKit reserves menu-label insets even with its indicator hidden.
            .overlay { PanelSettingsIcon(hasError: hasError).allowsHitTesting(false) }
            .modifier(PanelControlSurface(bordered: true))
            .accessibilityLabel(L10n.text("Panel settings and menu")).help(model.selectedSession?.progressMessage ?? model.selectedSession?.state.title ?? L10n.text("Panel settings and menu"))
            .popover(isPresented: $showingError, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.text("Could not complete the action")).font(.headline)
                    if let error = model.selectedSession?.error { Text(L10n.display(error)).font(.caption).textSelection(.enabled) }
                    if let message = model.message { Text(L10n.display(message)).font(.caption).textSelection(.enabled) }
                    Button(L10n.text("Open Logs…")) { model.showLogs() }
                    Button(L10n.text("Close")) { showingError = false; model.message = nil }
                }.padding(16).frame(width: 300, alignment: .leading)
            }
            }
        }
        .padding(model.verticalPanel ? .vertical : .horizontal, PanelMetrics.inset)
        .frame(width: model.panelWidth, height: model.verticalPanel ? 374 : PanelMetrics.rowHeight)
        if busy && !model.verticalPanel {
            HStack(spacing: 10) {
                Text(L10n.display(model.selectedSession?.progressMessage ?? model.selectedSession?.state.title ?? L10n.text("Working…")))
                    .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .help(L10n.display(model.selectedSession?.progressMessage ?? ""))
                ProgressView().progressViewStyle(.linear).frame(width: 90)
                    .accessibilityLabel(L10n.text("Operation in progress; exact percentage unavailable"))
            }.padding(.horizontal, 12).padding(.bottom, 5).frame(height: 22)
        }
        }
        .frame(width: model.panelWidth, height: model.panelHeight)
        .environment(\.locale, L10n.locale)
        .background(hubBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5))
        .onChange(of: model.message) { _, message in if message != nil { showingError = true } }
        .onChange(of: model.selectedSession?.error) { _, error in if error != nil { showingError = true } }
    }
}

private enum SettingsDestination: String, CaseIterable, Identifiable {
    case general, projects, tools, panel
    var id: Self { self }
    var title: String {
        switch self {
        case .general: return L10n.text("General")
        case .projects: return L10n.text("Projects")
        case .tools: return L10n.text("Tools")
        case .panel: return L10n.text("Panel")
        }
    }
    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .projects: return "folder"
        case .tools: return "wrench.and.screwdriver"
        case .panel: return "macwindow"
        }
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    private let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                .padding(.horizontal, 18)
            VStack(alignment: .leading, spacing: 0) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1))
        }
    }
}

private struct SettingsField<Content: View>: View {
    let title: String
    private let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 24) {
                Text(title).font(.system(size: 13, weight: .medium)).fixedSize()
                Spacer(minLength: 0)
                content.frame(minWidth: 240, maxWidth: 380)
            }
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.system(size: 13, weight: .medium))
                content
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 16)
    }
}

private struct SettingsNote: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.callout).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 18).padding(.vertical, 14)
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var destination: SettingsDestination = .general
    @State private var confirmClearProjects = false

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                        .font(.system(size: 24)).foregroundStyle(Color.blue).accessibilityHidden(true)
                    Text("Fluttios").font(.system(size: 23, weight: .bold))
                }.padding(.horizontal, 22).padding(.top, 30).padding(.bottom, 26)
                Divider().padding(.horizontal, 16)
                VStack(spacing: 6) {
                    ForEach(SettingsDestination.allCases) { item in
                        Button { destination = item } label: {
                            HStack(spacing: 12) {
                                Image(systemName: item.symbol).font(.system(size: 20)).frame(width: 26).accessibilityHidden(true)
                                Text(item.title).font(.system(size: 15, weight: destination == item ? .semibold : .regular))
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 14).frame(height: 48)
                            .foregroundStyle(destination == item ? Color.white : Color.primary)
                            .background(destination == item ? Color.blue : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                            .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                            .accessibilityValue(destination == item ? L10n.text("Selected") : L10n.text("Not selected"))
                    }
                }.padding(14)
                Spacer()
                Divider()
                Button { model.showPanel() } label: {
                    Label(L10n.text("Show Panel"), systemImage: "rectangle.on.rectangle")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.plain).padding(20)
            }
            .frame(width: 220)
            .background(Color(nsColor: .underPageBackgroundColor))
            Divider()
            VStack(spacing: 0) {
                HStack {
                    Text(destination.title).font(.system(size: 23, weight: .semibold))
                    Spacer()
                    if destination == .projects {
                        Button(L10n.text("Open Project…"), systemImage: "plus") { model.openProject() }
                    }
                }.padding(.horizontal, 28).padding(.top, 28).padding(.bottom, 22)
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        if let error = model.store.persistenceError {
                            SettingsSection(L10n.text("Save Error")) {
                                Text(L10n.display(error)).foregroundStyle(.red).textSelection(.enabled).padding(18)
                                Divider()
                                Button(L10n.text("Retry Saving with Backup")) {
                                    do { let backup = try model.store.recoverPersistence(); model.message = backup.map { L10n.text("Previous file preserved: ") + $0.path } ?? L10n.text("Saving restored.") }
                                    catch { model.message = error.localizedDescription }
                                }.padding(18)
                            }
                        }
                        switch destination {
                        case .general: generalSettings
                        case .projects: projectSettings
                        case .tools: toolsSettings
                        case .panel: panelSettings
                        }
                        if let message = model.message {
                            HStack(alignment: .top, spacing: 12) {
                                Text(L10n.display(message)).font(.callout).textSelection(.enabled)
                                Spacer(minLength: 0)
                                Button { model.message = nil } label: { Image(systemName: "xmark") }
                                    .buttonStyle(.plain).accessibilityLabel(L10n.text("Dismiss message"))
                            }.padding(18).background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                        }
                    }.frame(maxWidth: 860, alignment: .leading)
                        .padding(.horizontal, 28).padding(.bottom, 28)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                Divider()
                HStack {
                    Text(L10n.text("Settings are saved automatically"))
                    Spacer()
                    Text("Fluttios")
                }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 28).frame(height: 40)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .environment(\.locale, L10n.locale)
        .tint(.blue)
        .frame(minWidth: 920, minHeight: 640)
    }

    private var projectSettings: some View {
        VStack(alignment: .leading, spacing: 28) {
            if model.store.projects.isEmpty {
                ContentUnavailableView(L10n.text("Open a Flutter Project"), systemImage: "folder", description: Text(L10n.text("Select a folder containing pubspec.yaml. The app starts only after you press Run.")))
            } else {
                SettingsSection(L10n.text("Saved Projects")) {
                    ForEach(Array(model.store.projects.enumerated()), id: \.element.id) { index, project in
                        if index > 0 { Divider() }
                        SavedProjectSettingsRow(model: model, project: project)
                    }
                }
                HStack {
                    if model.manager.hasActiveSessions {
                        Text(L10n.text("Stop running sessions before clearing saved projects."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(L10n.text("Clear Saved Projects…"), role: .destructive) { confirmClearProjects = true }
                        .disabled(!model.canClearSavedProjects)
                }
                if let project = model.store.selected {
                    ProjectEditor(model: model, initial: project).id(project.id)
                }
            }
        }
        .confirmationDialog(L10n.text("Clear all saved projects? Project files and app data will remain on disk."), isPresented: $confirmClearProjects) {
            Button(L10n.text("Clear Saved Projects"), role: .destructive) { model.clearSavedProjects() }
            Button(L10n.text("Cancel"), role: .cancel) {}
        }
    }

    private var toolsSettings: some View {
        VStack(alignment: .leading, spacing: 28) {
            SettingsSection(L10n.text("Project and Simulator")) {
                SettingsField(L10n.text("Project")) {
                    Picker(L10n.text("Project"), selection: Binding(get: { model.store.selectedID }, set: { id in
                        if let project = model.store.projects.first(where: { $0.id == id }) { model.select(project) }
                    })) {
                        Text(L10n.text("Select a project")).tag(nil as UUID?)
                        ForEach(model.store.projects) { project in
                            Text(model.store.label(project)).tag(Optional(project.id))
                        }
                    }.labelsHidden().accessibilityLabel(L10n.text("Project for simulator tools"))
                }
                Divider()
                SettingsField(L10n.text("Device")) { DeviceMenu(model: model) }
            }
            if let project = model.store.selected {
                SimulatorToolsSettings(model: model, project: project).id(project.id)
            } else {
                Text(L10n.text("Add a Flutter project in Projects to use simulator tools."))
                    .font(.callout).foregroundStyle(.secondary)
            }

            SettingsSection("Flutter SDK") {
                SettingsField(L10n.text("Default SDK")) {
                    HStack {
                        TextField(L10n.text("Automatic"), text: $model.globalSDK)
                            .textFieldStyle(.roundedBorder).accessibilityLabel(L10n.text("Default Flutter SDK"))
                        Button(L10n.text("Choose…")) { model.chooseSDK { model.globalSDK = $0 } }
                    }
                }
                Divider()
                SettingsNote(L10n.text("Used when the project has no SDK configured. Searches Homebrew, standard SDK folders, and the project's .fvm/flutter_sdk."))
            }
            SettingsSection(L10n.text("Development Environment")) {
                SettingsField(L10n.text("Flutter and Xcode")) {
                    HStack {
                        Spacer(minLength: 0)
                        if model.checkingTools { ProgressView().controlSize(.small) }
                        Button(model.checkingTools ? L10n.text("Checking…") : L10n.text("Check")) { model.checkTools() }.disabled(model.checkingTools)
                    }
                }
                Divider()
                SettingsNote(L10n.text("Xcode is selected from system settings or an installed app. Finder uses its own PATH."))
                if let error = model.simulators.error {
                    Divider()
                    Text(L10n.display(error)).font(.callout).foregroundStyle(.red).textSelection(.enabled).padding(18)
                }
            }
        }
    }

    private var panelSettings: some View {
        VStack(alignment: .leading, spacing: 28) {
            SettingsSection(L10n.text("Panel Placement")) {
                Toggle(L10n.text("Free Position"), isOn: $model.freePanel)
                    .toggleStyle(.switch).padding(18)
                Divider()
                SettingsField(L10n.text("Simulator Side")) {
                    Picker(L10n.text("Side of the Simulator window"), selection: $model.panelSide) {
                        ForEach(PanelSide.allCases, id: \.self) { side in Text(side.title).tag(side) }
                    }.labelsHidden().pickerStyle(.segmented).disabled(model.standalonePanel)
                }
                Divider()
                SettingsNote(model.freePanel ? L10n.text("Turn off Free Position to choose an attachment side.") : (model.standalonePanel ? L10n.text("For this device, the panel works independently of Simulator.") : L10n.text("If there is not enough room on the selected side, the panel appears on the opposite side.")))
            }
            SettingsSection(L10n.text("Simulator Window Access")) {
                SettingsField(L10n.text("Accessibility")) {
                    HStack {
                        Spacer(minLength: 0)
                        Label(model.tracker.trusted ? L10n.text("Allowed") : L10n.text("Permission required"), systemImage: model.tracker.trusted ? "checkmark.circle" : "lock")
                            .foregroundStyle(.secondary)
                    }
                }
                Divider()
                SettingsNote(L10n.text("Enable Fluttios in System Settings → Privacy & Security → Accessibility. Access is detected automatically."))
                if !model.tracker.trusted {
                    Divider()
                    HStack {
                        Button(L10n.text("Allow Access…")) { model.tracker.requestPermission() }
                        Spacer()
                        Button(L10n.text("Check Permission")) { model.tracker.refresh() }
                    }.padding(18)
                }
                Divider()
                SettingsNote(L10n.text("You can select a window manually in the panel menu: ⚙ → Panel Position → Attach to Simulator Window."))
            }
        }
    }

    private var generalSettings: some View {
        VStack(alignment: .leading, spacing: 28) {
            SettingsSection("Fluttios") {
                SettingsField(L10n.text("Version")) {
                    Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.1")
                        .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .textSelection(.enabled)
                }
                Divider()
                SettingsField(L10n.text("Build")) {
                    Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "2")
                        .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            SettingsSection(L10n.text("Language")) {
                SettingsField(L10n.text("Language")) {
                    Picker(L10n.text("Language"), selection: $model.language) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.title).tag(language)
                        }
                    }.labelsHidden().accessibilityLabel(L10n.text("Language"))
                }
                Divider()
                SettingsNote(L10n.text("Follows the system language. English is used for unsupported languages."))
            }
            SettingsSection(L10n.text("Automatic Launch")) {
                Toggle(L10n.text("Launch with Simulator"), isOn: Binding(get: { model.background.enabled || model.background.status == .requiresApproval }, set: { model.background.setEnabled($0) }))
                    .toggleStyle(.switch).padding(18)
                Divider()
                SettingsField(L10n.text("Background Helper")) {
                    Text(model.background.title).font(.callout).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                if let error = model.background.error {
                    Divider()
                    Text(L10n.display(error)).font(.callout).foregroundStyle(.red).textSelection(.enabled).padding(18)
                }
                Divider()
                SettingsField(L10n.text("macOS Settings")) {
                    Button(L10n.text("Open Login Items…")) { model.background.systemSettings() }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
    }
}

private struct SimulatorToolsSettings: View {
    @ObservedObject var model: AppModel
    let project: Project
    @State private var editingLink: SavedDeepLink?
    @State private var linkName = ""
    @State private var linkURL = ""
    @State private var linkError: String?
    private var session: FlutterSession? { model.manager.sessions[project.id] }
    private var available: Bool {
        model.simulatorToolDevice?.isIOSSimulator == true && model.simulatorToolDevice?.state == "Booted"
            && !model.simulatorToolBusy && session?.state.isBusy != true
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            SettingsSection(L10n.text("Saved Links")) {
                if project.deepLinks.isEmpty {
                    SettingsNote(L10n.text("Save links to screens and test scenarios for this project."))
                }
                ForEach(project.deepLinks) { link in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(link.name).font(.body.weight(.medium))
                            Text(link.url).font(.callout).foregroundStyle(.secondary)
                                .textSelection(.enabled).lineLimit(2).help(link.url)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        Button(L10n.text("Open")) { model.simulatorAction(.link(link.url)) }.disabled(!available)
                            .accessibilityLabel(L10n.text("Open link {0}", "\(link.name)"))
                        Button { edit(link) } label: { Image(systemName: "pencil") }
                            .accessibilityLabel(L10n.text("Edit link {0}", "\(link.name)")).help(L10n.text("Edit link"))
                        Button(role: .destructive) { remove(link) } label: { Image(systemName: "trash") }
                            .accessibilityLabel(L10n.text("Delete link {0}", "\(link.name)")).help(L10n.text("Delete link"))
                    }.padding(18)
                    Divider()
                }
                if editingLink != nil {
                    VStack(alignment: .leading, spacing: 12) {
                        TextField(L10n.text("Link name"), text: $linkName).textFieldStyle(.roundedBorder)
                            .accessibilityLabel(L10n.text("Link name"))
                        TextField(L10n.text("myapp://profile or https://example.com/profile"), text: $linkURL)
                            .textFieldStyle(.roundedBorder).accessibilityLabel(L10n.text("Link URL")).onSubmit { saveLink() }
                        if let linkError { Text(linkError).font(.callout).foregroundStyle(.red) }
                        HStack {
                            Button(L10n.text("Cancel")) { editingLink = nil; linkError = nil }
                            Spacer()
                            Button(L10n.text("Save")) { saveLink() }
                                .disabled(linkName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || linkURL.isEmpty)
                        }
                    }.padding(18)
                } else {
                    Button(L10n.text("Add Link…"), systemImage: "plus") { edit(SavedDeepLink()) }.padding(18)
                }
                Divider()
                SettingsNote(L10n.text("Links open in the selected iOS Simulator. The app must support the URL scheme or Universal Link; web links may open in Safari."))
            }
            if model.simulatorToolDevice?.isIOSSimulator != true || model.simulatorToolDevice?.state != "Booted" {
                Text(L10n.text("Select a running iOS Simulator to perform actions. You can save links without a running device."))
                    .font(.callout).foregroundStyle(.secondary)
            }
            if model.simulatorToolProjectID == project.id {
                if model.simulatorToolBusy {
                    HStack(spacing: 10) { ProgressView().controlSize(.small); Text(L10n.text("Action in progress…")) }
                        .font(.callout).accessibilityElement(children: .combine)
                } else if let result = model.simulatorToolResult {
                    Text(L10n.display(result)).font(.callout).textSelection(.enabled)
                }
            }
        }
        .task { await model.refreshDevices() }
        .onChange(of: session?.state) { _, state in
            if state == .running || state == .ready || state == .disconnected || state == .error {
                Task { await model.refreshDevices() }
            }
        }
    }
    private func edit(_ link: SavedDeepLink) {
        editingLink = link; linkName = link.name; linkURL = link.url; linkError = nil
    }
    private func saveLink() {
        guard var link = editingLink, var current = model.store.projects.first(where: { $0.id == project.id }) else { return }
        do {
            link.name = linkName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !link.name.isEmpty else { throw FluttiosError.message(L10n.text("Enter a link name.")) }
            link.url = try SavedDeepLink.validatedURL(linkURL)
            if let index = current.deepLinks.firstIndex(where: { $0.id == link.id }) { current.deepLinks[index] = link }
            else { current.deepLinks.append(link) }
            model.store.update(current); editingLink = nil; linkError = nil
        } catch { linkError = error.localizedDescription }
    }
    private func remove(_ link: SavedDeepLink) {
        guard var current = model.store.projects.first(where: { $0.id == project.id }) else { return }
        current.deepLinks.removeAll { $0.id == link.id }; model.store.update(current)
        if editingLink?.id == link.id { editingLink = nil; linkError = nil }
    }
}

private struct SavedProjectSettingsRow: View {
    @ObservedObject var model: AppModel
    let project: Project
    @State private var confirmRemoval = false
    private var busy: Bool { model.manager.sessions[project.id]?.hasWork == true }
    private var selected: Bool { model.store.selectedID == project.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Button { model.select(project) } label: {
                    HStack(spacing: 12) {
                        model.projectImage(project).resizable().scaledToFit()
                            .frame(width: 32, height: 32)
                            .clipShape(RoundedRectangle(cornerRadius: 6)).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.store.label(project)).font(.system(size: 14, weight: .medium))
                                .lineLimit(1).truncationMode(.middle)
                            Text(project.path).font(.caption).foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.middle)
                        }
                        Spacer(minLength: 8)
                        Text(model.manager.sessions[project.id]?.state.title ?? L10n.text("Ready"))
                            .font(.caption).foregroundStyle(.secondary)
                        Image(systemName: "checkmark").foregroundStyle(Color.blue)
                            .opacity(selected ? 1 : 0).frame(width: 16)
                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain).help(project.path)
                    .accessibilityValue(selected ? L10n.text("Selected") : L10n.text("Not selected"))

                HStack(spacing: 4) {
                    action(L10n.text("Open project folder for {0}", project.name), symbol: "folder") {
                        model.openProjectFolder(project)
                    }
                    action(L10n.text("Open app data for {0}", project.name), symbol: "externaldrive") {
                        model.openProjectDataFolder(project.id)
                    }.disabled(model.simulatorToolBusy)
                    action(L10n.text("Reset app permissions for {0}", project.name), symbol: "lock.rotation") {
                        model.resetProjectPermissions(project.id)
                    }.disabled(busy || model.simulatorToolBusy)
                        .help(busy ? L10n.text("Press Stop before resetting permissions") : L10n.text("Reset app permissions"))
                    action(L10n.text("Change location for {0}", project.name), symbol: "folder.badge.gearshape") {
                        model.openProject(replacing: project.id)
                    }.disabled(busy || model.simulatorToolBusy)
                    Button(role: .destructive) { confirmRemoval = true } label: {
                        Image(systemName: "trash").frame(width: 28, height: 28)
                    }.disabled(busy || model.simulatorToolBusy || model.manager.shuttingDown)
                        .help(L10n.text("Remove from List"))
                        .accessibilityLabel(L10n.text("Remove saved project {0}", project.name))
                }.buttonStyle(.borderless).controlSize(.small)
            }.padding(.horizontal, 18).padding(.vertical, 14)
            if !FileManager.default.fileExists(atPath: project.path) {
                Text(L10n.text("Folder unavailable. Choose a new location or remove the entry."))
                    .font(.caption).foregroundStyle(.red).padding(.horizontal, 18).padding(.bottom, 12)
            }
            if model.simulatorToolProjectID == project.id {
                if model.simulatorToolBusy {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(L10n.text("Action in progress…")).font(.caption)
                    }.padding(.horizontal, 18).padding(.bottom, 12)
                } else if let result = model.simulatorToolResult {
                    Text(L10n.display(result)).font(.caption).foregroundStyle(.secondary)
                        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 18).padding(.bottom, 12)
                }
            }
        }
        .background(selected ? Color.blue.opacity(0.08) : Color.clear)
        .confirmationDialog(L10n.text("Remove this project from the list? Files will remain on disk."), isPresented: $confirmRemoval) {
            Button(L10n.text("Remove"), role: .destructive) { model.removeSavedProject(project.id) }
            Button(L10n.text("Cancel"), role: .cancel) {}
        }
    }

    private func action(_ title: String, symbol: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) { Image(systemName: symbol).frame(width: 28, height: 28) }
            .help(title).accessibilityLabel(title)
    }
}

struct ProjectEditor: View {
    @ObservedObject var model: AppModel
    @State private var project: Project
    init(model: AppModel, initial: Project) {
        self.model = model; _project = State(initialValue: initial)
    }
    private var busy: Bool { model.manager.sessions[project.id]?.hasWork ?? false }
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsSection(L10n.text("Launch")) {
                SettingsField(L10n.text("Device and Mode")) { DeviceMenu(model: model) }
                Divider()
                HStack { SessionButtons(model: model); Spacer(); Button(L10n.text("Logs…")) { model.showLogs() } }.padding(18)
                if let error = model.manager.sessions[project.id]?.error {
                    Button(error) { model.showLogs() }.buttonStyle(.plain).foregroundStyle(.red).padding(18)
                }
            }
            SettingsSection(L10n.text("Project Options")) {
                SettingsField(L10n.text("Name")) {
                    TextField(L10n.text("Project name"), text: $project.name).textFieldStyle(.roundedBorder).onSubmit { save() }
                }
                Divider()
                SettingsField(L10n.text("Project Flutter SDK")) {
                    HStack {
                        TextField(L10n.text("Automatic / FVM"), text: Binding(get: { project.sdkPath ?? "" }, set: { project.sdkPath = $0.isEmpty ? nil : $0; save() }))
                            .textFieldStyle(.roundedBorder).accessibilityLabel(L10n.text("Project Flutter SDK"))
                        Button(L10n.text("Choose…")) { model.chooseSDK { project.sdkPath = $0; save() } }
                    }
                }
                Divider()
                SettingsNote(L10n.text("Changes are saved automatically."))
            }.disabled(busy)
            if busy {
                Text(L10n.text("Press Stop to change launch options. Switching projects preserves the session."))
                    .font(.callout).foregroundStyle(.secondary)
            }

        }
        .onChange(of: project) { _, _ in save() }
        .onReceive(model.store.$projects) { projects in
            if let updated = projects.first(where: { $0.id == project.id }), updated != project { project = updated }
        }

    }
    private func save() {
        guard !busy else { return }
        model.store.update(project)
    }
}

struct LogsView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                ProjectMenu(model: model); Spacer()
                Button(L10n.text("Copy")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.selectedSession?.logs.map { $0.text }.joined(separator: "\n") ?? "", forType: .string)
                }
                Button(L10n.text("Clear")) { model.selectedSession?.clearLogs() }
            }.padding()
            Divider()
            LogConsole(entries: model.selectedSession?.logs ?? [], projectID: model.store.selectedID)
            Text(L10n.text("Up to 2000 entries per project • quitting the app requires a new Run")).font(.caption).foregroundStyle(.secondary).padding(8)
        }.frame(minWidth: 700, minHeight: 400)
    }
}

// AppKit owns selection and text layout, avoiding flipped selectable Text layers
// inside SwiftUI's lazy scrolling container.
struct LogConsole: NSViewRepresentable {
    let entries: [LogEntry]
    let projectID: UUID?

    final class Coordinator {
        var entryIDs: [UUID] = []
        var projectID: UUID?
        let timestamp: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss"
            return formatter
        }()
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
        let changedProject = coordinator.projectID != projectID
        guard changedProject || coordinator.entryIDs != ids else { return }
        let visible = scroll.contentView.bounds
        let followEnd = changedProject || coordinator.entryIDs.isEmpty || visible.maxY >= text.bounds.maxY - 24
        let selection = text.selectedRange()
        let output = NSMutableAttributedString(string: "")
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let paragraph = NSMutableParagraphStyle()
        paragraph.paragraphSpacing = 4
        for entry in entries {
            output.append(NSAttributedString(string: coordinator.timestamp.string(from: entry.date) + "  ", attributes: [
                .font: font, .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: paragraph
            ]))
            output.append(NSAttributedString(string: entry.text + "\n", attributes: [
                .font: font, .foregroundColor: entry.isError ? NSColor.systemRed : NSColor.labelColor, .paragraphStyle: paragraph
            ]))
        }
        text.textStorage?.setAttributedString(output)
        coordinator.entryIDs = ids
        coordinator.projectID = projectID
        if followEnd {
            text.scrollRangeToVisible(NSRange(location: output.length, length: 0))
        } else {
            // Preserve a selection while new lines arrive during inspection.
            if selection.location <= output.length {
                text.setSelectedRange(NSRange(location: selection.location, length: min(selection.length, output.length - selection.location)))
            }
            scroll.contentView.scroll(to: visible.origin)
            scroll.reflectScrolledClipView(scroll.contentView)
        }
    }
}
