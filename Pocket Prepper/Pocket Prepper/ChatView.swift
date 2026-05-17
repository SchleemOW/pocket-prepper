import SwiftUI
import Combine

struct ChatView: View {
    let module: Module
    @EnvironmentObject var llmService: LLMService
    @State private var messages: [ChatMessage] = []
    @State private var inputText = ""
    @State private var isThinking = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            ForEach(messages) { message in
                                MessageBubble(message: message)
                                    .id(message.id)
                            }
                            if isThinking {
                                ThinkingIndicator()
                                    .id("thinking")
                            }
                        }
                        .padding()
                    }
                    .onChange(of: messages.count) {
                        if let last = messages.last {
                            withAnimation {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }

                Divider().background(Color.green.opacity(0.3))

                HStack(spacing: 12) {
                    TextField("Ask anything...", text: $inputText, axis: .vertical)
                        .font(.system(.callout, design: .monospaced))
                        .foregroundColor(.white)
                        .tint(.green)
                        .lineLimit(1...4)
                        .focused($inputFocused)
                        .onSubmit { sendMessage() }

                    Button {
                        sendMessage()
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.black)
                            .frame(width: 32, height: 32)
                            .background(inputText.isEmpty || isThinking ? Color.gray : Color.green)
                            .cornerRadius(16)
                    }
                    .disabled(inputText.isEmpty || isThinking)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.black)
            }
        }
        .navigationTitle(module.name.uppercased())
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.black, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .preferredColorScheme(.dark)
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isThinking else { return }

        inputText = ""
        inputFocused = false
        isThinking = true

        messages.append(ChatMessage(role: .user, text: text))

        Task {
            let chunks = await Task.detached(priority: .userInitiated) {
                RAGService.shared.retrieve(question: text, module: self.module)
            }.value

            let sources = RAGService.shared.uniqueTitles(from: chunks)

            let answer: String
            if chunks.isEmpty {
                answer = "No relevant information found. Try rephrasing your question or selecting a different module."
            } else {
                // Show the most relevant chunks with source labels
                answer = chunks.enumerated().map { (i, chunk) in
                    let header = chunk.title.isEmpty ? "" : "[\(chunk.title)]\n"
                    return "\(header)\(chunk.text.trimmingCharacters(in: .whitespacesAndNewlines))"
                }.joined(separator: "\n\n---\n\n")
            }

            await MainActor.run {
                messages.append(ChatMessage(role: .assistant, text: answer, sources: sources))
                isThinking = false
            }
        }
    }
}

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(message.role == .user ? "YOU" : "PREPPER")
                .font(.system(.caption2, design: .monospaced).weight(.bold))
                .foregroundColor(message.role == .user ? .gray : .green)

            Text(message.text)
                .font(.system(.callout, design: .monospaced))
                .foregroundColor(.white)
                .textSelection(.enabled)

            if !message.sources.isEmpty {
                Text("SRC: \(message.sources.joined(separator: ", "))")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.gray.opacity(0.5))
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            message.role == .user
                ? Color.white.opacity(0.05)
                : Color.green.opacity(0.05)
        )
        .cornerRadius(8)
    }
}

struct ThinkingIndicator: View {
    @State private var dotCount = 0
    let timer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()

    var body: some View {
        Text("SEARCHING" + String(repeating: ".", count: dotCount))
            .font(.system(.caption, design: .monospaced))
            .foregroundColor(.green.opacity(0.6))
            .onReceive(timer) { _ in
                dotCount = (dotCount + 1) % 4
            }
    }
}
