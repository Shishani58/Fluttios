import AppKit
import ApplicationServices
import Darwin

/// Optional fast geometry notifications. Private symbols are resolved at runtime;
/// Accessibility remains the fallback when this facility is unavailable.
@MainActor final class WindowServerObserver {
    static let shared = WindowServerObserver()
    private typealias Callback = @convention(c) (UInt32, UnsafeMutableRawPointer?, Int, UnsafeMutableRawPointer?) -> Void
    private typealias Register = @convention(c) (Callback, UInt32, UnsafeMutableRawPointer?) -> Int32
    private typealias Request = @convention(c) (Int32, UnsafeMutablePointer<UInt32>?, Int32) -> Int32
    private typealias Bounds = @convention(c) (Int32, UInt32, UnsafeMutablePointer<CGRect>) -> Int32
    private typealias WindowID = @convention(c) (AXUIElement, UnsafeMutablePointer<UInt32>) -> Int32
    private var connection: Int32 = 0
    private var request: Request?
    private var bounds: Bounds?
    private var windowID: WindowID?
    private var watched: Set<UInt32> = []
    private var registered = false
    private var verifiedGeometry = false
    var onGeometry: ((UInt32, CGRect) -> Void)?
    var onVisibility: ((UInt32, Bool) -> Void)?

    private init() {
        guard ProcessInfo.processInfo.environment["FLUTTIOS_DISABLE_PRIVATE_WINDOW_API"] != "1" else { return }
        guard let sky = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
              let ax = dlopen("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", RTLD_LAZY),
              let main = dlsym(sky, "SLSMainConnectionID"),
              let registration = dlsym(sky, "SLSRegisterNotifyProc"),
              let subscription = dlsym(sky, "SLSRequestNotificationsForWindows"),
              let geometry = dlsym(sky, "SLSGetWindowBounds"),
              let identity = dlsym(ax, "_AXUIElementGetWindow") else { return }
        connection = unsafeBitCast(main, to: (@convention(c) () -> Int32).self)()
        request = unsafeBitCast(subscription, to: Request.self)
        bounds = unsafeBitCast(geometry, to: Bounds.self)
        windowID = unsafeBitCast(identity, to: WindowID.self)
        let register = unsafeBitCast(registration, to: Register.self)
        // This singleton and its loaded libraries live for the application's lifetime.
        // Copy the event data before dispatch: WindowServer owns the callback buffer.
        let callback: Callback = { event, data, size, _ in
            guard let data, size >= MemoryLayout<UInt32>.size else { return }
            let id = data.loadUnaligned(as: UInt32.self)
            if Thread.isMainThread {
                MainActor.assumeIsolated { WindowServerObserver.shared.receive(event, id: id) }
            } else {
                DispatchQueue.main.async { WindowServerObserver.shared.receive(event, id: id) }
            }
        }
        registered = [UInt32(806), 807, 815, 816].allSatisfy { register(callback, $0, nil) == 0 }
    }
    func id(for element: AXUIElement) -> UInt32? {
        guard registered, let windowID else { return nil }
        var id: UInt32 = 0
        return windowID(element, &id) == 0 && id != 0 ? id : nil
    }
    @discardableResult func watch(_ ids: Set<UInt32>) -> Bool {
        guard registered, let request else { return false }
        if ids == watched { return true }
        var list = Array(ids)
        let result = list.withUnsafeMutableBufferPointer { request(connection, $0.baseAddress, Int32($0.count)) }
        guard result == 0 else { watched = []; return false }
        watched = ids
        return true
    }
    func frame(for id: UInt32) -> CGRect? {
        guard watched.contains(id), let bounds else { return nil }
        var frame = CGRect.zero
        guard bounds(connection, id, &frame) == 0, frame.width > 100, frame.height > 150 else { return nil }
        return frame
    }
    private func receive(_ event: UInt32, id: UInt32) {
        guard watched.contains(id) else { return }
        switch event {
        case 806, 807:
            if let frame = frame(for: id) {
                if !verifiedGeometry, ProcessInfo.processInfo.arguments.contains("--verify-panel-follow") {
                    verifiedGeometry = true
                    NSLog("Fluttios follow: direct WindowServer geometry received, window=%u", id)
                }
                onGeometry?(id, frame)
            }
        case 815: onVisibility?(id, true)
        case 816: onVisibility?(id, false)
        default: break
        }
    }
}
