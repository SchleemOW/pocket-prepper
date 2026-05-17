import MLX
import Tokenizers
import Combine
import Foundation
import MLXLLM
import MLXLMCommon

@MainActor
class LLMService: ObservableObject {
    static let shared = LLMService()

    @Published var isLoaded = false
    @Published var isLoading = false
    @Published var loadingProgress: Double = 0
    @Published var isGenerating = false

    private var modelContainer: ModelContainer?
    private let modelID = "mlx-community/Llama-3.2-1B-Instruct-4bit"

    private let systemPrompt = """
        You are a practical survival and civilization-rebuilding expert. \
        Answer using ONLY the provided context from verified knowledge sources. \
        Be specific, practical, and actionable. Prioritize safety. \
        If the context lacks enough detail to answer fully, say so clearly. \
        Never invent information not present in the context.
        """

    func loadModel() async {
        guard !isLoaded && !isLoading else { return }
        isLoading = true

        do {
            let config = ModelConfiguration(id: modelID)
            modelContainer = try await LLMModelFactory.shared.loadContainer(
                configuration: config
            ) { [weak self] progress in
                Task { @MainActor [weak self] in
                    self?.loadingProgress = progress.fractionCompleted
                }
            }
            isLoaded = true
            print("LLM loaded: \(modelID)")
        } catch {
            print("Failed to load LLM: \(error)")
        }
        isLoading = false
    }

    func generate(
        question: String,
        context: String,
        onToken: @escaping @Sendable (String) -> Void
    ) async -> String {
        guard let modelContainer else {
            onToken("Model not loaded yet. Please wait for download to complete.")
            return ""
        }

        isGenerating = true
        defer { isGenerating = false }

        let fullPrompt = """
            System: \(systemPrompt)

            Context from survival knowledge base:
            \(context)

            User: \(question)

            Answer (based only on the context above):
            """

        let collector = ResponseCollector()

        do {
            let _ = try await modelContainer.perform { ctx in
                let tokens = ctx.tokenizer.encode(text: fullPrompt)
                let input = LMInput(tokens: .init(tokens))

                // Track all generated tokens to decode incrementally
                var allTokens: [Int] = []
                var previousText = ""

                return try MLXLMCommon.generate(
                    input: input,
                    parameters: GenerateParameters(temperature: 0.3),
                    context: ctx
                ) { newTokens in
                    // Append new tokens to our running list
                    allTokens.append(contentsOf: newTokens)

                    // Decode ALL tokens so far
                    let fullText = ctx.tokenizer.decode(tokens: allTokens)

                    // Extract only the NEW text since last decode
                    let newText: String
                    if fullText.count > previousText.count {
                        newText = String(fullText.dropFirst(previousText.count))
                    } else {
                        newText = ""
                    }
                    previousText = fullText

                    if !newText.isEmpty {
                        Task { @MainActor in onToken(newText) }
                        Task { await collector.append(newText) }
                    }

                    return .more
                }
            }
        } catch {
            print("Generation error: \(error)")
            onToken("\n[Error generating response]")
        }

        return await collector.value
    }

    func stop() {
        isGenerating = false
    }
}

actor ResponseCollector {
    private(set) var value: String = ""
    func append(_ text: String) { value += text }
}
