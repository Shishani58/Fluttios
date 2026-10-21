import AppKit
import SimFlutDockCore
import SwiftUI

enum PickerMetrics {
    static let width: CGFloat = 360
}

extension LaunchMode {
    var symbol: String {
        switch self {
        case .debug: return "ladybug"
        case .profile: return "gauge.with.dots.needle.50percent"
        case .release: return "shippingbox"
        }
    }
}

extension SimulatorDevice {
    var symbol: String {
        switch targetPlatform {
        case "ios": return name.localizedCaseInsensitiveContains("ipad") ? "ipad" : "iphone"
        case "android": return "smartphone"
        case "darwin", "windows", "linux": return "desktopcomputer"
        case let platform where platform.hasPrefix("web"): return "globe"
        default: return "display"
        }
    }
}

enum PanelMetrics {
    static let controlSize: CGFloat = 36
    static let controlHeight: CGFloat = 34
    static let rowHeight: CGFloat = 48
    static let groupSpacing: CGFloat = 8
    static let inset: CGFloat = 7
    static let logsColor = Color(red: 0.88, green: 0.52, blue: 0.49)
    static let iconSize: CGFloat = 14
}

private struct PanelControlWidthKey: EnvironmentKey {
    static let defaultValue = PanelMetrics.controlSize
}

extension EnvironmentValues {
    var panelControlWidth: CGFloat {
        get { self[PanelControlWidthKey.self] }
        set { self[PanelControlWidthKey.self] = newValue }
    }
}

struct PanelIcon: View {
    let symbol: String
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: PanelMetrics.iconSize, weight: .medium))
            .imageScale(.medium)
            .frame(width: 18, height: 18)
            .accessibilityHidden(true)
    }
}

struct PanelControlSurface: ViewModifier {
    var active = true
    var pressed = false
    var bordered = false
    @Environment(\.isEnabled) private var enabled
    @State private var hovered = false

    func body(content: Content) -> some View {
        content
            .background {
                if active {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.primary.opacity(enabled && (hovered || pressed) ? 0.10 : (bordered ? 0.055 : 0)))
                        .overlay {
                            if bordered {
                                RoundedRectangle(cornerRadius: 7)
                                    .strokeBorder(Color.primary.opacity(0.11), lineWidth: 0.5)
                            }
                        }
                }
            }
            .contentShape(Rectangle())
            .onHover { hovered = $0 }
    }
}

struct PanelButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PanelButtonContent(configuration: configuration)
    }
    private struct PanelButtonContent: View {
        let configuration: ButtonStyle.Configuration
        @Environment(\.isEnabled) private var enabled
        @Environment(\.panelControlWidth) private var controlWidth
        var body: some View {
            configuration.label
                .font(.system(size: PanelMetrics.iconSize, weight: .medium))
                .frame(width: controlWidth, height: PanelMetrics.controlHeight)
                .modifier(PanelControlSurface(pressed: configuration.isPressed, bordered: true))
                .opacity(enabled ? 1 : 0.35)
        }
    }
}
