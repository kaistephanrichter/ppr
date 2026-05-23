import Foundation

/// Single result from POST /api/rag/search
struct AIRagSearchResult: Decodable {
    let title: String
    let correspondent: String
    let date: String
    let score: Double
    let crossScore: Double
    let snippet: String
    let docId: Int?

    enum CodingKeys: String, CodingKey {
        case title, correspondent, date, score, snippet
        case crossScore = "cross_score"
        case docId = "doc_id"
    }
}

/// Response from POST /api/rag/ask
struct AIRagAnswer: Decodable {
    let answer: String?
    let sources: [AIRagSource]?
}

struct AIRagSource: Decodable {
    let docId: Int?
    let title: String?
    let snippet: String?

    enum CodingKeys: String, CodingKey {
        case title, snippet
        case docId = "doc_id"
    }
}
