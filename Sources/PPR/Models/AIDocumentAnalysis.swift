import Foundation

/// Response from POST /manual/analyze
/// The server wraps suggestions inside a "document" key.
struct AIDocumentAnalysis: Decodable {
    let correspondent: String?
    let title: String?
    let tags: [String]?
    let documentType: String?

    // Top-level wrapper
    private enum TopKeys: String, CodingKey { case document }
    // Fields inside "document"
    private enum DocKeys: String, CodingKey {
        case correspondent, title, tags
        case documentType = "document_type"
    }

    init(from decoder: Decoder) throws {
        // Prefer nested structure {"document": {...}}; fall back to flat
        if let top = try? decoder.container(keyedBy: TopKeys.self),
           let doc = try? top.nestedContainer(keyedBy: DocKeys.self, forKey: .document) {
            title        = try? doc.decodeIfPresent(String.self, forKey: .title)
            correspondent = try? doc.decodeIfPresent(String.self, forKey: .correspondent)
            tags         = try? doc.decodeIfPresent([String].self, forKey: .tags)
            documentType = try? doc.decodeIfPresent(String.self, forKey: .documentType)
        } else {
            let flat = try decoder.container(keyedBy: DocKeys.self)
            title        = try? flat.decodeIfPresent(String.self, forKey: .title)
            correspondent = try? flat.decodeIfPresent(String.self, forKey: .correspondent)
            tags         = try? flat.decodeIfPresent([String].self, forKey: .tags)
            documentType = try? flat.decodeIfPresent(String.self, forKey: .documentType)
        }
    }

    init(correspondent: String? = nil, title: String? = nil,
         tags: [String]? = nil, documentType: String? = nil) {
        self.correspondent = correspondent
        self.title = title
        self.tags = tags
        self.documentType = documentType
    }
}
