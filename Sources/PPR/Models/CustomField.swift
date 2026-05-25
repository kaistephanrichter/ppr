import Foundation

/// Definition of a custom field configured on the Paperless-ngx server.
struct CustomField: Identifiable, Decodable, Hashable {
    let id: Int
    let name: String
    let dataType: String?
}

/// A custom field value attached to a specific document.
/// `field` is the CustomField.id; `value` is decoded from any JSON scalar.
struct DocumentCustomFieldValue: Decodable {
    let field: Int
    let value: String?

    enum CodingKeys: String, CodingKey { case field, value }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        field = try c.decode(Int.self, forKey: .field)

        // The value can be String, Int, Double, Bool, or null in the JSON.
        // Decode arrays (document_link type) are silently ignored.
        if (try? c.decodeNil(forKey: .value)) == true {
            value = nil
        } else if let b = try? c.decode(Bool.self, forKey: .value) {
            value = b ? String(localized: "custom_field.value.yes") : String(localized: "custom_field.value.no")
        } else if let i = try? c.decode(Int.self, forKey: .value) {
            value = String(i)
        } else if let d = try? c.decode(Double.self, forKey: .value) {
            value = d.truncatingRemainder(dividingBy: 1) == 0
                ? String(Int(d))
                : String(d)
        } else if let s = try? c.decode(String.self, forKey: .value) {
            value = s
        } else {
            value = nil
        }
    }
}
