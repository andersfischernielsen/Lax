import CoreGraphics
import CoreText
import Foundation
import ImageIO
import LaxKit
import UniformTypeIdentifiers

/// A made-up workspace for screenshots and demos: launched with `-demo`, Lax signs in to
/// "Acme", whose Slack API calls and images are answered here. Nothing touches the
/// Keychain or the network, and the people, channels and messages are fictional.
enum DemoSlack {
    static let isEnabled = CommandLine.arguments.contains("-demo")

    static let account = SlackAccount(
        teamID: "T0DEMO", userID: "U1", teamName: "Acme", userName: "alex",
        credentials: SlackCredentials(workspaceDomain: "acme.slack.com", token: "xoxc-demo", cookies: [])
    )

    /// A session whose requests are answered by `Responder`.
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [Responder.self]
        return URLSession(configuration: configuration)
    }()

    // MARK: - Time

    /// Messages are placed relative to launch, so "Yesterday" and "Today" stay true.
    private static let launch = Date()

    private static func ts(daysAgo: Int, at hour: Int, _ minute: Int) -> String {
        let calendar = Calendar.current
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: launch))!
        let date = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
        return String(format: "%.6f", min(date, launch.addingTimeInterval(-60)).timeIntervalSince1970)
    }

    /// Messages the demo scenes point at.
    static let allHandsTS = ts(daysAgo: 1, at: 10, 30)
    static let reviewTS = ts(daysAgo: 0, at: 9, 20)
    static let deployTS = ts(daysAgo: 0, at: 8, 40)
    static let walkthroughTS = ts(daysAgo: 1, at: 14, 5)

    // MARK: - People and conversations

    private static let people: [(id: String, name: String, display: String, color: (Double, Double, Double))] = [
        ("U1", "alex", "Alex Morgan", (0.35, 0.45, 0.95)),
        ("U2", "maya", "Maya Chen", (0.90, 0.40, 0.45)),
        ("U3", "jonas", "Jonas Berg", (0.25, 0.65, 0.55)),
        ("U4", "priya", "Priya Patel", (0.95, 0.60, 0.20)),
        ("U5", "sam", "Sam Okafor", (0.55, 0.40, 0.85)),
        ("U6", "lena", "Lena Weiss", (0.20, 0.60, 0.85)),
    ]

    private static let conversations = #"""
        {"ok":true,"channels":[
          {"id":"C1","name":"general","is_channel":true,"topic":{"value":"Company-wide news and announcements"}},
          {"id":"C2","name":"design","is_channel":true,"topic":{"value":"Pixels, prototypes and critique"}},
          {"id":"C3","name":"engineering","is_channel":true,"topic":{"value":"Everything we build"}},
          {"id":"C4","name":"random","is_channel":true},
          {"id":"C5","name":"releases","is_channel":true,"topic":{"value":"Deploys and builds"}},
          {"id":"G2","name":"leadership","is_group":true,"is_private":true},
          {"id":"D1","is_im":true,"user":"U2"},
          {"id":"D2","is_im":true,"user":"U3"},
          {"id":"D3","is_im":true,"user":"U4"},
          {"id":"G1","name":"mpdm-maya--jonas--sam-1","is_mpim":true,"is_private":true}
        ]}
        """#

    // MARK: - Messages

    private static func message(_ ts: String, _ user: String, _ text: String, extra: String = "") -> String {
        let escaped = String(decoding: try! JSONEncoder().encode(text), as: UTF8.self)
        return #"{"type":"message","ts":"\#(ts)","user":"\#(user)","text":\#(escaped)\#(extra)}"#
    }

    private static func reactions(_ list: [(String, [String])]) -> String {
        let items = list.map { name, users in
            #"{"name":"\#(name)","count":\#(users.count),"users":[\#(users.map { "\"\($0)\"" }.joined(separator: ","))]}"#
        }
        return #","reactions":[\#(items.joined(separator: ","))]"#
    }

    private static func history(_ channel: String) -> [String] {
        switch channel {
        case "C1":
            [
                message(lenaRetroTS, "U6", "> Ship small, ship often\nLove this line from the retro :sparkles:"),
                message(
                    reviewTS, "U2",
                    "<@U1> could you review the onboarding copy before lunch? `copy-v3.md` is ready :pray:",
                    extra: reactions([("eyes", ["U3"])])),
                message(ts(daysAgo: 0, at: 8, 55), "U5", ":partyparrot: :partyparrot: :partyparrot:"),
                message(
                    ts(daysAgo: 1, at: 16, 45), "U4", "Sunset from the new office :sunrise_over_mountains:",
                    extra:
                        #","files":[{"id":"F1","name":"office.png","title":"office.png","mimetype":"image/png","pretty_type":"PNG","url_private":"https://files.slack.com/demo/office.png","permalink":"https://acme.slack.com/files/F1","thumb_720":"https://files.slack.com/demo/office.png","thumb_720_w":720,"thumb_720_h":405}]"#
                ),
                message(
                    allHandsTS, "U3",
                    "Reminder: *all-hands* moves to Thursday at 15:00. Agenda in <https://example.com/agenda|the planning doc>.",
                    extra:
                        #","thread_ts":"\#(allHandsTS)","reply_count":3,"latest_reply":"\#(ts(daysAgo: 0, at: 9, 5))""#
                        + reactions([("+1", ["U1", "U2", "U4", "U5"]), ("calendar", ["U6"])])),
                message(
                    ts(daysAgo: 1, at: 9, 12), "U2",
                    "Morning all! :wave: The new office plants have arrived :potted_plant:",
                    extra: reactions([
                        ("heart", ["U1", "U3"]), ("partyparrot", ["U4", "U5", "U6"]), ("seedling", ["U3"]),
                    ])),
            ]
        case "C2":
            [
                message(
                    ts(daysAgo: 0, at: 10, 2), "U4",
                    "New icon explorations are up :art: Feedback welcome, especially on the dark variants"),
                message(
                    walkthroughTS, "U2", "Quick walkthrough of the new onboarding flow :movie_camera:",
                    extra:
                        #","files":[{"id":"F2","name":"walkthrough.mp4","title":"walkthrough.mp4","mimetype":"video/mp4","pretty_type":"MPEG 4 Video","url_private":"https://files.slack.com/demo/walkthrough.mp4","permalink":"https://acme.slack.com/files/F2","thumb_video":"https://files.slack.com/demo/walkthrough-poster.png","thumb_video_w":1280,"thumb_video_h":720}]"#
                ),
                message(ts(daysAgo: 1, at: 11, 20), "U6", "<!subteam^S1> critique at 14:00 :shipit:"),
            ]
        case "C5":
            [
                #"{"type":"message","ts":"\#(deployTS)","user":"U9","bot_id":"B1","username":"Deploybot","text":"api v2.14.0 is ready for production","blocks":[{"type":"header","block_id":"h","text":{"type":"plain_text","text":"Deploy to production"}},{"type":"section","block_id":"s","text":{"type":"mrkdwn","text":"*api* `v2.14.0` passed all checks and is ready to ship.\n• 14 commits by 5 people\n• Migrations: none"}},{"type":"actions","block_id":"a","elements":[{"type":"button","action_id":"approve","text":{"type":"plain_text","text":"Approve"},"style":"primary","value":"approve"},{"type":"button","action_id":"rollback","text":{"type":"plain_text","text":"Hold"},"style":"danger","value":"hold"},{"type":"button","action_id":"logs","text":{"type":"plain_text","text":"View Logs"},"url":"https://example.com/logs"}]}]}"#,
                #"{"type":"message","ts":"\#(ts(daysAgo: 1, at: 17, 30))","user":"U9","bot_id":"B1","username":"Deploybot","text":"","attachments":[{"color":"2eb67d","title":"Build #482 passed","title_link":"https://example.com/builds/482","text":"`main` at `4f9c2e1` · 6 min 12 s","fields":[{"title":"Tests","value":"1,284 passed","short":true},{"title":"Coverage","value":"87.4 %","short":true}]}]}"#,
            ]
        case "D1":
            [
                message(ts(daysAgo: 0, at: 9, 48), "U2", "Thanks! Also, lunch at the new ramen place? :ramen:"),
                message(
                    ts(daysAgo: 0, at: 9, 46), "U1", "Looks great, just two small notes in the doc :white_check_mark:"),
                message(
                    ts(daysAgo: 0, at: 9, 25), "U2",
                    "Here's the copy :point_down: <https://example.com/copy-v3|copy-v3.md>"),
            ]
        case "G1": [message(ts(daysAgo: 0, at: 7, 50), "U5", "Who's bringing snacks on Friday? :doughnut:")]
        default: [message(ts(daysAgo: 2, at: 12, 0), "U3", "Nothing new here yet :zzz:")]
        }
    }

    private static let lenaRetroTS = ts(daysAgo: 0, at: 9, 41)

    private static var allHandsThread: [String] {
        [
            message(
                allHandsTS, "U3",
                "Reminder: *all-hands* moves to Thursday at 15:00. Agenda in <https://example.com/agenda|the planning doc>.",
                extra: #","thread_ts":"\#(allHandsTS)","reply_count":3"#),
            message(
                ts(daysAgo: 1, at: 10, 34), "U2", "Thanks for the heads-up!", extra: #","thread_ts":"\#(allHandsTS)""#),
            message(
                ts(daysAgo: 1, at: 10, 52), "U1", "Added it to the team calendar :white_check_mark:",
                extra: #","thread_ts":"\#(allHandsTS)""#),
            message(
                ts(daysAgo: 0, at: 9, 5), "U4", "Could we record it for the Lisbon office? :pray:",
                extra: #","thread_ts":"\#(allHandsTS)""#),
        ]
    }

    // MARK: - Responses

    static func response(to method: String, fields: [String: String]) -> String {
        switch method {
        case "users.conversations":
            return conversations
        case "users.info":
            let id = fields["user"] ?? "U1"
            if id == "U9" {
                return
                    #"{"ok":true,"user":{"id":"U9","name":"deploybot","is_bot":true,"profile":{"real_name":"Deploybot","image_72":"https://avatars.slack-edge.com/demo/U9.png"}}}"#
            }
            let person = people.first { $0.id == id } ?? people[0]
            return
                #"{"ok":true,"user":{"id":"\#(person.id)","name":"\#(person.name)","profile":{"real_name":"\#(person.display)","display_name":"\#(person.display)","image_72":"https://avatars.slack-edge.com/demo/\#(person.id).png"}}}"#
        case "client.counts":
            return #"""
                {"ok":true,"threads":{"has_unreads":true,"mention_count":0},
                 "channels":[{"id":"C1","has_unreads":true,"mention_count":1,"latest":"\#(lenaRetroTS)"},
                             {"id":"C2","has_unreads":true,"mention_count":0},{"id":"C3","has_unreads":false},
                             {"id":"C4","has_unreads":true,"mention_count":0},{"id":"C5","has_unreads":false},
                             {"id":"G2","has_unreads":false}],
                 "mpims":[{"id":"G1","has_unreads":true,"mention_count":1,"latest":"\#(ts(daysAgo: 0, at: 7, 50))"}],
                 "ims":[{"id":"D1","has_unreads":true,"mention_count":1,"latest":"\#(ts(daysAgo: 0, at: 9, 48))"},
                        {"id":"D2","has_unreads":false,"latest":"\#(ts(daysAgo: 1, at: 15, 0))"},
                        {"id":"D3","has_unreads":false,"latest":"\#(ts(daysAgo: 3, at: 11, 0))"}]}
                """#
        case "conversations.history":
            let messages = history(fields["channel"] ?? "")
            return #"{"ok":true,"has_more":false,"messages":[\#(messages.joined(separator: ","))]}"#
        case "conversations.replies":
            return #"{"ok":true,"messages":[\#(allHandsThread.joined(separator: ","))]}"#
        case "conversations.info":
            // #general is read up to yesterday, so today's messages show as unread.
            let lastRead =
                fields["channel"] == "C1"
                ? ts(daysAgo: 0, at: 8, 0) : String(format: "%.6f", launch.timeIntervalSince1970)
            return #"{"ok":true,"channel":{"id":"\#(fields["channel"] ?? "")","last_read":"\#(lastRead)"}}"#
        case "conversations.members":
            return #"{"ok":true,"members":["U1","U2","U3","U5"]}"#
        case "subscriptions.thread.getView":
            return #"""
                {"ok":true,"has_more":false,"threads":[
                  {"root_msg":\#(allHandsThread[0].dropLast()),"channel":"C1","latest_reply":"\#(ts(daysAgo: 0, at: 9, 5))"},
                   "latest_replies":[\#(allHandsThread[3])],"unread_replies":[\#(allHandsThread[3])]},
                  {"root_msg":{"type":"message","ts":"\#(walkthroughTS)","thread_ts":"\#(walkthroughTS)","user":"U2","text":"Quick walkthrough of the new onboarding flow :movie_camera:","channel":"C2","latest_reply":"\#(ts(daysAgo: 1, at: 15, 0))","reply_count":2},
                   "latest_replies":[],"unread_replies":[]}
                ]}
                """#
        case "search.messages":
            let matches = [
                (allHandsTS, "U3", "Reminder: *all-hands* moves to Thursday at 15:00.", "C1", "general"),
                (
                    ts(daysAgo: 6, at: 13, 15), "U6",
                    "Slides from the last *all-hands* are in the shared drive :books:", "C1", "general"
                ),
                (ts(daysAgo: 9, at: 16, 40), "U4", "Can we do a design demo at the next *all-hands*?", "C2", "design"),
            ].map { ts, user, text, channel, name in
                message(ts, user, text, extra: #","channel":{"id":"\#(channel)","name":"\#(name)"}"#)
            }
            return #"{"ok":true,"messages":{"matches":[\#(matches.joined(separator: ","))]}}"#
        case "users.prefs.get":
            return #"{"ok":true,"prefs":{"muted_channels":"C4"}}"#
        case "emoji.list":
            let names = ["partyparrot", "shipit", "lgtm"]
            let entries = names.map { #""\#($0)":"https://emoji.slack-edge.com/demo/\#($0).png""# }
            return #"{"ok":true,"emoji":{\#(entries.joined(separator: ","))}}"#
        case "usergroups.list":
            return #"{"ok":true,"usergroups":[{"id":"S1","handle":"design-team"}]}"#
        case "chat.postMessage":
            let text = fields["text"] ?? ""
            return
                #"{"ok":true,"message":\#(message(String(format: "%.6f", Date().timeIntervalSince1970), "U1", text))}"#
        case "rtm.connect":
            return #"{"ok":false,"error":"demo"}"#
        default:
            return #"{"ok":true}"#
        }
    }

    // MARK: - Images

    /// Drawn on the fly: avatars from initials, emoji from emoji glyphs, photos from gradients.
    static func image(for url: URL) -> Data? {
        let name = url.deletingPathExtension().lastPathComponent
        switch url.host() {
        case "avatars.slack-edge.com":
            if name == "U9" {
                return drawn(size: 144) { draw(glyph: "🤖", in: $0, background: (0.2, 0.25, 0.3), size: 144) }
            }
            guard let person = people.first(where: { $0.id == name }) else { return nil }
            let initials = person.display.split(separator: " ").compactMap(\.first).map(String.init).joined()
            return drawn(size: 144) { draw(text: initials, in: $0, background: person.color, size: 144) }
        case "emoji.slack-edge.com":
            let glyph = ["partyparrot": "🦜", "shipit": "🐿️", "lgtm": "👌"][name] ?? "⭐️"
            return drawn(size: 128) { draw(glyph: glyph, in: $0, background: nil, size: 128) }
        default:
            return drawn(width: 1280, height: 720) { context in
                let colors =
                    name.contains("walkthrough")
                    ? [
                        CGColor(red: 0.2, green: 0.2, blue: 0.45, alpha: 1),
                        CGColor(red: 0.45, green: 0.3, blue: 0.7, alpha: 1),
                    ]
                    : [
                        CGColor(red: 0.98, green: 0.6, blue: 0.3, alpha: 1),
                        CGColor(red: 0.45, green: 0.3, blue: 0.65, alpha: 1),
                    ]
                let gradient = CGGradient(
                    colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1])!
                context.drawLinearGradient(
                    gradient, start: CGPoint(x: 0, y: 720), end: CGPoint(x: 0, y: 0), options: [])
                context.setFillColor(CGColor(red: 1, green: 0.85, blue: 0.5, alpha: 0.9))
                context.fillEllipse(in: CGRect(x: 820, y: 180, width: 220, height: 220))
                context.setFillColor(CGColor(red: 0.15, green: 0.12, blue: 0.25, alpha: 0.85))
                context.fill(CGRect(x: 0, y: 0, width: 1280, height: 150))
            }
        }
    }

    private static func drawn(size: Int, _ draw: (CGContext) -> Void) -> Data? {
        drawn(width: size, height: size, draw)
    }

    private static func drawn(width: Int, height: Int, _ draw: (CGContext) -> Void) -> Data? {
        guard
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
            case let data = NSMutableData(),
            let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        draw(context)
        guard let image = context.makeImage() else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        return data as Data
    }

    private static func draw(text: String, in context: CGContext, background: (Double, Double, Double), size: Int) {
        let side = CGFloat(size)
        context.setFillColor(CGColor(red: background.0, green: background.1, blue: background.2, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        let font = CTFontCreateWithName("SF Pro Rounded Bold" as CFString, side * 0.4, nil)
        centered(text, font: font, color: CGColor(gray: 1, alpha: 1), in: context, side: side)
    }

    private static func draw(glyph: String, in context: CGContext, background: (Double, Double, Double)?, size: Int) {
        let side = CGFloat(size)
        if let background {
            context.setFillColor(CGColor(red: background.0, green: background.1, blue: background.2, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        }
        let font = CTFontCreateWithName("Apple Color Emoji" as CFString, side * 0.75, nil)
        centered(glyph, font: font, color: CGColor(gray: 0, alpha: 1), in: context, side: side)
    }

    private static func centered(_ text: String, font: CTFont, color: CGColor, in context: CGContext, side: CGFloat) {
        let attributes = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: color] as CFDictionary
        let line = CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, text as CFString, attributes)!)
        let bounds = CTLineGetImageBounds(line, context)
        context.textPosition = CGPoint(
            x: (side - bounds.width) / 2 - bounds.minX, y: (side - bounds.height) / 2 - bounds.minY)
        CTLineDraw(line, context)
    }

    // MARK: - Answering requests

    /// Answers every request: images by URL, API calls by method.
    final class Responder: URLProtocol {
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            guard let url = request.url else { return }
            let body: Data
            if url.pathExtension == "png" || url.pathExtension == "mp4" {
                body = DemoSlack.image(for: url) ?? Data()
            } else {
                let form = request.httpBody ?? request.httpBodyStream.map(Self.read) ?? Data()
                body = Data(DemoSlack.response(to: url.lastPathComponent, fields: Self.fields(form)).utf8)
            }
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
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

        private static func fields(_ body: Data) -> [String: String] {
            Dictionary(
                String(decoding: body, as: UTF8.self).split(separator: "&").compactMap { pair in
                    let parts = pair.split(separator: "=", maxSplits: 1).map {
                        String($0).removingPercentEncoding ?? String($0)
                    }
                    return parts.count == 2 ? (parts[0], parts[1]) : nil
                }, uniquingKeysWith: { _, last in last })
        }
    }
}
