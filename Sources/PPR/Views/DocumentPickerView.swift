import SwiftUI
import UniformTypeIdentifiers
import PDFKit

struct DocumentPickerView: UIViewControllerRepresentable {
    let onPick: (Data) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let types: [UTType] = [.pdf, .image, .jpeg, .png, .tiff, .heic, .heif]
        let vc = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        vc.allowsMultipleSelection = false
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, onCancel: onCancel)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (Data) -> Void
        let onCancel: () -> Void

        init(onPick: @escaping (Data) -> Void, onCancel: @escaping () -> Void) {
            self.onPick = onPick
            self.onCancel = onCancel
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { onCancel(); return }
            Task {
                guard url.startAccessingSecurityScopedResource() else { await MainActor.run { onCancel() }; return }
                defer { url.stopAccessingSecurityScopedResource() }

                let data: Data?
                if url.pathExtension.lowercased() == "pdf" {
                    data = try? Data(contentsOf: url)
                } else if let image = UIImage(contentsOfFile: url.path),
                          let page = PDFPage(image: image)
                {
                    let pdf = PDFDocument()
                    pdf.insert(page, at: 0)
                    data = pdf.dataRepresentation()
                } else {
                    data = nil
                }

                await MainActor.run {
                    if let data { onPick(data) } else { onCancel() }
                }
            }
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onCancel()
        }
    }
}
