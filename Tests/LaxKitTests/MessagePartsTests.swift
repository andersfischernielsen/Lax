import Foundation
import Testing
@testable import LaxKit

private func decode(_ json: String) throws -> SlackMessage {
    try JSONDecoder().decode(SlackMessage.self, from: Data(json.utf8))
}

@Test func decodesReactions() throws {
    let message = try decode(#"{"ts":"1.0","text":"","reactions":[{"name":"tada","users":["U1","U2"],"count":2}]}"#)
    #expect(message.reactions == [SlackReaction(name: "tada", users: ["U1", "U2"], count: 2)])
}

@Test func addingAndRemovingReactions() {
    let start = [SlackReaction(name: "tada", users: ["U2"], count: 1)]
    let added = SlackReaction.applying("tada", by: "U1", added: true, to: start)
    #expect(added == [SlackReaction(name: "tada", users: ["U2", "U1"], count: 2)])
    #expect(SlackReaction.applying("tada", by: "U1", added: true, to: added) == added)
    #expect(SlackReaction.applying("eyes", by: "U1", added: true, to: start).map(\.name) == ["tada", "eyes"])
    #expect(SlackReaction.applying("tada", by: "U2", added: false, to: start).isEmpty)
    #expect(SlackReaction.applying("tada", by: "U9", added: false, to: start) == start)
}

@Test func timelineAppliesReactions() {
    var timeline = Timeline()
    timeline.upsert(SlackMessage(ts: "1.0", userID: "U1", text: ""))
    timeline.react("+1", by: "U2", added: true, to: "1.0")
    timeline.react("+1", by: "U2", added: true, to: "9.0")
    #expect(timeline.messages[0].reactions.map(\.count) == [1])
}

@Test func parsesReactionEvents() {
    let event = RealTimeEvent.parse(Data(#"""
        {"type":"reaction_added","user":"U2","reaction":"eyes","item_user":"U1",
         "item":{"type":"message","channel":"C1","ts":"1.0"}}
        """#.utf8))
    #expect(event == .reaction(channel: "C1", ts: "1.0", name: "eyes", userID: "U2", added: true))
    let fileReaction = RealTimeEvent.parse(Data(#"""
        {"type":"reaction_removed","user":"U2","reaction":"eyes","item":{"type":"file","file":"F1"}}
        """#.utf8))
    #expect(fileReaction == nil)
}

@Test func imagesGetPreviewsAndOtherFilesDont() throws {
    let message = try decode(#"""
        {"ts":"1.0","text":"","files":[
          {"id":"F1","name":"shot.png","title":"Screenshot","mimetype":"image/png",
           "url_private":"https://files.slack.com/files-pri/T1-F1/shot.png","permalink":"https://acme.slack.com/files/U1/F1/shot.png",
           "thumb_360":"https://files.slack.com/files-tmb/T1-F1/shot_360.png","thumb_360_w":360,"thumb_360_h":200},
          {"id":"F2","name":"notes.pdf","mimetype":"application/pdf","pretty_type":"PDF"},
          {"id":"F3","mode":"hidden_by_limit"}
        ]}
        """#)
    #expect(message.files.map(\.id) == ["F1", "F2"])
    #expect(message.files[0].name == "Screenshot")
    #expect(message.files[0].preview?.width == 360)
    #expect(message.files[1].preview == nil)
    #expect(message.files[1].prettyType == "PDF")
}
