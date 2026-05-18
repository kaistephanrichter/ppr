import SwiftUI

struct SettingsView: View {
    @Environment(AppConfiguration.self) private var configuration
    @State private var saveError: String?
    @State private var isSaved = false
    @State private var isTestingConnection = false
    @State private var connectionOKVersion: String?
    @State private var connectionErrorMessage: String?
    @State private var testedURL = ""
    @State private var testedToken = ""
    @State private var showConnectionErrorSheet = false
    @State private var connectionErrorDetail: String = ""
    @State private var allTags: [TagSummary] = []
    @State private var isLoadingTags = false

    private var credentialsMatchLastTest: Bool {
        configuration.serverURL == testedURL && configuration.apiToken == testedToken
    }

    var body: some View {
        @Bindable var config = configuration
        return NavigationStack {
            Form {
                Section {
                    TextField(String(localized: "server.settings.field.url"), text: $config.serverURL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        #if os(iOS)
                            .keyboardType(.URL)
                        #endif
                        .onChange(of: config.serverURL) { isSaved = false }

                    SecureField(String(localized: "server.settings.field.token"), text: $config.apiToken)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .onChange(of: config.apiToken) { isSaved = false }

                    if isSaved {
                        Label(String(localized: "server.settings.saved_in_keychain"),
                              systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button(action: saveCredentials) {
                            Label(String(localized: "server.settings.button.save"),
                                  systemImage: "lock.icloud")
                        }
                        .disabled(!config.canConnect)

                        if let saveError {
                            Text(saveError)
                                .foregroundStyle(.red)
                        }
                    }
                } header: {
                    Text(String(localized: "server.settings.section.server"))
                } footer: {
                    Text(String(localized: "server.settings.footer"))
                }

                Section(String(localized: "server.settings.section.connection")) {
                    if isTestingConnection {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text(String(localized: "server.settings.testing_connection"))
                                .foregroundStyle(.secondary)
                        }
                    } else if let version = connectionOKVersion, credentialsMatchLastTest {
                        NavigationLink {
                            ServerStatusDetailView()
                        } label: {
                            Label(String(format: String(localized: "server.settings.connected"), version),
                                  systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    } else if let connectionErrorMessage, !connectionErrorMessage.isEmpty, credentialsMatchLastTest {
                        Button {
                            connectionErrorDetail = connectionErrorMessage
                            showConnectionErrorSheet = true
                        } label: {
                            Label(String(localized: "server.status.connection_failed"),
                                  systemImage: "xmark.circle.fill")
                                .foregroundStyle(.red)
                        }
                        .sheet(isPresented: $showConnectionErrorSheet) {
                            ErrorDetailSheet(
                                title: String(localized: "error.detail.title"),
                                detail: connectionErrorDetail
                            )
                        }
                    } else {
                        Button(String(localized: "server.settings.button.test_connection")) {
                            Task { await testConnection() }
                        }
                        .disabled(!config.canConnect)
                    }
                }

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
                isSaved = configuration.didLoadFromKeychain && configuration.canConnect
                guard configuration.canConnect && configuration.didLoadFromKeychain else { return }
                await testConnection()
                await loadTags()
            }
        }
    }

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

    private func testConnection() async {
        connectionErrorMessage = nil
        guard configuration.canConnect else { return }
        saveCredentials()
        isTestingConnection = true
        defer { isTestingConnection = false }
        let url = configuration.serverURL
        let token = configuration.apiToken
        do {
            let remote = try await PaperlessAPI.status(serverURL: url, token: token)
            connectionOKVersion = remote.pngxVersion
            testedURL = url
            testedToken = token
            connectionErrorMessage = nil
        } catch {
            connectionOKVersion = nil
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
            Task { await LocalNetworkAccess.warmUpBonjourBrowse() }
        } catch {
            saveError = error.localizedDescription
            isSaved = false
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
                    Text(tag.name)
                        .foregroundStyle(.primary)
                    Spacer()
                    if configuration.excludedTagIDs.contains(tag.id) {
                        Image(systemName: "checkmark")
                            .foregroundStyle(Color.accentColor)
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
