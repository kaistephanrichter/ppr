import Foundation

/// Response from GET /api/rag/status (requires x-api-key authentication)
struct AIRagStatus: Decodable {
    let serverUp: Bool?
    let dataLoaded: Bool?
    let indexReady: Bool?
    let chromaReady: Bool?
    let bm25Ready: Bool?
    let aiStatus: String?
    let aiModel: String?
    let indexingStatus: AIRagIndexingStatus?

    var isFullyReady: Bool {
        (serverUp == true) && (indexReady == true)
    }
}

struct AIRagIndexingStatus: Decodable {
    let running: Bool?
    let lastIndexed: String?
    let documentsCount: Int?
    let upToDate: Bool?
    let message: String?
}

/// Single result from POST /api/rag/search
struct AIRagSearchResult: Decodable {
    let title: String
    let correspondent: String?
    let date: String?
    let score: Double
    let crossScore: Double?
    let snippet: String
    let docId: Int?
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
}
