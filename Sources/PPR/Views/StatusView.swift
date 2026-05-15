import SwiftUI

struct StatusView: View {
    var body: some View {
        NavigationStack {
            ServerStatusDetailView()
        }
    }
}

#Preview {
    StatusView()
        .environment(AppConfiguration())
}
