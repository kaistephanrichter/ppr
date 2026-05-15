import SwiftUI

@main
struct PPRApp: App {
    @State private var configuration = AppConfiguration()
    @State private var importQueue = ImportQueue()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(configuration)
                .environment(importQueue)
                .onOpenURL { url in
                    importQueue.receive(url: url)
                }
        }
    }
}
