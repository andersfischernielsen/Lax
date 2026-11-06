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

    @Test func userGroupHandlesByID() async throws {
        StubURLProtocol.reset(["usergroups.list": [#"""
            {"ok":true,"usergroups":[{"id":"S1","handle":"platform","name":"Platform"},{"id":"S2","handle":"oncall"}]}
            """#]])
        #expect(try await client.userGroupHandles() == ["S1": "platform", "S2": "oncall"])
    }

    @Test func unreadCountsCoverAllConversationKinds() async throws {
        StubURLProtocol.reset(["client.counts": [#"""
            {"ok":true,"threads":{},
             "channels":[{"id":"C1","has_unreads":true,"mention_count":2},{"id":"C2","has_unreads":false}],
             "mpims":[{"id":"G1","has_unreads":true,"mention_count":1}],
             "ims":[{"id":"D1","has_unreads":true,"mention_count":3}]}
            """#]])
        let unread = try await client.unreadCounts()
        #expect(unread["C1"] == .init(hasUnreads: true, mentions: 2))
        #expect(unread["C2"] == .init())
        #expect(unread["G1"].mentions == 1)
        #expect(unread["D1"].mentions == 3)
    }

    @Test func repliesFollowCursors() async throws {
        StubURLProtocol.reset(["conversations.replies": [
            #"{"ok":true,"messages":[{"ts":"1.0","thread_ts":"1.0","text":"root"}],"response_metadata":{"next_cursor":"n"}}"#,
            #"{"ok":true,"messages":[{"ts":"2.0","thread_ts":"1.0","text":"reply"}]}"#,
        ]])
        let messages = try await client.replies(channel: "C1", threadTS: "1.0")
        #expect(messages.map(\.text) == ["root", "reply"])
        #expect(StubURLProtocol.requests[1].formFields["cursor"] == "n")
        #expect(StubURLProtocol.requests[0].formFields["ts"] == "1.0")
    }

    @Test func mutedChannelsFromPrefs() async throws {
        StubURLProtocol.reset([
            "users.prefs.get": [#"{"ok":true,"prefs":{"muted_channels":"C1","all_notifications_prefs":"{\"channels\":{\"C2\":{\"muted\":true}}}"}}"#],
            "users.prefs.setNotifications": [#"{"ok":true}"#],
        ])
        #expect(try await client.mutePrefs().muted == ["C1", "C2"])
        try await client.setMuted(true, channel: "C3")
        let fields = StubURLProtocol.requests[1].formFields
        #expect(fields["name"] == "muted")
        #expect(fields["value"] == "true")
        #expect(fields["channel_id"] == "C3")
    }

    @Test func editDeleteAndPermalink() async throws {
        StubURLProtocol.reset([
            "chat.update": [#"{"ok":true,"channel":"C1","ts":"1.0","text":"fixed"}"#],
            "chat.delete": [#"{"ok":true,"channel":"C1","ts":"1.0"}"#],
            "chat.getPermalink": [#"{"ok":true,"permalink":"https://acme.slack.com/archives/C1/p1000"}"#],
        ])
        try await client.editMessage("1.0", in: "C1", text: "fixed")
        try await client.deleteMessage("1.0", in: "C1")
        #expect(try await client.permalink(to: "1.0", in: "C1").path == "/archives/C1/p1000")
        let requests = StubURLProtocol.requests
        #expect(requests[0].formFields["text"] == "fixed")
        #expect(requests[1].formFields["ts"] == "1.0")
        #expect(requests[2].formFields["message_ts"] == "1.0")
    }

    @Test func membersFollowCursors() async throws {
        StubURLProtocol.reset(["conversations.members": [
            #"{"ok":true,"members":["U1","U2"],"response_metadata":{"next_cursor":"n"}}"#,
            #"{"ok":true,"members":["U3"],"response_metadata":{"next_cursor":""}}"#,
        ]])
        #expect(try await client.members(of: "G1") == ["U1", "U2", "U3"])
    }

    @Test func pinnedMessagesSkipOtherItems() async throws {
        StubURLProtocol.reset(["pins.list": [#"""
            {"ok":true,"items":[
              {"type":"message","channel":"C1","message":{"ts":"2.0","user":"U1","text":"pinned"}},
              {"type":"file","file":{"id":"F1"}}
            ]}
            """#]])
        #expect(try await client.pinnedMessages(in: "C1").map(\.text) == ["pinned"])
    }

    @Test func searchReturnsMessagesWithChannels() async throws {
        StubURLProtocol.reset(["search.messages": [#"""
            {"ok":true,"query":"deploy","messages":{"total":2,"matches":[
              {"type":"message","ts":"2.0","user":"U1","text":"deploy done","channel":{"id":"C1","name":"general"}},
              {"type":"message","ts":"1.0","user":"U2","text":"deploy?","channel":{"id":"D1","name":"U2","is_im":true}},
              {"type":"message","text":"broken, no ts"}
            ]}}
            """#]])
        let results = try await client.searchMessages("deploy")
        #expect(results.map(\.message.text) == ["deploy done", "deploy?"])
        #expect(results.map(\.channelName) == ["general", nil])
        #expect(StubURLProtocol.requests[0].formFields["query"] == "deploy")
    }

    @Test func displayNameGoesInTheProfileJSON() async throws {
        StubURLProtocol.reset(["users.profile.set": [#"{"ok":true,"profile":{"display_name":"Ann \"A\""}}"#]])
        try await client.setDisplayName(#"Ann "A""#)
        let profile = try #require(StubURLProtocol.requests[0].formFields["profile"])
        let decoded = try JSONDecoder().decode([String: String].self, from: Data(profile.utf8))
        #expect(decoded == ["display_name": #"Ann "A""#])
    }

    @Test func realTimeURLComesFromRTMConnect() async throws {
        StubURLProtocol.reset(["rtm.connect": [#"{"ok":true,"url":"wss://wss-primary.slack.com/websocket/abc"}"#]])
        #expect(try await client.realTimeURL().absoluteString == "wss://wss-primary.slack.com/websocket/abc")
    }

    @Test func followedThreadsListsRootsWithUnreadReplies() async throws {
        StubURLProtocol.reset(["subscriptions.thread.getView": [
            #"""
            {"ok":true,"has_more":true,"threads":[
              {"root_msg":{"type":"message","ts":"10.0","thread_ts":"10.0","user":"U1","text":"Root",
                           "channel":"C1","latest_reply":"12.0","last_read":"11.0","reply_count":2},
               "latest_replies":[{"type":"message","ts":"12.0","thread_ts":"10.0","user":"U2","text":"b"},
                                 {"type":"message","ts":"11.0","thread_ts":"10.0","user":"U3","text":"a"}],
               "unread_replies":[{"type":"message","ts":"12.0","thread_ts":"10.0","user":"U2","text":"b"}]},
              {"broken":true}
            ]}
            """#,
        ]])
        let page = try await client.followedThreads(limit: 5, now: Date(timeIntervalSince1970: 100))
        #expect(page.hasMore)
        let thread = try #require(page.threads.first)
        #expect(page.threads.count == 1)
        #expect(thread.id == "C1/10.0")
        #expect(thread.root.text == "Root")
        #expect(thread.latestReplies.map(\.ts) == ["11.0", "12.0"])
        #expect(thread.unreadReplies == 1)
        #expect(thread.latestReplyTS == "12.0")
        let fields = StubURLProtocol.requests[0].formFields
        #expect(fields["current_ts"] == "100.000000")
        #expect(fields["limit"] == "5")
    }

    @Test func markingAThreadReadSendsItsPosition() async throws {
        StubURLProtocol.reset(["subscriptions.thread.mark": [#"{"ok":true}"#]])
        try await client.markThreadRead(channel: "C1", threadTS: "10.0", ts: "12.0")
        let fields = StubURLProtocol.requests[0].formFields
        #expect(fields["channel"] == "C1")
        #expect(fields["thread_ts"] == "10.0")
        #expect(fields["ts"] == "12.0")
        #expect(fields["read"] == "1")
    }
}
