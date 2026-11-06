import SwiftUI
import WebKit

struct SignInView: View {
    let controller: SignInController
    let cancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            WebViewHost(webView: controller.webView)
            Divider()
            HStack {
                status
                Spacer()
                Button("Cancel", role: .cancel, action: cancel)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(12)
        }
        .frame(minWidth: 520, idealWidth: 640, minHeight: 600, idealHeight: 720)
    }

    @ViewBuilder private var status: some View {
        switch controller.phase {
        case .browsing:
            Text("Sign in to your workspace. Lax keeps only the session token, in your Keychain.")
                .foregroundStyle(.secondary)
        case .verifying:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Checking the session with Slack…")
            }
        case .failed(let message):
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                Text(message).lineLimit(2)
                Button("Try Again") { controller.retry() }
            }
        }
    }
}

private struct WebViewHost: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
