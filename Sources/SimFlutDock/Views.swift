import SwiftUI
import AppKit
import SimFlutDockCore

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
    @Environment(\.panelControlWidth) private var controlWidth
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
                .frame(width: compact ? controlWidth : nil, height: compact ? PanelMetrics.controlHeight : nil)
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

private struct PanelControlWidthKey: EnvironmentKey {
    static let defaultValue = PanelMetrics.controlSize
}

private extension EnvironmentValues {
    var panelControlWidth: CGFloat {
        get { self[PanelControlWidthKey.self] }
        set { self[PanelControlWidthKey.self] = newValue }
    }
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
        @Environment(\.panelControlWidth) private var controlWidth
        var body: some View {
            configuration.label
                .font(.system(size: PanelMetrics.iconSize, weight: .medium))
                .frame(width: controlWidth, height: PanelMetrics.controlHeight)
                .modifier(PanelControlSurface(pressed: configuration.isPressed, bordered: true))
                .opacity(enabled ? 1 : 0.35)
        }
    }
}

struct DeviceMenu: View {
    @ObservedObject var model: AppModel
    var compact = false
    @Environment(\.panelControlWidth) private var controlWidth
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
                .frame(width: compact ? controlWidth : nil, height: compact ? PanelMetrics.controlHeight : nil)
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
    @FocusState private var searchFocused: Bool

