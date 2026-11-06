import AppKit
import SwiftUI

/// A plain text field for command panels: hands ↑, ↓, Return and Esc to its owner and takes
/// focus as soon as it's on screen. SwiftUI's `TextField` can't do either on the Mac: its
/// field editor consumes the arrow keys, and focus set on appear can land before the field
/// is in a window.
struct CommandField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    let move: (Int) -> Void
    let submit: () -> Void
    let cancel: () -> Void

    func makeNSView(context: Context) -> FocusingTextField {
        let field = FocusingTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .preferredFont(forTextStyle: .title3)
        field.placeholderString = placeholder
        field.setAccessibilityIdentifier("quick-switcher-field")
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ field: FocusingTextField, context: Context) {
        context.coordinator.owner = self
        if field.stringValue != text { field.stringValue = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(owner: self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var owner: CommandField

        init(owner: CommandField) {
            self.owner = owner
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            owner.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.moveUp(_:)): owner.move(-1)
            case #selector(NSResponder.moveDown(_:)): owner.move(1)
            case #selector(NSResponder.insertNewline(_:)): owner.submit()
            case #selector(NSResponder.cancelOperation(_:)): owner.cancel()
            default: return false
            }
            return true
        }
    }

    final class FocusingTextField: NSTextField {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // After the current layout pass, once the window can make it first responder.
            Task { @MainActor [weak self] in self?.window?.makeFirstResponder(self) }
        }
    }
}
