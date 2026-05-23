import SwiftUI

struct SettingsView: View {
    @Environment(AppConfiguration.self) private var configuration

    // Paperless connection state
    @State private var isTestingPaperless = false
    @State private var paperlessVersion: String?
    @State private var paperlessError: String?
    @State private var showPaperlessErrorSheet = false

    // AI connection state
    @State private var isTestingAI = false
    @State private var aiConnectedVersion: String?
    @State private var aiError: String?
    @State private var showAIErrorSheet = false

    // Tags
    @State private var allTags: [TagSummary] = []
    @State private var isLoadingTags = false

    var body: some View {
        NavigationStack {
            Form {
                // MARK: Paperless Server
                Section(String(localized: "server.settings.section.server")) {
                    // Row 1: navigate to config + status detail
                    NavigationLink {
                        PaperlessServerSettingsView()
                    } label: {
                        if configuration.canConnect {
                            Label(configuration.serverURL, systemImage: "server.rack")
                                .lineLimit(1)
                        } else {
                            Label(String(localized: "settings.server.not_configured"),
                                  systemImage: "server.rack")
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Row 2: connection status / test button
                    if isTestingPaperless {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text(String(localized: "server.settings.testing_connection"))
                                .foregroundStyle(.secondary)
                        }
                    } else if let version = paperlessVersion {
                        Label(String(format: String(localized: "server.settings.connected"), version),
                              systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else if let error = paperlessError, !error.isEmpty {
                        Button {
                            showPaperlessErrorSheet = true
                        } label: {
                            Label(String(localized: "server.status.connection_failed"),
                                  systemImage: "xmark.circle.fill")
                                .foregroundStyle(.red)
                        }
                        .sheet(isPresented: $showPaperlessErrorSheet) {
                            ErrorDetailSheet(
                                title: String(localized: "error.detail.title"),
                                detail: error
                            )
                        }
                    } else {
                        Button(String(localized: "server.settings.button.test_connection")) {
                            Task { await testPaperlessConnection() }
                        }
                        .disabled(!configuration.canConnect)
                    }
                }

                // MARK: AI Server
                Section(String(localized: "ai.settings.section.server")) {
                    // Row 1: navigate to config + status detail
                    NavigationLink {
                        AIServerSettingsView()
                    } label: {
                        if configuration.hasAIServer {
                            Label(configuration.aiServerURL, systemImage: "sparkles")
                                .lineLimit(1)
                        } else {
                            Label(String(localized: "ai.settings.not_configured"),
                                  systemImage: "sparkles")
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Row 2: connection status / test button
                    if isTestingAI {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text(String(localized: "server.settings.testing_connection"))
                                .foregroundStyle(.secondary)
                        }
                    } else if let error = aiError, !error.isEmpty {
                        Button {
                            showAIErrorSheet = true
                        } label: {
                            Label(String(localized: "server.status.connection_failed"),
                                  systemImage: "xmark.circle.fill")
                                .foregroundStyle(.red)
                        }
                        .sheet(isPresented: $showAIErrorSheet) {
                            ErrorDetailSheet(
                                title: String(localized: "error.detail.title"),
                                detail: error
                            )
                        }
                    } else if let version = aiConnectedVersion {
                        Label(
                            version.isEmpty
                                ? String(localized: "ai.settings.status.connected")
                                : String(format: String(localized: "ai.settings.status.connected_version"), version),
                            systemImage: "checkmark.circle.fill"
                        )
                        .foregroundStyle(.green)
                    } else {
                        Button(String(localized: "server.settings.button.test_connection")) {
                            Task { await testAIConnection() }
                        }
                        .disabled(!configuration.hasAIServer)
                    }
                }

                // MARK: AI Features
                if configuration.hasAIServer {
                    Section {
                        Toggle(isOn: Binding(
                            get: { configuration.aiSimilarDocsEnabled },
                            set: { configuration.aiSimilarDocsEnabled = $0 }
                        )) {
                            Label(String(localized: "ai.features.similar_docs"),
                                  systemImage: "doc.on.doc")
                        }
                        Toggle(isOn: Binding(
                            get: { configuration.aiChatEnabled },
                            set: { configuration.aiChatEnabled = $0 }
                        )) {
                            Label(String(localized: "ai.features.chat"),
                                  systemImage: "bubble.left.and.text.bubble.right")
                        }
                    } header: {
                        Text(String(localized: "ai.features.section"))
                    }
                }

                // MARK: Excluded Tags
                Section {
                    if isLoadingTags {
                        ProgressView()
                    } else {
                        NavigationLink {
                            ExcludedTagsSelectionView(allTags: allTags)
                        } label: {
                            excludedTagsPillRow
                        }
                    }
                } header: {
                    Text(String(localized: "settings.section.excluded_tags"))
                } footer: {
                    Text(String(localized: "settings.excluded_tags.footer"))
                }
            }
            .navigationTitle(String(localized: "nav.settings"))
            .task {
                guard configuration.canConnect && configuration.didLoadFromKeychain else { return }
                await testPaperlessConnection()
                await loadTags()
                await testAIConnection()
            }
        }
    }

    // MARK: - Excluded Tags row

    @ViewBuilder
    private var excludedTagsPillRow: some View {
        let excluded = allTags.filter { configuration.excludedTagIDs.contains($0.id) }
        if excluded.isEmpty {
            Text(String(localized: "filter.option.none"))
                .foregroundStyle(.secondary)
        } else {
            HStack(spacing: 4) {
                let visible = Array(excluded.prefix(3))
                let overflow = excluded.count - visible.count
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
    }

    // MARK: - Actions

    private func testPaperlessConnection() async {
        guard configuration.canConnect else { return }
        isTestingPaperless = true
        paperlessVersion = nil
        paperlessError = nil
        defer { isTestingPaperless = false }
        do {
            let remote = try await PaperlessAPI.status(
                serverURL: configuration.serverURL,
                token: configuration.apiToken
            )
            paperlessVersion = remote.pngxVersion
        } catch {
            paperlessError = PaperlessAPI.formattedUserError(error)
                ?? (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }

    private func testAIConnection() async {
        guard configuration.hasAIServer else { return }
        isTestingAI = true
        aiConnectedVersion = nil
        aiError = nil
        defer { isTestingAI = false }
        let url = configuration.aiServerURL
        let key = configuration.aiApiKey
        do {
            if !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                _ = try await AIServerAPI.ragStatus(serverURL: url, apiKey: key)
            }
            let health = try await AIServerAPI.health(serverURL: url, apiKey: key)
            aiConnectedVersion = health.version ?? ""
        } catch {
            aiError = PaperlessAPI.formattedUserError(error)
                ?? (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }

    private func loadTags() async {
        guard configuration.canConnect else { return }
        isLoadingTags = true
        defer { isLoadingTags = false }
        do {
            allTags = try await PaperlessAPI.tags(
                serverURL: configuration.serverURL,
                token: configuration.apiToken
            )
        } catch {
            allTags = []
        }
    }
}

// MARK: - ExcludedTagsSelectionView

struct ExcludedTagsSelectionView: View {
    @Environment(AppConfiguration.self) private var configuration
    let allTags: [TagSummary]

    var body: some View {
        List(allTags) { tag in
            Button {
                if configuration.excludedTagIDs.contains(tag.id) {
                    configuration.excludedTagIDs.remove(tag.id)
                } else {
                    configuration.excludedTagIDs.insert(tag.id)
                }
            } label: {
                HStack {
                    Text(tag.name).foregroundStyle(.primary)
                    Spacer()
                    if configuration.excludedTagIDs.contains(tag.id) {
                        Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                    }
                }
            }
        }
        .navigationTitle(String(localized: "settings.excluded_tags.nav_title"))
        .toolbar(.hidden, for: .tabBar)
    }
}

#Preview {
    SettingsView()
        .environment(AppConfiguration())
}
