import Foundation

/// `auth.test`: confirms the credentials work and says who they belong to.
public struct AuthTestResponse: Decodable, Equatable, Sendable {
    public let url: String
    public let team: String
    public let user: String
    public let teamID: String
    public let userID: String

    enum CodingKeys: String, CodingKey {
        case url, team, user
        case teamID = "team_id"
        case userID = "user_id"
    }
}

extension SlackAPIClient {
    public func authTest() async throws -> AuthTestResponse {
        try await call("auth.test")
    }
}
