import Foundation

/// A signed-in Slack user on one workspace: who it is, plus how to act as them.
public struct SlackAccount: Codable, Hashable, Identifiable, Sendable {
    public var teamID: String
    public var userID: String
    public var teamName: String
    public var userName: String
    public var credentials: SlackCredentials

    public init(
        teamID: String, userID: String, teamName: String, userName: String,
        credentials: SlackCredentials
    ) {
        self.teamID = teamID
        self.userID = userID
        self.teamName = teamName
        self.userName = userName
        self.credentials = credentials
    }

    public var id: String { "\(teamID):\(userID)" }

    /// Checks the credentials with `auth.test` and fills in the identity.
    public static func verify(_ credentials: SlackCredentials, session: URLSession = .shared) async throws
        -> SlackAccount
    {
        let auth = try await SlackAPIClient(credentials: credentials, session: session).authTest()
        return SlackAccount(
            teamID: auth.teamID, userID: auth.userID, teamName: auth.team,
            userName: auth.user, credentials: credentials)
    }
}
