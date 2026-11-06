import LaxKit
import SwiftUI

struct ContentView: View {
    @Bindable var model: AppModel

    var body: some View {
        NavigationSplitView {
            SidebarView(model: model)
                .navigationSplitViewColumnWidth(min: 200, ideal: 250)
        } detail: {
            if let workspace = model.currentWorkspace {
                if let conversation = workspace.selectedConversation {
                    ConversationView(workspace: workspace, conversation: conversation)
                        .id(conversation.id)
                } else {
                    ContentUnavailableView("No Conversation Selected", systemImage: "bubble.left.and.bubble.right",
                                           description: Text("Pick a channel or direct message."))
                }
            } else {
                ContentUnavailableView {
                    Label("No Slack Workspace", systemImage: "bubble.left.and.bubble.right")
                } description: {
                    Text("Sign in with your usual Slack login, SSO included.")
                } actions: {
                    Button("Add Workspace…") { model.beginSignIn() }
                }
            }
        }
        .sheet(item: $model.signIn) { controller in
            SignInView(controller: controller, cancel: model.cancelSignIn)
        }
        .alert("Something went wrong", isPresented: errorBinding) {
            Button("OK") { clearErrors() }
        } message: {
            Text(model.errorMessage ?? model.currentWorkspace?.errorMessage ?? "")
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { model.errorMessage != nil || model.currentWorkspace?.errorMessage != nil },
                set: { if !$0 { clearErrors() } })
    }

    private func clearErrors() {
        model.errorMessage = nil
        model.currentWorkspace?.errorMessage = nil
    }
}
