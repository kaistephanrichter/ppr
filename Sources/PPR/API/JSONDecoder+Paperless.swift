import Foundation

extension JSONDecoder {
    static func paperless() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { d in
            let c = try d.singleValueContainer()
            let raw = try c.decode(String.self)
            // Paperless-ngx sends microseconds (6 digits); ISO8601DateFormatter only
            // handles milliseconds (3 digits). Strip extra digits before parsing.
            var s = raw
            if let r = s.range(of: #"\.\d{4,}"#, options: .regularExpression) {
                s.replaceSubrange(r, with: "." + s[r].dropFirst().prefix(3))
            }
            let f1 = ISO8601DateFormatter()
            f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = f1.date(from: s) { return date }
            let f2 = ISO8601DateFormatter()
            f2.formatOptions = [.withInternetDateTime]
            if let date = f2.date(from: s) { return date }
            throw DecodingError.dataCorruptedError(
                in: c, debugDescription: "Unparseable date: \(raw)")
        }
        return decoder
    }
}
