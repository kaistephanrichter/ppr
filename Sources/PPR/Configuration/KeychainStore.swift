import Foundation
import Security

enum KeychainStore {
    private static let service = "app.ppr.PPR.credentials"

    private enum Account: String {
        case serverURL
        case apiToken
        case aiServerURL
        case aiApiKey
    }

    private enum KeychainError: Error {
        case unexpectedStatus(OSStatus)
    }

    static func load() -> (serverURL: String, apiToken: String) {
        (loadString(.serverURL) ?? "", loadString(.apiToken) ?? "")
    }

    static func save(serverURL: String, apiToken: String) throws {
        try saveString(serverURL, account: .serverURL)
        try saveString(apiToken, account: .apiToken)
    }

    static func loadAIServerURL() -> String {
        loadString(.aiServerURL) ?? ""
    }

    static func saveAIServerURL(_ url: String) throws {
        try saveString(url, account: .aiServerURL)
    }

    static func loadAIApiKey() -> String {
        loadString(.aiApiKey) ?? ""
    }

    static func saveAIApiKey(_ key: String) throws {
        try saveString(key, account: .aiApiKey)
    }

    private static func saveString(_ value: String, account: Account) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue,
        ]

        let updateAttributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, updateAttributes as CFDictionary)
        if updateStatus == errSecSuccess { return }

        // Item did not exist yet — add it.
        var addAttributes = query
        addAttributes[kSecValueData as String] = data
        addAttributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(addAttributes as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw KeychainError.unexpectedStatus(addStatus) }
    }

    private static func loadString(_ account: Account) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
