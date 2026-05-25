/// Networking layer for the paperless-ngx REST API.
/// Handles authentication, pagination, document CRUD, uploads, and metadata endpoints.
import Foundation

enum PaperlessAPI {
    private static let decoder: JSONDecoder = .paperless()

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 60
        return URLSession(configuration: configuration)
    }()

    private static func normalizedBaseURLString(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard URL(string: trimmed) != nil else { return nil }
        return trimmed.hasSuffix("/") ? trimmed : trimmed + "/"
    }

    private static func buildURL(serverURL: String, path: String) throws -> URL {
        guard let baseString = normalizedBaseURLString(serverURL) else {
            throw PaperlessAPIError.invalidServerURL
        }
        guard let base = URL(string: baseString) else {
            throw PaperlessAPIError.invalidServerURL
        }
        // Strip only a leading slash; keep the trailing slash so Django doesn't
        // issue a 301 redirect (which causes URLSession to drop the Authorization header).
        let normalizedPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        guard let url = URL(string: normalizedPath, relativeTo: base) else {
            throw PaperlessAPIError.invalidServerURL
        }
        return url.absoluteURL
    }

    private static func authorizedRequest(url: URL, token: String) throws -> URLRequest {
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty else { throw PaperlessAPIError.missingCredentials }

        var request = URLRequest(url: url)
        request.setValue("Token \(trimmedToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let acceptLanguage = Locale.preferredLanguages.first, !acceptLanguage.isEmpty {
            request.setValue(acceptLanguage, forHTTPHeaderField: "Accept-Language")
        }
        request.timeoutInterval = 30
        return request
    }

    /// Transport-layer retries (timeouts, dropped connections). HTTP retries for transient server/rate-limit codes.
    private static let maxRequestAttempts = 3

    private static func isRetryableURLErrorCode(_ code: URLError.Code) -> Bool {
        switch code {
        case .timedOut, .networkConnectionLost, .cannotConnectToHost, .dnsLookupFailed:
            return true
        case .notConnectedToInternet, .cannotFindHost:
            return true
        default:
            return false
        }
    }

    private static func isRetryableHTTPStatusCode(_ code: Int) -> Bool {
        switch code {
        case 408, 429, 502, 503, 504:
            return true
        default:
            return false
        }
    }

    private static func sleepBeforeRetry(afterAttempt attempt: Int) async throws {
        try Task.checkCancellation()
        // Exponential backoff: 2^attempt seconds, max 8s (here at most 1s then 2s before 2nd/3rd try).
        let seconds = min(8, 1 << min(attempt, 3))
        try await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
    }

    private static func perform<T: Decodable>(_ request: URLRequest, _ type: T.Type) async throws -> T {
        await LocalNetworkAccess.warmUpBonjourBrowse()

        for attempt in 0 ..< maxRequestAttempts {
            try Task.checkCancellation()

            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await session.data(for: request)
            } catch {
                if error is CancellationError || Task.isCancelled { throw error }
                if let urlError = error as? URLError, urlError.code == .cancelled { throw CancellationError() }
                if let urlError = error as? URLError, urlError.isLocalNetworkProhibited {
                    throw PaperlessAPIError.localNetworkBlocked
                }
                if let urlError = error as? URLError, isRetryableURLErrorCode(urlError.code),
                   attempt < maxRequestAttempts - 1
                {
                    try await sleepBeforeRetry(afterAttempt: attempt)
                    continue
                }
                if let urlError = error as? URLError {
                    throw PaperlessAPIError.transport(urlError.localizedPaperlessDescription)
                }
                throw PaperlessAPIError.transport(error.localizedDescription)
            }

            guard let http = response as? HTTPURLResponse else {
                throw PaperlessAPIError.transport("Missing HTTP response.")
            }

            if http.statusCode == 401 || http.statusCode == 403 {
                throw PaperlessAPIError.unauthorized
            }

            if (200 ..< 300).contains(http.statusCode) {
                // Paperless redirects unauthenticated requests to the login page with HTTP 200
                // instead of returning 401. Detect this by checking for the login form JSON.
                if let text = String(data: data.prefix(64), encoding: .utf8),
                   text.contains("\"login\"") || text.contains("\"password\"")
                {
                    throw PaperlessAPIError.unauthorized
                }
                do {
                    return try decoder.decode(T.self, from: data)
                } catch {
                    if error is CancellationError || Task.isCancelled { throw error }
                    throw PaperlessAPIError.decodingFailed(error.localizedDescription)
                }
            }

            if isRetryableHTTPStatusCode(http.statusCode), attempt < maxRequestAttempts - 1 {
                try await sleepBeforeRetry(afterAttempt: attempt)
                continue
            }

            let snippet = String(data: data.prefix(800), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw PaperlessAPIError.httpResponse(code: http.statusCode, bodySnippet: snippet)
        }

        throw PaperlessAPIError.transport("Request failed after \(maxRequestAttempts) attempts.")
    }

    /// Human-readable message plus technical lines for on-screen diagnostics.
    static func formattedUserError(_ error: Error) -> String? {
        if error is CancellationError { return nil }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain, ns.code == URLError.cancelled.rawValue { return nil }

        let headline: String
        if let le = error as? LocalizedError, let d = le.errorDescription, !d.isEmpty {
            headline = d
        } else {
            headline = error.localizedDescription
        }

        var lines: [String] = [headline, "", "— Technisch —"]
        lines.append("\(ns.domain) [\(ns.code)]")
        if let url = ns.userInfo["NSErrorFailingURLStringKey"] as? String {
            lines.append("URL: \(url)")
        }
        if let path = ns.userInfo["_NSURLErrorNWPathKey"] as? String {
            lines.append("NWPath: \(path)")
        }
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError {
            lines.append(
                "Underlying: \(underlying.domain) [\(underlying.code)] — \(underlying.localizedDescription)"
            )
        }
        return lines.joined(separator: "\n")
    }

    /// Single-attempt perform without retries, used for fast connectivity probing.
    private static func performOnce<T: Decodable>(_ request: URLRequest, _ type: T.Type) async throws -> T {
        await LocalNetworkAccess.warmUpBonjourBrowse()
        try Task.checkCancellation()

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            if error is CancellationError || Task.isCancelled { throw error }
            if let urlError = error as? URLError, urlError.code == .cancelled { throw CancellationError() }
            if let urlError = error as? URLError, urlError.isLocalNetworkProhibited {
                throw PaperlessAPIError.localNetworkBlocked
            }
            if let urlError = error as? URLError {
                throw PaperlessAPIError.transport(urlError.localizedPaperlessDescription)
            }
            throw PaperlessAPIError.transport(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw PaperlessAPIError.transport("Missing HTTP response.")
        }
        if http.statusCode == 401 || http.statusCode == 403 { throw PaperlessAPIError.unauthorized }
        guard (200 ..< 300).contains(http.statusCode) else {
            let snippet = String(data: data.prefix(800), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw PaperlessAPIError.httpResponse(code: http.statusCode, bodySnippet: snippet)
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            if error is CancellationError || Task.isCancelled { throw error }
            throw PaperlessAPIError.decodingFailed(error.localizedDescription)
        }
    }

    /// Lightweight connectivity check (fetches 1 tag, no retries).
    static func connectivityCheck(serverURL: String, token: String) async throws {
        var components = URLComponents(
            url: try buildURL(serverURL: serverURL, path: "api/tags/"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "page_size", value: "1"),
        ]
        guard let url = components?.url else { throw PaperlessAPIError.invalidServerURL }
        let request = try authorizedRequest(url: url, token: token)
        _ = try await performOnce(request, PaginatedEnvelope<TagSummary>.self)
    }

    static func aiServerHealth(serverURL: String) async throws -> AIServerStatus {
        let url = try buildURL(serverURL: serverURL, path: "health")
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10
        return try await performOnce(request, AIServerStatus.self)
    }

    static func status(serverURL: String, token: String) async throws -> RemoteStatus {
        let url = try buildURL(serverURL: serverURL, path: "api/status/")
        let request = try authorizedRequest(url: url, token: token)
        return try await perform(request, RemoteStatus.self)
    }

    static func statistics(serverURL: String, token: String) async throws -> RemoteStatistics {
        let url = try buildURL(serverURL: serverURL, path: "api/statistics/")
        let request = try authorizedRequest(url: url, token: token)
        return try await perform(request, RemoteStatistics.self)
    }

    static func documents(
        serverURL: String, token: String,
        page: Int, pageSize: Int,
        search: String = "",
        tagIDs: [Int] = [],
        correspondentID: Int? = nil,
        documentTypeID: Int? = nil,
        storagePathID: Int? = nil,
        ordering: String? = nil
    ) async throws -> PaginatedEnvelope<DocumentSummary> {
        var components = URLComponents(
            url: try buildURL(serverURL: serverURL, path: "api/documents/"),
            resolvingAgainstBaseURL: false
        )
        var items: [URLQueryItem] = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "page_size", value: String(pageSize)),
        ]
        if !search.isEmpty { items.append(URLQueryItem(name: "search", value: search)) }
        for id in tagIDs { items.append(URLQueryItem(name: "tags__id__all", value: String(id))) }
        if let id = correspondentID { items.append(URLQueryItem(name: "correspondent__id", value: String(id))) }
        if let id = documentTypeID { items.append(URLQueryItem(name: "document_type__id", value: String(id))) }
        if let id = storagePathID { items.append(URLQueryItem(name: "storage_path__id", value: String(id))) }
        if let ordering { items.append(URLQueryItem(name: "ordering", value: ordering)) }
        components?.queryItems = items
        guard let url = components?.url else { throw PaperlessAPIError.invalidServerURL }
        let request = try authorizedRequest(url: url, token: token)
        return try await perform(request, PaginatedEnvelope<DocumentSummary>.self)
    }

    /// Fetch a specific set of documents by their IDs (for semantic search results).
    static func documentsByIDs(
        ids: [Int],
        serverURL: String,
        token: String
    ) async throws -> [DocumentSummary] {
        guard !ids.isEmpty else { return [] }
        var components = URLComponents(
            url: try buildURL(serverURL: serverURL, path: "api/documents/"),
            resolvingAgainstBaseURL: false
        )
        // Paperless uses a single comma-separated id__in value, not repeated params.
        let items: [URLQueryItem] = [
            URLQueryItem(name: "page_size", value: String(ids.count)),
            URLQueryItem(name: "id__in", value: ids.map(String.init).joined(separator: ",")),
        ]
        components?.queryItems = items
        guard let url = components?.url else { throw PaperlessAPIError.invalidServerURL }
        let request = try authorizedRequest(url: url, token: token)
        let envelope = try await perform(request, PaginatedEnvelope<DocumentSummary>.self)
        return envelope.results
    }

    static func document(id: Int, serverURL: String, token: String) async throws -> DocumentDetail {
        let url = try buildURL(serverURL: serverURL, path: "api/documents/\(id)/")
        let request = try authorizedRequest(url: url, token: token)
        return try await perform(request, DocumentDetail.self)
    }

    static func updateDocument(
        id: Int, title: String, created: String?,
        documentType: Int?, correspondent: Int?, tags: [Int],
        serverURL: String, token: String
    ) async throws -> DocumentDetail {
        let url = try buildURL(serverURL: serverURL, path: "api/documents/\(id)/")
        var request = try authorizedRequest(url: url, token: token)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let patch = DocumentPatch(title: title, created: created,
                                  documentType: documentType, correspondent: correspondent, tags: tags)
        request.httpBody = try JSONEncoder().encode(patch)
        return try await perform(request, DocumentDetail.self)
    }

    static func documentThumb(id: Int, serverURL: String, token: String) async throws -> Data {
        let url = try buildURL(serverURL: serverURL, path: "api/documents/\(id)/thumb/")
        var request = try authorizedRequest(url: url, token: token)
        request.setValue("image/jpeg, image/*", forHTTPHeaderField: "Accept")
        return try await performData(request)
    }

    static func documentPreview(id: Int, serverURL: String, token: String) async throws -> Data {
        let url = try buildURL(serverURL: serverURL, path: "api/documents/\(id)/preview/")
        var request = try authorizedRequest(url: url, token: token)
        request.setValue("application/pdf, */*", forHTTPHeaderField: "Accept")
        return try await performData(request)
    }

    private static func performData(_ request: URLRequest) async throws -> Data {
        await LocalNetworkAccess.warmUpBonjourBrowse()
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw PaperlessAPIError.transport("Missing HTTP response.")
        }
        if http.statusCode == 401 || http.statusCode == 403 { throw PaperlessAPIError.unauthorized }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw PaperlessAPIError.httpResponse(code: http.statusCode, bodySnippet: nil)
        }
        return data
    }


    static func tags(serverURL: String, token: String, pageSize: Int = 500) async throws -> [TagSummary] {
        var components = URLComponents(
            url: try buildURL(serverURL: serverURL, path: "api/tags/"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "page_size", value: String(pageSize)),
        ]
        guard let url = components?.url else { throw PaperlessAPIError.invalidServerURL }
        let request = try authorizedRequest(url: url, token: token)
        let page = try await perform(request, PaginatedEnvelope<TagSummary>.self)
        return page.results
    }

    static func documentTypes(serverURL: String, token: String, pageSize: Int = 500) async throws -> [DocumentType] {
        var components = URLComponents(
            url: try buildURL(serverURL: serverURL, path: "api/document_types/"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "page_size", value: String(pageSize))]
        guard let url = components?.url else { throw PaperlessAPIError.invalidServerURL }
        let request = try authorizedRequest(url: url, token: token)
        let page = try await perform(request, PaginatedEnvelope<DocumentType>.self)
        return page.results
    }

    static func correspondents(serverURL: String, token: String, pageSize: Int = 500) async throws -> [Correspondent] {
        var components = URLComponents(
            url: try buildURL(serverURL: serverURL, path: "api/correspondents/"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "page_size", value: String(pageSize))]
        guard let url = components?.url else { throw PaperlessAPIError.invalidServerURL }
        let request = try authorizedRequest(url: url, token: token)
        let page = try await perform(request, PaginatedEnvelope<Correspondent>.self)
        return page.results
    }

    static func storagePaths(serverURL: String, token: String, pageSize: Int = 500) async throws -> [StoragePath] {
        var components = URLComponents(
            url: try buildURL(serverURL: serverURL, path: "api/storage_paths/"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "page_size", value: String(pageSize))]
        guard let url = components?.url else { throw PaperlessAPIError.invalidServerURL }
        let request = try authorizedRequest(url: url, token: token)
        let page = try await perform(request, PaginatedEnvelope<StoragePath>.self)
        return page.results
    }

    static func customFields(serverURL: String, token: String, pageSize: Int = 500) async throws -> [CustomField] {
        var components = URLComponents(
            url: try buildURL(serverURL: serverURL, path: "api/custom_fields/"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "page_size", value: String(pageSize))]
        guard let url = components?.url else { throw PaperlessAPIError.invalidServerURL }
        let request = try authorizedRequest(url: url, token: token)
        let page = try await perform(request, PaginatedEnvelope<CustomField>.self)
        return page.results
    }

    private static func jsonPostRequest(url: URL, token: String, body: [String: String]) throws -> URLRequest {
        var request = try authorizedRequest(url: url, token: token)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    static func createTag(name: String, serverURL: String, token: String) async throws -> TagSummary {
        let url = try buildURL(serverURL: serverURL, path: "api/tags/")
        let request = try jsonPostRequest(url: url, token: token, body: ["name": name])
        return try await perform(request, TagSummary.self)
    }

    static func createCorrespondent(name: String, serverURL: String, token: String) async throws -> Correspondent {
        let url = try buildURL(serverURL: serverURL, path: "api/correspondents/")
        let request = try jsonPostRequest(url: url, token: token, body: ["name": name])
        return try await perform(request, Correspondent.self)
    }

    static func createDocumentType(name: String, serverURL: String, token: String) async throws -> DocumentType {
        let url = try buildURL(serverURL: serverURL, path: "api/document_types/")
        let request = try jsonPostRequest(url: url, token: token, body: ["name": name])
        return try await perform(request, DocumentType.self)
    }

    static func uploadDocument(
        pdfData: Data,
        filename: String,
        title: String,
        created: String?,
        documentType: Int?,
        correspondent: Int?,
        tags: [Int],
        storagePath: Int?,
        serverURL: String,
        token: String
    ) async throws {
        let url = try buildURL(serverURL: serverURL, path: "api/documents/post_document/")
        var request = try authorizedRequest(url: url, token: token)
        request.httpMethod = "POST"

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"document\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/pdf\r\n\r\n".data(using: .utf8)!)
        body.append(pdfData)
        body.append("\r\n".data(using: .utf8)!)

        if !title.isEmpty { field("title", title) }
        if let created { field("created", created) }
        if let documentType { field("document_type", String(documentType)) }
        if let correspondent { field("correspondent", String(correspondent)) }
        for tag in tags { field("tags", String(tag)) }
        if let storagePath { field("storage_path", String(storagePath)) }

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        // Upload response is a plain task ID string — we just need success/failure.
        struct TaskResponse: Decodable { let taskId: String? }
        _ = try? await perform(request, TaskResponse.self)
    }
}
