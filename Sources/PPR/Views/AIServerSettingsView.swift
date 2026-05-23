import SwiftUI

struct AIServerSettingsView: View {
    @Environment(AppConfiguration.self) private var configuration

    @State private var isSaved = false
    @State private var saveError: String?
    @State private var isTesting = false
    @State private var healthStatus: AIServerStatus?
    @State private var connectionErrorMessage: String?
    @State private var testedURL = ""

    private var credentialsMatchLastTest: Bool {
        configuration.aiServerURL == testedURL
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
                    connectionErrorMessage = nil
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
                    connectionErrorMessage = nil
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
                        health.version.map { String(format: String(localized: "server.settings.connected"), $0) }
                            ?? String(localized: "ai.settings.status.connected"),
                        systemImage: "checkmark.circle.fill"
                    )
                    .foregroundStyle(.green)
                } else if let error = connectionErrorMessage, !error.isEmpty, credentialsMatchLastTest {
                    Label(error, systemImage: "xmark.circle.fill")
                        .foregroundStyle(.red)
                } else {
                    Button(String(localized: "server.settings.button.test_connection")) {
                        Task { await testConnection() }
                    }
                    .disabled(!configuration.hasAIServer)
                }
            }

            if let health = healthStatus, credentialsMatchLastTest {
                Section(String(localized: "ai.settings.section.details")) {
                    if let version = health.version {
                        LabeledContent("paperless-ai", value: version)
                    }
                    if let status = health.status {
                        LabeledContent(String(localized: "ai.settings.field.status")) {
                            Text(status)
                                .foregroundStyle(health.isHealthy ? .green : .red)
                        }
                    }
                    if let message = health.message, !message.isEmpty {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
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
        .task {
            isSaved = configuration.hasAIServer
            if configuration.hasAIServer { await testConnection() }
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
            healthStatus = try await AIServerAPI.health(serverURL: url, apiKey: key)
            testedURL = url
            connectionErrorMessage = nil
        } catch {
            healthStatus = nil
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
