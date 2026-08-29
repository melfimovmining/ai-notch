import Foundation
import Security

/// Where the admin credential and the spend budget live.
///
/// The key goes in the Keychain rather than `UserDefaults`, because an Admin
/// API key is not a read-only credential: the same key can list and deactivate
/// the organisation's API keys, change member roles, and remove members. A
/// plist in `~/Library/Preferences` is world-readable to anything running as
/// the user; the Keychain item is at least scoped to this app.
enum AdminCredentials {
    private static let service = "com.sidenotch.ainotch.adminkey"
    private static let account = "default"

    // MARK: - The key

    static var key: String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let string = String(data: data, encoding: .utf8),
              !string.isEmpty
        else { return nil }
        return string
    }

    static var hasKey: Bool { key != nil }

    /// Stores the key, replacing any existing one. Passing nil or "" clears it.
    @discardableResult
    static func setKey(_ newKey: String?) -> Bool {
        let trimmed = newKey?.trimmingCharacters(in: .whitespacesAndNewlines)

        SecItemDelete(baseQuery as CFDictionary)
        guard let trimmed, !trimmed.isEmpty else { return true }

        var query = baseQuery
        query[kSecValueData as String] = Data(trimmed.utf8)
        // Available without unlocking, but never leaves this Mac in a backup.
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    // MARK: - The credit balance anchor

    private static let balanceKey = "creditBalanceUSD"
    private static let anchorKey = "creditBalanceAnchor"

    /// The balance you last read off the Console, in dollars.
    ///
    /// Anthropic publishes no endpoint for the credit balance — not in the
    /// Admin API reference, and the Console renders it server-side behind a
    /// session cookie — so the app cannot read it or notice a top-up. This is
    /// the anchor it counts down from instead.
    static var creditBalance: Double? {
        get {
            let stored = UserDefaults.standard.double(forKey: balanceKey)
            return stored > 0 ? stored : nil
        }
        set {
            guard let newValue, newValue > 0 else {
                UserDefaults.standard.removeObject(forKey: balanceKey)
                UserDefaults.standard.removeObject(forKey: anchorKey)
                return
            }
            UserDefaults.standard.set(newValue, forKey: balanceKey)
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: anchorKey)
        }
    }

    /// When that balance was recorded. Spend is counted from this point on.
    static var balanceAnchor: Date? {
        let stored = UserDefaults.standard.double(forKey: anchorKey)
        return stored > 0 ? Date(timeIntervalSince1970: stored) : nil
    }

    static var hasBalance: Bool { creditBalance != nil }
}
