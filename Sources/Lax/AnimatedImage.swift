import AppKit
import SwiftUI

/// An image that plays if it's animated (a GIF); SwiftUI's `Image` shows only the first frame.
struct AnimatedImage: NSViewRepresentable {
    let image: NSImage

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.animates = true
        view.imageScaling = .scaleProportionallyUpOrDown
        // Sized by SwiftUI, not by the image.
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return view
    }

    func updateNSView(_ view: NSImageView, context: Context) {
        if view.image !== image { view.image = image }
    }

    /// Whatever SwiftUI offers: callers give an exact frame. Left to itself an image view
    /// reports the image's own size, or nothing, and the emoji vanishes or overflows.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSImageView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? image.size.width, height: proposal.height ?? image.size.height)
    }
}

extension NSImage {
    /// More than one frame, as in an animated GIF.
    var isAnimated: Bool {
        representations.contains { (($0 as? NSBitmapImageRep)?.value(forProperty: .frameCount) as? Int ?? 1) > 1 }
    }
}

/// An emoji image at `height`, playing if animated.
struct EmojiImage: View {
    let image: NSImage
    let height: CGFloat

    var body: some View {
        // An exact size, keeping the image's proportions.
        let width = height * image.size.width / max(image.size.height, 1)
        Group {
            if image.isAnimated {
                AnimatedImage(image: image)
            } else {
                Image(nsImage: image).resizable()
            }
        }
        .frame(width: width, height: height)
    }
}
