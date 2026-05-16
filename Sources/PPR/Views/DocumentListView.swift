/// Document browser with search, filtering, and infinite scroll pagination.
/// Filter sheet shows document types, correspondents, and tags (top 7 by usage + "show all").
/// Active filters are displayed as removable pills below the search bar.
import SwiftUI

struct DocumentListView: View {
    @Environment(AppConfiguration.self) private var configuration
    @Environment(NetworkMonitor.self) private var networkMonitor

    @State private var documents: [DocumentSummary] = []
    @State private var totalCount = 0
    @State private var nextPageURL: String?
    @State private var page = 1
    private let pageSize = 25

    @State private var allTags: [TagSummary] = []
    @State private var allCorrespondents: [Correspondent] = []
    @State private var allDocumentTypes: [DocumentType] = []

    @State private var searchText = ""
    @State private var filterTagIDs: Set<Int> = Set(UserDefaults.standard.array(forKey: "filterTagIDs") as? [Int] ?? [])
    @State private var filterCorrespondent: Correspondent?
    @State private var filterDocumentType: DocumentType?
    @State private var showFilterSheet = false

    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var didInitialLoad = false
    @AppStorage("documentListGroupBy") private var groupBy: GroupBy = .none
    @State private var showErrorDetail = false

    // Persisted filter IDs (restored after metadata loads)
    private static let savedCorrespondentIDKey = "filterCorrespondentID"
    private static let savedDocumentTypeIDKey = "filterDocumentTypeID"

    enum GroupBy: String, CaseIterable {
        case none, documentType, correspondent
    }

    enum SortOrder: String, CaseIterable {
        case newestFirst, oldestFirst, titleAZ, titleZA, addedRecent
    }

    @AppStorage("documentListSortOrder") private var sortOrder: SortOrder = .newestFirst

    private var isFiltered: Bool {
        !filterTagIDs.isEmpty || filterCorrespondent != nil || filterDocumentType != nil
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color(.systemBackground))

                if isFiltered {
                    activeFilterPills
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                        .background(Color(.systemBackground))
                }

                Divider()

