import AppKit
import SwiftUI

/// A standard segmented control of symbols that fills its width with equal segments.
/// SwiftUI's segmented picker keeps its natural width on the Mac.
struct SegmentedSwitcher: NSViewRepresentable {
    struct Segment {
        let title: String
        let systemImage: String
    }

    let segments: [Segment]
    @Binding var selection: Int

    func makeNSView(context: Context) -> NSSegmentedControl {
        let images = segments.map {
            NSImage(systemSymbolName: $0.systemImage, accessibilityDescription: $0.title) ?? NSImage()
        }
        let control = NSSegmentedControl(
            images: images, trackingMode: .selectOne,
            target: context.coordinator, action: #selector(Coordinator.changed(_:)))
        control.segmentDistribution = .fillEqually
        for (index, segment) in segments.enumerated() {
            control.setToolTip(segment.title, forSegment: index)
        }
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.selection = $selection
        if control.selectedSegment != selection { control.selectedSegment = selection }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView control: NSSegmentedControl, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? control.intrinsicContentSize.width, height: control.intrinsicContentSize.height)
    }

    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }

    @MainActor
    final class Coordinator: NSObject {
        var selection: Binding<Int>

        init(selection: Binding<Int>) {
            self.selection = selection
        }

        @objc func changed(_ control: NSSegmentedControl) {
            selection.wrappedValue = control.selectedSegment
        }
    }
}
