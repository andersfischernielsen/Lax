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
        Group {
            if image.isAnimated {
                AnimatedImage(image: image)
            } else {
                Image(nsImage: image).resizable()
            }
        }
        .aspectRatio(image.size.width / max(image.size.height, 1), contentMode: .fit)
        .frame(height: height)
    }
}
