import AppKit
import LaxKit
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

/// An animated emoji's frames, decoded once, for drawing inside text.
struct EmojiAnimation {
    let frames: [CGImage]
    let durations: [Double]

    /// Nil unless `image` has more than one frame.
    init?(_ image: NSImage) {
        // A copy: stepping through frames changes the image, which may be playing elsewhere.
        guard let original = image.representations.lazy.compactMap({ $0 as? NSBitmapImageRep }).first,
            let rep = original.copy() as? NSBitmapImageRep,
            let count = rep.value(forProperty: .frameCount) as? Int, count > 1
        else { return nil }
        var frames: [CGImage] = []
        var durations: [Double] = []
        for index in 0..<count {
            rep.setProperty(.currentFrame, withValue: index)
            guard let frame = rep.cgImage else { continue }
            frames.append(frame)
            durations.append(rep.value(forProperty: .currentFrameDuration) as? Double ?? 0.1)
        }
        guard frames.count > 1 else { return nil }
        self.frames = frames
        self.durations = durations
    }

    func frame(at time: Double) -> CGImage {
        frames[FrameTiming.frame(at: time, durations: durations)]
    }
}

/// Marks a custom emoji inside `Text`, so `AnimatedEmojiRenderer` can find it.
struct EmojiTag: TextAttribute {
    let name: String
}

/// Draws text as usual, except that animated emoji show their frame for `time`.
struct AnimatedEmojiRenderer: TextRenderer {
    let time: Double
    let animation: (String) -> EmojiAnimation?

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for line in layout {
            for run in line {
                if let tag = run[EmojiTag.self], let animation = animation(tag.name) {
                    context.draw(Image(decorative: animation.frame(at: time), scale: 1), in: run.typographicBounds.rect)
                } else {
                    context.draw(run)
                }
            }
        }
    }
}