    private var canEdit: Bool { model.store.selected != nil && model.selectedSession?.hasWork != true }
    private var devices: [SimulatorDevice] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.simulators.devices.filter {
            query.isEmpty || "\($0.name) \(runtimeTitle($0))".localizedCaseInsensitiveContains(query)
        }.sorted {
            if ($0.state == "Booted") != ($1.state == "Booted") { return $0.state == "Booted" }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    var body: some View {
        let visibleDevices = devices
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
                    TextField(L10n.text("Search devices or OS versions"), text: $search).textFieldStyle(.plain)
                        .focused($searchFocused)
                    if !search.isEmpty {
                        Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel(L10n.text("Clear search"))
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.08)))
                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .medium))
                        .frame(width: 24, height: 28).contentShape(Rectangle())
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .keyboardShortcut(.cancelAction).help(L10n.text("Close"))
                .accessibilityLabel(L10n.text("Close device picker"))
            }.padding(12)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(0..<3, id: \.self) { section in
                        let group = visibleDevices.filter { device in
                            let pinned = model.pinnedSimulatorIDs.contains(device.id)
                            switch section {
                            case 0: return device.isIOSSimulator && pinned
                            case 1: return !device.isIOSSimulator
                            default: return device.isIOSSimulator && !pinned
                            }
                        }
                        if !group.isEmpty {
                            HStack {
                                Text(section == 0 ? L10n.text("Pinned") : (section == 1 ? L10n.text("Other Devices") : L10n.text("iOS Simulators")))
                                Spacer()
                                Text("\(group.count)").monospacedDigit()
                            }
                            .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                            .padding(.leading, 42).padding(.trailing, 12).padding(.top, 10).padding(.bottom, 4)
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
                    if visibleDevices.isEmpty {
                        VStack(spacing: 6) {
                            Text(model.simulators.refreshing ? L10n.text("Searching for devices…") : (search.isEmpty ? L10n.text("No devices found") : L10n.text("No matches"))).fontWeight(.medium)
                            Text(model.simulators.refreshing ? L10n.text("Getting the list from Xcode and Flutter.") : (search.isEmpty ? L10n.text("Refresh the list and check the connection.") : L10n.text("Try another name or OS version.")))
                                .font(.system(size: 12)).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity).padding(.vertical, 32)
                    }
                }
                .padding(.horizontal, 8).padding(.bottom, 8)
            }
            .frame(height: 420)

            Divider().padding(.bottom, 10)
            VStack(alignment: .leading, spacing: 0) {
                if let error = model.simulatorBootError {
                    notice(error, symbol: "exclamationmark.triangle")
                }
                HStack(spacing: 10) {
                    HStack(spacing: 2) {
                        ForEach(LaunchMode.allCases, id: \.self) { mode in
                            Button { model.chooseLaunchMode(mode) } label: {
                                Text(mode.title)
                                    .font(.system(size: 11, weight: .medium))
                                    .frame(maxWidth: .infinity, minHeight: 24)
                                    .background(model.launchMode == mode ? Color(nsColor: .controlBackgroundColor) : .clear,
                                                in: RoundedRectangle(cornerRadius: 5))
                                    .shadow(color: .black.opacity(model.launchMode == mode ? 0.08 : 0), radius: 1, y: 1)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(!canEdit || !mode.supports(model.selectedDevice))
                            .accessibilityValue(model.launchMode == mode ? L10n.text("Selected") : L10n.text("Not selected"))
                        }
                    }
                    .padding(2).background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 7))
                    .accessibilityLabel(L10n.text("Launch Mode"))
                }.padding(.bottom, 10)
                HStack {
                    Button { model.chooseDevice(nil) } label: {
                        Label(L10n.text("Automatic"), systemImage: model.store.selected?.deviceID == nil ? "checkmark" : "sparkles")
                            .foregroundStyle(model.store.selected?.deviceID == nil ? Color.accentColor : Color.primary)
                    }
                    .disabled(!canEdit)
                    .help(L10n.text("Select a running simulator when pressing Run"))
                    .accessibilityValue(model.store.selected?.deviceID == nil ? L10n.text("Selected") : L10n.text("Not selected"))
                    Spacer()
                    Button { Task { await model.refreshDevices() } } label: {
                        Label(model.simulators.refreshing ? L10n.text("Refreshing…") : L10n.text("Refresh"), systemImage: "arrow.clockwise")
                    }.disabled(model.simulators.refreshing)
                }.buttonStyle(.bordered).controlSize(.small)
                if model.simulators.error != nil {
                    Button { model.message = model.simulators.error } label: {
                        Label(L10n.text("Device discovery error"), systemImage: "exclamationmark.triangle")
                    }.foregroundStyle(.orange).controlSize(.small).padding(.top, 8)
                }
            }.padding(.horizontal, 14).padding(.bottom, 12)
        }
        .frame(width: 460)
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            searchFocused = true
            await model.refreshDevices()
        }
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

    private var foreground: Color { selected ? .white : .primary }
    private var secondaryForeground: Color { selected ? .white.opacity(0.75) : .secondary }

    var body: some View {
        HStack(spacing: 0) {
            Button(action: action) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold))
                        .opacity(selected ? 1 : 0).frame(width: 12).accessibilityHidden(true)
                    Image(systemName: symbol).font(.system(size: 14))
                        .foregroundStyle(selected ? foreground : .secondary)
                        .frame(width: 16).accessibilityHidden(true)
                    Text(title).font(.system(size: 13, weight: selected ? .semibold : .regular))
                        .lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 6)
                    if active || booting {
                        Circle().fill(booting ? Color.orange : Color.green)
                            .frame(width: 6, height: 6).accessibilityHidden(true)
                    }
                    Text(detail).font(.system(size: 12)).monospacedDigit()
                        .foregroundStyle(secondaryForeground)
                        .lineLimit(pinned == nil ? nil : 1)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: pinned == nil ? 210 : 78, alignment: .trailing)
                }
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                .padding(.trailing, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain).disabled(!canSelect)
            .help("\(title) — \(detail)\(status.map { " — " + $0 } ?? "")")
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("\(title), \(detail)\(status.map { ", " + $0 } ?? "")")
            .accessibilityValue(selected ? L10n.text("Selected") : L10n.text("Not selected"))

            if pinned != nil {
                // Only simulators need launch and pin columns. Other targets use this space for the full SDK version.
                Group {
                    if booting {
                        ProgressView().controlSize(.mini)
                            .accessibilityLabel(L10n.text("Starting {0}", "\(title)"))
                    } else if let boot {
                        Button(action: boot) {
                            Image(systemName: "play.fill").font(.system(size: 10))
                                .frame(width: 24, height: 28).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).foregroundStyle(selected ? foreground : Color.accentColor)
                        .help(L10n.text("Start simulator {0}", "\(title)"))
                        .accessibilityLabel(L10n.text("Start simulator {0}", "\(title)"))
                    } else {
                        Color.clear.accessibilityHidden(true)
                    }
                }.frame(width: 24, height: 28)
                Group {
                    if let pin {
                        Button(action: pin) {
                            Image(systemName: pinned == true ? "pin.fill" : "pin")
                                .font(.system(size: 11))
                                .frame(width: 24, height: 28).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(selected ? foreground : (pinned == true ? Color.accentColor : Color.secondary))
                        .help(pinned == true ? L10n.text("Unpin {0}", "\(title)") : L10n.text("Pin {0}", "\(title)"))
                        .accessibilityLabel(pinned == true ? L10n.text("Unpin {0}", "\(title)") : L10n.text("Pin {0}", "\(title)"))
                    } else {
                        Color.clear.accessibilityHidden(true)
                    }
                }.frame(width: 24, height: 28)
            }
        }
        .padding(.leading, 8).padding(.trailing, 4)
        .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
        .background(selected ? Color.accentColor : Color.primary.opacity(hovered ? 0.05 : 0), in: RoundedRectangle(cornerRadius: 6))
        .onHover { hovered = $0 }
    }
}

