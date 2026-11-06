import Foundation
import Testing

@testable import LaxKit

@Test func uploadIsARegularFile() throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appending(path: "notes.txt")
    try Data("hello".utf8).write(to: file)

    let upload = try #require(Upload(fileAt: file))
    #expect(upload.name == "notes.txt")
    #expect(upload.byteCount == 5)
    #expect(Upload(fileAt: folder) == nil)
    #expect(Upload(fileAt: folder.appending(path: "missing.txt")) == nil)
    #expect(Upload(fileAt: URL(string: "https://example.com/notes.txt")!) == nil)
}

// In EndpointTests: the URL stub is shared, so these must not run alongside its other tests.
extension EndpointTests {
    private func uploads(_ names: String...) throws -> [Upload] {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return try names.map { name in
            let file = folder.appending(path: name)
            try Data(name.utf8).write(to: file)
            return try #require(Upload(fileAt: file))
        }
    }

    @Test func shareUploadsEachFileThenSharesThemTogether() async throws {
        StubURLProtocol.reset([
            "files.getUploadURLExternal": [
                #"{"ok":true,"upload_url":"https://files.slack.com/upload/v1/AAA","file_id":"F1"}"#,
                #"{"ok":true,"upload_url":"https://files.slack.com/upload/v1/BBB","file_id":"F2"}"#,
            ],
            "AAA": ["OK"], "BBB": ["OK"],
            "files.completeUploadExternal": [#"{"ok":true,"files":[]}"#],
        ])
        try await client.share(uploads("a.txt", "bb.txt"), in: "C1", threadTS: "1.2", comment: "hi <@U1>")

        let requests = StubURLProtocol.requests
        #expect(
            requests.map { $0.url?.lastPathComponent }
                == [
                    "files.getUploadURLExternal", "AAA", "files.getUploadURLExternal", "BBB",
                    "files.completeUploadExternal",
                ]
        )
        #expect(requests[0].formFields["filename"] == "a.txt")
        #expect(requests[0].formFields["length"] == "5")
        // The upload URL authorizes itself; the session stays with Slack's API.
        #expect(requests[1].value(forHTTPHeaderField: "Cookie") == nil)
        let complete = requests[4].formFields
        #expect(complete["files"] == #"[{"id":"F1","title":"a.txt"},{"id":"F2","title":"bb.txt"}]"#)
        #expect(complete["channel_id"] == "C1")
        #expect(complete["thread_ts"] == "1.2")
        #expect(complete["initial_comment"] == "hi <@U1>")
    }

    @Test func shareWithoutACommentSendsNone() async throws {
        StubURLProtocol.reset([
            "files.getUploadURLExternal": [
                #"{"ok":true,"upload_url":"https://files.slack.com/upload/v1/AAA","file_id":"F1"}"#
            ],
            "AAA": ["OK"],
            "files.completeUploadExternal": [#"{"ok":true}"#],
        ])
        try await client.share(uploads("a.txt"), in: "C1")
        let complete = StubURLProtocol.requests[2].formFields
        #expect(complete["initial_comment"] == nil)
        #expect(complete["thread_ts"] == nil)
    }

    @Test func shareRefusesUploadURLsOffSlack() async throws {
        StubURLProtocol.reset([
            "files.getUploadURLExternal": [#"{"ok":true,"upload_url":"https://example.com/upload","file_id":"F1"}"#]
        ])
        await #expect(throws: URLError.self) { try await client.share(uploads("a.txt"), in: "C1") }
        #expect(StubURLProtocol.requests.count == 1)
    }
}
