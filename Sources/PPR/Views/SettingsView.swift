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
                        ProgressView(String(localized: "server.settings.testing_connection"))
                    } else if let version = connectionOKVersion, credentialsMatchLastTest {
                        NavigationLink {
                            ServerStatusDetailView()
                        } label: {
                            Label(String(format: String(localized: "server.settings.connected"), version),
                                  systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    } else {
                        Button(String(localized: "server.settings.button.test_connection")) {
                            Task { await testConnection() }
                        }
                        .disabled(!config.canConnect)

                        if let connectionErrorMessage, !connectionErrorMessage.isEmpty {
                            Text(verbatim: connectionErrorMessage)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "nav.settings"))
            .task {
                isSaved = configuration.didLoadFromKeychain && configuration.canConnect
                guard configuration.canConnect && configuration.didLoadFromKeychain else { return }
                await testConnection()
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
}

#Preview {
    SettingsView()
        .environment(AppConfiguration())
}
