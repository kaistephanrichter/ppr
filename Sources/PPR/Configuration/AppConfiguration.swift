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

    /// AI companion server (paperless-ai-next) URL — optional
    var aiServerURL: String = ""

    /// API key for the AI server (x-api-key header)
    var aiApiKey: String = ""

    /// Whether semantic search via the AI server is enabled
    var aiSemanticSearchEnabled: Bool = false {
        didSet { UserDefaults.standard.set(aiSemanticSearchEnabled, forKey: "aiSemanticSearchEnabled") }
    }

    var hasAIServer: Bool {
        let trimmed = aiServerURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return URL(string: trimmed) != nil && !trimmed.isEmpty
    }

    var hasAIServerWithKey: Bool {
        hasAIServer && !aiApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

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
        aiServerURL = KeychainStore.loadAIServerURL()
        aiApiKey = KeychainStore.loadAIApiKey()
        excludedTagIDs = Set(UserDefaults.standard.array(forKey: "excludedTagIDs") as? [Int] ?? [])
        aiSemanticSearchEnabled = UserDefaults.standard.bool(forKey: "aiSemanticSearchEnabled")
        didLoadFromKeychain = true
    }

    func saveToKeychain() throws {
        try KeychainStore.save(serverURL: serverURL, apiToken: apiToken)
    }

    func saveAIServerURL() throws {
        try KeychainStore.saveAIServerURL(aiServerURL)
    }

    func saveAIApiKey() throws {
        try KeychainStore.saveAIApiKey(aiApiKey)
    }
}
