import AppKit
import LaxKit
import WebKit

/// Drives Slack's own web sign-in in an embedded web view (so SSO and 2FA work
/// as they do in a browser), then lifts the session out of it.
@MainActor @Observable
final class SignInController: NSObject, Identifiable, WKNavigationDelegate, WKUIDelegate {
    enum Phase: Equatable {
        case browsing
        case verifying
        case failed(String)
    }

    private(set) var phase: Phase = .browsing
    let webView: WKWebView

    @ObservationIgnored private let onSignedIn: ([SlackAccount]) -> Void
    @ObservationIgnored private var urlObservation: NSKeyValueObservation?
    @ObservationIgnored private var extraction: Task<Void, Never>?

    init(onSignedIn: @escaping ([SlackAccount]) -> Void) {
        let configuration = WKWebViewConfiguration()
        // Nothing from this session is kept on disk; Lax keeps only the Keychain copy.
        configuration.websiteDataStore = .nonPersistent()
        // Without a Safari-like user agent Slack may call the browser unsupported.
        configuration.applicationNameForUserAgent = "Version/26.0 Safari/605.1.15"
        webView = WKWebView(frame: .zero, configuration: configuration)
        self.onSignedIn = onSignedIn
        super.init()

        webView.navigationDelegate = self
        webView.uiDelegate = self
        // The web client switches pages without full loads, so watch the URL itself.
        urlObservation = webView.observe(\.url) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.extractIfSignedIn() }
        }
        webView.load(URLRequest(url: URL(string: "https://slack.com/signin")!))
    }

    func retry() {
        phase = .browsing
        extraction = nil
        extractIfSignedIn()
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        // Slack offers to open its desktop app via slack:// links; stay in the web view.
        guard let scheme = action.request.url?.scheme else { return .allow }
        return scheme == "https" || scheme == "http" || scheme == "about" ? .allow : .cancel
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        // Slack opens some steps, such as 2FA, in a new tab. Web views drop those
        // unless handled, so load them here instead.
        webView.load(action.request)
        return nil
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo) async {
        let alert = NSAlert()
        alert.messageText = message
        alert.runModal()
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo) async -> Bool {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func extractIfSignedIn() {
        guard extraction == nil, SlackWebSession.isSignedInClientURL(webView.url) else { return }
        extraction = Task { await extract() }
    }

    private func extract() async {
        phase = .verifying
        // The web client writes its config shortly after the page appears.
        for _ in 0..<15 {
            let found = await currentCredentials()
            if !found.isEmpty {
                await verify(found)
                return
            }
            try? await Task.sleep(for: .seconds(1))
        }
        phase = .failed("Signed in, but Lax couldn't find the Slack session.")
    }

    private func currentCredentials() async -> [SlackCredentials] {
        guard let config = try? await webView.evaluateJavaScript(SlackWebSession.localConfigScript) as? String
        else { return [] }
        let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
        return SlackWebSession.credentials(localConfig: config, cookies: cookies)
            .filter { !$0.cookies.isEmpty }
    }

    private func verify(_ found: [SlackCredentials]) async {
        var accounts: [SlackAccount] = []
        var lastError: Error?
        for credentials in found {
            do {
                accounts.append(try await SlackAccount.verify(credentials))
            } catch {
                lastError = error
            }
        }
        if accounts.isEmpty {
            phase = .failed("Slack rejected the session: \(lastError.map(String.init(describing:)) ?? "unknown error")")
        } else {
            onSignedIn(accounts)
        }
    }
}
