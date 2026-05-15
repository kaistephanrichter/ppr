import Foundation
import PDFKit
import UniformTypeIdentifiers

/// Holds a document received from an external source (Share Sheet, "Open with…").
/// Injected into the environment so any view can consume it.
@Observable
final class ImportQueue {
    var pendingDocument: Data?

    /// Tries to load a file URL delivered by the system (Share Sheet / Files).
    func receive(url: URL) {
        // Security-scoped access is needed for document picker URLs but NOT for
        // Share Sheet inbox URLs (already copied into the app sandbox). Call it
        // optimistically and only balance with stop if it succeeded.
        let didStartAccess = url.startAccessingSecurityScopedResource()
        defer { if didStartAccess { url.stopAccessingSecurityScopedResource() } }

        let ext = url.pathExtension.lowercased()
        if ext == "pdf", let data = try? Data(contentsOf: url) {
            pendingDocument = data
        } else if let image = UIImage(contentsOfFile: url.path),
                  let page = PDFPage(image: image)
        {
            let pdf = PDFDocument()
            pdf.insert(page, at: 0)
            pendingDocument = pdf.dataRepresentation()
        }
    }
}
