import SwiftUI

/// Edits the user's Slack display name.
struct DisplayNameView: View {
    @Binding var name: String
    let save: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Display Name").font(.headline)
            Text("Shown instead of your full name. Leave empty to use your full name.")
                .font(.callout)
                .foregroundStyle(.secondary)
            TextField("Display name", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: cancel).keyboardShortcut(.cancelAction)
                Button("Save", action: save).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}
