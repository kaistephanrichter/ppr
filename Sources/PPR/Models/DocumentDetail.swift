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
    let customFields: [DocumentCustomFieldValue]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id               = try c.decode(Int.self,    forKey: .id)
        title            = try c.decode(String.self, forKey: .title)
        created          = try? c.decodeIfPresent(String.self, forKey: .created)
        documentType     = try? c.decodeIfPresent(Int.self,    forKey: .documentType)
        correspondent    = try? c.decodeIfPresent(Int.self,    forKey: .correspondent)
        tags             = (try? c.decode([Int].self, forKey: .tags)) ?? []
        content          = try? c.decodeIfPresent(String.self, forKey: .content)
        originalFileName = try? c.decodeIfPresent(String.self, forKey: .originalFileName)
        added            = try? c.decodeIfPresent(String.self, forKey: .added)
        customFields     = (try? c.decodeIfPresent([DocumentCustomFieldValue].self, forKey: .customFields)) ?? []
    }

    // NOTE: No explicit raw values — with convertFromSnakeCase the decoder
    // converts JSON "document_type" → "documentType" then matches against
    // CodingKey.stringValue. Raw values must therefore be camelCase.
    private enum CodingKeys: CodingKey {
        case id, title, created, tags, content, added, correspondent
        case documentType       // matches JSON "document_type"
        case originalFileName   // matches JSON "original_file_name"
        case customFields       // matches JSON "custom_fields"
    }
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
