import Foundation

public enum RealTimeUpdate: Sendable {
    public enum Status: Equatable, Sendable {
        case connecting
        case connected
        case waiting(retryIn: Duration)
        /// Slack rejected the session; signing in again is the only fix.
        case signedOut
    }

    case status(Status)
    case event(RealTimeEvent)
}

/// Keeps a real-time WebSocket to Slack open for as long as `updates()` is iterated,
/// reconnecting with back-off when it drops.
public struct RealTimeConnection: Sendable {
    public let client: SlackAPIClient
    private let session: URLSession
    private let pingInterval: Duration

    public init(client: SlackAPIClient, session: URLSession = .shared, pingInterval: Duration = .seconds(30)) {
        self.client = client
        self.session = session
        self.pingInterval = pingInterval
    }

    public func updates() -> AsyncStream<RealTimeUpdate> {
        AsyncStream { continuation in
            let task = Task { await run(continuation) }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// 1, 2, 4 … seconds, capped at a minute.
    static func backoff(attempt: Int) -> Duration {
        .seconds(min(1 << min(attempt, 6), 60))
    }

    static let signedOutErrors: Set<String> = ["invalid_auth", "not_authed", "account_inactive", "token_revoked"]

    private func run(_ continuation: AsyncStream<RealTimeUpdate>.Continuation) async {
        var attempt = 0
        while !Task.isCancelled {
            continuation.yield(.status(.connecting))
            do {
                let socket = try await open()
                try await withTaskCancellationHandler {
                    try await expectHello(socket)
                    attempt = 0
                    continuation.yield(.status(.connected))
                    try await serve(socket, continuation)
                } onCancel: {
                    socket.cancel(with: .goingAway, reason: nil)
                }
            } catch SlackAPIError.slack(let error) where Self.signedOutErrors.contains(error) {
                continuation.yield(.status(.signedOut))
                break
            } catch {
                // Dropped or failed to connect: retry below.
            }
            guard !Task.isCancelled else { break }
            let delay = Self.backoff(attempt: attempt)
            attempt += 1
            continuation.yield(.status(.waiting(retryIn: delay)))
            try? await Task.sleep(for: delay)
        }
        continuation.finish()
    }

    private func open() async throws -> URLSessionWebSocketTask {
        var request = URLRequest(url: try await client.realTimeURL())
        if let cookie = client.credentials.cookieHeader {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
        }
        let socket = session.webSocketTask(with: request)
        socket.resume()
        return socket
    }

    private func expectHello(_ socket: URLSessionWebSocketTask) async throws {
        guard Self.event(from: try await socket.receive()) == .hello else {
            throw URLError(.badServerResponse)
        }
    }

    /// Returns when Slack says goodbye; throws when the socket fails.
    private func serve(_ socket: URLSessionWebSocketTask,
                       _ continuation: AsyncStream<RealTimeUpdate>.Continuation) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                while true {
                    guard let event = Self.event(from: try await socket.receive()) else { continue }
                    if event == .goodbye { return }
                    continuation.yield(.event(event))
                }
            }
            group.addTask { [pingInterval] in
                var id = 0
                while true {
                    try await Task.sleep(for: pingInterval)
                    id += 1
                    try await socket.send(.string(#"{"type":"ping","id":\#(id)}"#))
                }
            }
            try await group.next()
            group.cancelAll()
        }
    }

    private static func event(from message: URLSessionWebSocketTask.Message) -> RealTimeEvent? {
        switch message {
        case .string(let text): RealTimeEvent.parse(Data(text.utf8))
        case .data(let data): RealTimeEvent.parse(data)
        @unknown default: nil
        }
    }
}
