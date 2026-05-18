import SwiftUI
import Combine

struct ChatView: View {
    let module: Module
    @EnvironmentObject var llmService: LLMService
    @EnvironmentObject var moduleManager: ModuleManager
    @State private var messages: [ChatMessage] = []
    @State private var inputText = ""
    @State private var isThinking = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {

                // MARK: - RAG-only disclaimer banner
                if !llmService.isAICapable {
                    HStack(spacing: 8) {
                        Image(systemName: "text.magnifyingglass")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.black)
                        Text("KNOWLEDGE SEARCH MODE — No AI generation on this device. Answers retrieved directly from reference manuals. Requires iPhone 15 Pro or later for on-device AI.")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.black)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.green)
                }

                // MARK: - Messages
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16) {
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
                        withAnimation {
                            if isThinking {
                                proxy.scrollTo("thinking", anchor: .bottom)
                            } else if let last = messages.last {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }

                Divider().background(Color.green.opacity(0.3))

                // MARK: - Input bar
                HStack(spacing: 12) {
                    TextField("Ask anything...", text: $inputText, axis: .vertical)
                        .font(.system(.callout, design: .monospaced))
                        .foregroundColor(.white)
                        .tint(.green)
                        .lineLimit(1...4)
                        .focused($inputFocused)
                        .onSubmit { Task { await sendMessage() } }

                    Button {
                        Task { await sendMessage() }
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.black)
                            .frame(width: 32, height: 32)
                            .background(
                                (inputText.isEmpty || isThinking)
                                    ? Color.green.opacity(0.3)
                                    : Color.green
                            )
                            .clipShape(Circle())
                    }
                    .disabled(inputText.isEmpty || isThinking)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .navigationTitle(module.name.uppercased())
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.black, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    callSOS()
                } label: {
                    Label("SOS", systemImage: "phone.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.red)
                        .clipShape(Capsule())
                }
            }
        }
    }

    // MARK: - Send message

    private func sendMessage() async {
        let question = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }

        // Guardrails
        if isBlockedQuery(question) {
            inputText = ""
            let blocked = ChatMessage(
                role: .assistant,
                text: "⚠️ This app provides reference information only. For emergencies, call 112 or your local emergency number immediately. Do not rely on this app as a substitute for emergency services."
            )
            messages.append(ChatMessage(role: .user, text: question))
            messages.append(blocked)
            return
        }

        inputText = ""
        inputFocused = false
        messages.append(ChatMessage(role: .user, text: question))
        isThinking = true

        // RAG retrieval
        let chunks = await Task.detached {
            await RAGService.shared.retrieve(question: question, module: module, topK: 15)
        }.value

        let context = RAGService.shared.buildContext(from: chunks)
        let sources = RAGService.shared.uniqueTitles(from: chunks)

        isThinking = false

        if context.isEmpty {
            messages.append(ChatMessage(
                role: .assistant,
                text: "No relevant information found in this module for that question. Try rephrasing or check another module.",
                sources: []
            ))
            return
        }

        // Generate or return RAG context
        llmService.isGenerating = true

        let response: String
        if llmService.isAICapable {
            response = await llmService.generate(
                question: question,
                context: context,
                onToken: { _ in }
            )
        } else {
            // RAG-only: return the context directly, formatted cleanly
            response = formatRAGResponse(chunks: chunks)
        }

        llmService.isGenerating = false

        // Build source attribution
        let sourceText = sources.isEmpty ? "" : "SRC: \(sources.prefix(3).joined(separator: ", "))"

        messages.append(ChatMessage(
            role: .assistant,
            text: response,
            sources: sourceText.isEmpty ? [] : [sourceText]
        ))
    }

    // MARK: - Format RAG chunks for display

    private func formatRAGResponse(chunks: [RAGChunk]) -> String {
        // Deduplicate by title, take top 4 most relevant
        var seenTitles = Set<String>()
        var dedupedChunks: [RAGChunk] = []
        for chunk in chunks {
            if !seenTitles.contains(chunk.title) {
                seenTitles.insert(chunk.title)
                dedupedChunks.append(chunk)
            }
            if dedupedChunks.count == 4 { break }
        }

        return dedupedChunks.map { chunk in
            chunk.text
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\\*\\*(.+?)\\*\\*", with: "$1", options: .regularExpression)
                .replacingOccurrences(of: "\\*(.+?)\\*", with: "$1", options: .regularExpression)
        }.joined(separator: "\n\n")
    }

    // MARK: - Guardrails

    private func isBlockedQuery(_ text: String) -> Bool {
        let lower = text.lowercased()
        let blocked = [
            "call 911", "call 112", "call emergency",
            "diagnose me", "am i going to die",
            "will this save", "guarantee", "promise me",
            "make a bomb", "how to poison", "how to kill"
        ]
        return blocked.contains { lower.contains($0) }
    }

    // MARK: - SOS

    private func callSOS() {
        if let url = URL(string: "tel://112") {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
            if message.role == .user {
                HStack {
                    Spacer(minLength: 60)
                    Text(message.text)
                        .font(.system(.callout, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.green.opacity(0.2))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.green.opacity(0.4), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("PREPPER")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.green)

                    Text(LocalizedStringKey(message.text))
                        .font(.system(.callout, design: .monospaced))
                        .foregroundColor(.white.opacity(0.9))
                        .textSelection(.enabled)

                    ForEach(message.sources, id: \.self) { source in
                        Text(source)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.green.opacity(0.6))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - Thinking Indicator

struct ThinkingIndicator: View {
    @State private var dotCount = 1
    let timer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 4) {
            Text("PREPPER")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.green)
            Text(String(repeating: ".", count: dotCount))
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(.green)
                .frame(width: 24, alignment: .leading)
        }
        .onReceive(timer) { _ in
            dotCount = dotCount % 3 + 1
        }
    }
}
