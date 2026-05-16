/// Dedicated search view for finding documents by text query.
/// Shown as the search tab in the tab bar.
import SwiftUI

struct SearchView: View {
    @Environment(AppConfiguration.self) private var configuration

    @State private var searchText = ""
    @State private var results: [DocumentSummary] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Group {
                if !configuration.canConnect {
                    ContentUnavailableView(
                        String(localized: "server.not_configured.title"),
                        systemImage: "magnifyingglass",
                        description: Text(String(localized: "server.not_configured.description"))
                    )
                } else if searchText.isEmpty {
                    ContentUnavailableView(
                        String(localized: "search.empty.title"),
                        systemImage: "magnifyingglass",
                        description: Text(String(localized: "search.empty.description"))
                    )
                } else if isSearching {
                    ProgressView()
                        .frame(maxHeight: .infinity)
                } else if results.isEmpty {
                    ContentUnavailableView(
                        String(localized: "search.no_results.title"),
                        systemImage: "doc.text.magnifyingglass",
                        description: Text(String(localized: "search.no_results.description"))
                    )
                } else {
                    List(results) { doc in
                        NavigationLink {
                            DocumentDetailView(summary: doc)
                                .environment(configuration)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(doc.title.isEmpty ? String(localized: "documents.row.untitled") : doc.title)
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(2)
                                if let created = doc.created {
                                    Text(formattedDate(created))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle(String(localized: "tab.search"))
            .searchable(text: $searchText, prompt: String(localized: "documents.search.placeholder"))
            .onChange(of: searchText) { _, newValue in
                searchTask?.cancel()
                guard !newValue.isEmpty else {
                    results = []
                    return
                }
                searchTask = Task {
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    guard !Task.isCancelled else { return }
                    await performSearch(query: newValue)
                }
            }
        }
    }

    private func performSearch(query: String) async {
        guard configuration.canConnect else { return }
        isSearching = true
        defer { isSearching = false }
        do {
            let envelope = try await PaperlessAPI.documents(
                serverURL: configuration.serverURL,
                token: configuration.apiToken,
                page: 1, pageSize: 25,
                search: query
            )
            if !Task.isCancelled {
                results = envelope.results
            }
        } catch {
            if !Task.isCancelled {
                results = []
            }
        }
    }

    private func formattedDate(_ s: String) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        if let d = f.date(from: s) { return d.formatted(date: .abbreviated, time: .omitted) }
        return s
    }
}
