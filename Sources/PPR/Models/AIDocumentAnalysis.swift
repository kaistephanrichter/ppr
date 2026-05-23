import Foundation

/// Response from POST /manual/analyze
struct AIDocumentAnalysis: Decodable {
    let correspondent: String?
    let title: String?
    let tags: [String]?
    let documentType: String?
}
