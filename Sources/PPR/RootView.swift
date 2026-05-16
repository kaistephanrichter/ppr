import SwiftUI

/// Tab-based root view. Shows onboarding on first launch (when no server is configured),
/// then provides three tabs: Capture, Documents, and Settings.
struct RootView: View {
    @Environment(AppConfiguration.self) private var configuration
    @Environment(ImportQueue.self) private var importQueue
    @Environment(NetworkMonitor.self) private var networkMonitor

    @State private var selectedTab = 0
    @State private var showOnboarding = false
    @State private var showSplash = true
    @State private var splashScale: CGFloat = 0.6
    @State private var splashOpacity: Double = 0

    var body: some View {
        ZStack {
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
            .opacity(showSplash ? 0 : 1)

            if showSplash {
                splashView
                    .transition(.opacity)
            }
        }
        .task {
            configuration.loadFromKeychain()
            withAnimation(.easeOut(duration: 0.4)) {
                splashOpacity = 1
                splashScale = 1.0
            }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            withAnimation(.easeOut(duration: 0.3)) { showSplash = false }
            await LocalNetworkAccess.warmUpBonjourBrowse()
            if configuration.serverURL.isEmpty {
                showOnboarding = true
            }
            if configuration.canConnect {
                networkMonitor.startMonitoring(
                    serverURL: configuration.serverURL,
                    token: configuration.apiToken
                )
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

    private var splashView: some View {
        Color(.systemBackground)
            .ignoresSafeArea()
            .overlay {
                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 160, height: 160)
                    .scaleEffect(splashScale)
                    .opacity(splashOpacity)
            }
    }
}

#Preview {
    RootView()
        .environment(AppConfiguration())
        .environment(ImportQueue())
        .environment(NetworkMonitor())
}
