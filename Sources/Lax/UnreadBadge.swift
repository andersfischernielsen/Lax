import SwiftUI

/// An unread count: the number in a red-outlined circle that stretches for longer numbers.
/// Shows nothing for zero.
struct UnreadBadge: View {
    let count: Int

    var body: some View {
        if count > 0 {
            Text(count, format: .number)
                .font(.caption2.weight(.semibold).monospacedDigit())
                .foregroundStyle(.primary)
                .padding(.horizontal, 5)
                .frame(minWidth: 18, minHeight: 18)
                .overlay(Capsule().strokeBorder(.red, lineWidth: 1.5))
                .accessibilityLabel(count == 1 ? "1 unread" : "\(count) unread")
        }
    }
}
