import SwiftUI

struct AIServerSettingsView: View {
    @Environment(AppConfiguration.self) private var configuration

    @State private var isSaved = false
    @State private var saveError: String?
    @State private var isTesting = false
    @State private var healthStatus: AIServerStatus?
    @State private var ragStatus: AIRagStatus?
    @State private var connectionErrorMessage: String?
    @State private var testedURL = ""
    @State private var testedKey = ""
    @State private var showConnectionErrorSheet = false
    @State private var isTriggering = false
    @State private var triggerMessage: String?

    private var credentialsMatchLastTest: Bool {
        configuration.aiServerURL == testedURL && configuration.aiApiKey == testedKey
    }

    var body: some View {
        @Bindable var config = configuration
        return Form {
            Section {
                TextField(
                    String(localized: "ai.settings.field.url"),
                    text: $config.aiServerURL
                )
                .textContentType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                #if os(iOS)
                    .keyboardType(.URL)
                #endif
                .onChange(of: config.aiServerURL) {
                    isSaved = false
                    healthStatus = nil
                    ragStatus = nil
                    connectionErrorMessage = nil
                    testedURL = ""
                    testedKey = ""
                }

                SecureField(
                    String(localized: "ai.settings.field.api_key"),
                    text: $config.aiApiKey
                )
                .textContentType(.password)
                .autocorrectionDisabled()
                .onChange(of: config.aiApiKey) {
                    isSaved = false
                    healthStatus = nil
                    ragStatus = nil
                    connectionErrorMessage = nil
                    testedURL = ""
                    testedKey = ""
                }

                if isSaved {
                    Label(String(localized: "server.settings.saved_in_keychain"),
                          systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Button(action: saveURL) {
                        Label(String(localized: "server.settings.button.save"),
                              systemImage: "lock.icloud")
                    }
                    .disabled(!configuration.hasAIServer)

                    if let saveError {
                        Text(saveError).foregroundStyle(.red)
                    }
                }
            } header: {
                Text(String(localized: "ai.settings.section.server"))
            } footer: {
                Text(String(localized: "ai.settings.footer"))
            }

            Section(String(localized: "server.settings.section.connection")) {
                if isTesting {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(String(localized: "server.settings.testing_connection"))
                            .foregroundStyle(.secondary)
                    }
                } else if let health = healthStatus, credentialsMatchLastTest, health.isHealthy {
                    Label(
                        health.version.map { String(format: String(localized: "ai.settings.status.connected_version"), $0) }
                            ?? String(localized: "ai.settings.status.connected"),
                        systemImage: "checkmark.circle.fill"
                    )
                    .foregroundStyle(.green)
                } else if let error = connectionErrorMessage, !error.isEmpty, credentialsMatchLastTest {
                    Button {
                        showConnectionErrorSheet = true
                    } label: {
                        Label(String(localized: "server.status.connection_failed"),
                              systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                    .sheet(isPresented: $showConnectionErrorSheet) {
                        ErrorDetailSheet(
                            title: String(localized: "error.detail.title"),
                            detail: error
                        )
                    }
                } else {
                    Button(String(localized: "server.settings.button.test_connection")) {
                        Task { await testConnection() }
                    }
                    .disabled(!configuration.hasAIServer)
                }
            }

            if let rag = ragStatus, credentialsMatchLastTest {
                ragStatisticsSection(rag)

                Section {
                    if isTriggering {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text(String(localized: "ai.settings.index.triggering"))
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Button {
                            Task { await triggerReindex() }
                        } label: {
                            Label(String(localized: "ai.settings.index.trigger"), systemImage: "arrow.trianglehead.2.clockwise")
                        }
                    }
                    if let msg = triggerMessage {
                        Text(msg).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Toggle(isOn: $config.aiSemanticSearchEnabled) {
                    Label(String(localized: "ai.settings.semantic_search"),
                          systemImage: "sparkle.magnifyingglass")
                }
                .disabled(!configuration.hasAIServer || healthStatus?.isHealthy != true)
            } header: {
                Text(String(localized: "ai.settings.section.features"))
            } footer: {
                Text(String(localized: "ai.settings.semantic_search.footer"))
            }
        }
        .navigationTitle(String(localized: "ai.settings.nav.title"))
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            if healthStatus?.isHealthy == true && credentialsMatchLastTest {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await testConnection() }
                    } label: {
                        Label(String(localized: "status.button.refresh"), systemImage: "arrow.clockwise")
                    }
                    .disabled(isTesting)
                }
            }
        }
        .task {
            isSaved = configuration.hasAIServer
            if configuration.hasAIServer { await testConnection() }
        }
    }

