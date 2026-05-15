import Foundation

struct DocumentDetail: Identifiable, Decodable {
    let id: Int
    let title: String
    let created: String?
    let documentType: Int?
    let correspondent: Int?
    let tags: [Int]
    let content: String?
    let originalFileName: String?
    let added: String?
}

struct DocumentPatch: Encodable {
    let title: String
    let created: String?
    let documentType: Int?
    let correspondent: Int?
    let tags: [Int]

    enum CodingKeys: String, CodingKey {
        case title, created, tags, correspondent
        case documentType = "document_type"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(title, forKey: .title)
        try c.encode(created, forKey: .created)
        try c.encode(documentType, forKey: .documentType)
        try c.encode(correspondent, forKey: .correspondent)
        try c.encode(tags, forKey: .tags)
    }
}
