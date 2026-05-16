/// PPR – Paperless-ngx iOS Client
/// Main app entry point. Sets up the environment with shared configuration
/// and import queue, and handles file open URLs for document import.
import SwiftUI

@main
struct PPRApp: App {
    @State private var configuration = AppConfiguration()
    @State private var importQueue = ImportQueue()
    @State private var networkMonitor = NetworkMonitor()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(configuration)
                .environment(importQueue)
                .environment(networkMonitor)
                .onOpenURL { url in
                    importQueue.receive(url: url)
                }
        }
    }
}
