import Foundation

/// Keeps attachment tied to windows that actually appeared, independently of a project's saved device.
public struct AutomaticPanelBinding {
    public private(set) var windowID: UUID?
    private var knownIDs: Set<UUID> = []
    public init() {}

    /// Returns true when a newly discovered window should reopen the panel.
    @discardableResult public mutating func update(windowIDs: [UUID], focusedID: UUID?) -> Bool {
        let current = Set(windowIDs)
        let newIDs = current.subtracting(knownIDs)
        knownIDs = current
        let previous = windowID
        let focused = focusedID.flatMap { current.contains($0) ? $0 : nil }
        if let focused, newIDs.contains(focused) { windowID = focused }
        else if newIDs.count == 1 { windowID = newIDs.first }
        else if let focused { windowID = focused }
        else if let previous, current.contains(previous) { windowID = previous }
        else { windowID = current.count == 1 ? current.first : nil }
        guard let windowID else { return false }
        return newIDs.contains(windowID) || previous == nil
    }
}
