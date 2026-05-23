/// Metadata form shown before uploading a captured document.
/// Allows setting title, date, document type, correspondent, and tags.
/// Tags are displayed as compact pills with a sheet for full selection.
import SwiftUI

struct CaptureMetadataView: View {
    @Environment(AppConfiguration.self) private var configuration
    @Environment(\.dismiss) private var dismiss

    let pdfData: Data
    let onUploaded: () -> Void

    @State private var title = ""
    @State private var createdDate = Date()
    @State private var selectedDocumentType: DocumentType?
    @State private var selectedCorrespondent: Correspondent?
    @State private var selectedStoragePath: StoragePath?
    @State private var selectedTagIDs: Set<Int> = []

    @State private var documentTypes: [DocumentType] = []
    @State private var correspondents: [Correspondent] = []
    @State private var storagePaths: [StoragePath] = []
    @State private var availableTags: [TagSummary] = []

    @State private var isLoadingMetadata = false
    @State private var loadError: String?
    @State private var isUploading = false
    @State private var uploadError: String?

    // Create new item alerts
    private enum CreateSheet { case docType, correspondent, tag }
    @State private var createSheet: CreateSheet?
    @State private var newItemName = ""
    @State private var isCreating = false
    @State private var createError: String?
    @State private var showTagSheet = false

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "metadata.section.document")) {
                    TextField(String(localized: "metadata.field.title_placeholder"), text: $title)
                        .autocorrectionDisabled()
                    DatePicker(String(localized: "metadata.field.date"), selection: $createdDate, displayedComponents: .date)
                }

                Section {
                    Picker(String(localized: "metadata.field.document_type"), selection: $selectedDocumentType) {
                        Text(String(localized: "metadata.field.document_type.none")).tag(Optional<DocumentType>.none)
                        ForEach(documentTypes) { type in
                            Text(type.name).tag(Optional(type))
                        }
                    }
                    Button {
                        newItemName = ""
                        createError = nil
                        createSheet = .docType
                    } label: {
                        Label(String(localized: "metadata.button.new_document_type"), systemImage: "plus")
                            .font(.subheadline)
                    }

                    Picker(String(localized: "metadata.field.correspondent"), selection: $selectedCorrespondent) {
                        Text(String(localized: "metadata.field.correspondent.none")).tag(Optional<Correspondent>.none)
                        ForEach(correspondents) { c in
                            Text(c.name).tag(Optional(c))
                        }
                    }
                    Button {
                        newItemName = ""
                        createError = nil
                        createSheet = .correspondent
                    } label: {
                        Label(String(localized: "metadata.button.new_correspondent"), systemImage: "plus")
                            .font(.subheadline)
                    }

                    if !storagePaths.isEmpty {
                        Picker(String(localized: "metadata.field.storage_path"), selection: $selectedStoragePath) {
                            Text(String(localized: "metadata.field.storage_path.none")).tag(Optional<StoragePath>.none)
                            ForEach(storagePaths) { sp in
                                Text(sp.name).tag(Optional(sp))
                            }
                        }
                    }
                } header: {
                    Text(String(localized: "metadata.section.classification"))
                }

                Section {
                    Button { showTagSheet = true } label: {
                        HStack {
                            Text(String(localized: "metadata.section.tags"))
                                .foregroundStyle(.primary)
                            Spacer()
                            if selectedTagIDs.isEmpty {
                                Text(String(localized: "metadata.field.document_type.none"))
                                    .foregroundStyle(.secondary)
                            } else {
                                selectedTagPills
                            }
                        }
                    }
                }

                if isLoadingMetadata {
                    Section {
                        HStack {
                            ProgressView()
                            Text(String(localized: "metadata.loading"))
                                .foregroundStyle(.secondary)
                                .font(.footnote)
                        }
                    }
                }

                if let loadError {
                    Section {
                        Text(String(format: String(localized: "metadata.load_error"), loadError))
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }

                if let uploadError {
                    Section {
                        Text(uploadError)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle(String(localized: "metadata.nav.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .disabled(isUploading)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if isUploading {
                        ProgressView()
                    } else {
                        Button { Task { await upload() } } label: {
                            Image(systemName: "checkmark").bold()
                        }
                    }
                }
            }
            .task {
                await loadMetadata()
            }
            .sheet(isPresented: $showTagSheet) {
                TagSelectionSheet(
                    availableTags: availableTags,
                    selectedTagIDs: $selectedTagIDs,
                    onCreateTag: {
                        newItemName = ""
                        createError = nil
                        createSheet = .tag
                    }
                )
                .presentationDetents([.medium, .large])
            }
            .alert(createAlertTitle, isPresented: createAlertBinding) {
                TextField(String(localized: "alert.new_item.name_placeholder"), text: $newItemName)
                    .autocorrectionDisabled()
                if isCreating {
                    ProgressView()
                } else {
                    Button(String(localized: "alert.new_item.button.create")) {
                        let action = createSheet
                        let name = newItemName
                        Task { await createItem(action: action, name: name) }
                    }
                    .disabled(newItemName.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button(String(localized: "button.cancel"), role: .cancel) { createSheet = nil }
                }
                if let createError {
                    Text(createError).foregroundStyle(.red)
                }
            } message: {
                if let createError {
                    Text(createError)
                }
            }
        }
    }

    // MARK: - Tag Pills

    @ViewBuilder
    private var selectedTagPills: some View {
        let selected = availableTags.filter { selectedTagIDs.contains($0.id) }
        FlowLayout(spacing: 4) {
            ForEach(selected) { tag in
                Text(tag.name)
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.15))
                    .foregroundStyle(Color.accentColor)
                    .clipShape(Capsule())
            }
        }
    }

    private var createAlertTitle: String {
        switch createSheet {
        case .docType: String(localized: "alert.new_document_type.title")
        case .correspondent: String(localized: "alert.new_correspondent.title")
        case .tag: String(localized: "alert.new_tag.title")
        case nil: ""
        }
    }

    private var createAlertBinding: Binding<Bool> {
        Binding(
            get: { createSheet != nil },
            set: { if !$0 { createSheet = nil } }
        )
    }

    private func createItem(action: CreateSheet?, name rawName: String) async {
        let name = rawName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, let action else { return }
        isCreating = true
        createError = nil
        defer { isCreating = false }

        let url = configuration.serverURL
        let token = configuration.apiToken

        do {
            switch action {
            case .docType:
                let created = try await PaperlessAPI.createDocumentType(name: name, serverURL: url, token: token)
                documentTypes.append(created)
                documentTypes.sort { $0.name.localizedCompare($1.name) == .orderedAscending }
                selectedDocumentType = created
            case .correspondent:
                let created = try await PaperlessAPI.createCorrespondent(name: name, serverURL: url, token: token)
                correspondents.append(created)
                correspondents.sort { $0.name.localizedCompare($1.name) == .orderedAscending }
                selectedCorrespondent = created
            case .tag:
                let created = try await PaperlessAPI.createTag(name: name, serverURL: url, token: token)
                availableTags.append(created)
                availableTags.sort { $0.name.localizedCompare($1.name) == .orderedAscending }
                selectedTagIDs.insert(created.id)
            }
            createSheet = nil
        } catch {
            createError = error.localizedDescription
        }
    }

    private func loadMetadata() async {
        isLoadingMetadata = true
        loadError = nil
        defer { isLoadingMetadata = false }

        let url = configuration.serverURL
        let token = configuration.apiToken
        var errors: [String] = []

        do {
            documentTypes = try await PaperlessAPI.documentTypes(serverURL: url, token: token)
        } catch {
            errors.append("Typen: \(error.localizedDescription)")
        }
        do {
            correspondents = try await PaperlessAPI.correspondents(serverURL: url, token: token)
        } catch {
            errors.append("Korrespondenten: \(error.localizedDescription)")
        }
        do {
            storagePaths = try await PaperlessAPI.storagePaths(serverURL: url, token: token)
        } catch {
            // Storage paths are optional — silently ignore if unavailable
        }
        do {
            availableTags = try await PaperlessAPI.tags(serverURL: url, token: token)
        } catch {
            errors.append("Tags: \(error.localizedDescription)")
        }

        if !errors.isEmpty {
            loadError = errors.joined(separator: "\n")
        }
    }

    private func upload() async {
        uploadError = nil
        isUploading = true
        defer { isUploading = false }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let createdString = dateFormatter.string(from: createdDate)

        let filename = title.isEmpty
            ? "scan_\(createdString).pdf"
            : "\(title).pdf"

        do {
            try await PaperlessAPI.uploadDocument(
                pdfData: pdfData,
                filename: filename,
                title: title,
                created: createdString,
                documentType: selectedDocumentType?.id,
                correspondent: selectedCorrespondent?.id,
                tags: Array(selectedTagIDs),
                storagePath: selectedStoragePath?.id,
                serverURL: configuration.serverURL,
                token: configuration.apiToken
            )
            onUploaded()
            dismiss()
        } catch {
            uploadError = PaperlessAPI.formattedUserError(error)
                ?? (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }
}

// MARK: - Tag Selection Sheet

private struct TagSelectionSheet: View {
    let availableTags: [TagSummary]
    @Binding var selectedTagIDs: Set<Int>
    let onCreateTag: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(availableTags) { tag in
                    Button {
                        if selectedTagIDs.contains(tag.id) {
                            selectedTagIDs.remove(tag.id)
                        } else {
                            selectedTagIDs.insert(tag.id)
                        }
                    } label: {
                        HStack {
                            Text(tag.name)
                                .foregroundStyle(.primary)
                            Spacer()
                            if selectedTagIDs.contains(tag.id) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                }

                Button {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        onCreateTag()
                    }
                } label: {
                    Label(String(localized: "metadata.button.new_tag"), systemImage: "plus")
                        .font(.subheadline)
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

// MARK: - Flow Layout

private struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, origin) in result.origins.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            totalHeight = y + rowHeight
        }

        return (CGSize(width: maxWidth, height: totalHeight), origins)
    }
}
