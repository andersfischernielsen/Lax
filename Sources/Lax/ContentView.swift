import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationSplitView {
            List {}
                .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        } detail: {
            ContentUnavailableView(
                "No Slack Workspace",
                systemImage: "bubble.left.and.bubble.right",
                description: Text("Sign-in comes next.")
            )
        }
    }
}
