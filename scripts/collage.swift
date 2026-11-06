// Lays screenshots out in three columns: collage.swift <output> <names…>, run from the folder
// layout docs/screenshots/<name>.png.
import AppKit

let arguments = Array(CommandLine.arguments.dropFirst())
let output = URL(fileURLWithPath: arguments[0])
let folder = output.deletingLastPathComponent()
let images = arguments.dropFirst().compactMap { NSImage(contentsOf: folder.appending(path: "\($0).png")) }

let columns = 3, cellWidth = 960.0, gap = 40.0
// One scale for all, so a small window (Settings) stays small beside the main window.
let scale = cellWidth / Double(images.map { $0.size.width }.max() ?? cellWidth)
let cells = images.map { image in NSSize(width: image.size.width * scale, height: image.size.height * scale) }
let rows = stride(from: 0, to: cells.count, by: columns).map { Array(cells[$0 ..< min($0 + columns, cells.count)]) }
let rowHeights = rows.map { $0.map(\.height).max() ?? 0 }
let size = NSSize(width: Double(columns) * cellWidth + Double(columns - 1) * gap,
                  height: rowHeights.reduce(0, +) + Double(rows.count - 1) * gap)

let collage = NSImage(size: size, flipped: true) { _ in
    var y = 0.0
    for (row, height) in rowHeights.enumerated() {
        for column in 0 ..< columns {
            let index = row * columns + column
            guard index < images.count else { break }
            // Centred in its cell.
            let x = Double(column) * (cellWidth + gap) + (cellWidth - cells[index].width) / 2
            let top = y + (height - cells[index].height) / 2
            images[index].draw(in: NSRect(x: x, y: top, width: cells[index].width, height: cells[index].height))
        }
        y += height + gap
    }
    return true
}
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                              colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
collage.draw(in: NSRect(origin: .zero, size: size))
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: output)
