import SwiftUI
import PhotosUI
import PDFKit

struct PhotoPickerView: UIViewControllerRepresentable {
    let onPick: (Data) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.selectionLimit = 0
        config.filter = .images
        let vc = PHPickerViewController(configuration: config)
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, onCancel: onCancel)
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPick: (Data) -> Void
        let onCancel: () -> Void

        init(onPick: @escaping (Data) -> Void, onCancel: @escaping () -> Void) {
            self.onPick = onPick
            self.onCancel = onCancel
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard !results.isEmpty else { onCancel(); return }

            Task {
                let pdf = PDFDocument()
                for result in results {
                    guard result.itemProvider.canLoadObject(ofClass: UIImage.self) else { continue }
                    let image: UIImage? = await withCheckedContinuation { continuation in
                        result.itemProvider.loadObject(ofClass: UIImage.self) { object, _ in
                            continuation.resume(returning: object as? UIImage)
                        }
                    }
                    if let image, let page = PDFPage(image: image) {
                        pdf.insert(page, at: pdf.pageCount)
                    }
                }
                let data = pdf.dataRepresentation()
                await MainActor.run {
                    if let data, pdf.pageCount > 0 {
                        onPick(data)
                    } else {
                        onCancel()
                    }
                }
            }
        }
    }
}
