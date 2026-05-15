import SwiftUI

/// Tab-based root view. Shows onboarding on first launch (when no server is configured),
/// then provides three tabs: Capture, Documents, and Settings.
struct RootView: View {
    @Environment(AppConfiguration.self) private var configuration
    @Environment(ImportQueue.self) private var importQueue

    @State private var selectedTab = 0
    @State private var showOnboarding = false

    var body: some View {
        TabView(selection: $selectedTab) {
            CaptureView()
                .tabItem { Label(String(localized: "tab.capture"), systemImage: "doc.badge.plus") }
                .tag(0)

            DocumentListView()
                .tabItem { Label(String(localized: "tab.documents"), systemImage: "doc.text.magnifyingglass") }
                .tag(1)

            SettingsView()
                .tabItem { Label(String(localized: "tab.settings"), systemImage: "gearshape") }
                .tag(2)
        }
        .task {
            configuration.loadFromKeychain()
            await LocalNetworkAccess.warmUpBonjourBrowse()
            if configuration.serverURL.isEmpty {
                showOnboarding = true
            }
        }
        .onChange(of: importQueue.pendingDocument) { _, newValue in
            if newValue != nil {
                selectedTab = 0
            }
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView()
        }
    }
}

#Preview {
    RootView()
        .environment(AppConfiguration())
        .environment(ImportQueue())
}
