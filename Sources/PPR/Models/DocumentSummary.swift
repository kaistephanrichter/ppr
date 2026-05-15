import Foundation

struct DocumentSummary: Identifiable, Decodable, Hashable {
    let id: Int
    let title: String
    let created: String?
    let documentType: Int?
    let correspondent: Int?
    let tags: [Int]
}

struct PaginatedEnvelope<T: Decodable>: Decodable {
    let count: Int
    let next: String?
    let previous: String?
    let results: [T]
}

struct TagSummary: Identifiable, Decodable, Hashable {
    let id: Int
    let name: String
    let color: String?
    let documentCount: Int?

    enum CodingKeys: String, CodingKey {
        case id, name, color
        case documentCount = "document_count"
    }
}
