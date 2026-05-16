/// Document detail view with PDF preview, metadata editing (title, date, type,
/// correspondent, tags), and save functionality. Tags are shown as pills with
/// a sheet for selection.
import SwiftUI
import PDFKit

struct DocumentDetailView: View {
    @Environment(AppConfiguration.self) private var configuration
    @Environment(\.dismiss) private var dismiss

    let summary: DocumentSummary

    // Loaded data
    @State private var detail: DocumentDetail?
    @State private var isLoading = true
    @State private var loadError: String?

    // Filter metadata
    @State private var allDocumentTypes: [DocumentType] = []
    @State private var allCorrespondents: [Correspondent] = []
    @State private var allTags: [TagSummary] = []

    // Editable fields
    @State private var editTitle = ""
    @State private var editCreatedDate = Date()
    @State private var editDocumentType: DocumentType?
    @State private var editCorrespondent: Correspondent?
    @State private var editTagIDs: Set<Int> = []

    // PDF
    @State private var pdfData: Data?
    @State private var showFullPDF = false

    // Save
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var showTagSheet = false
    @State private var showShareSheet = false
    @State private var didPopulateFields = false

    private var hasChanges: Bool {
        guard didPopulateFields, let detail else { return false }
        if editTitle != detail.title { return true }
        if editDocumentType?.id != detail.documentType { return true }
        if editCorrespondent?.id != detail.correspondent { return true }
        if editTagIDs != Set(detail.tags) { return true }
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        if dateFormatter.string(from: editCreatedDate) != (detail.created ?? "") { return true }
        return false
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if let loadError, detail == nil {
                ContentUnavailableView(
                    String(localized: "detail.error.title"),
                    systemImage: "exclamationmark.triangle",
                    description: Text(verbatim: loadError)
                )
            } else {
                List {
                    if let pdfData {
                        Section {
                            Button { showFullPDF = true } label: {
                                PDFKitView(data: pdfData)
                                    .frame(height: 260)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(alignment: .bottomTrailing) {
                                        Label(String(localized: "detail.button.fullscreen"),
                                              systemImage: "arrow.up.left.and.arrow.down.right")
                                            .font(.caption)
                                            .padding(6)
                                            .background(.ultraThinMaterial)
                                            .clipShape(RoundedRectangle(cornerRadius: 6))
                                            .padding(10)
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }

                    Section(String(localized: "metadata.section.document")) {
                        TextField(String(localized: "metadata.field.title"), text: $editTitle)
                            .autocorrectionDisabled()
                        DatePicker(String(localized: "metadata.field.date"),
                                   selection: $editCreatedDate, displayedComponents: .date)
                    }

                    Section(String(localized: "metadata.section.classification")) {
                        Picker(String(localized: "metadata.field.document_type"), selection: $editDocumentType) {
                            Text(String(localized: "metadata.field.document_type.none")).tag(Optional<DocumentType>.none)
                            ForEach(allDocumentTypes) { t in Text(t.name).tag(Optional(t)) }
                        }
                        Picker(String(localized: "metadata.field.correspondent"), selection: $editCorrespondent) {
                            Text(String(localized: "metadata.field.correspondent.none")).tag(Optional<Correspondent>.none)
                            ForEach(allCorrespondents) { c in Text(c.name).tag(Optional(c)) }
                        }
                        Button { showTagSheet = true } label: {
                            HStack {
                                Text(String(localized: "metadata.section.tags"))
                                    .foregroundStyle(.primary)
                                Spacer()
                                if editTagIDs.isEmpty {
                                    Text(String(localized: "metadata.field.document_type.none"))
                                        .foregroundStyle(.secondary)
                                } else {
                                    selectedTagPills
                                }
                            }
                        }
                    }

                    if let content = detail?.content, !content.isEmpty {
                        Section(String(localized: "detail.section.content_ocr")) {
                            Text(content)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let detail {
                        Section(String(localized: "detail.section.info")) {
                            if let name = detail.originalFileName {
                                LabeledContent(String(localized: "detail.field.filename"), value: name)
                                    .font(.footnote)
                            }
                            if let added = detail.added {
                                LabeledContent(String(localized: "detail.field.added"),
                                               value: formattedDateTime(added))
                                    .font(.footnote)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(detail?.title ?? summary.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack {
                    if pdfData != nil {
                        Button {
                            showShareSheet = true
                        } label: {
                            Label(String(localized: "detail.button.share"), systemImage: "square.and.arrow.up")
                        }
                    }
                    if isSaving {
                        ProgressView()
                    } else if hasChanges {
                        Button(String(localized: "detail.button.save")) { Task { await save() } }
                            .bold()
                    }
                }
            }
        }
        .task {
            await loadAll()
        }
        .sheet(isPresented: $showTagSheet) {
            DetailTagSelectionSheet(allTags: allTags, selectedTagIDs: $editTagIDs)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showFullPDF) {
            if let pdfData {
                NavigationStack {
                    PDFKitView(data: pdfData)
                        .ignoresSafeArea(edges: .bottom)
                        .navigationTitle(detail?.title ?? summary.title)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button(String(localized: "button.done")) { showFullPDF = false }
                            }
                        }
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let pdfData {
                ActivityViewController(activityItems: [pdfData])
            }
        }
        .alert(String(localized: "detail.alert.save_error.title"), isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button(String(localized: "button.ok"), role: .cancel) {}
        } message: {
            Text(saveError ?? "")
        }
    }

    // MARK: - Tag Pills

    @ViewBuilder
    private var selectedTagPills: some View {
        let selected = allTags.filter { editTagIDs.contains($0.id) }
        HStack(spacing: 4) {
            let visible = Array(selected.prefix(3))
            let overflow = selected.count - visible.count
            ForEach(visible) { tag in
                Text(tag.name)
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.15))
                    .foregroundStyle(Color.accentColor)
                    .clipShape(Capsule())
            }
            if overflow > 0 {
                Text("+\(overflow)")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Helpers

    private func formattedDate(_ s: String) -> Date {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return f.date(from: s) ?? Date()
    }

    private func formattedDateTime(_ s: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d.formatted(date: .abbreviated, time: .shortened) }
        let f2 = ISO8601DateFormatter()
        if let d = f2.date(from: s) { return d.formatted(date: .abbreviated, time: .shortened) }
        return s
    }

    // MARK: - Load

    private func loadAll() async {
        isLoading = true
        loadError = nil
        let url = configuration.serverURL
        let token = configuration.apiToken

        async let detailTask = PaperlessAPI.document(id: summary.id, serverURL: url, token: token)
        async let typesTask = PaperlessAPI.documentTypes(serverURL: url, token: token)
        async let corrsTask = PaperlessAPI.correspondents(serverURL: url, token: token)
        async let tagsTask = PaperlessAPI.tags(serverURL: url, token: token)
        async let pdfTask = PaperlessAPI.documentPreview(id: summary.id, serverURL: url, token: token)

        do { detail = try await detailTask } catch { loadError = error.localizedDescription }
        allDocumentTypes = (try? await typesTask) ?? []
        allCorrespondents = (try? await corrsTask) ?? []
        allTags = (try? await tagsTask) ?? []
        pdfData = try? await pdfTask

        if let d = detail {
            editTitle = d.title
            editCreatedDate = d.created.map { formattedDate($0) } ?? Date()
            editDocumentType = allDocumentTypes.first { $0.id == d.documentType }
            editCorrespondent = allCorrespondents.first { $0.id == d.correspondent }
            editTagIDs = Set(d.tags)
            didPopulateFields = true
        }
        isLoading = false
    }

    // MARK: - Save

    private func save() async {
        isSaving = true
        saveError = nil
        defer { isSaving = false }
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let createdString = dateFormatter.string(from: editCreatedDate)
        do {
            let updated = try await PaperlessAPI.updateDocument(
                id: summary.id,
                title: editTitle,
                created: createdString,
                documentType: editDocumentType?.id,
                correspondent: editCorrespondent?.id,
                tags: Array(editTagIDs),
                serverURL: configuration.serverURL,
                token: configuration.apiToken
            )
            detail = updated
            editTitle = updated.title
            editCreatedDate = updated.created.map { formattedDate($0) } ?? Date()
            editDocumentType = allDocumentTypes.first { $0.id == updated.documentType }
            editCorrespondent = allCorrespondents.first { $0.id == updated.correspondent }
            editTagIDs = Set(updated.tags)
        } catch {
            saveError = PaperlessAPI.formattedUserError(error)
                ?? (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }
}

// MARK: - Tag Selection Sheet (Detail)

private struct DetailTagSelectionSheet: View {
    let allTags: [TagSummary]
    @Binding var selectedTagIDs: Set<Int>
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(allTags) { tag in
                    Button {
                        if selectedTagIDs.contains(tag.id) { selectedTagIDs.remove(tag.id) }
                        else { selectedTagIDs.insert(tag.id) }
                    } label: {
                        HStack {
                            Text(tag.name).foregroundStyle(.primary)
                            Spacer()
                            if selectedTagIDs.contains(tag.id) {
                                Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "metadata.section.tags"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "button.done")) { dismiss() }
                }
            }
        }
    }
}

// MARK: - PDFKit wrapper

struct PDFKitView: UIViewRepresentable {
    let data: Data

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.document = PDFDocument(data: data)
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {}
}

// MARK: - Activity View Controller wrapper

struct ActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
