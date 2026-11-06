import SwiftUI

/// Edits a sent message's text.
struct EditMessageView: View {
    @Binding var text: String
    let save: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit Message").font(.headline)
            TextField("Message", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(3...12)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
                .onSubmit(save)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: cancel).keyboardShortcut(.cancelAction)
                Button("Save", action: save).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 480)
    }
}
