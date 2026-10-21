import AppKit
import SimFlutDockCore
import SwiftUI

struct LogsView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                ProjectMenu(model: model)
                DeviceMenu(model: model)
                Spacer()
                Button(L10n.text("Copy")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(
                        model.selectedSession?.logs.map { $0.text }.joined(separator: "\n") ?? "", forType: .string)
                }
                Button(L10n.text("Clear")) { model.selectedSession?.clearLogs() }
            }.padding()
            Divider()
            LogConsole(entries: model.selectedSession?.logs ?? [], sessionID: model.selectedSession?.id)
            Text(L10n.text("Up to 2000 entries per session • quitting the app requires a new Run")).font(.caption)
                .foregroundStyle(.secondary).padding(8)
        }.frame(minWidth: 700, minHeight: 400)
    }
}

// AppKit owns selection and text layout, avoiding flipped selectable Text layers
// inside SwiftUI's lazy scrolling container.
struct LogConsole: NSViewRepresentable {
    let entries: [LogEntry]
    let sessionID: UUID?

    final class Coordinator {
        var entryIDs: [UUID] = []
        var sessionID: UUID?
        let timestamp: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss"
            return formatter
        }()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        let text = NSTextView(frame: scroll.contentView.bounds)
        text.isEditable = false
        text.isSelectable = true
        text.isRichText = false
        text.drawsBackground = false
        text.textContainerInset = NSSize(width: 16, height: 16)
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]
        text.textContainer?.widthTracksTextView = true
        text.textContainer?.containerSize = NSSize(width: scroll.contentSize.width, height: .greatestFiniteMagnitude)
        scroll.documentView = text
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let text = scroll.documentView as? NSTextView else { return }
        let coordinator = context.coordinator
        let ids = entries.map(\.id)
        let changedSession = coordinator.sessionID != sessionID
        guard changedSession || coordinator.entryIDs != ids else { return }
        let visible = scroll.contentView.bounds
        let followEnd = changedSession || coordinator.entryIDs.isEmpty || visible.maxY >= text.bounds.maxY - 24
        let selection = text.selectedRange()
        let output = NSMutableAttributedString(string: "")
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let paragraph = NSMutableParagraphStyle()
        paragraph.paragraphSpacing = 4
        for entry in entries {
            output.append(
                NSAttributedString(
                    string: coordinator.timestamp.string(from: entry.date) + "  ",
                    attributes: [
                        .font: font, .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: paragraph,
                    ]))
            output.append(
                NSAttributedString(
                    string: entry.text + "\n",
                    attributes: [
                        .font: font, .foregroundColor: entry.isError ? NSColor.systemRed : NSColor.labelColor,
                        .paragraphStyle: paragraph,
                    ]))
        }
        text.textStorage?.setAttributedString(output)
        coordinator.entryIDs = ids
        coordinator.sessionID = sessionID
        if followEnd {
            text.scrollRangeToVisible(NSRange(location: output.length, length: 0))
        } else {
            // Preserve a selection while new lines arrive during inspection.
            if selection.location <= output.length {
                text.setSelectedRange(
                    NSRange(
                        location: selection.location, length: min(selection.length, output.length - selection.location))
                )
            }
            scroll.contentView.scroll(to: visible.origin)
            scroll.reflectScrolledClipView(scroll.contentView)
        }
    }
}
