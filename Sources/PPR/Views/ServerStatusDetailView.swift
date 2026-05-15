import SwiftUI

/// Full server status page — used both as the Status tab and as a navigation destination from Settings.
struct ServerStatusDetailView: View {
    @Environment(AppConfiguration.self) private var configuration

    @State private var status: RemoteStatus?
    @State private var statistics: RemoteStatistics?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if !configuration.canConnect {
                ContentUnavailableView(
                    String(localized: "status.not_configured.title"),
                    systemImage: "link.badge.plus",
                    description: Text(String(localized: "server.not_configured.description.settings"))
                )
            } else if isLoading && status == nil {
                ProgressView(String(localized: "status.loading"))
            } else if let errorMessage, !errorMessage.isEmpty {
                ContentUnavailableView(
                    String(localized: "documents.load_error.title"),
                    systemImage: "exclamationmark.triangle",
                    description: Text(verbatim: errorMessage)
                )
            } else if let status {
                statusList(status: status, statistics: statistics)
            } else {
                ContentUnavailableView(
                    String(localized: "status.no_data.title"),
                    systemImage: "questionmark.circle",
                    description: Text(String(localized: "status.no_data.description"))
                )
            }
        }
        .navigationTitle(String(localized: "status.nav.title"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await refresh() }
                } label: {
                    Label(String(localized: "status.button.refresh"), systemImage: "arrow.clockwise")
                }
                .disabled(!configuration.canConnect || isLoading)
            }
        }
        .refreshable { await refresh() }
        .task(id: configuration.canConnect) {
            if configuration.canConnect { await refresh() }
        }
    }

    // MARK: - Public state for compact summary

    var summaryStatus: SummaryStatus {
        if let errorMessage, !errorMessage.isEmpty { return .error }
        guard let status else { return isLoading ? .loading : .unknown }
        let tasks = status.tasks
        let hasError = [tasks?.redisStatus, tasks?.celeryStatus, tasks?.indexStatus,
                        tasks?.classifierStatus, tasks?.sanityCheckStatus, status.database?.status]
            .compactMap { $0 }
            .contains { $0.uppercased() == "ERROR" || $0.uppercased() == "FAILURE" }
        let hasWarning = [tasks?.redisStatus, tasks?.celeryStatus, tasks?.indexStatus,
                          tasks?.classifierStatus, tasks?.sanityCheckStatus, status.database?.status]
            .compactMap { $0 }
            .contains { $0.uppercased() == "WARNING" }
        if hasError { return .error }
        if hasWarning { return .warning }
        return .ok(status.pngxVersion)
    }

    enum SummaryStatus {
        case loading, unknown, ok(String), warning, error
    }

    // MARK: - Private

    @ViewBuilder
    private func statusList(status: RemoteStatus, statistics: RemoteStatistics?) -> some View {
        List {
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
                    if let unapplied = database.migrationStatus?.unappliedMigrations, !unapplied.isEmpty {
                        LabeledContent(String(localized: "status.field.db_open_migrations"),
                                       value: "\(unapplied.count)")
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
    }

    @ViewBuilder
    private func statusRow(title: String, value: String, error: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent(title) {
                Text(value)
                    .foregroundStyle(statusColor(value))
            }
            if let error, !error.isEmpty {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
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

    private func statusColor(_ value: String) -> Color {
        switch value.uppercased() {
        case "OK": return .green
        case "WARNING": return .orange
        case "ERROR", "FAILURE": return .red
        default: return .primary
        }
    }

    private func refresh() async {
        guard configuration.canConnect else { return }
        isLoading = true
        defer { isLoading = false }
        let url = configuration.serverURL
        let token = configuration.apiToken
        do {
            async let statusTask = PaperlessAPI.status(serverURL: url, token: token)
            async let statsTask = PaperlessAPI.statistics(serverURL: url, token: token)
            status = try await statusTask
            statistics = try? await statsTask
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            if Task.isCancelled { return }
            status = nil
            statistics = nil
            errorMessage = PaperlessAPI.formattedUserError(error)
                ?? (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        ServerStatusDetailView()
            .environment(AppConfiguration())
    }
}
