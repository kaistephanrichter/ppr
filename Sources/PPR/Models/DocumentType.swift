import Foundation

struct DocumentType: Identifiable, Decodable, Hashable {
    let id: Int
    let name: String
    let documentCount: Int?

    enum CodingKeys: String, CodingKey {
        case id, name
        case documentCount = "document_count"
    }
}

struct Correspondent: Identifiable, Decodable, Hashable {
    let id: Int
    let name: String
    let documentCount: Int?

    enum CodingKeys: String, CodingKey {
        case id, name
        case documentCount = "document_count"
    }
}