struct SessionButtons: View {
    @ObservedObject var model: AppModel
    var compact = false
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
            Button { model.restart(full: false) } label: { Label { Text("Hot Reload") } icon: { sessionIcon("bolt", regular: "bolt.fill") }.foregroundStyle(.orange) }
                .disabled(!(model.selectedSession?.canRestart ?? false))
                .help(L10n.text("Hot Reload — preserve Dart state"))
            Button { model.restart(full: true) } label: { Label { Text("Hot Restart") } icon: { sessionIcon("arrow.clockwise", regular: "arrow.clockwise") }.foregroundStyle(.green) }
                .disabled(!(model.selectedSession?.canRestart ?? false))
                .help(L10n.text("Hot Restart — reset Dart state. After native code changes, use Stop and Run."))
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
        model.verticalPanel ? AnyLayout(VStackLayout(spacing: PanelMetrics.groupSpacing)) : AnyLayout(HStackLayout(spacing: narrowPanel ? 4 : PanelMetrics.groupSpacing))
    }
    private var narrowPanel: Bool { !model.verticalPanel && model.panelWidth < 380 }
    private var controlWidth: CGFloat {
        // Eight controls, five group gaps, two drag separators and outer insets.
        narrowPanel ? min(PanelMetrics.controlSize, max(24, (model.panelWidth - 60) / 8)) : PanelMetrics.controlSize
    }
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
                SessionButtons(model: model, compact: true)
            }
            blockSeparator
            panelLayout {
            Button { model.showLogs() } label: {
                PanelIcon(symbol: "doc.text").foregroundStyle(PanelMetrics.logsColor)
            }
            .buttonStyle(PanelButtonStyle())
            .accessibilityLabel(L10n.text("Show logs for the selected project"))
            .help(L10n.text("Show logs for the selected project"))
            Color.clear
                .frame(width: controlWidth, height: PanelMetrics.controlHeight)
                .overlay {
                    Menu {
                        if hasError {
                            Button { showingError = true } label: { Label(L10n.text("Show Error…"), systemImage: "exclamationmark.triangle") }
                            Divider()
                        }
                        Button { model.showSettings() } label: { Label(L10n.text("Settings…"), systemImage: "gearshape") }
                        Button(L10n.text("Check for Updates…")) { model.updater.check() }
                        Menu {
                            Toggle(L10n.text("Free Position"), isOn: $model.freePanel)
                            Button(L10n.text("Reset Position")) { model.resetPanel() }
                            Menu(L10n.text("Attach to Simulator Window")) {
                                if model.tracker.windows.isEmpty { Text(model.tracker.trusted ? L10n.text("No open Simulator windows") : L10n.text("Allow access in SimFlutDock settings")) }
                                ForEach(model.tracker.windows) { window in
                                    Button("\(window.title) (\(Int(window.frame.minX)), \(Int(window.frame.minY)))") { model.bindWindow(window.id) }
                                }
                            }
                            Divider()
                            Button(L10n.text("Refresh Attachment")) { model.tracker.refresh() }
                        } label: { Label(L10n.text("Panel Position"), systemImage: "rectangle.3.group") }
                        Divider()
                        Button { model.quitApp() } label: { Label(L10n.text("Quit SimFlutDock"), systemImage: "power") }
                    } label: {
                        Color.clear.frame(width: 18, height: 18)
                    }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            // Keep the icon outside the native menu's label and layout insets.
            .overlay(alignment: .center) {
                PanelIcon(symbol: "gearshape")
                    .foregroundStyle(Color(red: 0.42, green: 0.70, blue: 0.95))
                    .allowsHitTesting(false)
            }
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
        .environment(\.panelControlWidth, controlWidth)
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
    var subtitle: String {
        switch self {
        case .general: return L10n.text("Language, updates, and application launch")
        case .projects: return L10n.text("Saved projects and launch options")
        case .tools: return L10n.text("Simulator, links, and development environment")
        case .panel: return L10n.text("Panel placement and behavior")
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

private enum SettingsAppearance {
    static let canvas = adaptive(dark: 0x202124, light: 0xf5f5f7)
    static let sidebar = adaptive(dark: 0x191a1c, light: 0xebebee)
    static let surface = adaptive(dark: 0x292a2d, light: 0xffffff)
    private static func adaptive(dark: UInt32, light: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let rgb = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((rgb >> 16) & 255) / 255,
                           green: CGFloat((rgb >> 8) & 255) / 255,
                           blue: CGFloat(rgb & 255) / 255, alpha: 1)
        })
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
                .padding(.horizontal, 4)
            VStack(alignment: .leading, spacing: 0) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(SettingsAppearance.surface, in: RoundedRectangle(cornerRadius: 10))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.primary.opacity(0.09), lineWidth: 1))
        }
    }
}

