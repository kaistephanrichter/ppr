/// Networking layer for the paperless-ai-next companion server.
/// Authenticates via `x-api-key` header.
import Foundation

enum AIServerAPI {

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        return URLSession(configuration: config)
    }()

    // MARK: - Helpers

    private static func buildURL(serverURL: String, path: String) throws -> URL {
        let trimmed = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.hasSuffix("/") ? trimmed : trimmed + "/"
        guard let baseURL = URL(string: base),
              let url = URL(string: path, relativeTo: baseURL) else {
            throw PaperlessAPIError.invalidServerURL
        }
        return url.absoluteURL
    }

    private static func request(url: URL, apiKey: String, method: String = "GET") -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.isEmpty {
            req.setValue(key, forHTTPHeaderField: "x-api-key")
        }
        return req
    }

    private static func perform<T: Decodable>(_ req: URLRequest, _ type: T.Type) async throws -> T {
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw PaperlessAPIError.transport("Missing HTTP response.")
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw PaperlessAPIError.unauthorized
        }
        guard (200..<300).contains(http.statusCode) else {
            let snippet = String(data: data.prefix(400), encoding: .utf8)
            throw PaperlessAPIError.httpResponse(code: http.statusCode, bodySnippet: snippet)
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw PaperlessAPIError.decodingFailed(error.localizedDescription)
        }
    }

    // MARK: - Health

    static func health(serverURL: String, apiKey: String) async throws -> AIServerStatus {
        let url = try buildURL(serverURL: serverURL, path: "health")
        let req = request(url: url, apiKey: apiKey)
        return try await perform(req, AIServerStatus.self)
    }

    // MARK: - Document Analysis

    /// Analyze document text with AI to suggest title, tags, document type, and correspondent.
    /// Endpoint: POST /manual/analyze
    static func analyzeDocument(
        content: String,
        existingTags: [String],
        serverURL: String,
        apiKey: String
    ) async throws -> AIDocumentAnalysis {
        let url = try buildURL(serverURL: serverURL, path: "manual/analyze")
        var req = request(url: url, apiKey: apiKey, method: "POST")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 60 // AI analysis can take a moment
        let body: [String: Any] = [
            "content": content,
            "existingTags": existingTags
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await perform(req, AIDocumentAnalysis.self)
    }

    // MARK: - RAG Search

    /// Hybrid semantic + keyword search across indexed documents.
    /// Endpoint: POST /api/rag/search
    static func ragSearch(
        query: String,
        serverURL: String,
        apiKey: String
    ) async throws -> [AIRagSearchResult] {
        let url = try buildURL(serverURL: serverURL, path: "api/rag/search")
        var req = request(url: url, apiKey: apiKey, method: "POST")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["query": query])
        return try await perform(req, [AIRagSearchResult].self)
    }

    // MARK: - RAG Ask

    /// Ask a free-form question grounded in the document archive.
    /// Endpoint: POST /api/rag/ask
    static func ragAsk(
        question: String,
        serverURL: String,
        apiKey: String
    ) async throws -> AIRagAnswer {
        let url = try buildURL(serverURL: serverURL, path: "api/rag/ask")
        var req = request(url: url, apiKey: apiKey, method: "POST")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["question": question])
        return try await perform(req, AIRagAnswer.self)
    }
}
