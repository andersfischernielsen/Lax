import AppKit
import SwiftUI

/// The message field: an AppKit text view, so keys and the cursor are handled the standard
/// way. SwiftUI's text field can't tell Shift-Return from Return, and its selection can't be
/// mapped back onto the draft reliably.
struct MessageField: NSViewRepresentable {
    enum Key {
        case send
        case up
        case down
        case tab
        case escape
    }

    let placeholder: String
    @Binding var text: String
    /// Where the cursor is, in characters; set it to move the cursor.
    @Binding var cursor: Int
    /// Grows with the text, up to `maxLines`.
    @Binding var height: CGFloat
    var maxLines = 8
    var identifier = "composer"
    /// Handles a key; false lets the text view do its usual thing.
    let key: (Key) -> Bool

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        let textView = scrollView.documentView as! NSTextView
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = .preferredFont(forTextStyle: .body)
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.setAccessibilityIdentifier(identifier)
        textView.setAccessibilityPlaceholderValue(placeholder)
        textView.string = text
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.owner = self
        let textView = scrollView.documentView as! NSTextView
        if textView.string != text { textView.string = text }
        // Put the cursor where the draft says, unless it's there already.
        if context.coordinator.reportedCursor != cursor {
            let offset = min(max(cursor, 0), text.count)
            let index = text.index(text.startIndex, offsetBy: offset)
            textView.setSelectedRange(NSRange(index..<index, in: text))
            context.coordinator.reportedCursor = offset
        }
        context.coordinator.reportHeight(of: textView)
    }

    func makeCoordinator() -> Coordinator { Coordinator(owner: self) }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var owner: MessageField
        var reportedCursor = -1

        init(owner: MessageField) {
            self.owner = owner
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            owner.text = textView.string
            reportHeight(of: textView)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let string = textView.string
            // The selection is in the text view's own (UTF-16) terms; convert it safely.
            guard let range = Range(textView.selectedRange(), in: string) else { return }
            let offset = string.distance(from: string.startIndex, to: range.upperBound)
            reportedCursor = offset
            if owner.cursor != offset { owner.cursor = offset }
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                // Shift-Return is a new line, as Option-Return already is.
                if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                    textView.insertNewlineIgnoringFieldEditor(nil)
                    return true
                }
                return owner.key(.send)
            case #selector(NSResponder.moveUp(_:)): return owner.key(.up)
            case #selector(NSResponder.moveDown(_:)): return owner.key(.down)
            case #selector(NSResponder.insertTab(_:)): return owner.key(.tab)
            case #selector(NSResponder.cancelOperation(_:)): return owner.key(.escape)
            default: return false
            }
        }

        func reportHeight(of textView: NSTextView) {
            guard let layout = textView.layoutManager, let container = textView.textContainer,
                  let font = textView.font else { return }
            layout.ensureLayout(for: container)
            let line = layout.defaultLineHeight(for: font)
            let used = max(layout.usedRect(for: container).height, line)
            let height = min(used, line * CGFloat(owner.maxLines)).rounded(.up)
            // After this update: changing SwiftUI state while it's applied is not allowed.
            if owner.height != height {
                Task { @MainActor in self.owner.height = height }
            }
        }
    }
}
