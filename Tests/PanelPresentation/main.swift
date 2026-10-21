import AppKit
import Combine

// Standalone AppKit regression harness: no project data or Simulator actions.
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let frame = NSRect(x: -10000, y: -10000, width: 50, height: 374)
func window() -> NSWindow {
    let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    return window
}
let settings = window()
let panel = ControlPanel(
    contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
panel.isReleasedWhenClosed = false
panel.isFloatingPanel = false
panel.hidesOnDeactivate = false
panel.observeMenus()
let popover = window()
let sheet = window()
defer {
    panel.removeChildWindow(popover)
    settings.removeChildWindow(sheet)
    for window in [settings, panel, popover, sheet] { window.orderOut(nil) }
}
var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
    checks += 1
}
settings.orderFront(nil)
check(ControlPanel.settingsOwnFocus(settings, keyWindow: settings), "Focused settings must hide the panel")
check(!ControlPanel.settingsOwnFocus(settings, keyWindow: panel), "Panel focus must not hide the panel")
check(!ControlPanel.settingsOwnFocus(settings, keyWindow: nil), "Focus handoff must not hide the panel")
panel.addChildWindow(popover, ordered: .above)
check(!ControlPanel.settingsOwnFocus(settings, keyWindow: popover), "Panel popover must not be mistaken for settings")
settings.addChildWindow(sheet, ordered: .above)
check(ControlPanel.settingsOwnFocus(settings, keyWindow: sheet), "Settings child dialogs must hide the panel")
settings.orderOut(nil)
check(!ControlPanel.settingsOwnFocus(settings, keyWindow: settings), "Closed settings must not suppress the panel")
check(
    !ControlPanel.settingsOwnFocus(settings, keyWindow: sheet),
    "Hidden settings descendants must not suppress the panel")
panel.showIfNeeded()
check(panel.isVisible, "Hidden panel must reopen")
let number = panel.windowNumber
for _ in 0..<20 { panel.showIfNeeded() }
check(
    panel.isVisible && panel.windowNumber == number && popover.parent === panel,
    "Refresh must preserve the panel and its popover")
panel.orderOut(nil)
panel.showIfNeeded()
check(panel.isVisible, "Panel must reopen after explicit hiding")

// Explicit presentation must not leave the panel at a floating window level.
panel.bringToFront()
check(panel.level == .normal && !panel.isFloatingPanel, "Tray presentation must use ordinary window ordering")
for _ in 0..<20 { panel.showIfNeeded() }
check(panel.level == .normal, "Background refresh must preserve the ordinary window level")
panel.orderOut(nil)
panel.bringToFront()
check(panel.isVisible && panel.level == .normal, "Explicit presentation must reopen the panel without pinning it")

final class TrackedMenu: NSMenu {
    var cancellations = 0
    override func cancelTrackingWithoutAnimation() {
        cancellations += 1
        super.cancelTrackingWithoutAnimation()
    }
}
let menu = TrackedMenu(title: "Panel position")
let submenu = TrackedMenu(title: "Attach to Simulator")
let center = NotificationCenter.default
center.post(name: NSMenu.didBeginTrackingNotification, object: menu)
center.post(name: NSMenu.didBeginTrackingNotification, object: submenu)
panel.orderOut(nil)
check(menu.cancellations == 1 && submenu.cancellations == 1, "Hiding the panel must dismiss every tracked submenu")
panel.showIfNeeded()
center.post(name: NSMenu.didBeginTrackingNotification, object: menu)
center.post(name: NSMenu.didEndTrackingNotification, object: menu)
panel.orderOut(nil)
check(menu.cancellations == 1, "Already closed menus must be released from tracking")
panel.showIfNeeded()
center.post(name: NSMenu.didBeginTrackingNotification, object: menu)
if let otherApp = NSWorkspace.shared.runningApplications.first(where: {
    $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
}) {
    NSWorkspace.shared.notificationCenter.post(
        name: NSWorkspace.didActivateApplicationNotification, object: NSWorkspace.shared,
        userInfo: [NSWorkspace.applicationUserInfoKey: otherApp])
    check(menu.cancellations == 2, "Switching to another application must dismiss panel menus")
}
print("Panel presentation: \(checks) checks passed")
