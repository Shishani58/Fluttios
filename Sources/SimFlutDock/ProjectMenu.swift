import AppKit
import SimFlutDockCore
import SwiftUI

struct ProjectMenu: View {
    @ObservedObject var model: AppModel
    var compact = false
    @Environment(\.panelControlWidth) private var controlWidth
    @State private var showingPicker = false

    var body: some View {
        Button {
            showingPicker.toggle()
        } label: {
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
        .help(
            L10n.text(
                "{0} — select a project. Running sessions are preserved.",
                "\(model.store.selected.map { model.store.label($0) } ?? L10n.text("Open Project"))")
        )
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
        let extra: CGFloat =
            !showsResult ? 0 : (model.simulatorToolBusy ? 30 : (model.simulatorToolResult == nil ? 0 : 80))
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
                            Button {
                                search = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel(
                                L10n.text("Clear search"))
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
                    Text(
                        model.store.projects.isEmpty
                            ? L10n.text("Select a folder containing pubspec.yaml.")
                            : L10n.text("Try another name or path.")
                    )
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
    private var session: FlutterSession? { model.session(for: project) }
    private var state: SessionState { session?.state ?? .ready }
    private var device: SimulatorDevice? {
        model.device(for: project)
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
                .accessibilityValue(
                    (selected ? L10n.text("Selected") : L10n.text("Not selected"))
                        + (heapBytes.map {
                            L10n.text(", main Dart isolate memory: ")
                                + ByteCountFormatter.string(fromByteCount: $0, countStyle: .memory)
                        } ?? ""))
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 4) {
                        Button {
                            model.openProjectFolder(project)
                        } label: {
                            Image(systemName: "folder").frame(width: 20, height: 20)
                        }.help(L10n.text("Project Folder") + " — " + project.path)
                            .accessibilityLabel(L10n.text("Open project folder for {0}", "\(project.name)"))
                        Button {
                            model.openProjectDataFolder(project.id)
                        } label: {
                            Image(systemName: "externaldrive").frame(width: 20, height: 20)
                        }.help(L10n.text("Open app data on the simulator"))
                            .accessibilityLabel(L10n.text("Open app data for {0}", "\(project.name)"))
                            .disabled(model.simulatorToolBusy)
                        Button {
                            model.resetProjectPermissions(project.id)
                        } label: {
                            Image(systemName: "lock.rotation").frame(width: 20, height: 20)
                        }.help(
                            session?.hasWork == true
                                ? L10n.text("Press Stop before resetting permissions")
                                : L10n.text("Reset app permissions")
                        )
                        .accessibilityLabel(L10n.text("Reset app permissions for {0}", "\(project.name)"))
                        .disabled(model.simulatorToolBusy || session?.hasWork == true)
                    }.font(.system(size: 11)).buttonStyle(.borderless).controlSize(.small)
                    if let heapBytes, state == .running {
                        Text("Dart \(ByteCountFormatter.string(fromByteCount: heapBytes, countStyle: .memory))")
                            .font(.system(size: 10)).monospacedDigit().foregroundStyle(.secondary)
                            .help(
                                L10n.text(
                                    "Main Dart isolate memory. Excludes the Flutter engine, graphics, and other isolates."
                                ))
                    } else if state == .running {
                        Text(
                            session?.launchProject?.launch.mode.title
                                ?? project.launch.mode.title
                        )
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
                Image(systemName: "checkmark").font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.accentColor).opacity(selected ? 1 : 0).frame(width: 12).accessibilityHidden(
                        true)
            }.padding(8)
            if model.simulatorToolProjectID == project.id {
                if model.simulatorToolBusy {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text(L10n.text("Action in progress…"))
                    }
                    .font(.system(size: 11)).padding(.horizontal, 8).padding(.bottom, 8)
                } else if let result = model.simulatorToolResult {
                    Text(L10n.display(result)).font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                        .padding(.horizontal, 8).padding(.bottom, 8)
                }
            }
        }
        .background(
            selected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(hovered ? 0.05 : 0),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .onHover { hovered = $0 }
        .task(id: [session?.id.uuidString ?? "", state.rawValue]) {
            heapBytes = nil
            guard state == .running else { return }
            while !Task.isCancelled {
                let value = await session?.mainIsolateHeapBytes()
                guard !Task.isCancelled else { return }
                heapBytes = value
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
            }
        }
    }
}
