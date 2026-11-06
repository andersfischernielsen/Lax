import AppKit
import LaxKit
import SwiftUI

/// A searchable grid of standard and custom emoji.
struct EmojiPickerView: View {
    let customEmoji: [String: SlackEmoji]
    let emojiImage: (String) -> NSImage?
    let requestImages: (Set<String>) -> Void
    let pick: (String) -> Void
    let cancel: () -> Void
    @State private var query = ""

    var body: some View {
        let names = Emoji.pickerNames(matching: query, custom: customEmoji)
        VStack(spacing: 0) {
            TextField("Search emoji", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(12)
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(36)), count: 10), spacing: 4) {
                    ForEach(names, id: \.self) { name in
                        Button { pick(name) } label: { cell(name) }
                            .buttonStyle(.plain)
                            .help(":\(name):")
                            .accessibilityLabel(name.replacing("_", with: " "))
                            .onAppear { if Emoji.character(for: name) == nil { requestImages([name]) } }
                    }
                }
                .padding(.horizontal, 12)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: cancel).keyboardShortcut(.cancelAction)
            }
            .padding(12)
        }
        .frame(width: 440, height: 420)
    }

    @ViewBuilder private func cell(_ name: String) -> some View {
        Group {
            if let character = Emoji.character(for: name) {
                Text(character).font(.title2)
            } else if let image = emojiImage(name) {
                Image(nsImage: image).resizable().scaledToFit().frame(height: 24)
            } else {
                RoundedRectangle(cornerRadius: 4).fill(.quaternary).frame(width: 24, height: 24)
            }
        }
        .frame(width: 36, height: 36)
        .contentShape(Rectangle())
    }
}