    @ViewBuilder
    private func ragStatisticsSection(_ rag: AIRagStatus) -> some View {
        Section {
            if let count = rag.indexingStatus?.documentsCount {
                LabeledContent(String(localized: "ai.settings.stat.indexed_docs"),
                               value: count.formatted())
            }
            if let model = rag.aiModel, !model.isEmpty {
                LabeledContent(String(localized: "ai.settings.stat.model"), value: model)
            }
            ragIndexStatusRows(rag.indexingStatus)
            if let ready = rag.chromaReady {
                readinessRow(label: "Chroma", ready: ready)
            }
            if let ready = rag.bm25Ready {
                readinessRow(label: "BM25", ready: ready)
            }
        } header: {
            Text(String(localized: "ai.settings.section.statistics"))
        } footer: {
            if let msg = rag.indexingStatus?.message, !msg.isEmpty {
                Text(msg).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func ragIndexStatusRows(_ indexing: AIRagIndexingStatus?) -> some View {
        if let indexing {
            if indexing.running == true {
                LabeledContent(String(localized: "ai.settings.stat.index_status")) {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text(String(localized: "ai.settings.stat.index_running"))
                            .foregroundStyle(.secondary)
                    }
                }
            } else if let upToDate = indexing.upToDate {
                LabeledContent(String(localized: "ai.settings.stat.index_status")) {
                    Label(
                        upToDate
                            ? String(localized: "ai.settings.stat.index_up_to_date")
                            : String(localized: "ai.settings.stat.index_outdated"),
                        systemImage: upToDate ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
                    )
                    .foregroundStyle(upToDate ? .green : .orange)
                    .labelStyle(.titleAndIcon)
                }
            }
            if let last = indexing.lastIndexed {
                LabeledContent(String(localized: "ai.settings.stat.last_indexed"),
                               value: formatIndexDate(last))
            }
        }
    }

    @ViewBuilder
    private func readinessRow(label: String, ready: Bool) -> some View {
        LabeledContent(label) {
            Label(
                ready ? String(localized: "ai.settings.stat.ready")
                      : String(localized: "ai.settings.stat.not_ready"),
                systemImage: ready ? "checkmark.circle.fill" : "xmark.circle.fill"
            )
            .foregroundStyle(ready ? .green : .red)
            .labelStyle(.titleAndIcon)
        }
    }

    private func formatIndexDate(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: iso) {
            let rel = RelativeDateTimeFormatter()
            rel.unitsStyle = .full
            return rel.localizedString(for: date, relativeTo: Date())
        }
        // Fallback: strip time portion
        return String(iso.prefix(10))
    }

    private func triggerReindex() async {
        guard configuration.hasAIServerWithKey else { return }
        isTriggering = true
        triggerMessage = nil
        defer { isTriggering = false }
        do {
            try await AIServerAPI.triggerReindex(serverURL: configuration.aiServerURL, apiKey: configuration.aiApiKey)
            triggerMessage = String(localized: "ai.settings.index.triggered")
            // Refresh status after a short delay
            try? await Task.sleep(for: .seconds(2))
            ragStatus = try? await AIServerAPI.ragStatus(serverURL: configuration.aiServerURL, apiKey: configuration.aiApiKey)
        } catch {
            triggerMessage = PaperlessAPI.formattedUserError(error)
                ?? error.localizedDescription
        }
    }

    private func saveURL() {
        saveError = nil
        do {
            try configuration.saveAIServerURL()
            try configuration.saveAIApiKey()
            isSaved = true
            Task { await testConnection() }
        } catch {
            saveError = error.localizedDescription
            isSaved = false
        }
    }

    private func testConnection() async {
        guard configuration.hasAIServer else { return }
        // Save silently without triggering another testConnection() call
        try? configuration.saveAIServerURL()
        try? configuration.saveAIApiKey()
        isSaved = true
        isTesting = true
        defer { isTesting = false }
        let url = configuration.aiServerURL
        let key = configuration.aiApiKey
        do {
            // If an API key is configured, verify it against an authenticated endpoint first
            if !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ragStatus = try await AIServerAPI.ragStatus(serverURL: url, apiKey: key)
            }
            healthStatus = try await AIServerAPI.health(serverURL: url, apiKey: key)
            testedURL = url
            testedKey = key
            connectionErrorMessage = nil
        } catch {
            healthStatus = nil
            ragStatus = nil
            testedURL = url
            testedKey = key
            connectionErrorMessage = PaperlessAPI.formattedUserError(error)
                ?? (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        AIServerSettingsView()
            .environment(AppConfiguration())
    }
}
