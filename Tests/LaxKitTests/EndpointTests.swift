import Foundation
import Testing
@testable import LaxKit

@Suite(.serialized)
struct EndpointTests {
    let client = SlackAPIClient(
        credentials: SlackCredentials(workspaceDomain: "acme.slack.com", token: "xoxc-1",
                                      cookies: [SlackCookie(name: "d", value: "x")]),
        session: StubURLProtocol.session()
    )

    @Test func conversationsFollowsCursorsAndClassifiesKinds() async throws {
        StubURLProtocol.reset(["users.conversations": [
            #"""
            {"ok":true,"channels":[
              {"id":"C1","name":"general","is_channel":true,"is_private":false,"topic":{"value":"Hi"}},
              {"id":"G1","name":"secret","is_group":true}
            ],"response_metadata":{"next_cursor":"abc"}}
            """#,
            #"""
            {"ok":true,"channels":[
              {"id":"D1","is_im":true,"user":"U2"},
              {"id":"G2","name":"mpdm-a--b-1","is_mpim":true,"is_private":true}
            ],"response_metadata":{"next_cursor":""}}
            """#,
        ]])
        let conversations = try await client.conversations()
        #expect(conversations.map(\.kind) == [.channel, .privateChannel, .directMessage, .groupDirectMessage])
        #expect(conversations[0].topic == "Hi")
        #expect(conversations[2].userID == "U2")

        let requests = StubURLProtocol.requests
        #expect(requests.count == 2)
        #expect(requests[0].formFields["cursor"] == nil)
        #expect(requests[1].formFields["cursor"] == "abc")
        #expect(requests[0].formFields["types"] == "public_channel,private_channel,mpim,im")
    }

    @Test func historyPassesPagingParameters() async throws {
        StubURLProtocol.reset(["conversations.history": [#"""
            {"ok":true,"has_more":true,"messages":[
              {"type":"message","ts":"1700000002.000200","user":"U1","text":"second","edited":{"ts":"1"}},
              {"type":"message","ts":"1700000001.000100","bot_id":"B1","username":"CI","text":"first","subtype":"bot_message"}
            ]}
            """#]])
        let page = try await client.history(channel: "C1", limit: 2, before: "1700000003.000000")
        #expect(page.hasMore)
        #expect(page.messages.map(\.text) == ["second", "first"])
        #expect(page.messages[0].isEdited)
        #expect(page.messages[1].username == "CI")
        let fields = StubURLProtocol.requests[0].formFields
        #expect(fields["channel"] == "C1")
        #expect(fields["limit"] == "2")
        #expect(fields["latest"] == "1700000003.000000")
    }

    @Test func userInfoDecodesProfile() async throws {
        StubURLProtocol.reset(["users.info": [#"""
            {"ok":true,"user":{"id":"U1","name":"jdoe","profile":{"display_name":"","real_name":"Jane Doe",
             "image_72":"https://avatars.slack-edge.com/x_72.png"}}}
            """#]])
        let user = try await client.user(id: "U1")
        #expect(user.preferredName == "Jane Doe")
        #expect(user.avatarURL?.host == "avatars.slack-edge.com")
    }

    @Test func postMessageSendsThreadReply() async throws {
        StubURLProtocol.reset(["chat.postMessage": [#"""
            {"ok":true,"channel":"C1","ts":"1700000005.000500",
             "message":{"type":"message","ts":"1700000005.000500","user":"U1","text":"hello & bye","thread_ts":"1700000001.000100"}}
            """#]])
        let message = try await client.postMessage(channel: "C1", text: "hello & bye", threadTS: "1700000001.000100")
        #expect(message.threadTS == "1700000001.000100")
        let fields = StubURLProtocol.requests[0].formFields
        #expect(fields["text"] == "hello & bye")
        #expect(fields["thread_ts"] == "1700000001.000100")
    }

    @Test func readPositionRoundTrip() async throws {
        StubURLProtocol.reset([
            "conversations.info": [#"{"ok":true,"channel":{"id":"C1","last_read":"1700000001.000100"}}"#],
            "conversations.mark": [#"{"ok":true}"#],
        ])
        #expect(try await client.lastRead(channel: "C1") == "1700000001.000100")
        try await client.markRead(channel: "C1", ts: "1700000009.000900")
        let mark = StubURLProtocol.requests[1]
        #expect(mark.url?.lastPathComponent == "conversations.mark")
        #expect(mark.formFields["ts"] == "1700000009.000900")
    }

    @Test func realTimeURLComesFromRTMConnect() async throws {
        StubURLProtocol.reset(["rtm.connect": [#"{"ok":true,"url":"wss://wss-primary.slack.com/websocket/abc"}"#]])
        #expect(try await client.realTimeURL().absoluteString == "wss://wss-primary.slack.com/websocket/abc")
    }
}
