import LaxKit
import SwiftUI

struct ContentView: View {
    let model: AppModel
    @State private var window = WindowModel()
    // Restored per window when Lax relaunches.
    @SceneStorage("account") private var storedAccount: String?
    @SceneStorage("conversation") private var storedConversation: String?

    var body: some View {
        @Bindable var window = window
        let workspace = model.workspace(window.accountID)
        NavigationSplitView {
            SidebarView(model: model, workspace: workspace)
                .navigationSplitViewColumnWidth(min: 200, ideal: 250)
        } detail: {
            if let workspace {
                if let results = window.searchResults {
                    SearchResultsView(workspace: workspace, results: results)
                } else if let conversation = workspace.conversation(window.conversationID) {
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
                    Button("Add Workspace…") { window.beginSignIn(with: model) }
                }
            }
        }
        // On the split view, not the detail, so the inspector gets the full window height.
        .inspector(isPresented: $window.showsInspector) {
            Group {
                if let workspace, let thread = window.thread {
                    ThreadView(workspace: workspace, thread: thread).id(thread)
                } else {
                    ContentUnavailableView("No Thread", systemImage: "bubble.left.and.text.bubble.right",
                                           description: Text("Choose Reply in Thread on a message to see its replies here."))
                }
            }
            .inspectorColumnWidth(min: 300, ideal: 380, max: 560)
            .toolbar {
                Spacer()
                Button("Thread", systemImage: "sidebar.trailing") { window.showsInspector.toggle() }
                    .help(window.showsInspector ? "Hide the thread" : "Show the thread")
            }
        }
        .environment(window)
        .focusedSceneValue(window)
        .searchable(text: $window.searchQuery, placement: .toolbar, prompt: "Search messages")
        .onSubmit(of: .search) { search(in: workspace) }
        .onChange(of: window.searchQuery) { _, query in if query.isEmpty { window.clearSearch() } }
        .sheet(isPresented: editingDisplayName) {
            DisplayNameView(name: displayName, save: {
                if let name = window.editingDisplayName { workspace?.saveDisplayName(name) }
                window.editingDisplayName = nil
            }, cancel: { window.editingDisplayName = nil })
        }
        .sheet(item: $window.signIn) { controller in
            SignInView(controller: controller, cancel: { window.signIn = nil })
        }
        .alert(problem(workspace)?.title ?? "", isPresented: hasProblem(workspace), presenting: problem(workspace)) { _ in
            Button("OK") { clearProblems(workspace) }
        } message: { problem in
            Text(problem.reason)
        }
        .task {
            window.accountID = storedAccount
            window.conversationID = storedConversation ?? workspace?.lastConversationID
        }
        .onChange(of: window.accountID) { _, id in storedAccount = id }
        .onChange(of: window.conversationID) { _, id in storedConversation = id }
    }

    private func search(in workspace: WorkspaceModel?) {
        let query = window.searchQuery.trimmingCharacters(in: .whitespaces)
        guard let workspace, !query.isEmpty else { return window.clearSearch() }
        Task {
            if let results = await workspace.search(query) { window.searchResults = results }
        }
    }

    private var editingDisplayName: Binding<Bool> {
        Binding(get: { window.editingDisplayName != nil },
                set: { if !$0 { window.editingDisplayName = nil } })
    }

    private var displayName: Binding<String> {
        Binding(get: { window.editingDisplayName ?? "" }, set: { window.editingDisplayName = $0 })
    }

    private func problem(_ workspace: WorkspaceModel?) -> Problem? {
        model.problem ?? workspace?.problem
    }

    private func hasProblem(_ workspace: WorkspaceModel?) -> Binding<Bool> {
        Binding(get: { problem(workspace) != nil }, set: { if !$0 { clearProblems(workspace) } })
    }

    private func clearProblems(_ workspace: WorkspaceModel?) {
        model.problem = nil
        workspace?.problem = nil
    }
}
