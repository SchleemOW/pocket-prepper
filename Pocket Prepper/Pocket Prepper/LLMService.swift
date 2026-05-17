import Combine
import Foundation

// RAG-only mode for iPhone 14 (6GB RAM)
// Shows retrieved chunks directly from military manuals and medical guides.
// No on-device LLM - the source material is already high quality.

@MainActor
class LLMService: ObservableObject {
    static let shared = LLMService()

    @Published var isLoaded = true  // Always "ready" - no model to load
    @Published var isLoading = false
    @Published var loadingProgress: Double = 1.0
    @Published var isGenerating = false

    func loadModel() async {
        // No model needed in RAG-only mode
        isLoaded = true
    }

    func generate(
        question: String,
        context: String,
        onToken: @escaping @Sendable (String) -> Void
    ) async -> String {
        // In RAG-only mode, just return the context directly
        return context
    }

    func stop() {
        isGenerating = false
    }
}
