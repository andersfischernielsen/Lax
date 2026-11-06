import AppKit
import LaxKit
import QuickLookThumbnailing
import SwiftUI

/// Files waiting in the composer, each with a thumbnail and a button to take it out.
struct UploadStrip: View {
    @Binding var uploads: [Upload]
    let isUploading: Bool

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(uploads) { upload in
                    UploadChip(upload: upload, isUploading: isUploading) {
                        uploads.removeAll { $0 == upload }
                    }
                }
            }
        }
        .scrollIndicators(.never)
    }
}

private struct UploadChip: View {
    let upload: Upload
    let isUploading: Bool
    let remove: () -> Void
    @State private var thumbnail: NSImage?
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: thumbnail ?? NSWorkspace.shared.icon(forFile: upload.url.path))
                .resizable()
                .scaledToFill()
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            VStack(alignment: .leading) {
                Text(upload.name).lineLimit(1).truncationMode(.middle)
                Text(Int64(upload.byteCount).formatted(.byteCount(style: .file)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 160, alignment: .leading)
            if isUploading {
                ProgressView().controlSize(.small)
            } else {
                Button("Remove", systemImage: "xmark.circle.fill", action: remove)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Remove \(upload.name)")
            }
        }
        .padding(6)
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 8))
        .task(id: upload) {
            let request = QLThumbnailGenerator.Request(
                fileAt: upload.url, size: CGSize(width: 32, height: 32), scale: displayScale,
                representationTypes: .thumbnail)
            thumbnail = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).nsImage
        }
    }
}

/// Files to upload from the pasteboard or a drop.
enum PastedFiles {
    /// Copied files, or a copied picture on its own, such as a screenshot. Text copied
    /// along with a picture of itself, as from Word, isn't one: it pastes as text.
    static func uploads(on pasteboard: NSPasteboard) -> [Upload] {
        let urls =
            pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        if !urls.isEmpty { return urls.compactMap(Upload.init(fileAt:)) }
        guard pasteboard.string(forType: .string) == nil, let image = NSImage(pasteboard: pasteboard),
            let png = pngData(image)
        else { return [] }
        return saved(png: png).map { [$0] } ?? []
    }

    /// Dropped files, or dropped pictures, such as one dragged out of a browser.
    @MainActor
    static func uploads(from providers: [NSItemProvider]) async -> [Upload] {
        var uploads: [Upload] = []
        for provider in providers {
            if let upload = await upload(from: provider) { uploads.append(upload) }
        }
        return uploads
    }

    @MainActor
    private static func upload(from provider: NSItemProvider) async -> Upload? {
        if provider.canLoadObject(ofClass: URL.self) {
            let url = await withCheckedContinuation { continuation in
                _ = provider.loadObject(ofClass: URL.self) { url, _ in continuation.resume(returning: url) }
            }
            if let upload = url.flatMap(Upload.init(fileAt:)) { return upload }
        }
        guard provider.canLoadObject(ofClass: NSImage.self) else { return nil }
        let png = await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: NSImage.self) { image, _ in
                continuation.resume(returning: (image as? NSImage).flatMap(pngData))
            }
        }
        return png.flatMap(saved(png:))
    }

    private static func pngData(_ image: NSImage) -> Data? {
        image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:))?.representation(using: .png, properties: [:])
    }

    /// A picture saved where it can be uploaded from, named as Slack names pasted images.
    private static func saved(png: Data) -> Upload? {
        let file = FileManager.default.temporaryDirectory
            .appending(path: "Pasted/\(UUID().uuidString)/image.png")
        do {
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: file)
        } catch {
            return nil
        }
        return Upload(fileAt: file)
    }
}

/// ⌘V while `isActive`: files or a picture on the pasteboard are attached, where the text
/// field would paste only their names. Anything else pastes as usual.
struct FilePaste: NSViewRepresentable {
    let isActive: Bool
    let attach: ([Upload]) -> Void

    func makeNSView(context: Context) -> MonitorView {
        let view = MonitorView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: MonitorView, context: Context) {
        view.isActive = isActive
        view.attach = attach
    }

    final class MonitorView: NSView {
        var isActive = false
        var attach: ([Upload]) -> Void = { _ in }
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.isActive, event.window === self.window,
                    event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                    event.charactersIgnoringModifiers == "v"
                else { return event }
                let uploads = PastedFiles.uploads(on: .general)
                guard !uploads.isEmpty else { return event }
                self.attach(uploads)
                return nil
            }
        }
    }
}

extension View {
    /// Files and pictures dropped anywhere on the view are attached, with a highlight
    /// while they're dragged over it.
    func attachingDroppedFiles(_ attach: @escaping ([Upload]) -> Void) -> some View {
        modifier(FileDrop(attach: attach))
    }
}

private struct FileDrop: ViewModifier {
    let attach: ([Upload]) -> Void
    @State private var isTargeted = false

    func body(content: Content) -> some View {
        content
            .overlay {
                if isTargeted {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(.tint, lineWidth: 3)
                        .padding(4)
                        .allowsHitTesting(false)
                }
            }
            .onDrop(of: [.fileURL, .image], isTargeted: $isTargeted) { providers in
                Task { attach(await PastedFiles.uploads(from: providers)) }
                return true
            }
    }
}
