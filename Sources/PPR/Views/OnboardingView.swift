/// Onboarding screen shown on first launch when no server is configured.
/// Collects server URL and API token, saves to keychain, then dismisses.
import SwiftUI

struct OnboardingView: View {
    @Environment(AppConfiguration.self) private var configuration
    @Environment(\.dismiss) private var dismiss

    @State private var serverURL = ""
    @State private var apiToken = ""
    @State private var isSaving = false
    @State private var saveError: String?

    private var canStart: Bool {
        !serverURL.trimmingCharacters(in: .whitespaces).isEmpty &&
        !apiToken.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // MARK: Logo + Welcome
                VStack(spacing: 16) {
                    Image("AppLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 120, height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 26))
                        .padding(.top, 60)

                    Text(String(localized: "onboarding.welcome.title"))
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)

                    Text(String(localized: "onboarding.welcome.subtitle"))
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)

                // MARK: Requirement note
                VStack(spacing: 8) {
                    Text(String(localized: "onboarding.requirement.description"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Link(String(localized: "onboarding.requirement.link"),
                         destination: URL(string: "https://docs.paperless-ngx.com")!)
                        .font(.subheadline)
                }
                .padding(.horizontal, 32)
                .padding(.top, 24)

                // MARK: Form fields
                VStack(spacing: 0) {
                    // Server URL section
                    VStack(alignment: .leading, spacing: 6) {
                        Text(String(localized: "onboarding.server.section.title"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)

                        TextField(
                            String(localized: "onboarding.server.url.placeholder"),
                            text: $serverURL
                        )
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .padding()
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, 16)

                        Text(String(localized: "onboarding.server.url.footer"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                    }
                    .padding(.top, 32)

                    // API Token section
                    VStack(alignment: .leading, spacing: 6) {
                        Text(String(localized: "onboarding.token.section.title"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)

                        SecureField(
                            String(localized: "onboarding.token.placeholder"),
                            text: $apiToken
                        )
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .padding()
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, 16)

                        Text(String(localized: "onboarding.token.instructions"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                    }
                    .padding(.top, 24)
                }

                // MARK: Error
                if let saveError {
                    Text(saveError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .padding(.top, 16)
                }

                // MARK: CTA
                Text(String(localized: "onboarding.permissions.note"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.top, 24)

                Button {
                    startApp()
                } label: {
                    if isSaving {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding()
                    } else {
                        Text(String(localized: "onboarding.button.start"))
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canStart || isSaving)
                .padding(.horizontal, 32)
                .padding(.top, 32)
                .padding(.bottom, 48)
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }

    private func startApp() {
        saveError = nil
        isSaving = true
        configuration.serverURL = serverURL.trimmingCharacters(in: .whitespaces)
        configuration.apiToken = apiToken.trimmingCharacters(in: .whitespaces)
        do {
            try configuration.saveToKeychain()
            dismiss()
        } catch {
            saveError = error.localizedDescription
            isSaving = false
        }
    }
}

#Preview {
    OnboardingView()
        .environment(AppConfiguration())
}
