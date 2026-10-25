import AppKit
import SimFlutDockCore
import SwiftUI

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
        .disabled(
            model.manager.shuttingDown
                || (model.selectedSessionKey.map {
                    model.manager.foregroundIDs.contains($0) || model.manager.rerunningIDs.contains($0)
                } ?? false))
    }
    @ViewBuilder
    private func sessionIcon(_ symbol: String, regular: String) -> some View {
        if compact {
            PanelIcon(symbol: symbol)
        } else {
            Image(systemName: regular)
        }
    }
    private var rerunIcon: some View {
        ZStack(alignment: .topLeading) {
            Image(systemName: "play.fill")
                .font(.system(size: 12, weight: .medium))
                .frame(width: 14, height: 14)
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 9, weight: .medium))
                .frame(width: 9, height: 9)
                .offset(x: 9, y: 9)
        }
        .frame(width: 18, height: 18)
        .accessibilityHidden(true)
    }
    private var buttons: some View {
        Group {
            Button {
                model.run()
            } label: {
                Label {
                    Text(model.selectedSession?.hasWork == true ? "Rerun" : "Run")
                } icon: {
                    if model.checkingLaunchDevice {
                        ProgressView().controlSize(.small).frame(width: 18, height: 18)
                    } else if model.selectedSession?.hasWork == true {
                        rerunIcon
                    } else {
                        sessionIcon("play", regular: "play.fill")
                    }
                }.foregroundStyle(.green)
            }
            .disabled(!model.canRunOrRerun)
            .help(
                model.selectedSession?.hasWork == true
                    ? L10n.text("Rerun — stop, rebuild and launch the selected session")
                    : L10n.text("Run — start a new {0} session on the selected device", "\(model.launchMode.title)"))
            Button {
                model.restart(full: false)
            } label: {
                Label {
                    Text("Hot Reload")
                } icon: {
                    sessionIcon("bolt", regular: "bolt.fill")
                }.foregroundStyle(.orange)
            }
            .disabled(!(model.selectedSession?.canRestart ?? false))
            .help(L10n.text("Hot Reload — preserve Dart state"))
            Button {
                model.restart(full: true)
            } label: {
                Label {
                    Text("Hot Restart")
                } icon: {
                    sessionIcon("arrow.clockwise", regular: "arrow.clockwise")
                }.foregroundStyle(.green)
            }
            .disabled(!(model.selectedSession?.canRestart ?? false))
            .help(L10n.text("Hot Restart — reset Dart state. After native code changes, use Rerun."))
            Button {
                model.selectedSession?.stop()
            } label: {
                Label {
                    Text("Stop")
                } icon: {
                    sessionIcon("stop", regular: "stop.fill")
                }.foregroundStyle(.red)
            }
            .disabled(!(model.selectedSession?.canStop ?? false))
            .help(L10n.text("Stop — stop only the selected session"))
        }
    }
}

