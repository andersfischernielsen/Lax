import Foundation
import Security

public enum CredentialStoreError: Error, Equatable {
    case keychain(OSStatus)
}

/// Keeps `SlackAccount`s in the macOS Keychain, one item per account.
public struct CredentialStore: Sendable {
    public let service: String

    public init(service: String = "Lax Slack Account") {
        self.service = service
    }

    public func save(_ account: SlackAccount) throws {
        let data = try JSONEncoder().encode(account)
        let status = SecItemUpdate(query(account: account.id) as CFDictionary,
                                   [kSecValueData: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query(account: account.id)
            item[kSecValueData] = data
            try check(SecItemAdd(item as CFDictionary, nil))
        } else {
            try check(status)
        }
    }

    public func load(id: String) throws -> SlackAccount? {
        var item = query(account: id)
        item[kSecReturnData] = true
        item[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(item as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        try check(status)
        guard let data = result as? Data else { return nil }
        return try JSONDecoder().decode(SlackAccount.self, from: data)
    }

    /// Every saved account, sorted by team name.
    public func loadAll() throws -> [SlackAccount] {
        // The file-based keychain can't return data for many items at once,
        // so list the item names first and load each one.
        let item: [CFString: Any] = [kSecClass: kSecClassGenericPassword,
                                     kSecAttrService: service,
                                     kSecReturnAttributes: true,
                                     kSecMatchLimit: kSecMatchLimitAll]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(item as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        try check(status)
        let ids = (result as? [[CFString: Any]] ?? []).compactMap { $0[kSecAttrAccount] as? String }
        return try ids.compactMap(load(id:)).sorted { $0.teamName < $1.teamName }
    }

    public func delete(id: String) throws {
        let status = SecItemDelete(query(account: id) as CFDictionary)
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
