/// Chat view for asking free-form questions about the document archive via RAG.
import SwiftUI

struct DocumentChatView: View {
    @Environment(AppConfiguration.self) private var configuration
    @Environment(TabRouter.self) private var tabRouter

    @State private var messages: [ChatMessage] = []
    @State private var inputText = ""
    @State private var isAsking = false
    @State private var scrollProxy: ScrollViewProxy?

    var body: some View {
        NavigationStack {
            Group {
                if !configuration.hasAIServer {
                    ContentUnavailableView {
                        Label(String(localized: "chat.unavailable.title"), systemImage: "sparkles")
                    } description: {
                        Text(String(localized: "chat.unavailable.description"))
                    } actions: {
                        Button(String(localized: "chat.unavailable.button")) {
                            tabRouter.selectedTab = 3
                        }
                        .buttonStyle(.bordered)
                    }
                } else {
                    chatContent
                }
            }
            .navigationTitle(String(localized: "tab.chat"))
        }
    }

    // MARK: - Chat content

    private var chatContent: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if messages.isEmpty {
                            emptyState
                        } else {
                            ForEach(messages) { message in
                                MessageBubble(message: message)
                                    .id(message.id)
                            }
                        }
                    }
                    .padding(.vertical, 12)
                }
                .scrollDismissesKeyboard(.interactively)
                .onAppear { scrollProxy = proxy }
                .onChange(of: messages.count) { _, _ in
                    if let last = messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            Divider()

            inputBar
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
                .padding(.top, 60)
            Text(String(localized: "chat.empty.title"))
                .font(.headline)
            Text(String(localized: "chat.empty.subtitle"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity)
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField(String(localized: "chat.input.placeholder"), text: $inputText, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .disabled(isAsking)

            Button {
                Task { await sendMessage() }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(canSend ? Color.accentColor : Color.secondary)
            }
            .disabled(!canSend)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.systemGroupedBackground))
    }

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isAsking
    }

    // MARK: - Send

    private func sendMessage() async {
        let question = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        inputText = ""
        isAsking = true
        defer { isAsking = false }

        var message = ChatMessage(question: question, isLoading: true)
        messages.append(message)

        do {
            let response = try await AIServerAPI.ragAsk(
                question: question,
                serverURL: configuration.aiServerURL,
                apiKey: configuration.aiApiKey
            )
            message.answer = response.answer
            message.sources = response.sources ?? []
            message.isLoading = false
        } catch {
            message.answer = nil
            message.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            message.isLoading = false
        }

        if let idx = messages.firstIndex(where: { $0.id == message.id }) {
            messages[idx] = message
        }
    }
}

// MARK: - Message model

struct ChatMessage: Identifiable {
    let id = UUID()
    let question: String
    var answer: String?
    var sources: [AIRagSource] = []
    var isLoading: Bool
    var error: String?
}

// MARK: - Message Bubble

private struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Question
            HStack {
                Spacer()
                Text(message.question)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .padding(.leading, 60)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            // Answer / loading / error
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)

                if message.isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.top, 2)
                } else if let error = message.error {
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                } else if let answer = message.answer {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(answer)
                            .font(.subheadline)

                        if !message.sources.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(message.sources.prefix(3), id: \.docId) { source in
                                    if let title = source.title {
                                        Label(title, systemImage: "doc.text")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                        }
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.trailing, 60)
            .padding(.bottom, 16)
        }
    }
}

#Preview {
    DocumentChatView()
        .environment(AppConfiguration())
        .environment(TabRouter())
}
