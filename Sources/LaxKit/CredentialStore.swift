import Foundation
import Security

public enum CredentialStoreError: Error, Equatable {
    case keychain(OSStatus)
}

/// Keeps `SlackCredentials` in the macOS Keychain, one item per account.
public struct CredentialStore: Sendable {
    public let service: String

    public init(service: String = "Lax Slack Account") {
        self.service = service
    }

    /// `account` identifies the item, e.g. `"<teamID>:<userID>"`.
    public func save(_ credentials: SlackCredentials, account: String) throws {
        let data = try JSONEncoder().encode(credentials)
        let status = SecItemUpdate(query(account: account) as CFDictionary,
                                   [kSecValueData: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query(account: account)
            item[kSecValueData] = data
            try check(SecItemAdd(item as CFDictionary, nil))
        } else {
            try check(status)
        }
    }

    public func load(account: String) throws -> SlackCredentials? {
        var item = query(account: account)
        item[kSecReturnData] = true
        item[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(item as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        try check(status)
        guard let data = result as? Data else { return nil }
        return try JSONDecoder().decode(SlackCredentials.self, from: data)
    }

    public func delete(account: String) throws {
        let status = SecItemDelete(query(account: account) as CFDictionary)
        if status != errSecItemNotFound { try check(status) }
    }

    private func query(account: String) -> [CFString: Any] {
        [kSecClass: kSecClassGenericPassword,
         kSecAttrService: service,
         kSecAttrAccount: account]
    }

    private func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else { throw CredentialStoreError.keychain(status) }
    }
}
