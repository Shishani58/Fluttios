import AppKit

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
let panel = ControlPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
panel.isReleasedWhenClosed = false
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
check(!ControlPanel.settingsOwnFocus(settings, keyWindow: sheet), "Hidden settings descendants must not suppress the panel")
panel.showIfNeeded()
check(panel.isVisible, "Hidden panel must reopen")
let number = panel.windowNumber
for _ in 0..<20 { panel.showIfNeeded() }
check(panel.isVisible && panel.windowNumber == number && popover.parent === panel, "Refresh must preserve the panel and its popover")
panel.orderOut(nil)
panel.showIfNeeded()
check(panel.isVisible, "Panel must reopen after explicit hiding")
print("Panel presentation: \(checks) checks passed")
