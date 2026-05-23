import Foundation

struct AIServerStatus: Decodable {
    let status: String?
    let version: String?
    let message: String?

    var isHealthy: Bool {
        guard let s = status else { return false }
        return s.lowercased() == "ok" || s.lowercased() == "healthy"
    }
}
