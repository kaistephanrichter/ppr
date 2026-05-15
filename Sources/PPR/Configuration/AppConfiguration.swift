import Foundation
import Observation

@Observable
@MainActor
final class AppConfiguration {
    var serverURL: String = ""
    var apiToken: String = ""
    private(set) var didLoadFromKeychain = false

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
