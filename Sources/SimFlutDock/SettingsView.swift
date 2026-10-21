import AppKit
import SimFlutDockCore
import SwiftUI

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
        Color(
            nsColor: NSColor(name: nil) { appearance in
                let rgb = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
                return NSColor(
                    srgbRed: CGFloat((rgb >> 16) & 255) / 255,
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
                        .overlay(
                            RoundedRectangle(cornerRadius: 4).strokeBorder(
                                selected ? Color.accentColor : Color.primary.opacity(0.2),
                                style: StrokeStyle(lineWidth: 1, dash: selected ? [] : [3, 3]))
                        )
                        .frame(width: vertical ? 10 : 62, height: vertical ? 90 : 10)
                        .offset(
                            x: position == .left ? -48 : (position == .right ? 48 : 0),
                            y: position == .above ? -72 : (position == .below ? 72 : 0))
                }
            }.frame(width: 138, height: 166).accessibilityHidden(true)
            Text(
                detached
                    ? L10n.text("The panel can be moved independently of Simulator.")
                    : L10n.text(
                        "If there is not enough room on the selected side, the panel appears on the opposite side.")
            )
            .font(.system(size: 11)).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true).frame(maxWidth: 300, alignment: .leading)
        }.frame(maxWidth: .infinity).padding(.vertical, 10)
    }
}

