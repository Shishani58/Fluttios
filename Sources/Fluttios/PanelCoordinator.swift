import AppKit
import SwiftUI
import Combine
import FluttiosCore

final class ControlPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func showIfNeeded() {
        // Reordering a visible panel can interrupt its popover's presentation.
        if !isVisible { orderFront(nil) }
    }

    static func settingsOwnFocus(_ settings: NSWindow, keyWindow: NSWindow?) -> Bool {
        guard settings.isVisible, !settings.isMiniaturized else { return false }
        // App activation also happens when a companion popover takes focus.
        // Only settings and its sheets should hide the companion panel.
        var window = keyWindow
        while let current = window {
            if current === settings { return true }
            window = current.sheetParent ?? current.parent
        }
        return false
    }
}

@MainActor final class PanelCoordinator: NSObject, NSWindowDelegate {
    let panel: ControlPanel
    private let model: AppModel
    private var observations: Set<AnyCancellable> = []
    private var positioning = false
    private var positionedOrigin: CGPoint?
    private var suppressed = true
    private var attachedWindow: SimulatorWindow?
    private var dragAnchor: (window: SimulatorWindow, windowOrigin: CGPoint, panelOrigin: CGPoint)?
    private var dragging = false
    private var allowWithoutSimulator = false
    private var lastTargetID: String?
    private var automaticBinding = AutomaticPanelBinding()
    private weak var statusButton: NSStatusBarButton?
    private weak var settingsWindow: NSWindow?
    init(model: AppModel) {
        self.model = model
        panel = ControlPanel(contentRect: CGRect(x: 200, y: 200, width: 420, height: 48), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        panel.title = "Fluttios"; panel.titleVisibility = .hidden; panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = false; panel.level = .floating; panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false; panel.isMovableByWindowBackground = false
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        model.dragPanel = { [weak self] event in self?.drag(with: event) }
        panel.contentView = NSHostingView(rootView: PanelView(model: model))
        panel.delegate = self
        if UserDefaults.standard.object(forKey: "freePanelX") != nil {
            panel.setFrameOrigin(CGPoint(x: UserDefaults.standard.double(forKey: "freePanelX"), y: UserDefaults.standard.double(forKey: "freePanelY")))
        }
        model.hidePanel = { [weak self] in self?.suppressed = true; self?.panel.orderOut(nil) }
        model.tracker.onChange = { [weak self] in self?.update() }
        model.tracker.onGeometry = { [weak self] id, frame in
            guard let self, !self.suppressed, !self.dragging, !self.model.standalonePanel,
                  self.attachedWindow?.id == id, self.panel.isVisible,
                  !self.model.tracker.hidden, self.model.tracker.foreground else { return }
            self.position(beside: frame)
        }
        model.store.objectWillChange.sink { [weak self] in DispatchQueue.main.async { self?.update() } }.store(in: &observations)
        model.simulators.objectWillChange.sink { [weak self] in DispatchQueue.main.async { self?.update() } }.store(in: &observations)
        model.manager.objectWillChange.sink { [weak self] in DispatchQueue.main.async { self?.update() } }.store(in: &observations)
        model.$freePanel.sink { [weak self] _ in DispatchQueue.main.async { self?.update() } }.store(in: &observations)
        model.$panelSide.sink { [weak self] _ in DispatchQueue.main.async { self?.update() } }.store(in: &observations)
        // Re-evaluate after AppKit finishes activating, closing or minimizing settings.
        for name in [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification,
                     NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
                     NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification,
                     NSWindow.willCloseNotification] {
            NotificationCenter.default.publisher(for: name).sink { [weak self] _ in
                DispatchQueue.main.async { self?.update() }
            }.store(in: &observations)
        }
        model.bindWindow = { [weak self] id in
            guard let self else { return }
            self.model.panelWindowBindings[self.bindingKey] = id; self.model.freePanel = false; self.show()
        }
        model.resetPanel = { [weak self] in
            UserDefaults.standard.removeObject(forKey: "panelOffsetX"); UserDefaults.standard.removeObject(forKey: "panelOffsetY")
            self?.model.freePanel = false
            self?.show()
        }
        update()
    }
    private var bindingKey: String { model.panelBindingKey }
    func avoidCoveringSettings(_ window: NSWindow) {
        settingsWindow = window
        update()
    }
    private var boundWindow: SimulatorWindow? {
        guard !model.standalonePanel, model.tracker.trusted else { return nil }
        let tracker = model.tracker
        let explicit = model.manualPanelWindowID.flatMap { id in tracker.windows.first { $0.id == id } }
        let automatic = automaticBinding.windowID.flatMap { id in tracker.windows.first { $0.id == id } }
        let matches = tracker.matching(model.selectedDevice, knownDevices: model.simulators.devices)
        if model.selectedDevice != nil || model.store.selected?.deviceID != nil {
            return explicit ?? (matches.count == 1 ? matches.first : nil)
        }
        return explicit ?? automatic ?? (matches.count == 1 ? matches.first : nil)
    }
    func show(from button: NSStatusBarButton) {
        model.tracker.refresh()
        if boundWindow != nil {
            show()
        } else {
            statusButton = button
            attachedWindow = nil
            suppressed = false
            update()
        }
    }
    func show() {
        statusButton = nil
        suppressed = false
        model.tracker.refresh()
        let tracker = model.tracker
        if let window = boundWindow { tracker.reveal(window) }
        allowWithoutSimulator = !model.tracker.running
        // Recompute from the current geometry and the user's preferred side.
        model.tracker.refresh()
        update()
    }
    func update() {
        let tracker = model.tracker
        if !dragging, boundWindow == nil {
            model.actualPanelSide = nil
            model.panelWidth = 420
        }
        if !dragging, panel.frame.height != model.panelHeight || panel.frame.width != model.panelWidth {
            var frame = panel.frame
            frame.origin.y = frame.maxY - model.panelHeight
            frame.size.height = model.panelHeight
            frame.size.width = model.panelWidth
            positioning = true; panel.setFrame(frame, display: true); positioning = false
        }
        if lastTargetID != bindingKey {
            lastTargetID = bindingKey
            attachedWindow = nil
            // Keep Run reachable when the user selects a shutdown simulator.
            allowWithoutSimulator = panel.isVisible && boundWindow == nil
        }
        let deviceWindows = tracker.windows.filter { window in
            model.simulators.devices.contains { SimulatorWindowIdentity.matches(title: window.title, device: $0) }
        }
        let openedWindow = automaticBinding.update(windowIDs: deviceWindows.map(\.id), focusedID: tracker.focusedWindowID)
        if openedWindow, !model.standalonePanel {
            suppressed = false
            statusButton = nil
        }
        guard !suppressed else { panel.orderOut(nil); return }
        if let settingsWindow, NSApp.isActive,
           ControlPanel.settingsOwnFocus(settingsWindow, keyWindow: NSApp.keyWindow) {
            // Temporary visibility only: preserve the user's panel and binding state.
            panel.orderOut(nil)
            return
        }
        let window = boundWindow
        if window == nil, let button = statusButton, let buttonWindow = button.window {
            guard !dragging else { return }
            attachedWindow = nil
            model.attachmentStatus = model.standalonePanel ? (model.standaloneTarget ? L10n.text("Device • detached from Simulator") : L10n.text("Free Position")) :
                (tracker.trusted ? L10n.text("Select a Simulator window in the settings menu") : L10n.text("macOS has not granted Accessibility access to this copy of Fluttios"))
            let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
            let visible = buttonWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? anchor
            let origin = CGPoint(x: max(visible.minX, min(anchor.midX - panel.frame.width / 2, visible.maxX - panel.frame.width)),
                                 y: max(visible.minY, min(anchor.minY - panel.frame.height - 8, visible.maxY - panel.frame.height)))
            positioning = true
            panel.setFrameOrigin(origin)
            positioning = false
            panel.level = .floating
            panel.showIfNeeded()
            return
        }
        statusButton = nil
        // Keep the companion panel above other apps while Simulator is active.
        // Visibility is controlled below; ordinary window ordering can put it
        // behind another app even when its attached Simulator stays in front.
        panel.level = .floating
        if model.standalonePanel {
            guard !dragging else { return }
            attachedWindow = nil
            model.attachmentStatus = model.standaloneTarget ? L10n.text("Device • detached from Simulator") : L10n.text("Free Position")
            panel.showIfNeeded()
            return
        }
        if window != nil { allowWithoutSimulator = false }
        guard tracker.running ? ((!tracker.hidden && tracker.foreground) || (window == nil && allowWithoutSimulator)) : allowWithoutSimulator else {
            if panel.isVisible, ProcessInfo.processInfo.arguments.contains("--verify-panel-follow") {
                NSLog("Fluttios follow: panel hidden with host, hidden=%d foreground=%d", tracker.hidden, tracker.foreground)
            }
            panel.orderOut(nil); return
        }
        guard !dragging else { return }
        let matches = tracker.matching(model.selectedDevice, knownDevices: model.simulators.devices)
        if model.freePanel || !tracker.trusted {
            attachedWindow = nil; model.attachmentStatus = tracker.trusted ? L10n.text("Free Position") : L10n.text("macOS has not granted Accessibility access to this copy of Fluttios")
            panel.showIfNeeded(); return
        }
        guard let window else {
            if attachedWindow != nil { panel.orderOut(nil); return }
            attachedWindow = nil
            model.attachmentStatus = matches.count > 1 ? L10n.text("Select a Simulator window in the settings menu") : L10n.text("Device window not found • select a window in the settings menu")
            // Unbound panel stays usable but never silently follows the wrong device.
            panel.showIfNeeded(); return
        }
        guard !window.minimized && !window.hidden else { panel.orderOut(nil); return }
        if model.attachmentStatus != window.title { model.attachmentStatus = window.title }
        attachedWindow = window
        position(beside: tracker.currentFrame(of: window))
        panel.showIfNeeded()
    }
    private func position(beside windowFrame: CGRect) {
        let screen = NSScreen.screens.max { intersectionArea($0.frame, windowFrame) < intersectionArea($1.frame, windowFrame) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? windowFrame
        var size = PanelPlacement.attachedSize(window: windowFrame, visible: visible)
        size.height = model.horizontalPanelHeight
        let layout = PanelPlacement.attachedLayout(window: windowFrame, horizontalSize: size,
                                                   verticalSize: CGSize(width: 50, height: 374),
                                                   visible: visible, side: model.panelSide)
        model.actualPanelSide = layout.side
        if model.panelWidth != layout.frame.width { model.panelWidth = layout.frame.width }
        let frame = layout.frame
        guard panel.frame != frame else { return }
        positionedOrigin = frame.origin
        positioning = true; panel.setFrame(frame, display: true); positioning = false
        if ProcessInfo.processInfo.arguments.contains("--verify-panel-follow") {
            NSLog("Fluttios follow: simulator=%@ panel=%@ screen=%@ visible=%@ screens=%@", NSStringFromRect(windowFrame), NSStringFromRect(panel.frame), NSStringFromRect(screen?.frame ?? .zero), NSStringFromRect(visible), NSScreen.screens.map { "\(NSStringFromRect($0.frame)) visible=\(NSStringFromRect($0.visibleFrame))" }.joined(separator: "; "))
        }
    }
    private func intersectionArea(_ a: CGRect, _ b: CGRect) -> CGFloat { let rect = a.intersection(b); return rect.isNull ? 0 : rect.width * rect.height }
    private func drag(with event: NSEvent) {
        statusButton = nil
        dragAnchor = !model.standalonePanel ? attachedWindow.map { ($0, model.tracker.currentFrame(of: $0).origin, panel.frame.origin) } : nil
        dragging = true
        panel.performDrag(with: event)
        dragging = false; dragAnchor = nil
        model.tracker.refresh()
        update()
    }
    func windowDidMove(_ notification: Notification) {
        guard !positioning, panel.frame.origin != positionedOrigin else { return }
        positionedOrigin = nil
        if let anchor = dragAnchor {
            let origin = CGPoint(x: anchor.windowOrigin.x + panel.frame.minX - anchor.panelOrigin.x,
                                 y: anchor.windowOrigin.y + panel.frame.minY - anchor.panelOrigin.y)
            model.tracker.move(anchor.window, to: origin)
        } else {
            UserDefaults.standard.set(panel.frame.minX, forKey: "freePanelX"); UserDefaults.standard.set(panel.frame.minY, forKey: "freePanelY")
        }
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { suppressed = true; sender.orderOut(nil); return false }
}
