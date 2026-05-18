import Foundation
import Combine

// MARK: - Device Capability Detection

func deviceModelIdentifier() -> String {
    var sysinfo = utsname()
    uname(&sysinfo)
    return withUnsafePointer(to: &sysinfo.machine) {
        $0.withMemoryRebound(to: CChar.self, capacity: 1) {
            String(validatingUTF8: $0) ?? "unknown"
        }
    }
}

func isCapableOfOnDeviceAI() -> Bool {
    #if targetEnvironment(simulator)
    return true // Simulator uses Ollama, always "capable"
    #else
    let model = deviceModelIdentifier()
    // A17 Pro chip or newer: iPhone 15 Pro, 15 Pro Max, 16, 16 Plus, 16 Pro, 16 Pro Max
    let capableModels = [
        "iPhone16,2", "iPhone16,3",   // iPhone 15 Pro, 15 Pro Max
        "iPhone17,1", "iPhone17,2",   // iPhone 16, 16 Plus
        "iPhone17,3", "iPhone17,4",   // iPhone 16 Pro, 16 Pro Max
    ]
    return capableModels.contains(model)
    #endif
}

// MARK: - LLMService

@MainActor
class LLMService: ObservableObject {
    static let shared = LLMService()

    @Published var isLoaded = false
    @Published var isLoading = false
    @Published var loadingProgress: Double = 0
    @Published var isGenerating = false

    /// Whether this device can run on-device AI (A17 Pro chip or newer)
    let isAICapable: Bool = isCapableOfOnDeviceAI()

    func loadModel() async {
        #if targetEnvironment(simulator)
        // Simulator: Ollama handles inference, nothing to load
        isLoaded = true
        #else
        guard isAICapable else {
            // RAG-only device — mark as "loaded" so UI doesn't show spinner
            isLoaded = true
            return
        }
        // TODO: Load MLX model here for capable devices
        // For now, fall through to RAG-only until MLX integration is restored
        isLoaded = true
        #endif
    }

    func generate(
        question: String,
        context: String,
        onToken: @escaping @Sendable (String) -> Void
    ) async -> String {
        #if targetEnvironment(simulator)
        return await generateViaOllama(question: question, context: context)
        #else
        if isAICapable {
            // TODO: Route to MLX on capable devices
            // For now falls through to RAG-only
            return context
        } else {
            return context
        }
        #endif
    }

    func stop() {
        isGenerating = false
    }

    // MARK: - Ollama (simulator only)

    #if targetEnvironment(simulator)
    private func generateViaOllama(question: String, context: String) async -> String {
        let systemPrompt = """
            You are a practical survival expert. Answer using ONLY the provided context \
            from verified knowledge sources. Be specific and actionable. \
            If context lacks detail, say so. Never invent information.
            """

        let prompt = """
            Context:
            \(context)

            Question: \(question)

            Answer based only on the context above:
            """

        let body: [String: Any] = [
            "model": "mistral",
            "prompt": "\(systemPrompt)\n\n\(prompt)",
            "stream": false
        ]

        guard let url = URL(string: "http://localhost:11434/api/generate"),
              let data = try? JSONSerialization.data(withJSONObject: body) else {
            return context
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = data
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60

        guard let (responseData, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
              let response = json["response"] as? String else {
            return context
        }

        return response
    }
    #endif
}
