import SwiftUI

/// Configuration page for the Paperless-ngx server.
/// Shows URL + token fields, a connection test, and — once connected — the full server status inline.
struct PaperlessServerSettingsView: View {
    @Environment(AppConfiguration.self) private var configuration

    @State private var saveError: String?
    @State private var isSaved = false
    @State private var isTestingConnection = false
    @State private var connectionOKVersion: String?
    @State private var connectionErrorMessage: String?
    @State private var testedURL = ""
    @State private var testedToken = ""
    @State private var showConnectionErrorSheet = false
    @State private var status: RemoteStatus?
    @State private var statistics: RemoteStatistics?

    private var credentialsMatchLastTest: Bool {
        configuration.serverURL == testedURL && configuration.apiToken == testedToken
    }

    var body: some View {
        @Bindable var config = configuration
        return Form {
            // MARK: Credentials
            Section {
                TextField(String(localized: "server.settings.field.url"), text: $config.serverURL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    #if os(iOS)
                        .keyboardType(.URL)
                    #endif
                    .onChange(of: config.serverURL) {
                        isSaved = false
                        connectionOKVersion = nil
                        connectionErrorMessage = nil
                        status = nil
                    }

                SecureField(String(localized: "server.settings.field.token"), text: $config.apiToken)
                    .textContentType(.password)
                    .autocorrectionDisabled()
                    .onChange(of: config.apiToken) {
                        isSaved = false
                        connectionOKVersion = nil
                        connectionErrorMessage = nil
                        status = nil
                    }

                if isSaved {
                    Label(String(localized: "server.settings.saved_in_keychain"),
                          systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Button(action: saveCredentials) {
                        Label(String(localized: "server.settings.button.save"),
                              systemImage: "lock.icloud")
                    }
                    .disabled(!configuration.canConnect)

                    if let saveError {
                        Text(saveError).foregroundStyle(.red)
                    }
                }
            } header: {
                Text(String(localized: "server.settings.section.server"))
            } footer: {
                Text(String(localized: "server.settings.footer"))
            }

            // MARK: Connection
            Section(String(localized: "server.settings.section.connection")) {
                if isTestingConnection {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(String(localized: "server.settings.testing_connection"))
                            .foregroundStyle(.secondary)
                    }
                } else if let version = connectionOKVersion, credentialsMatchLastTest {
                    Label(String(format: String(localized: "server.settings.connected"), version),
                          systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else if let errorMessage = connectionErrorMessage, !errorMessage.isEmpty, credentialsMatchLastTest {
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
                            detail: errorMessage
                        )
                    }
                } else {
                    Button(String(localized: "server.settings.button.test_connection")) {
                        Task { await testConnection() }
                    }
                    .disabled(!configuration.canConnect)
                }
            }

            // MARK: Status (only when connected)
            if let status, credentialsMatchLastTest, connectionOKVersion != nil {
                statusSections(status: status, statistics: statistics)
            }
        }
        .navigationTitle(String(localized: "server.settings.section.server"))
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            if connectionOKVersion != nil && credentialsMatchLastTest {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await testConnection() }
                    } label: {
                        Label(String(localized: "status.button.refresh"), systemImage: "arrow.clockwise")
                    }
                    .disabled(isTestingConnection)
                }
            }
        }
        .task {
            isSaved = configuration.didLoadFromKeychain && configuration.canConnect
            guard configuration.canConnect && configuration.didLoadFromKeychain else { return }
            await testConnection()
        }
    }

    // MARK: - Status sections

    @ViewBuilder
    private func statusSections(status: RemoteStatus, statistics: RemoteStatistics?) -> some View {
        if let statistics {
            Section(String(localized: "status.section.library")) {
                if let total = statistics.documentsTotal {
                    LabeledContent(String(localized: "status.field.documents"), value: "\(total)")
                }
                if let inbox = statistics.documentsInbox {
                    LabeledContent(String(localized: "status.field.inbox"), value: "\(inbox)")
                }
                if let tags = statistics.tagCount {
                    LabeledContent(String(localized: "status.field.tag_count"), value: "\(tags)")
                }
                if let types = statistics.documentTypeCount {
                    LabeledContent(String(localized: "status.field.document_types"), value: "\(types)")
                }
            }
        }

        Section(String(localized: "status.section.server")) {
            LabeledContent("Paperless-ngx", value: status.pngxVersion)
            if let install = status.installType {
                LabeledContent(String(localized: "status.field.install_type"), value: install.capitalized)
            }
            if let os = status.serverOs {
                LabeledContent(String(localized: "status.field.host_os"), value: os)
            }
        }

        if let storage = status.storage, storage.total != nil || storage.available != nil {
            Section(String(localized: "status.section.storage")) {
                if let total = storage.total {
                    LabeledContent(String(localized: "status.field.storage_total"),
                                   value: ByteCountFormatter.string(fromByteCount: total, countStyle: .binary))
                }
                if let available = storage.available {
                    LabeledContent(String(localized: "status.field.storage_available"),
                                   value: ByteCountFormatter.string(fromByteCount: available, countStyle: .binary))
                }
            }
        }

        if let database = status.database {
            Section(String(localized: "status.section.database")) {
                if let type = database.type {
                    LabeledContent(String(localized: "status.field.db_engine"), value: type.capitalized)
                }
                if let dbStatus = database.status {
                    statusRow(title: String(localized: "status.field.db_status"),
                              value: dbStatus, error: database.error)
                }
                if let migration = database.migrationStatus?.latestMigration {
                    LabeledContent(String(localized: "status.field.db_last_migration"), value: migration)
                }
            }
        }

        if let tasks = status.tasks {
            Section(String(localized: "status.section.tasks")) {
                if let redis = tasks.redisStatus {
                    statusRow(title: "Redis", value: redis, error: tasks.redisError)
                }
                if let celery = tasks.celeryStatus {
                    statusRow(title: "Celery", value: celery, error: tasks.celeryError)
                }
                if let index = tasks.indexStatus {
                    statusRow(title: String(localized: "status.field.search_index"),
                              value: index, error: tasks.indexError)
                }
                if let indexDate = tasks.indexLastModified {
                    LabeledContent(String(localized: "status.field.index_updated"),
                                   value: formatted(indexDate))
                }
                if let classifier = tasks.classifierStatus {
                    statusRow(title: String(localized: "status.field.classifier"),
                              value: classifier, error: tasks.classifierError)
                }
                if let trained = tasks.classifierLastTrained {
                    LabeledContent(String(localized: "status.field.classifier_trained"),
                                   value: formatted(trained))
                }
                if let sanity = tasks.sanityCheckStatus {
                    statusRow(title: String(localized: "status.field.integrity_check"),
                              value: sanity, error: tasks.sanityCheckError)
                }
            }
        }
    }

    @ViewBuilder
    private func statusRow(title: String, value: String, error: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent(title) {
                Text(value).foregroundStyle(statusColor(value))
            }
            if let error, !error.isEmpty {
                Text(error).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Helpers

    private func statusColor(_ value: String) -> Color {
        switch value.uppercased() {
        case "OK": return .green
        case "WARNING": return .orange
        case "ERROR", "FAILURE": return .red
        default: return .primary
        }
    }

    private func formatted(_ isoString: String) -> String {
        var s = isoString
        if let r = s.range(of: #"\.\d{4,}"#, options: .regularExpression) {
            s.replaceSubrange(r, with: "." + s[r].dropFirst().prefix(3))
        }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d.formatted(.dateTime) }
        f.formatOptions = [.withInternetDateTime]
        if let d = f.date(from: s) { return d.formatted(.dateTime) }
        return isoString
    }

    private func testConnection() async {
        guard configuration.canConnect else { return }
        saveCredentials()
        isTestingConnection = true
        defer { isTestingConnection = false }
        let url = configuration.serverURL
        let token = configuration.apiToken
        do {
            async let statusTask = PaperlessAPI.status(serverURL: url, token: token)
            async let statsTask = PaperlessAPI.statistics(serverURL: url, token: token)
            let remote = try await statusTask
            connectionOKVersion = remote.pngxVersion
            status = remote
            statistics = try? await statsTask
            testedURL = url
            testedToken = token
            connectionErrorMessage = nil
        } catch {
            connectionOKVersion = nil
            status = nil
            statistics = nil
            connectionErrorMessage = PaperlessAPI.formattedUserError(error)
                ?? (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }

    private func saveCredentials() {
        saveError = nil
        do {
            try configuration.saveToKeychain()
            isSaved = true
        } catch {
            saveError = error.localizedDescription
            isSaved = false
        }
    }
}

#Preview {
    NavigationStack {
        PaperlessServerSettingsView()
            .environment(AppConfiguration())
    }
}