struct SettingsField<Content: View>: View {
    let title: String
    var subtitle: String?
    private let content: Content
    init(_ title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }
    private var label: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 13, weight: .medium))
            if let subtitle {
                Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    var body: some View {
        HStack(spacing: 24) {
            label.frame(maxWidth: .infinity, alignment: .leading)
            content.frame(width: 280, alignment: .trailing)
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
    }
}

struct SettingsToggle: View {
    let title: String
    var subtitle: String?
    @Binding var isOn: Bool
    var body: some View {
        HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 13, weight: .medium))
                if let subtitle {
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            Toggle(title, isOn: $isOn).labelsHidden().toggleStyle(.switch).controlSize(.small)
                .accessibilityLabel(title)
        }.padding(.horizontal, 18).padding(.vertical, 14)
    }
}

private struct SettingsNote: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.system(size: 11)).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 18).padding(.vertical, 12)
    }
}

private struct PanelPlacementPreview: View {
    let side: PanelSide
    let detached: Bool
    var body: some View {
        HStack(spacing: 24) {
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(.primary.opacity(0.04))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.primary.opacity(0.25), lineWidth: 2))
                    .frame(width: 68, height: 116)
                Capsule().fill(.primary.opacity(0.25)).frame(width: 22, height: 4).offset(y: -48)
                ForEach([PanelSide.above, .right, .below, .left], id: \.self) { position in
                    let vertical = position.isVertical
                    let selected = !detached && side == position
                    RoundedRectangle(cornerRadius: 4)
                        .fill(selected ? Color.accentColor : Color.clear)
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(
                            selected ? Color.accentColor : Color.primary.opacity(0.2),
                            style: StrokeStyle(lineWidth: 1, dash: selected ? [] : [3, 3])))
                        .frame(width: vertical ? 10 : 62, height: vertical ? 90 : 10)
                        .offset(x: position == .left ? -48 : (position == .right ? 48 : 0),
                                y: position == .above ? -72 : (position == .below ? 72 : 0))
                }
            }.frame(width: 138, height: 166).accessibilityHidden(true)
            Text(detached ? L10n.text("The panel can be moved independently of Simulator.") : L10n.text("If there is not enough room on the selected side, the panel appears on the opposite side."))
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true).frame(maxWidth: 300, alignment: .leading)
        }.frame(maxWidth: .infinity).padding(.vertical, 10)
    }
}

