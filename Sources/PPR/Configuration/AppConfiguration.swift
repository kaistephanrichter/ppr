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
    var excludedTagIDs: Set<Int> = [] {
        didSet { UserDefaults.standard.set(Array(excludedTagIDs), forKey: "excludedTagIDs") }
    }

    var canConnect: Bool {
        let trimmedURL = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return URL(string: trimmedURL) != nil && !apiToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func loadFromKeychain() {
        let values = KeychainStore.load()
        serverURL = values.serverURL
        apiToken = values.apiToken
        excludedTagIDs = Set(UserDefaults.standard.array(forKey: "excludedTagIDs") as? [Int] ?? [])
        didLoadFromKeychain = true
    }

    func saveToKeychain() throws {
        try KeychainStore.save(serverURL: serverURL, apiToken: apiToken)
    }
}
