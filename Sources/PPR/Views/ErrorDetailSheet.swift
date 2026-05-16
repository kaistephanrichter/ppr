import SwiftUI

/// A reusable sheet that displays error details with copy and dismiss actions.
struct ErrorDetailSheet: View {
    let title: String
    let detail: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(verbatim: detail)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "error.detail.copy")) {
                        UIPasteboard.general.string = detail
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "button.done")) {
                        dismiss()
                    }
                }
            }
        }
    }
}
