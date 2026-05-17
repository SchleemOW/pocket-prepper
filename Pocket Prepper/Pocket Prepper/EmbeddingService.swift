import Foundation
import CoreML

class EmbeddingService {
    static let shared = EmbeddingService()

    private var model: MiniLM?
    private let maxTokens = 128
    private let vocabURL: URL?

    // Simple whitespace tokenizer with basic wordpiece
    // For production, replace with a proper BERT tokenizer
    private var vocab: [String: Int] = [:]
    private let clsToken = 101
    private let sepToken = 102
    private let padToken = 0
    private let unkToken = 100

    init() {
        // Load Core ML model
        do {
            let config = MLModelConfiguration()
            config.computeUnits = .all // Uses Neural Engine
            model = try MiniLM(configuration: config)
        } catch {
            print("Failed to load MiniLM: \(error)")
        }

        // Load vocab from bundle
        if let url = Bundle.main.url(forResource: "vocab", withExtension: "txt") {
            vocabURL = url
            loadVocab(from: url)
        } else {
            vocabURL = nil
            print("vocab.txt not found in bundle")
        }
    }

    // MARK: - Vocab loading

    private func loadVocab(from url: URL) {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return }
        let lines = content.components(separatedBy: .newlines)
        for (index, line) in lines.enumerated() {
            let token = line.trimmingCharacters(in: .whitespaces)
            if !token.isEmpty {
                vocab[token] = index
            }
        }
    }

    // MARK: - Tokenization

    private func tokenize(_ text: String) -> [Int] {
        let lowered = text.lowercased()
        let words = lowered.components(separatedBy: .whitespaces).filter { !$0.isEmpty }

        var tokens: [Int] = [clsToken]

        for word in words {
            // Try full word first
            if let id = vocab[word] {
                tokens.append(id)
            } else {
                // Basic wordpiece: try subwords
                var remaining = word
                var found = false
                while !remaining.isEmpty {
                    var matched = false
                    for length in stride(from: remaining.count, through: 1, by: -1) {
                        let sub = String(remaining.prefix(length))
                        let key = tokens.count > 1 ? "##\(sub)" : sub
                        if let id = vocab[key] {
                            tokens.append(id)
                            remaining = String(remaining.dropFirst(length))
                            matched = true
                            found = true
                            break
                        }
                    }
                    if !matched {
                        tokens.append(unkToken)
                        remaining = String(remaining.dropFirst())
                    }
                }
                if !found { tokens.append(unkToken) }
            }

            if tokens.count >= maxTokens - 1 { break }
        }

        tokens.append(sepToken)
        return tokens
    }

    // MARK: - Embedding

    func embed(_ text: String) -> [Float]? {
        guard let model else { return nil }

        var tokenIDs = tokenize(text)
        let seqLen = min(tokenIDs.count, maxTokens)
        tokenIDs = Array(tokenIDs.prefix(maxTokens))

        // Pad to maxTokens
        let inputIDs = tokenIDs + Array(repeating: padToken, count: maxTokens - tokenIDs.count)
        let attentionMask = (0..<maxTokens).map { $0 < seqLen ? 1 : 0 }

        // Build MLMultiArray inputs
        guard
            let inputIDsArray = try? MLMultiArray(shape: [1, NSNumber(value: maxTokens)], dataType: .int32),
            let attentionMaskArray = try? MLMultiArray(shape: [1, NSNumber(value: maxTokens)], dataType: .int32)
        else { return nil }

        for i in 0..<maxTokens {
            inputIDsArray[i] = NSNumber(value: inputIDs[i])
            attentionMaskArray[i] = NSNumber(value: attentionMask[i])
        }

        // Run inference
        guard let output = try? model.prediction(
            input_ids: inputIDsArray,
            attention_mask: attentionMaskArray
        ) else { return nil }

        // Extract 384-dim embedding
        let embeddingArray = output.embedding
        var result: [Float] = []
        for i in 0..<384 {
            result.append(embeddingArray[i].floatValue)
        }
        return result
    }
}