struct PanelDragHandle: NSViewRepresentable {
    let model: AppModel
    func makeNSView(context: Context) -> DragView {
        let view = DragView()
        view.drag = model.dragPanel
        return view
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
        model.launchBusy
    }
    private var hubBackground: Color {
        colorScheme == .dark
            ? Color(red: 32 / 255, green: 38 / 255, blue: 36 / 255) : Color(nsColor: .windowBackgroundColor)
    }
    private var panelLayout: AnyLayout {
        model.verticalPanel
            ? AnyLayout(VStackLayout(spacing: PanelMetrics.groupSpacing))
            : AnyLayout(HStackLayout(spacing: narrowPanel ? 4 : PanelMetrics.groupSpacing))
    }
    private var narrowPanel: Bool { !model.verticalPanel && model.panelWidth < 400 }
    private var controlWidth: CGFloat {
        // Nine controls, six group gaps, two drag separators and outer insets.
        narrowPanel ? min(PanelMetrics.controlSize, max(24, (model.panelWidth - 68) / 9)) : PanelMetrics.controlSize
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
                    Button {
                        model.showLogs()
                    } label: {
                        PanelIcon(symbol: "doc.text").foregroundStyle(PanelMetrics.logsColor)
                    }
                    .buttonStyle(PanelButtonStyle())
                    .accessibilityLabel(L10n.text("Show logs for the selected project"))
                    .help(L10n.text("Show logs for the selected project"))
                    Button {
                        model.openDevTools()
                    } label: {
                        PanelIcon(symbol: "wrench.and.screwdriver").foregroundStyle(.purple)
                    }
                    .buttonStyle(PanelButtonStyle())
                    .disabled(!model.canOpenDevTools)
                    .accessibilityLabel(L10n.text("Open DevTools for the selected session"))
                    .help(L10n.text("Open DevTools for the selected session"))
                    Color.clear
                        .frame(width: controlWidth, height: PanelMetrics.controlHeight)
                        .overlay {
                            Menu {
                                if hasError {
                                    Button {
                                        showingError = true
                                    } label: {
                                        Label(L10n.text("Show Error…"), systemImage: "exclamationmark.triangle")
                                    }
                                    Divider()
                                }
                                Button {
                                    model.showSettings()
                                } label: {
                                    Label(L10n.text("Settings…"), systemImage: "gearshape")
                                }
                                Menu {
                                    Toggle(L10n.text("Free Position"), isOn: $model.freePanel)
                                    Button(L10n.text("Reset Position")) { model.resetPanel() }
                                    if !model.tracker.trusted {
                                        Button(L10n.text("Allow access in SimFlutDock settings")) {
                                            model.showSettings()
                                        }
                                    } else if model.tracker.windows.isEmpty {
                                        Text(L10n.text("No open Simulator windows"))
                                    } else {
                                        Menu(L10n.text("Attach to Simulator Window")) {
                                            ForEach(model.tracker.windows) { window in
                                                Button(
                                                    "\(window.title) (\(Int(window.frame.minX)), \(Int(window.frame.minY)))"
                                                ) { model.bindWindow(window.id) }
                                            }
                                        }
                                    }
                                    Divider()
                                    Button(L10n.text("Refresh Attachment")) { model.tracker.refresh() }
                                } label: {
                                    Label(L10n.text("Panel Position"), systemImage: "rectangle.3.group")
                                }
                                Divider()
                                Button {
                                    model.quitApp()
                                } label: {
                                    Label(L10n.text("Quit SimFlutDock"), systemImage: "power")
                                }
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
                        .accessibilityLabel(L10n.text("Panel settings and menu")).help(
                            model.launchProgressMessage ?? model.selectedSession?.state.title
                                ?? L10n.text("Panel settings and menu")
                        )
                        .popover(isPresented: $showingError, arrowEdge: .bottom) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(L10n.text("Could not complete the action")).font(.headline)
                                if let error = model.selectedSession?.error {
                                    Text(L10n.display(error)).font(.caption).textSelection(.enabled)
                                }
                                if let message = model.message {
                                    Text(L10n.display(message)).font(.caption).textSelection(.enabled)
                                }
                                Button(L10n.text("Open Logs…")) { model.showLogs() }
                                Button(L10n.text("Close")) {
                                    showingError = false
                                    model.message = nil
                                }
                            }.padding(16).frame(width: 300, alignment: .leading)
                        }
                }
            }
            .environment(\.panelControlWidth, controlWidth)
            .padding(model.verticalPanel ? .vertical : .horizontal, PanelMetrics.inset)
            .frame(width: model.panelWidth, height: model.verticalPanel ? 416 : PanelMetrics.rowHeight)
            if busy && !model.verticalPanel {
                HStack(spacing: 10) {
                    Text(
                        L10n.display(
                            model.launchProgressMessage ?? model.selectedSession?.state.title
                                ?? L10n.text("Working…"))
                    )
                    .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .help(L10n.display(model.launchProgressMessage ?? ""))
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
        .onChange(of: model.checkingLaunchDevice) { _, checking in if checking { showingError = false } }
        .onChange(of: model.selectedSession?.error) { _, error in if error != nil { showingError = true } }
    }
}
