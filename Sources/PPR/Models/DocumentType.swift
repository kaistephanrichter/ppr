/// Models for document classification metadata from the paperless-ngx API.
/// Both DocumentType and Correspondent include an optional document_count
/// returned by the API to show usage frequency in filter views.
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

struct StoragePath: Identifiable, Decodable, Hashable {
    let id: Int
    let name: String
    let path: String?
    let documentCount: Int?

    enum CodingKeys: String, CodingKey {
        case id, name, path
        case documentCount = "document_count"
    }
}
