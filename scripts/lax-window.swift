// Prints the window number of Lax's largest window on screen, or with "smallest", its smallest
// (Settings, whose window has no title in the window list).
import CoreGraphics

let smallest = CommandLine.arguments.dropFirst().first == "smallest"
let windows = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? [])
    .filter { $0[kCGWindowOwnerName as String] as? String == "Lax" && $0[kCGWindowLayer as String] as? Int == 0 }
let area = { (window: [String: Any]) -> Double in
    let bounds = window[kCGWindowBounds as String] as? [String: Double] ?? [:]
    return (bounds["Width"] ?? 0) * (bounds["Height"] ?? 0)
}
if let window = smallest ? windows.min(by: { area($0) < area($1) }) : windows.max(by: { area($0) < area($1) }),
   let number = window[kCGWindowNumber as String] as? Int {
    print(number)
}
