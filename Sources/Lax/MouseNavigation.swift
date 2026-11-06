import AppKit
import SwiftUI

/// The mouse's back and forward buttons (buttons 4 and 5), for the window this is in.
struct MouseNavigation: NSViewRepresentable {
    let back: () -> Void
    let forward: () -> Void

    func makeNSView(context: Context) -> MonitorView {
        let view = MonitorView()
        view.back = back
        view.forward = forward
        return view
    }

    func updateNSView(_ view: MonitorView, context: Context) {
        view.back = back
        view.forward = forward
    }

    final class MonitorView: NSView {
        var back: () -> Void = {}
        var forward: () -> Void = {}
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .otherMouseUp) { [weak self] event in
                guard let self, event.window === self.window else { return event }
                switch event.buttonNumber {
                case 3: self.back()
                case 4: self.forward()
                default: return event
                }
                return nil
            }
        }
    }
}
