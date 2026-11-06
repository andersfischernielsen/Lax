import Foundation
import LaxKit

/// A fake Slack for UI tests: launched with `-ui-testing`, Lax signs in to one fixture
/// workspace whose API calls are answered here, never touching the Keychain or the network.
enum UITestingSlack {
    static let isEnabled = CommandLine.arguments.contains("-ui-testing")

    static let account = SlackAccount(
        teamID: "T1", userID: "U1", teamName: "Acme", userName: "me",
        credentials: SlackCredentials(workspaceDomain: "acme.slack.com", token: "xoxc-ui-testing", cookies: [])
    )

    /// A session whose requests go to `FixtureProtocol`.
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureProtocol.self]
        return URLSession(configuration: configuration)
    }()

    /// The JSON body Slack would send for `method` called with `fields`.
    static func response(to method: String, fields: [String: String]) -> String {
        switch method {
        case "users.conversations":
            return #"""
            {"ok":true,"channels":[
              {"id":"C1","name":"general","is_channel":true,"topic":{"value":"Company-wide"}},
              {"id":"C2","name":"random","is_channel":true},
              {"id":"C3","name":"design","is_channel":true},
              {"id":"D1","is_im":true,"user":"U2"},
              {"id":"D2","is_im":true,"user":"U3"}
            ]}
            """#
        case "users.info":
            let names = ["U1": "Me Myself", "U2": "Jane Doe", "U3": "Bob Lee"]
            let id = fields["user"] ?? "U1"
            return #"{"ok":true,"user":{"id":"\#(id)","name":"\#(id.lowercased())","profile":{"real_name":"\#(names[id] ?? id)"}}}"#
        case "client.counts":
            return #"""
            {"ok":true,"threads":{"has_unreads":false,"mention_count":0},
             "channels":[{"id":"C1","has_unreads":false},{"id":"C2","has_unreads":false},
                         {"id":"C3","has_unreads":true,"mention_count":1}],
             "ims":[{"id":"D1","has_unreads":false,"latest":"1700000300.000000"},
                    {"id":"D2","has_unreads":false,"latest":"1700000100.000000"}]}
            """#
        case "conversations.history":
            return history(fields["channel"] ?? "")
        case "conversations.replies":
            return #"""
            {"ok":true,"messages":[
              {"type":"message","ts":"1700000020.000000","thread_ts":"1700000020.000000","user":"U2","text":"Who's up for lunch?","reply_count":2},
              {"type":"message","ts":"1700000030.000000","thread_ts":"1700000020.000000","user":"U3","text":"Count me in"},
              {"type":"message","ts":"1700000040.000000","thread_ts":"1700000020.000000","user":"U1","text":"Me too"}
            ]}
            """#
        case "subscriptions.thread.getView":
            return #"""
            {"ok":true,"has_more":false,"threads":[
              {"root_msg":{"type":"message","ts":"1700000020.000000","thread_ts":"1700000020.000000","user":"U2",
                           "text":"Who's up for lunch?","channel":"C1","latest_reply":"1700000040.000000","reply_count":2},
               "latest_replies":[{"type":"message","ts":"1700000040.000000","thread_ts":"1700000020.000000","user":"U1","text":"Me too"}],
               "unread_replies":[]}
            ]}
            """#
        case "search.messages":
            return #"""
            {"ok":true,"messages":{"matches":[
              {"type":"message","ts":"1700000010.000000","user":"U2","text":"Welcome to general",
               "channel":{"id":"C1","name":"general"}}
            ]}}
            """#
        case "chat.postMessage":
            let text = fields["text"] ?? ""
            let escaped = String(data: try! JSONEncoder().encode(text), encoding: .utf8)!
            return #"{"ok":true,"message":{"type":"message","ts":"1700000900.000000","user":"U1","text":\#(escaped)}}"#
        case "conversations.info":
            return #"{"ok":true,"channel":{"id":"\#(fields["channel"] ?? "")","last_read":"1700000000.000000"}}"#
        case "users.prefs.get":
            return #"{"ok":true,"prefs":{"muted_channels":""}}"#
        case "emoji.list":
            return #"{"ok":true,"emoji":{}}"#
        case "usergroups.list":
            return #"{"ok":true,"usergroups":[]}"#
        case "conversations.members":
            return #"{"ok":true,"members":["U1"]}"#
        case "rtm.connect":
            // No live connection in tests: Lax shows itself offline and keeps retrying.
            return #"{"ok":false,"error":"ui_testing"}"#
        default:
            return #"{"ok":true}"#
        }
    }

    private static func history(_ channel: String) -> String {
        let messages: [String] = switch channel {
        case "C1": [
            #"{"type":"message","ts":"1700000040.000000","user":"U3","text":"See you all at noon"}"#,
            #"{"type":"message","ts":"1700000020.000000","thread_ts":"1700000020.000000","user":"U2","text":"Who's up for lunch?","reply_count":2,"latest_reply":"1700000040.000000"}"#,
            #"{"type":"message","ts":"1700000010.000000","user":"U2","text":"Welcome to general"}"#,
        ]
        case "C3": [
            #"{"type":"message","ts":"1700000060.000000","user":"U2","text":"<@U1> can you review the mockups?"}"#,
            #"{"type":"message","ts":"1700000050.000000","user":"U3","text":"New mockups are up"}"#,
        ]
        case "D1": [#"{"type":"message","ts":"1700000300.000000","user":"U2","text":"Hi there"}"#]
        default: [#"{"type":"message","ts":"1700000001.000000","user":"U3","text":"Hello in \#(channel)"}"#]
        }
        return #"{"ok":true,"has_more":false,"messages":[\#(messages.joined(separator: ","))]}"#
    }

    /// Answers every request from `response(to:fields:)`.
    final class FixtureProtocol: URLProtocol {
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            let method = request.url?.lastPathComponent ?? ""
            let body = request.httpBody ?? request.httpBodyStream.map(Self.read) ?? Data()
            let fields = Self.formFields(String(decoding: body, as: UTF8.self))
            let json = UITestingSlack.response(to: method, fields: fields)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(json.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}

        private static func read(_ stream: InputStream) -> Data {
            stream.open()
            defer { stream.close() }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                data.append(buffer, count: count)
            }
            return data
        }

        private static func formFields(_ body: String) -> [String: String] {
            Dictionary(body.split(separator: "&").compactMap { pair in
                let parts = pair.split(separator: "=", maxSplits: 1).map { String($0).removingPercentEncoding ?? String($0) }
                return parts.count == 2 ? (parts[0], parts[1]) : nil
            }, uniquingKeysWith: { _, last in last })
        }
    }
}
