import Foundation
import Testing
@testable import LaxKit

private func message(_ json: String) throws -> SlackMessage {
    try JSONDecoder().decode(SlackMessage.self, from: Data(json.utf8))
}

private let text = SlackText(userName: { ["U1": "jane"][$0] })

@Test func richTextBecomesMarkup() throws {
    let decoded = try message(#"""
        {"ts":"1.0","text":"","blocks":[{"type":"rich_text","elements":[
          {"type":"rich_text_section","elements":[
            {"type":"text","text":"Hi "},{"type":"user","user_id":"U1"},{"type":"text","text":" see "},
            {"type":"link","url":"https://x.io","text":"docs"},{"type":"text","text":" now ","style":{"bold":true}},
            {"type":"emoji","name":"tada","unicode":"1f389"},{"type":"text","text":" a<b"}]},
          {"type":"rich_text_list","style":"bullet","elements":[
            {"type":"rich_text_section","elements":[{"type":"text","text":"one"}]},
            {"type":"rich_text_section","elements":[{"type":"text","text":"two"}]}]},
          {"type":"rich_text_preformatted","elements":[{"type":"text","text":"let x = 1"}]}
        ]}]}
        """#)
    #expect(text.plain(decoded.markup) == "Hi @jane see docs now 🎉 a<b\n• one\n• two\nlet x = 1")
    let attributed = text.attributed(decoded.markup)
    let now = attributed.runs.first { String(attributed[$0.range].characters) == "now" }
    #expect(now?.inlinePresentationIntent == .stronglyEmphasized)
}

@Test func plainTextMessagesKeepTheirText() throws {
    let decoded = try message(#"""
        {"ts":"1.0","text":"hello *there*","blocks":[{"type":"rich_text","elements":[
          {"type":"rich_text_section","elements":[{"type":"text","text":"hello "},{"type":"text","text":"there","style":{"bold":true}}]}]}]}
        """#)
    #expect(decoded.markup == "hello *there*")
}

@Test func layoutBlocksReplaceTheSummaryText() throws {
    let decoded = try message(#"""
        {"ts":"1.0","text":"New alert","blocks":[
          {"type":"header","text":{"type":"plain_text","text":"Disk <90%>"}},
          {"type":"section","text":{"type":"mrkdwn","text":"*host-1* is full"},
           "fields":[{"type":"mrkdwn","text":"*Region*\nEU"}]},
          {"type":"divider"},
          {"type":"context","elements":[{"type":"mrkdwn","text":"via Datadog"},{"type":"image","image_url":"x"}]},
          {"type":"actions","elements":[]}
        ]}
        """#)
    #expect(text.plain(decoded.markup) == "Disk <90%>\nhost-1 is full\nRegion\nEU\n———\nvia Datadog")
}

@Test func decodesAttachments() throws {
    let decoded = try message(#"""
        {"ts":"1.0","text":"","attachments":[
          {"color":"danger","pretext":"Heads up","title":"CPU high","title_link":"https://dd.io/1",
           "text":"95% on *api*","fields":[{"title":"Host","value":"api-1","short":true}],"footer":"Datadog",
           "fallback":"CPU high on api"},
          {"color":"#36a64f","fallback":"Only a fallback"},
          {"blocks":[{"type":"section","text":{"type":"mrkdwn","text":"From blocks"}}]}
        ]}
        """#)
    let first = try #require(decoded.attachments.first)
    #expect(first.color == SlackAttachment.Color("E01E5A"))
    #expect(first.title == "CPU high")
    #expect(first.titleLink?.host == "dd.io")
    #expect(first.body == "95% on *api*")
    #expect(first.fields.map(\.title) == ["Host"])
    #expect(first.fields.first?.isShort == true)
    #expect(decoded.attachments[1].body == "Only a fallback")
    #expect(decoded.attachments[1].color?.green == Double(0xA6) / 255)
    #expect(decoded.attachments[2].body == "From blocks")
}
