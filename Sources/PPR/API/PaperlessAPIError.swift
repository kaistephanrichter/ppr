import Foundation

enum PaperlessAPIError: LocalizedError, Equatable, Sendable {
    case invalidServerURL
    case missingCredentials
    case unauthorized
    case httpResponse(code: Int, bodySnippet: String?)
    case decodingFailed(String)
    case localNetworkBlocked
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .invalidServerURL:
            return String(localized: "error.invalid_server_url")
        case .missingCredentials:
            return String(localized: "error.missing_credentials")
        case .unauthorized:
            return String(localized: "error.unauthorized")
        case .httpResponse(let code, let snippet):
            var s = "Der Server antwortet mit HTTP \(code)."
            if let snippet, !snippet.isEmpty {
                s += "\n\nAntwort (Auszug):\n\(snippet)"
            } else if code >= 500 {
                s += " (Serverfehler – Logs auf dem Paperless-Host prüfen.)"
            }
            return s
        case .decodingFailed(let detail):
            return "Could not read the server response (\(detail))."
        case .localNetworkBlocked:
            return String(localized: "error.local_network_blocked")
        case .transport(let detail):
            return detail
        }
    }
}
