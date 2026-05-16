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
    @State private var splashScale: CGFloat = 1.0
    @State private var splashOpacity: Double = 1.0

    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                Tab(String(localized: "tab.capture"), systemImage: "doc.badge.plus", value: 0) {
                    CaptureView()
                }

                Tab(String(localized: "tab.documents"), systemImage: "doc.text.magnifyingglass", value: 1) {
                    DocumentListView()
                }

                Tab(String(localized: "tab.settings"), systemImage: "gearshape", value: 2) {
                    SettingsView()
                }
            }
            .opacity(showSplash ? 0 : 1)

            if showSplash {
                splashView
                    .transition(.opacity)
            }
        }
        .task {
            configuration.loadFromKeychain()
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            withAnimation(.easeInOut(duration: 0.4)) {
                splashScale = 1.15
                splashOpacity = 0
            }
            try? await Task.sleep(nanoseconds: 400_000_000)
            showSplash = false
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
        GeometryReader { geo in
            Color(.systemBackground)
                .ignoresSafeArea()
                .overlay {
                    Image("AppLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 180, height: 180)
                        .scaleEffect(splashScale)
                        .opacity(splashOpacity)
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                }
        }
        .ignoresSafeArea()
    }
}

#Preview {
    RootView()
        .environment(AppConfiguration())
        .environment(ImportQueue())
        .environment(NetworkMonitor())
}
