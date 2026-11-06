import Foundation

/// A file on disk to share in a conversation.
public struct Upload: Hashable, Sendable, Identifiable {
    public let url: URL
    public let name: String
    public let byteCount: Int

    public var id: URL { url }

    /// The file at `url`, if it's a regular file; folders and missing files aren't.
    public init?(fileAt url: URL) {
        guard url.isFileURL,
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .nameKey]),
            values.isRegularFile == true, let byteCount = values.fileSize
        else { return nil }
        self.url = url
        name = values.name ?? url.lastPathComponent
        self.byteCount = byteCount
    }
}

extension SlackAPIClient {
    /// Shares files in a conversation, or in a thread when `threadTS` is given, posted
    /// with `comment` as their message. Each file is uploaded first, then all are shared
    /// together, as Slack's own clients do.
    public func share(
        _ uploads: [Upload], in channel: String, threadTS: String? = nil, comment: String = ""
    ) async throws {
        var files: [UploadedFile] = []
        for upload in uploads {
            let ticket: UploadTicket = try await call(
                "files.getUploadURLExternal",
                ["filename": upload.name, "length": String(upload.byteCount)])
            try await self.upload(upload.url, to: ticket.uploadURL)
            files.append(UploadedFile(id: ticket.fileID, title: upload.name))
        }
        var params = ["files": try Self.json(files), "channel_id": channel]
        params["thread_ts"] = threadTS
        if !comment.isEmpty { params["initial_comment"] = comment }
        let _: Empty = try await call("files.completeUploadExternal", params)
    }
}

/// Where to send one file's bytes, and the ID it will have once shared.
private struct UploadTicket: Decodable {
    let uploadURL: URL
    let fileID: String

    enum CodingKeys: String, CodingKey {
        case uploadURL = "upload_url"
        case fileID = "file_id"
    }
}

private struct UploadedFile: Encodable {
    let id: String
    let title: String
}

extension [Upload] {
    /// These files and then `files`, each file once.
    public func adding(_ files: [Upload]) -> [Upload] {
        files.reduce(self) { $0.contains($1) ? $0 : $0 + [$1] }
    }
}