private struct BackgroundLaunchSettings: View {
    @ObservedObject var background: BackgroundLaunch
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsToggle(title: L10n.text("Launch with Simulator"),
                           subtitle: L10n.text("Open the panel when Simulator starts."),
                           isOn: Binding(get: { background.enabled || background.status == .requiresApproval },
                                         set: { background.setEnabled($0) }))
            if background.status == .notFound || background.status == .requiresApproval {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.circle").foregroundStyle(.orange).accessibilityHidden(true)
                    Text(background.status == .notFound ? L10n.text("Background helper unavailable") : background.title).font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Button(L10n.text("Open Login Items…")) { background.systemSettings() }
                        .controlSize(.small)
                }.padding(.horizontal, 18).padding(.bottom, 14)
            }
            if let error = background.error {
                Text(L10n.display(error)).font(.callout).foregroundStyle(.red)
                    .textSelection(.enabled).padding(.horizontal, 18).padding(.bottom, 14)
            }
        }
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
                        .font(.system(size: 25)).foregroundStyle(Color.accentColor).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("SimFlutDock").font(.system(size: 15, weight: .semibold)).fixedSize()
                        Text(L10n.text("Settings")).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }.padding(.horizontal, 18).padding(.top, 25).padding(.bottom, 28)
                VStack(spacing: 5) {
                    ForEach(SettingsDestination.allCases) { item in
                        Button { destination = item } label: {
                            HStack(spacing: 12) {
                                Image(systemName: item.symbol).font(.system(size: 17)).frame(width: 22).accessibilityHidden(true)
                                Text(item.title).font(.system(size: 13, weight: destination == item ? .semibold : .regular))
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 12).frame(height: 40)
                            .foregroundStyle(destination == item ? Color.accentColor : Color.primary)
                            .background(destination == item ? Color.accentColor.opacity(0.16) : Color.clear, in: RoundedRectangle(cornerRadius: 7))
                            .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                            .accessibilityValue(destination == item ? L10n.text("Selected") : L10n.text("Not selected"))
                    }
                }.padding(.horizontal, 12)
                Spacer()
                Divider()
                Button { model.showPanel() } label: {
                    Label(L10n.text("Show Panel"), systemImage: "rectangle.on.rectangle")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.plain).font(.system(size: 12)).padding(18)
                Text(L10n.text("Version {0}", appVersion)).font(.system(size: 10)).foregroundStyle(.secondary)
                    .padding(.horizontal, 18).padding(.bottom, 18)
            }
            .frame(width: 206)
            .background(SettingsAppearance.sidebar)
            Divider()
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(destination.title).font(.system(size: 25, weight: .semibold))
                        Text(destination.subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if destination == .projects {
                        Button(L10n.text("Add Project"), systemImage: "plus") { model.openProject() }
                            .buttonStyle(.borderedProminent)
                    }
                }.padding(.horizontal, 30).padding(.top, 28).padding(.bottom, 24)
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
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
                    Label(L10n.text("Settings are saved automatically"), systemImage: "checkmark.circle")
                    Spacer()
                }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 28).frame(height: 40)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(SettingsAppearance.canvas)
        }
        .environment(\.locale, L10n.locale)
        .tint(.blue)
        .frame(minWidth: 900, minHeight: 640)
    }

    private var appVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.5" }

    private var projectSettings: some View {
        VStack(alignment: .leading, spacing: 22) {
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
        VStack(alignment: .leading, spacing: 22) {
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

            SettingsSection(L10n.text("Development Environment")) {
                SettingsField(L10n.text("Default Flutter SDK"), subtitle: L10n.text("Used when no project SDK is configured. Supports FVM.")) {
                    HStack(spacing: 8) {
                        TextField(L10n.text("Automatic"), text: $model.globalSDK)
                            .textFieldStyle(.roundedBorder).accessibilityLabel(L10n.text("Default Flutter SDK"))
                        Button(L10n.text("Choose…")) { model.chooseSDK { model.globalSDK = $0 } }.controlSize(.small)
                    }
                }
                Divider()
                SettingsField(L10n.text("Flutter and Xcode"), subtitle: L10n.text("Uses the active Xcode installation.")) {
                    HStack {
                        if model.checkingTools { ProgressView().controlSize(.small) }
                        Button(model.checkingTools ? L10n.text("Checking…") : L10n.text("Check")) { model.checkTools() }
                            .disabled(model.checkingTools).controlSize(.small)
                    }
                }
                if let error = model.simulators.error {
                    Divider()
                    Text(L10n.display(error)).font(.callout).foregroundStyle(.red).textSelection(.enabled).padding(18)
                }
            }
        }
    }

    private var panelSettings: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsSection(L10n.text("Panel Placement")) {
                SettingsToggle(title: L10n.text("Free Position"),
                               subtitle: L10n.text("The panel can be moved independently of Simulator."), isOn: $model.freePanel)
                Divider()
                SettingsField(L10n.text("Simulator Side")) {
                    Picker(L10n.text("Side of the Simulator window"), selection: $model.panelSide) {
                        ForEach([PanelSide.above, .right, .below, .left], id: \.self) { side in Text(side.title).tag(side) }
                    }.labelsHidden().pickerStyle(.segmented).disabled(model.standalonePanel)
                }
                Divider()
                PanelPlacementPreview(side: model.panelSide, detached: model.standalonePanel)
            }
            SettingsSection(L10n.text("Menu Bar Icon")) {
                SettingsToggle(title: L10n.text("Hide or show the panel on click"),
                               subtitle: L10n.text("When the panel is not attached to a Simulator window, one click hides it completely and the next shows it again."),
                               isOn: $model.toggleUnboundPanelFromTray)
            }
            SettingsSection(L10n.text("Simulator Window Access")) {
                SettingsField(L10n.text("Accessibility"), subtitle: L10n.text("Allow access to attach the panel to a Simulator window.")) {
                    HStack(spacing: 12) {
                        Label(model.tracker.trusted ? L10n.text("Allowed") : L10n.text("Permission required"),
                              systemImage: model.tracker.trusted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .font(.system(size: 11)).foregroundStyle(model.tracker.trusted ? Color.secondary : Color.orange)
                        if !model.tracker.trusted {
                            Button(L10n.text("Allow Access…")) { model.tracker.requestPermission() }.controlSize(.small)
                        }
                    }
                }
                Divider()
                HStack {
                    Text(L10n.text("You can select a window manually in the panel menu: ⚙ → Panel Position → Attach to Simulator Window."))
                        .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 12)
                    Button(L10n.text("Check Permission")) { model.tracker.refresh() }.controlSize(.small)
                }.padding(.horizontal, 18).padding(.vertical, 12)
            }
        }
    }

    private var generalSettings: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsSection(L10n.text("Preferences")) {
                SettingsField(L10n.text("Application Language"), subtitle: L10n.text("Changes apply immediately.")) {
                    Picker(L10n.text("Language"), selection: $model.language) {
                        ForEach(AppLanguage.allCases) { language in Text(language.title).tag(language) }
                    }.labelsHidden().accessibilityLabel(L10n.text("Language")).frame(width: 190)
                }
                Divider()
                BackgroundLaunchSettings(background: model.background)
            }
            SettingsSection(L10n.text("App Updates")) {
                AppUpdateSettings(updater: model.updater)
            }
            SettingsSection(L10n.text("About")) {
                HStack(spacing: 14) {
                    Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                        .font(.system(size: 28)).foregroundStyle(Color.accentColor).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("SimFlutDock").font(.system(size: 14, weight: .semibold))
                        Text(L10n.text("Version {0} · Build {1}", appVersion,
                                       Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "5"))
                            .font(.system(size: 11)).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    Spacer()
                }.padding(18)
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
        VStack(alignment: .leading, spacing: 22) {
            SettingsSection(L10n.text("Saved Links")) {
                if project.deepLinks.isEmpty {
                    SettingsNote(L10n.text("Save links to screens and test scenarios for this project."))
                }
                ForEach(project.deepLinks) { link in
                    HStack(spacing: 12) {
                        Image(systemName: "link").font(.system(size: 18)).foregroundStyle(.secondary).accessibilityHidden(true)
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
            guard !link.name.isEmpty else { throw SimFlutDockError.message(L10n.text("Enter a link name.")) }
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
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle").foregroundStyle(selected ? Color.accentColor : Color.secondary.opacity(0.4))
                            .frame(width: 18)
                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain).help(project.path)
                    .accessibilityValue(selected ? L10n.text("Selected") : L10n.text("Not selected"))

                Menu {
                    Button(L10n.text("Open project folder for {0}", project.name), systemImage: "folder") {
                        model.openProjectFolder(project)
                    }
                    Button(L10n.text("Open app data for {0}", project.name), systemImage: "externaldrive") {
                        model.openProjectDataFolder(project.id)
                    }.disabled(model.simulatorToolBusy)
                    Button(L10n.text("Reset app permissions for {0}", project.name), systemImage: "lock.rotation") {
                        model.resetProjectPermissions(project.id)
                    }.disabled(busy || model.simulatorToolBusy)
                    Button(L10n.text("Change location for {0}", project.name), systemImage: "folder.badge.gearshape") {
                        model.openProject(replacing: project.id)
                    }.disabled(busy || model.simulatorToolBusy)
                    Divider()
                    Button(L10n.text("Remove from List"), role: .destructive) { confirmRemoval = true }
                        .disabled(busy || model.simulatorToolBusy || model.manager.shuttingDown)
                } label: {
                    Image(systemName: "ellipsis").frame(width: 28, height: 24)
                }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .accessibilityLabel(L10n.text("Actions for {0}", project.name))
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
            SettingsSection(L10n.text("Project Options")) {
                SettingsField(L10n.text("Name")) {
                    TextField(L10n.text("Project name"), text: $project.name)
                        .textFieldStyle(.roundedBorder).accessibilityLabel(L10n.text("Project name"))
                        .onSubmit { save() }
                }.disabled(busy)
                Divider()
                SettingsField(L10n.text("Device and Mode")) { DeviceMenu(model: model) }
                Divider()
                HStack {
                    SessionButtons(model: model)
                    Spacer()
                    Button(L10n.text("Logs…")) { model.showLogs() }.controlSize(.small)
                }.padding(.horizontal, 18).padding(.vertical, 12)
                if let error = model.manager.sessions[project.id]?.error {
                    Button(error) { model.showLogs() }.buttonStyle(.plain).foregroundStyle(.red).padding(18)
                }
            }
            SettingsSection("Flutter SDK") {
                SettingsField(L10n.text("Project Flutter SDK"), subtitle: L10n.text("Uses the project SDK or the default SDK.")) {
                    HStack(spacing: 8) {
                        TextField(L10n.text("Automatic / FVM"), text: Binding(get: { project.sdkPath ?? "" }, set: { project.sdkPath = $0.isEmpty ? nil : $0; save() }))
                            .textFieldStyle(.roundedBorder).accessibilityLabel(L10n.text("Project Flutter SDK"))
                        Button(L10n.text("Choose…")) { model.chooseSDK { project.sdkPath = $0; save() } }.controlSize(.small)
                    }
                }
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