private struct BackgroundLaunchSettings: View {
    @ObservedObject var background: BackgroundLaunch
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsToggle(
                title: L10n.text("Launch with Simulator"),
                subtitle: L10n.text("Open the panel when Simulator starts."),
                isOn: Binding(
                    get: { background.enabled || background.status == .requiresApproval },
                    set: { background.setEnabled($0) }))
            if background.status == .notFound || background.status == .requiresApproval {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.circle").foregroundStyle(.orange).accessibilityHidden(true)
                    Text(background.status == .notFound ? L10n.text("Background helper unavailable") : background.title)
                        .font(.system(size: 11)).foregroundStyle(.secondary)
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
                        Button {
                            destination = item
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: item.symbol).font(.system(size: 17)).frame(width: 22)
                                    .accessibilityHidden(true)
                                Text(item.title).font(
                                    .system(size: 13, weight: destination == item ? .semibold : .regular))
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 12).frame(height: 40)
                            .foregroundStyle(destination == item ? Color.accentColor : Color.primary)
                            .background(
                                destination == item ? Color.accentColor.opacity(0.16) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 7)
                            )
                            .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                            .accessibilityValue(destination == item ? L10n.text("Selected") : L10n.text("Not selected"))
                    }
                }.padding(.horizontal, 12)
                Spacer()
                Divider()
                Button {
                    model.showPanel()
                } label: {
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
                                    do {
                                        let backup = try model.store.recoverPersistence()
                                        model.message =
                                            backup.map { L10n.text("Previous file preserved: ") + $0.path }
                                            ?? L10n.text("Saving restored.")
                                    } catch { model.message = error.localizedDescription }
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
                                Button {
                                    model.message = nil
                                } label: {
                                    Image(systemName: "xmark")
                                }
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

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.7"
    }

    private var projectSettings: some View {
        VStack(alignment: .leading, spacing: 22) {
            if model.store.projects.isEmpty {
                ContentUnavailableView(
                    L10n.text("Open a Flutter Project"), systemImage: "folder",
                    description: Text(
                        L10n.text("Select a folder containing pubspec.yaml. The app starts only after you press Run.")))
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
        .confirmationDialog(
            L10n.text("Clear all saved projects? Project files and app data will remain on disk."),
            isPresented: $confirmClearProjects
        ) {
            Button(L10n.text("Clear Saved Projects"), role: .destructive) { model.clearSavedProjects() }
            Button(L10n.text("Cancel"), role: .cancel) {}
        }
    }

    private var toolsSettings: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsSection(L10n.text("Project and Simulator")) {
                SettingsField(L10n.text("Project")) {
                    Picker(
                        L10n.text("Project"),
                        selection: Binding(
                            get: { model.store.selectedID },
                            set: { id in
                                if let project = model.store.projects.first(where: { $0.id == id }) {
                                    model.select(project)
                                }
                            })
                    ) {
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
                SettingsField(
                    L10n.text("Default Flutter SDK"),
                    subtitle: L10n.text("Used when no project SDK is configured. Supports FVM.")
                ) {
                    HStack(spacing: 8) {
                        TextField(L10n.text("Automatic"), text: $model.globalSDK)
                            .textFieldStyle(.roundedBorder).accessibilityLabel(L10n.text("Default Flutter SDK"))
                        Button(L10n.text("Choose…")) { model.chooseSDK { model.globalSDK = $0 } }.controlSize(.small)
                    }
                }
                Divider()
                SettingsField(
                    L10n.text("Flutter and Xcode"), subtitle: L10n.text("Uses the active Xcode installation.")
                ) {
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
                SettingsToggle(
                    title: L10n.text("Free Position"),
                    subtitle: L10n.text("The panel can be moved independently of Simulator."), isOn: $model.freePanel)
                Divider()
                SettingsField(L10n.text("Simulator Side")) {
                    Picker(L10n.text("Side of the Simulator window"), selection: $model.panelSide) {
                        ForEach([PanelSide.above, .right, .below, .left], id: \.self) { side in
                            Text(side.title).tag(side)
                        }
                    }.labelsHidden().pickerStyle(.segmented).disabled(model.standalonePanel)
                }
                Divider()
                PanelPlacementPreview(side: model.panelSide, detached: model.standalonePanel)
            }
            SettingsSection(L10n.text("Menu Bar Icon")) {
                SettingsToggle(
                    title: L10n.text("Hide or show the panel on click"),
                    subtitle: L10n.text(
                        "When the panel is not attached to a Simulator window, one click hides it completely and the next shows it again."
                    ),
                    isOn: $model.toggleUnboundPanelFromTray)
            }
            SettingsSection(L10n.text("Simulator Window Access")) {
                SettingsField(
                    L10n.text("Accessibility"),
                    subtitle: L10n.text("Allow access to attach the panel to a Simulator window.")
                ) {
                    HStack(spacing: 12) {
                        Label(
                            model.tracker.trusted ? L10n.text("Allowed") : L10n.text("Permission required"),
                            systemImage: model.tracker.trusted ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
                        )
                        .font(.system(size: 11)).foregroundStyle(model.tracker.trusted ? Color.secondary : Color.orange)
                        if !model.tracker.trusted {
                            Button(L10n.text("Allow Access…")) { model.tracker.requestPermission() }.controlSize(.small)
                        }
                    }
                }
                Divider()
                HStack {
                    Text(
                        L10n.text(
                            "You can select a window manually in the panel menu: ⚙ → Panel Position → Attach to Simulator Window."
                        )
                    )
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
                        Text(
                            L10n.text(
                                "Version {0} · Build {1}", appVersion,
                                Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "5")
                        )
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
    private var session: FlutterSession? { model.session(for: project) }
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
                        Image(systemName: "link").font(.system(size: 18)).foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(link.name).font(.body.weight(.medium))
                            Text(link.url).font(.callout).foregroundStyle(.secondary)
                                .textSelection(.enabled).lineLimit(2).help(link.url)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        Button(L10n.text("Open")) { model.simulatorAction(.link(link.url)) }.disabled(!available)
                            .accessibilityLabel(L10n.text("Open link {0}", "\(link.name)"))
                        Button {
                            edit(link)
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .accessibilityLabel(L10n.text("Edit link {0}", "\(link.name)")).help(L10n.text("Edit link"))
                        Button(role: .destructive) {
                            remove(link)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .accessibilityLabel(L10n.text("Delete link {0}", "\(link.name)")).help(L10n.text("Delete link"))
                    }.padding(18)
                    Divider()
                }
                if editingLink != nil {
                    VStack(alignment: .leading, spacing: 12) {
                        TextField(L10n.text("Link name"), text: $linkName).textFieldStyle(.roundedBorder)
                            .accessibilityLabel(L10n.text("Link name"))
                        TextField(L10n.text("myapp://profile or https://example.com/profile"), text: $linkURL)
                            .textFieldStyle(.roundedBorder).accessibilityLabel(L10n.text("Link URL")).onSubmit {
                                saveLink()
                            }
                        if let linkError { Text(linkError).font(.callout).foregroundStyle(.red) }
                        HStack {
                            Button(L10n.text("Cancel")) {
                                editingLink = nil
                                linkError = nil
                            }
                            Spacer()
                            Button(L10n.text("Save")) { saveLink() }
                                .disabled(
                                    linkName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || linkURL.isEmpty)
                        }
                    }.padding(18)
                } else {
                    Button(L10n.text("Add Link…"), systemImage: "plus") { edit(SavedDeepLink()) }.padding(18)
                }
                Divider()
                SettingsNote(
                    L10n.text(
                        "Links open in the selected iOS Simulator. The app must support the URL scheme or Universal Link; web links may open in Safari."
                    ))
            }
            if model.simulatorToolDevice?.isIOSSimulator != true || model.simulatorToolDevice?.state != "Booted" {
                Text(
                    L10n.text(
                        "Select a running iOS Simulator to perform actions. You can save links without a running device."
                    )
                )
                .font(.callout).foregroundStyle(.secondary)
            }
            if model.simulatorToolProjectID == project.id {
                if model.simulatorToolBusy {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text(L10n.text("Action in progress…"))
                    }
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
        editingLink = link
        linkName = link.name
        linkURL = link.url
        linkError = nil
    }
    private func saveLink() {
        guard var link = editingLink, var current = model.store.projects.first(where: { $0.id == project.id }) else {
            return
        }
        do {
            link.name = linkName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !link.name.isEmpty else { throw SimFlutDockError.message(L10n.text("Enter a link name.")) }
            link.url = try SavedDeepLink.validatedURL(linkURL)
            if let index = current.deepLinks.firstIndex(where: { $0.id == link.id }) {
                current.deepLinks[index] = link
            } else {
                current.deepLinks.append(link)
            }
            model.store.update(current)
            editingLink = nil
            linkError = nil
        } catch { linkError = error.localizedDescription }
    }
    private func remove(_ link: SavedDeepLink) {
        guard var current = model.store.projects.first(where: { $0.id == project.id }) else { return }
        current.deepLinks.removeAll { $0.id == link.id }
        model.store.update(current)
        if editingLink?.id == link.id {
            editingLink = nil
            linkError = nil
        }
    }
}

private struct SavedProjectSettingsRow: View {
    @ObservedObject var model: AppModel
    let project: Project
    @State private var confirmRemoval = false
    private var busy: Bool { model.manager.hasActiveSessions(for: project.id) }
    private var selected: Bool { model.store.selectedID == project.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    model.select(project)
                } label: {
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
                        Text(model.session(for: project)?.state.title ?? L10n.text("Ready"))
                            .font(.caption).foregroundStyle(.secondary)
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle").foregroundStyle(
                            selected ? Color.accentColor : Color.secondary.opacity(0.4)
                        )
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
                    }.disabled(model.session(for: project)?.hasWork == true || model.simulatorToolBusy)
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
        .confirmationDialog(
            L10n.text("Remove this project from the list? Files will remain on disk."), isPresented: $confirmRemoval
        ) {
            Button(L10n.text("Remove"), role: .destructive) { model.removeSavedProject(project.id) }
            Button(L10n.text("Cancel"), role: .cancel) {}
        }
    }

}

struct ProjectEditor: View {
    @ObservedObject var model: AppModel
    @State private var project: Project
    init(model: AppModel, initial: Project) {
        self.model = model
        _project = State(initialValue: initial)
    }
    private var busy: Bool { model.manager.hasActiveSessions(for: project.id) }
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
                if let error = model.session(for: project)?.error {
                    Button(error) { model.showLogs() }.buttonStyle(.plain).foregroundStyle(.red).padding(18)
                }
            }
            SettingsSection("Flutter SDK") {
                SettingsField(
                    L10n.text("Project Flutter SDK"), subtitle: L10n.text("Uses the project SDK or the default SDK.")
                ) {
                    HStack(spacing: 8) {
                        TextField(
                            L10n.text("Automatic / FVM"),
                            text: Binding(
                                get: { project.sdkPath ?? "" },
                                set: {
                                    project.sdkPath = $0.isEmpty ? nil : $0
                                    save()
                                })
                        )
                        .textFieldStyle(.roundedBorder).accessibilityLabel(L10n.text("Project Flutter SDK"))
                        Button(L10n.text("Choose…")) {
                            model.chooseSDK {
                                project.sdkPath = $0
                                save()
                            }
                        }.controlSize(.small)
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
