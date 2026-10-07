import AppKit
import ApplicationServices
import Combine
import SimFlutDockCore

struct SimulatorWindow: Identifiable {
    let id: UUID
    let title: String
    let element: AXUIElement
    let windowServerID: UInt32?
    let frame: CGRect
    let minimized: Bool
    let hidden: Bool
}

@MainActor final class SimulatorWindowTracker: ObservableObject {
    @Published private(set) var windows: [SimulatorWindow] = []
    private(set) var focusedWindowID: UUID?
    @Published private(set) var running = false
    @Published private(set) var foreground = false
    @Published private(set) var trusted = AXIsProcessTrusted()
    @Published private(set) var hidden = false
    @Published private(set) var discoveryStatus = ""
    var onChange: (() -> Void)?
    var onGeometry: ((UUID, CGRect) -> Void)?
    private final class HostObservation {
        let application: AXUIElement
        var observer: AXObserver?
        var watched: [(AXUIElement, String)] = []
        init(pid: pid_t) { application = AXUIElementCreateApplication(pid) }
        func disconnect() {
            guard let observer else { return }
            for (element, name) in watched { AXObserverRemoveNotification(observer, element, name as CFString) }
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
            watched = []; self.observer = nil
        }
        deinit { disconnect() }
    }
    private var hosts: [pid_t: HostObservation] = [:]
    private var permissionTask: Task<Void, Never>?
    private var workspaceTokens: [NSObjectProtocol] = []
    private var screenToken: NSObjectProtocol?
    private var refreshTask: Task<Void, Never>?
    private var hiddenBundles: Set<String> = []
    private var geometryFrames: [UUID: CGRect] = [:]
    init() {
        WindowServerObserver.shared.onGeometry = { [weak self] serverID, frame in
            guard let self, let window = self.windows.first(where: { $0.windowServerID == serverID }) else { return }
            self.deliverGeometry(window, frame: frame)
        }
        WindowServerObserver.shared.onVisibility = { [weak self] serverID, _ in
            guard let self, self.windows.contains(where: { $0.windowServerID == serverID }) else { return }
            // WindowServer ordering events are only refresh hints. Resolve
            // hidden/minimized state through AX before hiding the companion.
            self.scheduleRefresh()
        }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.didActivateApplicationNotification, NSWorkspace.didHideApplicationNotification, NSWorkspace.didUnhideApplicationNotification,
                     NSWorkspace.activeSpaceDidChangeNotification] {
            workspaceTokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                       let bundle = app.bundleIdentifier, SimulatorHost.bundleIDs.contains(bundle) {
                        if name == NSWorkspace.didHideApplicationNotification { self.hiddenBundles.insert(bundle) }
                        if name == NSWorkspace.didUnhideApplicationNotification || name == NSWorkspace.didTerminateApplicationNotification { self.hiddenBundles.remove(bundle) }
                    }
                    self.refresh()
                }
            })
        }
        screenToken = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        refresh()
        // Grants made in System Settings can arrive after the prompt flow, and a
        // nonactivating panel does not generate application activation events.
        permissionTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 2_000_000_000) } catch { return }
                guard let self else { return }
                if AXIsProcessTrusted() != self.trusted || (self.trusted && self.running && self.windows.isEmpty) { self.refresh() }
            }
        }
    }
    func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        refresh()
        if !trusted { _ = AXIsProcessTrustedWithOptions(options) }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
    private func read<T>(_ element: AXUIElement, _ attribute: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? T
    }
    func refresh() {
        trusted = AXIsProcessTrusted()
        let simulators = SimulatorHost.runningProcesses
        running = !simulators.isEmpty; hidden = !simulators.isEmpty && simulators.allSatisfy(\.isHidden)
        let active = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        foreground = SimulatorHost.bundleIDs.contains(active ?? "") || active == Bundle.main.bundleIdentifier
        discoveryStatus = running ? L10n.text("Waiting for Simulator / Device Hub windows") : L10n.text("Simulator / Device Hub is not running")
        guard trusted, running else {
            disconnect(); windows = []; focusedWindowID = nil; onChange?(); return
        }
        // Simulator and Device Hub can coexist. Observe every host rather than the first process.
        let runningPIDs = Set(simulators.map(\.processIdentifier))
        for oldPID in Array(hosts.keys) where !runningPIDs.contains(oldPID) {
            hosts.removeValue(forKey: oldPID)?.disconnect()
        }
        var newWindows: [SimulatorWindow] = []
        var focusedID: UUID?
        var reports: [String] = []
        for simulator in simulators {
            let pid = simulator.processIdentifier
            let host: HostObservation
            if let existing = hosts[pid] { host = existing }
            else {
                host = HostObservation(pid: pid); hosts[pid] = host
                AXUIElementSetMessagingTimeout(host.application, 1)
            }
            if host.observer == nil {
                var observer: AXObserver?
                if AXObserverCreate(pid, { _, element, notification, context in
                    guard let context else { return }
                    let tracker = Unmanaged<SimulatorWindowTracker>.fromOpaque(context).takeUnretainedValue()
                    DispatchQueue.main.async { [weak tracker] in
                        guard let tracker else { return }
                        if notification as String == kAXMovedNotification || notification as String == kAXResizedNotification {
                            tracker.refreshGeometry(element)
                        } else { tracker.scheduleRefresh() }
                    }
                }, &observer) == .success, let observer {
                    host.observer = observer
                    CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
                }
            }
            for notification in [kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification] {
                watch(host.application, notification, host: host)
            }
            var rawWindows: CFTypeRef?
            let windowError = AXUIElementCopyAttributeValue(host.application, kAXWindowsAttribute as CFString, &rawWindows)
            var elements = rawWindows as? [AXUIElement] ?? []
            let focusedElement: AXUIElement? = read(host.application, kAXFocusedWindowAttribute)
            let hostFrontmost: Bool = read(host.application, kAXFrontmostAttribute) ?? false
            // Some host windows are exposed as the focused/main window before
            // they appear in AXWindows (notably SwiftUI Device Hub windows).
            for attribute in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
                if let window: AXUIElement = read(host.application, attribute), !elements.contains(where: { CFEqual($0, window) }) { elements.append(window) }
            }
            var usableCount = 0
            let hostHidden: Bool = hiddenBundles.contains(simulator.application.bundleIdentifier ?? "") ||
                (read(host.application, kAXHiddenAttribute) ?? simulator.isHidden)
            for element in elements {
                AXUIElementSetMessagingTimeout(element, 1)
                let title: String = read(element, kAXTitleAttribute) ?? "Simulator"
                guard let position: AXValue = read(element, kAXPositionAttribute), let size: AXValue = read(element, kAXSizeAttribute),
                      AXValueGetType(position) == .cgPoint, AXValueGetType(size) == .cgSize else {
                    NSLog("SimFlutDock: AX window has no frame: %@", title); continue
                }
                var point = CGPoint.zero, dimensions = CGSize.zero
                AXValueGetValue(position, .cgPoint, &point); AXValueGetValue(size, .cgSize, &dimensions)
                guard dimensions.width > 100, dimensions.height > 150 else { continue }
                usableCount += 1
                let id = windows.first { CFEqual($0.element, element) }?.id ?? UUID()
                if hostFrontmost, let focusedElement, CFEqual(focusedElement, element) { focusedID = id }
                let frame = PanelPlacement.appKitRect(ax: CGRect(origin: point, size: dimensions), primaryTop: NSScreen.screens.first?.frame.maxY ?? 0)
                newWindows.append(SimulatorWindow(id: id, title: title, element: element,
                                                 windowServerID: WindowServerObserver.shared.id(for: element), frame: frame,
                                                 minimized: read(element, kAXMinimizedAttribute) ?? false, hidden: hostHidden))
                for notification in [kAXMovedNotification, kAXResizedNotification, kAXTitleChangedNotification,
                                     kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification, kAXUIElementDestroyedNotification] {
                    watch(element, notification, host: host)
                }
            }
            let report = L10n.text("{0}: AXWindows={1}, found {2}, with coordinates {3}", "\(simulator.localizedName ?? "Simulator")", "\(windowError.rawValue)", "\(elements.count)", "\(usableCount)")
            reports.append(report)
            if usableCount == 0 { NSLog("SimFlutDock: %@", report) }
            if let observer = host.observer {
                host.watched.removeAll { element, name in
                    guard !CFEqual(element, host.application), !elements.contains(where: { CFEqual($0, element) }) else { return false }
                    AXObserverRemoveNotification(observer, element, name as CFString); return true
                }
            }
        }
        discoveryStatus = reports.joined(separator: "\n")
        hidden = !simulators.isEmpty && simulators.allSatisfy { simulator in
            hiddenBundles.contains(simulator.application.bundleIdentifier ?? "") ||
            (hosts[simulator.processIdentifier].flatMap { read($0.application, kAXHiddenAttribute) as Bool? } ?? simulator.isHidden)
        }
        focusedWindowID = focusedID
        windows = newWindows
        geometryFrames = Dictionary(uniqueKeysWithValues: newWindows.map { ($0.id, $0.frame) })
        let serverIDs = Set(newWindows.compactMap(\.windowServerID))
        let fast = WindowServerObserver.shared.watch(serverIDs)
        if ProcessInfo.processInfo.arguments.contains("--verify-panel-follow") {
            NSLog("SimFlutDock follow: trusted=%d, windows=%d, WindowServer=%d, ids=%@", trusted, windows.count, fast, serverIDs.description)
        }
        onChange?()
    }
    private func refreshGeometry(_ element: AXUIElement) {
        guard let window = windows.first(where: { CFEqual($0.element, element) }) else { scheduleRefresh(); return }
        let frame: CGRect
        if let id = window.windowServerID, let serverFrame = WindowServerObserver.shared.frame(for: id) {
            frame = serverFrame
        } else {
            guard let position: AXValue = read(element, kAXPositionAttribute), let size: AXValue = read(element, kAXSizeAttribute),
                  AXValueGetType(position) == .cgPoint, AXValueGetType(size) == .cgSize else { scheduleRefresh(); return }
            var point = CGPoint.zero, dimensions = CGSize.zero
            AXValueGetValue(position, .cgPoint, &point); AXValueGetValue(size, .cgSize, &dimensions)
            frame = CGRect(origin: point, size: dimensions)
        }
        deliverGeometry(window, frame: frame)
    }
    private func deliverGeometry(_ window: SimulatorWindow, frame: CGRect) {
        let converted = PanelPlacement.appKitRect(ax: frame, primaryTop: NSScreen.screens.first?.frame.maxY ?? 0)
        geometryFrames[window.id] = converted
        onGeometry?(window.id, converted)
    }
    func currentFrame(of window: SimulatorWindow) -> CGRect {
        if let id = window.windowServerID, let frame = WindowServerObserver.shared.frame(for: id) {
            return PanelPlacement.appKitRect(ax: frame, primaryTop: NSScreen.screens.first?.frame.maxY ?? 0)
        }
        return geometryFrames[window.id] ?? window.frame
    }
    private func watch(_ element: AXUIElement, _ notification: String, host: HostObservation) {
        guard let observer = host.observer, !host.watched.contains(where: { CFEqual($0.0, element) && $0.1 == notification }) else { return }
        if AXObserverAddNotification(observer, element, notification as CFString, Unmanaged.passUnretained(self).toOpaque()) == .success {
            host.watched.append((element, notification))
        }
    }
    private func scheduleRefresh() {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 16_000_000) } catch { return }
            guard let self else { return }; self.refreshTask = nil; self.refresh()
        }
    }
    func matching(_ device: SimulatorDevice?, knownDevices: [SimulatorDevice]) -> [SimulatorWindow] {
        guard let device else { return windows }
        return windows.filter { SimulatorWindowIdentity.matches(title: $0.title, device: device, knownDevices: knownDevices) }
    }
    func raise(_ window: SimulatorWindow) {
        AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
    }
    func reveal(_ window: SimulatorWindow) {
        var pid: pid_t = 0
        AXUIElementGetPid(window.element, &pid)
        if let host = hosts[pid] {
            AXUIElementSetAttributeValue(host.application, kAXHiddenAttribute as CFString, kCFBooleanFalse)
            AXUIElementSetAttributeValue(host.application, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        }
        AXUIElementSetAttributeValue(window.element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        raise(window)
    }
    @discardableResult func move(_ window: SimulatorWindow, to origin: CGPoint) -> Bool {
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
        var position = CGPoint(x: origin.x, y: primaryTop - origin.y - currentFrame(of: window).height)
        guard let value = AXValueCreate(.cgPoint, &position) else { return false }
        return AXUIElementSetAttributeValue(window.element, kAXPositionAttribute as CFString, value) == .success
    }
    private func disconnect() {
        refreshTask?.cancel(); refreshTask = nil
        for host in hosts.values { host.disconnect() }
        hosts = [:]
        geometryFrames = [:]
        WindowServerObserver.shared.watch([])
    }
    deinit {
        refreshTask?.cancel(); permissionTask?.cancel()
        for token in workspaceTokens { NSWorkspace.shared.notificationCenter.removeObserver(token) }
        if let screenToken { NotificationCenter.default.removeObserver(screenToken) }
    }
}