                if !configuration.canConnect {
                    VStack(spacing: 16) {
                        Image("ErrorLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 120)
                        Text(String(localized: "server.not_configured.title"))
                            .font(.title2.bold())
                        Text(String(localized: "server.not_configured.description"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    .frame(maxHeight: .infinity)
                } else if networkMonitor.state == .offline {
                    VStack(spacing: 16) {
                        Image("ErrorLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 120)
                        Text(String(localized: "error.connection_failed"))
                            .font(.title2.bold())
                        Text(String(localized: "error.connection_failed.description"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    .frame(maxHeight: .infinity)
                } else if isLoading && documents.isEmpty {
                    ProgressView(String(localized: "documents.loading")).frame(maxHeight: .infinity)
                } else if let errorMessage, !errorMessage.isEmpty, documents.isEmpty {
                    VStack(spacing: 16) {
                        Image("ErrorLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 120)
                        Text(String(localized: "documents.load_error.title"))
                            .font(.title2.bold())
                        Text(verbatim: errorMessage)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    .frame(maxHeight: .infinity)
                    .onTapGesture { showErrorDetail = true }
                    .sheet(isPresented: $showErrorDetail) {
                        ErrorDetailSheet(
                            title: String(localized: "error.detail.title"),
                            detail: errorMessage
                        )
                    }
                } else {
                    documentList
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .refreshable { await resetAndLoad() }
            .task(id: configuration.canConnect) {
                guard configuration.canConnect, !didInitialLoad else { return }
                didInitialLoad = true
                await loadMetadataAndDocuments()
            }
            .onChange(of: searchText) { _, _ in
                searchDebounceTask?.cancel()
                searchDebounceTask = Task {
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    guard !Task.isCancelled else { return }
                    await resetAndLoad()
                }
            }
            .onChange(of: filterTagIDs) { _, newValue in
                UserDefaults.standard.set(Array(newValue), forKey: "filterTagIDs")
                Task { await resetAndLoad() }
            }
            .onChange(of: filterCorrespondent) { _, newValue in
                UserDefaults.standard.set(newValue?.id, forKey: Self.savedCorrespondentIDKey)
                Task { await resetAndLoad() }
            }
            .onChange(of: filterDocumentType) { _, newValue in
                UserDefaults.standard.set(newValue?.id, forKey: Self.savedDocumentTypeIDKey)
                Task { await resetAndLoad() }
            }
            .onChange(of: groupBy) { _, _ in
                collapsedSections = []
                Task { await resetAndLoad() }
            }
            .onChange(of: sortOrder) { _, _ in
                Task { await resetAndLoad() }
            }
        }
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
                TextField(String(localized: "documents.search.placeholder"), text: $searchText)
                    .autocorrectionDisabled()
                    .font(.subheadline)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color(.tertiaryLabel))
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            Button { showFilterSheet = true } label: {
                Image(systemName: isFiltered
                      ? "line.3.horizontal.decrease.circle.fill"
                      : "line.3.horizontal.decrease.circle")
                    .font(.title2)
                    .foregroundStyle(isFiltered ? Color.accentColor : Color.primary)
            }
            .disabled(!configuration.canConnect)
            .sheet(isPresented: $showFilterSheet) {
                FilterSheet(
                    allTags: allTags,
                    allCorrespondents: allCorrespondents,
                    allDocumentTypes: allDocumentTypes,
                    filterTagIDs: $filterTagIDs,
                    filterCorrespondent: $filterCorrespondent,
                    filterDocumentType: $filterDocumentType,
                    groupBy: $groupBy,
                    sortOrder: $sortOrder,
                    excludedTagIDs: configuration.excludedTagIDs
                )
                .presentationDetents([.medium, .large])
            }
        }
    }

    // MARK: - Active filter pills

    private var activeFilterPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if let type = filterDocumentType {
                    filterPill(label: type.name) { filterDocumentType = nil }
                }
                if let corr = filterCorrespondent {
                    filterPill(label: corr.name) { filterCorrespondent = nil }
                }
                ForEach(allTags.filter { filterTagIDs.contains($0.id) }) { tag in
                    filterPill(label: tag.name) { filterTagIDs.remove(tag.id) }
                }
            }
        }
    }

    private func filterPill(label: String, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .lineLimit(1)
            Button { onRemove() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
            }
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.accentColor.opacity(0.12))
        .foregroundStyle(Color.accentColor)
        .clipShape(Capsule())
    }

    // MARK: - List

    @ViewBuilder
    private var documentList: some View {
        List {
            if let errorMessage, !errorMessage.isEmpty {
                Section {
                    Text(verbatim: errorMessage).font(.footnote).foregroundStyle(.red)
                }
            }

            if groupBy == .none {
                ForEach(documents) { doc in
                    documentRow(doc)
                }
            } else {
                ForEach(groupedSections, id: \.title) { section in
                    Section {
                        DisclosureGroup(isExpanded: sectionBinding(for: section.title)) {
                            ForEach(section.documents) { doc in
                                documentRow(doc)
                            }
                        } label: {
                            HStack {
                                Text(section.title).font(.subheadline.weight(.semibold))
                                Spacer()
                                Text("\(section.documents.count)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            if nextPageURL != nil && groupBy == .none {
                HStack { Spacer(); ProgressView(); Spacer() }
                    .onAppear { Task { await loadNextPage() } }
            }
        }
        .listStyle(.plain)
        .scrollDismissesKeyboard(.immediately)
    }

    private func documentRow(_ doc: DocumentSummary) -> some View {
        NavigationLink {
            DocumentDetailView(summary: doc).environment(configuration)
        } label: {
            DocumentRowView(
                document: doc,
                allTags: allTags,
                allCorrespondents: allCorrespondents,
                allDocumentTypes: allDocumentTypes
            )
        }
    }

    // MARK: - Grouping

    @State private var collapsedSections: Set<String> = []

    private struct GroupedSection {
        let title: String
        let documents: [DocumentSummary]
    }

    private var groupedSections: [GroupedSection] {
        switch groupBy {
        case .none:
            return []
        case .documentType:
            let grouped = Dictionary(grouping: documents) { doc in
                allDocumentTypes.first { $0.id == doc.documentType }?.name
                    ?? String(localized: "metadata.field.document_type.none")
            }
            return grouped.keys.sorted().map { GroupedSection(title: $0, documents: grouped[$0]!) }
        case .correspondent:
            let grouped = Dictionary(grouping: documents) { doc in
                allCorrespondents.first { $0.id == doc.correspondent }?.name
                    ?? String(localized: "metadata.field.correspondent.none")
            }
            return grouped.keys.sorted().map { GroupedSection(title: $0, documents: grouped[$0]!) }
        }
    }

    private func sectionBinding(for title: String) -> Binding<Bool> {
        Binding(
            get: { !collapsedSections.contains(title) },
            set: { isExpanded in
                if isExpanded { collapsedSections.remove(title) }
                else { collapsedSections.insert(title) }
            }
        )
    }

    // MARK: - Load

    private func loadMetadataAndDocuments() async {
        async let tagsTask = PaperlessAPI.tags(serverURL: configuration.serverURL, token: configuration.apiToken)
        async let corrsTask = PaperlessAPI.correspondents(serverURL: configuration.serverURL, token: configuration.apiToken)
        async let typesTask = PaperlessAPI.documentTypes(serverURL: configuration.serverURL, token: configuration.apiToken)
        allTags = (try? await tagsTask) ?? []
        allCorrespondents = (try? await corrsTask) ?? []
        allDocumentTypes = (try? await typesTask) ?? []
        // Restore persisted filters
        if let savedTypeID = UserDefaults.standard.object(forKey: Self.savedDocumentTypeIDKey) as? Int {
            filterDocumentType = allDocumentTypes.first { $0.id == savedTypeID }
        }
        if let savedCorrID = UserDefaults.standard.object(forKey: Self.savedCorrespondentIDKey) as? Int {
            filterCorrespondent = allCorrespondents.first { $0.id == savedCorrID }
        }
        await resetAndLoad()
    }

    private func resetAndLoad() async {
        guard networkMonitor.state != .offline else { return }
        page = 1; nextPageURL = nil; errorMessage = nil
        await loadPage(reset: true)
        // When grouping, load all pages so groups are complete
        if groupBy != .none {
            while nextPageURL != nil, !Task.isCancelled {
                page += 1
                await loadPage(reset: false)
            }
        }
    }

    private func loadNextPage() async {
        guard nextPageURL != nil, !isLoading else { return }
        page += 1
        await loadPage(reset: false)
    }

    private var apiOrdering: String? {
        // Grouping takes priority for ordering
        if groupBy != .none {
            switch groupBy {
            case .none: break
            case .documentType: return "document_type__name"
            case .correspondent: return "correspondent__name"
            }
        }
        // Otherwise use sort order
        switch sortOrder {
        case .newestFirst: return "-created"
        case .oldestFirst: return "created"
        case .titleAZ: return "title"
        case .titleZA: return "-title"
        case .addedRecent: return "-added"
        }
    }

    private func loadPage(reset: Bool) async {
        guard configuration.canConnect else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let envelope = try await PaperlessAPI.documents(
                serverURL: configuration.serverURL,
                token: configuration.apiToken,
                page: page, pageSize: pageSize,
                search: searchText,
                tagIDs: Array(filterTagIDs),
                correspondentID: filterCorrespondent?.id,
                documentTypeID: filterDocumentType?.id,
                ordering: apiOrdering
            )
            totalCount = envelope.count
            nextPageURL = envelope.next
            if reset { documents = envelope.results }
            else { documents.append(contentsOf: envelope.results) }
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            if Task.isCancelled { return }
            if reset { documents = [] }
            errorMessage = PaperlessAPI.formattedUserError(error)
                ?? (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }
}

// MARK: - Row

private struct DocumentRowView: View {
    let document: DocumentSummary
    let allTags: [TagSummary]
    let allCorrespondents: [Correspondent]
    let allDocumentTypes: [DocumentType]

    private var docType: DocumentType? { allDocumentTypes.first { $0.id == document.documentType } }
    private var correspondentName: String? { allCorrespondents.first { $0.id == document.correspondent }?.name }
    private var documentTags: [TagSummary] { document.tags.compactMap { id in allTags.first { $0.id == id } } }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            typeAvatar
            VStack(alignment: .leading, spacing: 4) {
                Text(document.title.isEmpty ? String(localized: "documents.row.untitled") : document.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                    .foregroundStyle(.primary)

                HStack(spacing: 4) {
                    if let created = document.created {
                        Text(formattedDate(created))
                    }
                    if let name = correspondentName {
                        Text("·").foregroundStyle(.tertiary)
                        Text(name).lineLimit(1).truncationMode(.tail)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if !documentTags.isEmpty {
                    tagPills
                }
            }
        }
        .padding(.vertical, 5)
    }

    // MARK: Avatar

    private var typeAvatar: some View {
        let name = docType?.name
        let initials = name.map { avatarInitials($0) } ?? "·"
        let color = name.map { avatarColor($0) } ?? Color(.tertiaryLabel)
        return ZStack {
            Circle()
                .fill(color.opacity(0.15))
                .frame(width: 42, height: 42)
            Text(initials)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
        }
    }

    private func avatarInitials(_ name: String) -> String {
        let words = name.split(separator: " ")
        if words.count >= 2 {
            return (String(words[0].prefix(1)) + String(words[1].prefix(1))).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    private static let avatarPalette: [Color] = [
        .blue, .purple, .pink, .orange, .green, .teal, .indigo, .cyan, .mint, .red
    ]

    private func avatarColor(_ name: String) -> Color {
        let hash = name.unicodeScalars.reduce(0) { ($0 &* 31) &+ Int($1.value) }
        return Self.avatarPalette[abs(hash) % Self.avatarPalette.count]
    }

    // MARK: Tag pills

    private var tagPills: some View {
        let visible = Array(documentTags.prefix(3))
        let overflow = documentTags.count - visible.count
        return HStack(spacing: 4) {
            ForEach(visible) { tag in
                let color = Color(paperlessHex: tag.color) ?? .secondary
                Text(tag.name)
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(color.opacity(0.15))
                    .foregroundStyle(color)
                    .clipShape(Capsule())
            }
            if overflow > 0 {
                Text("+\(overflow)")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func formattedDate(_ s: String) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        if let d = f.date(from: s) { return d.formatted(date: .abbreviated, time: .omitted) }
        return s
    }
}

// MARK: - Filter Sheet

private struct FilterSheet: View {
    let allTags: [TagSummary]
    let allCorrespondents: [Correspondent]
    let allDocumentTypes: [DocumentType]

    @Binding var filterTagIDs: Set<Int>
    @Binding var filterCorrespondent: Correspondent?
    @Binding var filterDocumentType: DocumentType?
    @Binding var groupBy: DocumentListView.GroupBy
    @Binding var sortOrder: DocumentListView.SortOrder

    @Environment(\.dismiss) private var dismiss
    @State private var showAllTags = false

    var excludedTagIDs: Set<Int>

    private var topTags: [TagSummary] {
        Array(
            allTags
                .filter { !excludedTagIDs.contains($0.id) }
                .sorted { ($0.documentCount ?? 0) > ($1.documentCount ?? 0) }
                .prefix(7)
        )
    }

    private var allTagsAlphabetical: [TagSummary] {
        allTags.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "filter.section.group_by")) {
                    Picker(String(localized: "filter.picker.sort_by"), selection: $sortOrder) {
                        Text(String(localized: "filter.sort.newest")).tag(DocumentListView.SortOrder.newestFirst)
                        Text(String(localized: "filter.sort.oldest")).tag(DocumentListView.SortOrder.oldestFirst)
                        Text(String(localized: "filter.sort.title_az")).tag(DocumentListView.SortOrder.titleAZ)
                        Text(String(localized: "filter.sort.title_za")).tag(DocumentListView.SortOrder.titleZA)
                        Text(String(localized: "filter.sort.added_recent")).tag(DocumentListView.SortOrder.addedRecent)
                    }
                    .pickerStyle(.menu)

                    Picker(String(localized: "filter.picker.group_by"), selection: $groupBy) {
                        Text(String(localized: "filter.option.none")).tag(DocumentListView.GroupBy.none)
                        Text(String(localized: "filter.section.document_type")).tag(DocumentListView.GroupBy.documentType)
                        Text(String(localized: "metadata.field.correspondent")).tag(DocumentListView.GroupBy.correspondent)
                    }
                    .pickerStyle(.menu)
                }

                Section(String(localized: "filter.section.filter")) {
                    Picker(String(localized: "filter.picker.type_label"), selection: $filterDocumentType) {
                        Text(String(localized: "filter.option.all")).tag(Optional<DocumentType>.none)
                        ForEach(allDocumentTypes) { t in
                            Text(t.documentCount.map { "\(t.name) (\($0))" } ?? t.name).tag(Optional(t))
                        }
                    }
                    .pickerStyle(.menu)

                    Picker(String(localized: "metadata.field.correspondent"), selection: $filterCorrespondent) {
                        Text(String(localized: "filter.option.all")).tag(Optional<Correspondent>.none)
                        ForEach(allCorrespondents) { c in
                            Text(c.documentCount.map { "\(c.name) (\($0))" } ?? c.name).tag(Optional(c))
                        }
                    }
                    .pickerStyle(.menu)

                    let visibleTags = showAllTags ? allTagsAlphabetical : topTags
                    ForEach(visibleTags) { tag in
                        Button {
                            if filterTagIDs.contains(tag.id) { filterTagIDs.remove(tag.id) }
                            else { filterTagIDs.insert(tag.id) }
                        } label: {
                            HStack {
                                let color = Color(paperlessHex: tag.color) ?? Color.accentColor
                                Circle().fill(color).frame(width: 10, height: 10)
                                Text(tag.name).foregroundStyle(.primary)
                                if let count = tag.documentCount {
                                    Text("(\(count))")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if filterTagIDs.contains(tag.id) {
                                    Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                    }
                    if !showAllTags && allTags.count > 7 {
                        Button {
                            withAnimation { showAllTags = true }
                        } label: {
                            Label(String(localized: "filter.button.show_all_tags"), systemImage: "tag")
                                .font(.subheadline)
                        }
                    }
                }

                if !filterTagIDs.isEmpty || filterCorrespondent != nil || filterDocumentType != nil {
                    Section {
                        Button(role: .destructive) {
                            filterTagIDs = []; filterCorrespondent = nil; filterDocumentType = nil
                        } label: {
                            Label(String(localized: "filter.button.reset"), systemImage: "xmark.circle")
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "filter.nav.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button(String(localized: "button.done")) { dismiss() } }
            }
        }
    }
}

// MARK: - Color helper

private extension Color {
    init?(paperlessHex hex: String?) {
        guard let hex else { return nil }
        let s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard s.count == 6, let value = UInt64(s, radix: 16) else { return nil }
        self.init(
            red:   Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8)  & 0xFF) / 255,
            blue:  Double( value        & 0xFF) / 255
        )
    }
}

#Preview {
    DocumentListView()
        .environment(AppConfiguration())
        .environment(NetworkMonitor())
}
