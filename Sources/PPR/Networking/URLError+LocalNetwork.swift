import Foundation

extension URLError {
    /// True when the path is blocked because local-network access was not granted (iOS 14+).
    var isLocalNetworkProhibited: Bool {
        containsLocalNetworkProhibited(self as NSError)
    }

    /// Technical detail for user-visible error text (includes code).
    var localizedPaperlessDescription: String {
        let base = localizedDescription
        return "\(base) (URLError \(code.rawValue))"
    }
}

private func containsLocalNetworkProhibited(_ error: NSError) -> Bool {
    if let path = error.userInfo["_NSURLErrorNWPathKey"] as? String, path.contains("Local network prohibited") {
        return true
    }
    if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
        return containsLocalNetworkProhibited(underlying)
    }
    return false
}
