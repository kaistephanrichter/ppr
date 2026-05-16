/// Observable app configuration holding server URL and API token.
/// Persists credentials in the iOS Keychain via KeychainStore.
import Foundation
import Observation

@Observable
@MainActor
final class AppConfiguration {
    var serverURL: String = ""
    var apiToken: String = ""
    private(set) var didLoadFromKeychain = false

    /// Tag IDs to exclude from the "top tags" filter list
    var excludedTagIDs: Set<Int> {
        get { Set(UserDefaults.standard.array(forKey: "excludedTagIDs") as? [Int] ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: "excludedTagIDs") }
    }

    var canConnect: Bool {
        let trimmedURL = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return URL(string: trimmedURL) != nil && !apiToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func loadFromKeychain() {
        let values = KeychainStore.load()
        serverURL = values.serverURL
        apiToken = values.apiToken
        didLoadFromKeychain = true
    }

    func saveToKeychain() throws {
        try KeychainStore.save(serverURL: serverURL, apiToken: apiToken)
    }
}
