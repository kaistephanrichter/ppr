/// Document capture tab. Provides camera scanner, photo picker, and file import.
/// Shows status icons (idle/uploading/success/error) and presents metadata form before upload.
import SwiftUI
import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import PDFKit

private struct ScannedDocument: Identifiable {
    let id = UUID()
    let data: Data
}

struct CaptureView: View {
    @Environment(AppConfiguration.self) private var configuration
    @Environment(ImportQueue.self) private var importQueue
    @Environment(NetworkMonitor.self) private var networkMonitor

    @State private var showScanner = false
    @State private var showPhotoPicker = false
    @State private var showDocumentPicker = false
    @State private var scannedDocument: ScannedDocument?

    // Capture settings (persisted)
    @AppStorage("captureQuickUpload") private var quickUpload = false
    @AppStorage("captureTorchEnabled") private var torchEnabled = false
    @AppStorage("captureEnhancementEnabled") private var enhancementEnabled = false
    @State private var showSettings = false

    // Upload state
    @State private var isUploading = false
    @State private var uploadSuccessMessage: String?
    @State private var uploadError: String?
    @State private var showConnectionErrorDetail = false

    private var anySettingActive: Bool { quickUpload || torchEnabled || enhancementEnabled }

    var body: some View {
        NavigationStack {
            Group {
                if !configuration.canConnect {
                    ContentUnavailableView(
                        String(localized: "server.not_configured.title"),
                        systemImage: "link.badge.plus",
                        description: Text(String(localized: "server.not_configured.description"))
                    )
                } else {
                    captureContent
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "slider.horizontal.3")
                            .foregroundStyle(anySettingActive ? Color.accentColor : Color.primary)
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showScanner) {
            DocumentScannerView {
                handleCaptured(data: $0)
                showScanner = false
            } onCancel: {
                showScanner = false
            }
            .ignoresSafeArea()
            .onAppear { setTorch(torchEnabled) }
            .onDisappear { setTorch(false) }
        }
        .fullScreenCover(isPresented: $showPhotoPicker) {
            PhotoPickerView {
                handleCaptured(data: $0)
                showPhotoPicker = false
            } onCancel: {
                showPhotoPicker = false
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showDocumentPicker) {
            DocumentPickerView {
                handleCaptured(data: $0)
                showDocumentPicker = false
            } onCancel: {
                showDocumentPicker = false
            }
        }
        .sheet(item: $scannedDocument) { doc in
            CaptureMetadataView(pdfData: doc.data) {
                uploadSuccessMessage = String(localized: "capture.uploaded")
                scannedDocument = nil
            }
            .environment(configuration)
        }
        .sheet(isPresented: $showSettings) {
            CaptureSettingsSheet(
                quickUpload: $quickUpload,
                torchEnabled: $torchEnabled,
                enhancementEnabled: $enhancementEnabled
            )
            .presentationDetents([.medium])
        }
        .onChange(of: importQueue.pendingDocument) { _, newValue in
            if let data = newValue {
                handleCaptured(data: data)
                importQueue.pendingDocument = nil
            }
        }
        .task {
            if let data = importQueue.pendingDocument {
                handleCaptured(data: data)
                importQueue.pendingDocument = nil
            }
        }
    }

    // MARK: - Logic

    private func handleCaptured(data: Data) {
        uploadSuccessMessage = nil
        uploadError = nil
        let processed = enhancementEnabled ? enhancePDF(data) : data
        if quickUpload {
            Task { await directUpload(data: processed) }
        } else {
            scannedDocument = ScannedDocument(data: processed)
        }
    }

    private func setTorch(_ on: Bool) {
        guard let device = AVCaptureDevice.default(for: .video),
              device.hasTorch else { return }
        try? device.lockForConfiguration()
        device.torchMode = on ? .on : .off
        device.unlockForConfiguration()
    }

    private func directUpload(data: Data) async {
        isUploading = true
        defer { isUploading = false }
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        let dateString = df.string(from: Date())
        do {
            try await PaperlessAPI.uploadDocument(
                pdfData: data,
                filename: "scan_\(dateString).pdf",
                title: "",
                created: dateString,
                documentType: nil,
                correspondent: nil,
                tags: [],
                serverURL: configuration.serverURL,
                token: configuration.apiToken
            )
            uploadSuccessMessage = String(localized: "capture.uploaded")
        } catch {
            uploadError = PaperlessAPI.formattedUserError(error)
                ?? (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }

    /// Renders each PDF page through a CIFilter pipeline (contrast + sharpen)
    /// to improve OCR accuracy on low-quality scans.
    private func enhancePDF(_ data: Data) -> Data {
        guard let source = PDFDocument(data: data) else { return data }
        let output = PDFDocument()
        let context = CIContext()
        for i in 0 ..< source.pageCount {
            guard let page = source.page(at: i) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            let renderer = UIGraphicsImageRenderer(size: bounds.size)
            let uiImage = renderer.image { ctx in
                UIColor.white.setFill()
                ctx.fill(bounds)
                ctx.cgContext.translateBy(x: 0, y: bounds.height)
                ctx.cgContext.scaleBy(x: 1, y: -1)
                page.draw(with: .mediaBox, to: ctx.cgContext)
            }
            guard let ciImage = CIImage(image: uiImage) else {
                if let p = PDFPage(image: uiImage) { output.insert(p, at: output.pageCount) }
                continue
            }
            let controls = CIFilter.colorControls()
            controls.inputImage = ciImage
            controls.contrast = 1.15
            controls.saturation = 0
            controls.brightness = 0.02
            let sharpen = CIFilter.sharpenLuminance()
            sharpen.inputImage = controls.outputImage ?? ciImage
            sharpen.sharpness = 0.6
            sharpen.radius = 1.5
            let enhanced: UIImage
            if let out = sharpen.outputImage,
               let cg = context.createCGImage(out, from: out.extent) {
                enhanced = UIImage(cgImage: cg)
            } else {
                enhanced = uiImage
            }
            if let p = PDFPage(image: enhanced) { output.insert(p, at: output.pageCount) }
        }
        return output.dataRepresentation() ?? data
    }

    // MARK: - View

    @ViewBuilder
    private var captureContent: some View {
        VStack(spacing: 0) {
            // Status / icon area
            Group {
                if isUploading {
                    VStack(spacing: 16) {
                        Image("UploadLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 160)
                        Text(String(localized: "capture.uploading")).font(.title2.bold())
                        Text(String(localized: "capture.please_wait")).font(.subheadline).foregroundStyle(.secondary)
                    }
                } else if let msg = uploadSuccessMessage {
                    VStack(spacing: 16) {
                        Image("SuccessLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 160)
                        Text(msg).font(.title2.bold())
                        Text(String(localized: "capture.ready_next"))
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .onAppear {
                        Task {
                            try? await Task.sleep(nanoseconds: 2_500_000_000)
                            uploadSuccessMessage = nil
                        }
                    }
                } else if let err = uploadError {
                    VStack(spacing: 16) {
                        Image("ErrorLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 160)
                        Text(String(localized: "capture.upload_error")).font(.title2.bold())
                        Text(err).font(.caption).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                } else if !configuration.canConnect {
                    VStack(spacing: 16) {
                        Image("ErrorLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 120)
                        Text(String(localized: "server.not_configured.title")).font(.title2.bold())
                        Text(String(localized: "server.not_configured.description"))
                            .font(.subheadline).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                } else if networkMonitor.state == .offline || networkMonitor.state == .serverUnreachable {
                    VStack(spacing: 16) {
                        Image("ErrorLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 160)
                        Text(String(localized: "error.connection_failed")).font(.title2.bold())
                        Text(String(localized: "error.connection_failed.description"))
                            .font(.subheadline).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .onTapGesture { showConnectionErrorDetail = true }
                    .sheet(isPresented: $showConnectionErrorDetail) {
                        NavigationStack {
                            ScrollView {
                                Text(verbatim: networkMonitor.serverError ?? String(localized: "error.connection_failed.description"))
                                    .font(.body.monospaced())
                                    .textSelection(.enabled)
                                    .padding()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .navigationTitle(String(localized: "error.connection_failed"))
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                ToolbarItem(placement: .topBarTrailing) {
                                    Button(String(localized: "error.detail.copy")) {
                                        UIPasteboard.general.string = networkMonitor.serverError ?? ""
                                    }
                                }
                                ToolbarItem(placement: .topBarLeading) {
                                    Button(String(localized: "button.done")) { showConnectionErrorDetail = false }
                                }
                            }
                        }
                    }
                } else {
                    VStack(spacing: 16) {
                        Image("AppLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 160)
                        Text(String(localized: "capture.title")).font(.title2.bold())
                        Text(String(localized: "capture.subtitle"))
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
            .padding(.horizontal, 32)
            .frame(maxHeight: .infinity)

            // Buttons + settings panel
            VStack(spacing: 10) {
                Button {
                    uploadSuccessMessage = nil; uploadError = nil
                    showScanner = true
                } label: {
                    Label(String(localized: "capture.button.camera"), systemImage: torchEnabled ? "camera.fill" : "camera")
                        .font(.headline)
                        .frame(maxWidth: .infinity).padding()
                        .background(Color.accentColor).foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(isUploading)

                HStack(spacing: 10) {
                    Button {
                        uploadSuccessMessage = nil; uploadError = nil
                        showPhotoPicker = true
                    } label: {
                        Label(String(localized: "capture.button.library"), systemImage: "photo.on.rectangle")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(Color(.secondarySystemGroupedBackground))
                            .foregroundStyle(Color.accentColor)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(isUploading)

                    Button {
                        uploadSuccessMessage = nil; uploadError = nil
                        showDocumentPicker = true
                    } label: {
                        Label(String(localized: "capture.button.files"), systemImage: "folder")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(Color(.secondarySystemGroupedBackground))
                            .foregroundStyle(Color.accentColor)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(isUploading)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .animation(.easeInOut, value: isUploading)
        .animation(.easeInOut, value: uploadSuccessMessage)
        .animation(.easeInOut, value: uploadError)
    }
}

// MARK: - Settings Sheet

private struct CaptureSettingsSheet: View {
    @Binding var quickUpload: Bool
    @Binding var torchEnabled: Bool
    @Binding var enhancementEnabled: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(isOn: $quickUpload) {
                        VStack(alignment: .leading, spacing: 2) {
                            Label(String(localized: "settings.caption.direct_upload"), systemImage: "bolt")
                            Text(String(localized: "settings.caption.direct_upload.description"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } header: { Text(String(localized: "settings.section.upload")) }

                Section {
                    Toggle(isOn: $torchEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Label(String(localized: "settings.caption.torch"), systemImage: "flashlight.on.fill")
                            Text(String(localized: "settings.caption.torch.description"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Toggle(isOn: $enhancementEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Label(String(localized: "settings.caption.enhancement"), systemImage: "wand.and.stars")
                            Text(String(localized: "settings.caption.enhancement.description"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } header: { Text(String(localized: "settings.section.capture")) }
            }
            .navigationTitle(String(localized: "nav.settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "button.done")) { dismiss() }
                }
            }
        }
    }
}

#Preview {
    CaptureView()
        .environment(AppConfiguration())
        .environment(ImportQueue())
        .environment(NetworkMonitor())
}
