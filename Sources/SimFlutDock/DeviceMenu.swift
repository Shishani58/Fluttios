import AppKit
import SimFlutDockCore
import SwiftUI

struct DeviceMenu: View {
    @ObservedObject var model: AppModel
    var compact = false
    @Environment(\.panelControlWidth) private var controlWidth
    @State private var showingPicker = false

    var body: some View {
        Button {
            showingPicker.toggle()
        } label: {
            HStack(spacing: 4) {
                if compact {
                    PanelIcon(symbol: model.selectedDevice?.symbol ?? "iphone")
                } else {
                    Image(systemName: model.selectedDevice?.symbol ?? "iphone")
                        .frame(width: 14).accessibilityHidden(true)
                }
                if !compact {
                    Text(
                        "\(model.launchMode.title) · \(model.selectedDevice?.name ?? (model.store.selected?.deviceID != nil ? L10n.text("Unavailable") : L10n.text("Automatic")))"
                    )
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
        .accessibilityValue(
            "\(model.launchMode.title), \(model.selectedDevice?.name ?? (model.store.selected?.deviceID != nil ? L10n.text("Unavailable") : L10n.text("Automatic")))"
        )
    }
}

private struct DevicePicker: View {
    @ObservedObject var model: AppModel
    let close: () -> Void
    @State private var search = ""
    @FocusState private var searchFocused: Bool
    @AppStorage("devicePicker.otherDevicesExpanded") private var otherDevicesExpanded = true
    @AppStorage("devicePicker.simulatorsExpanded") private var simulatorsExpanded = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var canSelectDevice: Bool { model.store.selected != nil }
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
                        Button {
                            search = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
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
                            sectionHeader(section, count: group.count)
                            if isExpanded(section) {
                                ForEach(group) { device in
                                    DeviceChoiceRow(
                                        symbol: device.symbol, title: device.name, detail: runtimeTitle(device),
                                        selected: model.store.selected?.deviceID == device.id,
                                        status: model.bootingSimulatorIDs.contains(device.id)
                                            ? L10n.text("Starting…") : statusTitle(device),
                                        active: device.state == "Booted",
                                        canSelect: canSelectDevice,
                                        pinned: device.isIOSSimulator
                                            ? model.pinnedSimulatorIDs.contains(device.id) : nil,
                                        booting: model.bootingSimulatorIDs.contains(device.id),
                                        pin: device.isIOSSimulator ? { model.toggleSimulatorPin(device) } : nil,
                                        boot: device.isIOSSimulator && device.isAvailable && device.state == "Shutdown"
                                            ? { model.bootSimulator(device) } : nil
                                    ) {
                                        model.chooseDevice(device)
                                    }
                                }
                            }
                        }
                    }
                    if visibleDevices.isEmpty {
                        VStack(spacing: 6) {
                            Text(
                                model.simulators.refreshing
                                    ? L10n.text("Searching for devices…")
                                    : (search.isEmpty ? L10n.text("No devices found") : L10n.text("No matches"))
                            ).fontWeight(.medium)
                            Text(
                                model.simulators.refreshing
                                    ? L10n.text("Getting the list from Xcode and Flutter.")
                                    : (search.isEmpty
                                        ? L10n.text("Refresh the list and check the connection.")
                                        : L10n.text("Try another name or OS version."))
                            )
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
                            Button {
                                model.chooseLaunchMode(mode)
                            } label: {
                                Text(mode.title)
                                    .font(.system(size: 11, weight: .medium))
                                    .frame(maxWidth: .infinity, minHeight: 24)
                                    .background(
                                        model.launchMode == mode ? Color(nsColor: .controlBackgroundColor) : .clear,
                                        in: RoundedRectangle(cornerRadius: 5)
                                    )
                                    .shadow(color: .black.opacity(model.launchMode == mode ? 0.08 : 0), radius: 1, y: 1)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(!canSelectDevice || !mode.supports(model.selectedDevice))
                            .accessibilityLabel(mode.title)
                            .accessibilityValue(
                                model.launchMode == mode ? L10n.text("Selected") : L10n.text("Not selected"))
                        }
                    }
                    .padding(2).background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 7))
                    .accessibilityLabel(L10n.text("Launch Mode"))
                }.padding(.bottom, 10)
                if let session = model.selectedSession, session.hasWork,
                    session.launchProject?.launch.mode != model.launchMode
                {
                    notice(L10n.text("To apply the selected mode, press Rerun."), symbol: "info.circle")
                }
                HStack {
                    Button {
                        model.chooseDevice(nil)
                    } label: {
                        Label(
                            L10n.text("Automatic"),
                            systemImage: model.store.selected?.deviceID == nil ? "checkmark" : "sparkles"
                        )
                        .foregroundStyle(model.store.selected?.deviceID == nil ? Color.accentColor : Color.primary)
                    }
                    .disabled(!canSelectDevice)
                    .help(L10n.text("Select a running simulator when pressing Run"))
                    .accessibilityValue(
                        model.store.selected?.deviceID == nil ? L10n.text("Selected") : L10n.text("Not selected"))
                    Spacer()
                    Button {
                        Task { await model.refreshDevices() }
                    } label: {
                        Label(
                            model.simulators.refreshing ? L10n.text("Refreshing…") : L10n.text("Refresh"),
                            systemImage: "arrow.clockwise")
                    }.disabled(model.simulators.refreshing)
                }.buttonStyle(.bordered).controlSize(.small)
                if model.simulators.error != nil {
                    Button {
                        model.message = model.simulators.error
                    } label: {
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

    private func isExpanded(_ section: Int) -> Bool {
        switch section {
        case 1: return otherDevicesExpanded
        case 2: return simulatorsExpanded
        default: return true
        }
    }

    @ViewBuilder
    private func sectionHeader(_ section: Int, count: Int) -> some View {
        let title =
            section == 0
            ? L10n.text("Pinned") : (section == 1 ? L10n.text("Other Devices") : L10n.text("iOS Simulators"))
        let expanded = isExpanded(section)
        if section == 0 {
            HStack {
                Text(title)
                Spacer()
                Text("\(count)").monospacedDigit()
            }
            .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            .padding(.leading, 42).padding(.trailing, 12).padding(.top, 10).padding(.bottom, 4)
        } else {
            Button {
                if section == 1 { otherDevicesExpanded.toggle() } else { simulatorsExpanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .animation(
                            reduceMotion ? nil : .timingCurve(0.77, 0, 0.175, 1, duration: 0.18), value: expanded
                        )
                        .frame(width: 12).accessibilityHidden(true)
                    Text(title)
                    Spacer()
                    Text("\(count)").monospacedDigit()
                }
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                .padding(.leading, 22).padding(.trailing, 12)
                .frame(maxWidth: .infinity, minHeight: 30)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityValue(expanded ? L10n.text("Expanded") : L10n.text("Collapsed"))
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
                        .accessibilityLabel(
                            pinned == true ? L10n.text("Unpin {0}", "\(title)") : L10n.text("Pin {0}", "\(title)"))
                    } else {
                        Color.clear.accessibilityHidden(true)
                    }
                }.frame(width: 24, height: 28)
            }
        }
        .padding(.leading, 8).padding(.trailing, 4)
        .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
        .background(
            selected ? Color.accentColor : Color.primary.opacity(hovered ? 0.05 : 0),
            in: RoundedRectangle(cornerRadius: 6)
        )
        .onHover { hovered = $0 }
    }
}
