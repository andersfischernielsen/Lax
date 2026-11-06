import Foundation
import Testing

@testable import LaxKit

@Test func readsTheLegacyList() {
    #expect(MutePrefs(mutedChannels: "C1, C2,,").muted == ["C1", "C2"])
}

@Test func notificationPrefsAddAndOverride() {
    let prefs = MutePrefs(
        mutedChannels: "C1,C2",
        allNotificationsPrefs:
            #"{"channels":{"C2":{"muted":false},"C3":{"muted":true},"C4":{"desktop":"all"}},"global":{}}"#)
    #expect(prefs.muted == ["C1", "C3"])
}

@Test func toleratesMissingOrBrokenPrefs() {
    #expect(MutePrefs(allNotificationsPrefs: "{").muted.isEmpty)
}

@Test func prefChangesUpdateOneSourceAtATime() {
    var prefs = MutePrefs(mutedChannels: "C1", allNotificationsPrefs: #"{"channels":{"C2":{"muted":true}}}"#)
    prefs.apply(prefChange: "all_notifications_prefs", value: #"{"channels":{"C3":{"muted":true}}}"#)
    #expect(prefs.muted == ["C1", "C3"])
    prefs.apply(prefChange: "display_real_names", value: "true")
    #expect(prefs.muted == ["C1", "C3"])
}

@Test func parsesPrefChanges() {
    let event = RealTimeEvent.parse(Data(#"{"type":"pref_change","name":"muted_channels","value":"C1,C2"}"#.utf8))
    #expect(event == .prefChange(name: "muted_channels", value: "C1,C2"))
    let flag = RealTimeEvent.parse(Data(#"{"type":"pref_change","name":"display_real_names","value":true}"#.utf8))
    #expect(flag == .prefChange(name: "display_real_names", value: "true"))
}
