import Foundation
import Combine
import SwiftUI

#if !targetEnvironment(simulator)
import MLXLLM
import Hub
import MLXLMCommon
import MLX
#endif

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
    return true
    #else
    let model = deviceModelIdentifier()
    let capableModels = [
        "iPhone14,7", "iPhone14,8",
        "iPhone15,2", "iPhone15,3",
        "iPhone15,4", "iPhone15,5",
        "iPhone16,1", "iPhone16,2",
        "iPhone17,1", "iPhone17,2",
        "iPhone17,3", "iPhone17,4",
    ]
    return capableModels.contains(model)
    #endif
}

// MARK: - On-Device Model Config

struct OnDeviceModel {
    static let displayName = "Gemma 2 2B (4-bit)"
    static let approximateSizeGB = 1.58

    /// Track download state with UserDefaults — no more path guessing
    static var isDownloaded: Bool {
        get { UserDefaults.standard.bool(forKey: "modelDownloaded") }
        set { UserDefaults.standard.set(newValue, forKey: "modelDownloaded") }
    }
}

// MARK: - LLMService

@MainActor
class LLMService: ObservableObject {
    static let shared = LLMService()

    @Published var isLoaded = false
    @Published var isLoading = false
    @Published var loadingProgress: Double = 0
    @Published var isGenerating = false
    @Published var modelDownloadProgress: Double = 0
    @Published var isDownloadingModel = false
    @Published var modelError: String? = nil

    let isAICapable: Bool = isCapableOfOnDeviceAI()

    #if !targetEnvironment(simulator)
    private var modelContainer: ModelContainer? = nil
    #endif

    private init() {}

    // MARK: - Load model

    func loadModel() async {
        #if targetEnvironment(simulator)
        isLoaded = true
        #else
        guard isAICapable else {
            isLoaded = true
            return
        }

        // Already loaded in memory — don't reload
        if modelContainer != nil {
            isLoaded = true
            return
        }

        guard OnDeviceModel.isDownloaded else {
            isLoaded = false
            return
        }

        isLoading = true
        loadingProgress = 0

        do {
            MLX.GPU.set(cacheLimit: 20 * 1024 * 1024)

            let hub = HubApi(hfToken: nil, useOfflineMode: true)

            modelContainer = try await LLMModelFactory.shared.loadContainer(
                hub: hub,
                configuration: LLMRegistry.gemma_2_2b_it_4bit
            ) { progress in
                let fraction = progress.fractionCompleted
                Task { @MainActor [weak self] in
                    self?.loadingProgress = fraction
                }
            }
            isLoaded = true
        } catch {
            modelError = "Failed to load model: \(error.localizedDescription)"
            isLoaded = false
        }

        isLoading = false
        loadingProgress = 0
        #endif
    }

    // MARK: - Download model

    func downloadModel() async {
        #if !targetEnvironment(simulator)
        guard !isDownloadingModel else { return }

        // Already downloaded and loaded — skip
        if modelContainer != nil {
            isLoaded = true
            return
        }

        isDownloadingModel = true
        modelDownloadProgress = 0
        modelError = nil

        do {
            MLX.GPU.set(cacheLimit: 20 * 1024 * 1024)

            let hub = HubApi(hfToken: nil, useOfflineMode: false)

            modelContainer = try await LLMModelFactory.shared.loadContainer(
                hub: hub,
                configuration: LLMRegistry.gemma_2_2b_it_4bit
            ) { progress in
                let fraction = progress.fractionCompleted
                Task { @MainActor [weak self] in
                    self?.modelDownloadProgress = fraction
                }
            }

            // Mark as downloaded so we don't prompt again
            OnDeviceModel.isDownloaded = true

            isDownloadingModel = false
            modelDownloadProgress = 1.0
            isLoaded = true

        } catch {
            isDownloadingModel = false
            modelError = "Download failed: \(error.localizedDescription)"
        }
        #endif
    }

    // MARK: - Generate

    func generate(
        question: String,
        context: String,
        onToken: @escaping @Sendable (String) -> Void
    ) async -> String {
        #if targetEnvironment(simulator)
        return await generateViaOllama(question: question, context: context)
        #else
        guard isAICapable, let container = modelContainer else {
            return context
        }

        isGenerating = true

        let systemPrompt = """
            You are a field survival expert. The user may be in a life-threatening situation.
            Answer ONLY from the provided context. Be direct, specific, and actionable.
            Always structure your answer as numbered steps when instructions are needed.
            Do NOT say "the text doesn't address" or "seek medical attention" as your primary answer — give the best answer the context allows first.
            Do NOT add disclaimers, caveats, or suggestions to consult professionals.
            Do NOT repeat the question. Start your answer immediately.
            If the context truly has no relevant information, say: "Not covered in this module."
            Do NOT end with phrases like "Let me know if you have other questions" or "Remember, always prioritize safety." End when the answer is complete.
            """

        let userMessage = """
            Context from verified manuals:
            \(context)

            Question: \(question)

            Answer based only on the context above:
            """

        let params = GenerateParameters(maxTokens: 1024, temperature: 0.3)
        let session = ChatSession(container, instructions: systemPrompt, generateParameters: params)

        var fullResponse = ""
        do {
            for try await token in session.streamResponse(to: userMessage) {
                fullResponse += token
                onToken(token)
            }
        } catch {
            fullResponse = context
        }

        fullResponse = fullResponse
            .replacingOccurrences(of: "<end_of_turn>", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        isGenerating = false
        return fullResponse
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
            "model": "gemma2:2b",
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
