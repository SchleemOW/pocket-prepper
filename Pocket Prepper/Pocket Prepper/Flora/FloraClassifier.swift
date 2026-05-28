import Combine
import CoreML
import Vision
import UIKit
import os.log

// MARK: - Data Models

struct FloraClassification: Identifiable {
    let id = UUID()
    let speciesKey: String
    let commonName: String
    let scientificName: String
    let confidence: Float
    let packSource: FloraPack.Kind

    var confidencePercent: Int {
        Int((confidence * 100).rounded())
    }

    var confidenceLevel: ConfidenceLevel {
        switch confidence {
        case 0.80...: return .high
        case 0.50...: return .medium
        default:      return .low
        }
    }

    enum ConfidenceLevel: String {
        case high   = "High confidence"
        case medium = "Moderate — verify visually"
        case low    = "Low — use caution"

        var safetyNote: String? {
            switch self {
            case .high:   return nil
            case .medium: return "Cross-reference with field guide before acting on this identification."
            case .low:    return "⚠️ This identification is unreliable. Do NOT use for foraging or medical decisions."
            }
        }
    }
}

struct FloraSpeciesMeta: Codable {
    let key: String
    let commonName: String
    let scientificName: String
    let family: String
    let edible: Bool
    let toxic: Bool
    let medicinal: Bool
    let notes: String?
}

// MARK: - FloraClassifier

final class FloraClassifier: ObservableObject {
    static let shared = FloraClassifier()

    private let logger = Logger(subsystem: "schleem-digital.Pocket-Prepper", category: "FloraClassifier")

    private var loadedModels: [FloraPack.Kind: VNCoreMLModel] = [:]
    private var speciesMeta: [String: FloraSpeciesMeta] = [:]

    @Published var isModelLoaded = false
    @Published var loadingError: String?

    static let inputSize = CGSize(width: 224, height: 224)

    // MARK: - Model Loading

    func loadPack(_ pack: FloraPack) async throws {
        let modelURL = pack.modelURL
        let metaURL = pack.metadataURL

        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            throw FloraError.modelNotFound(pack.kind.rawValue)
        }

        logger.info("Loading flora model: \(pack.kind.rawValue)")

        let config = MLModelConfiguration()
        config.computeUnits = .cpuAndNeuralEngine

        let mlModel = try await Task.detached(priority: .userInitiated) {
            try MLModel(contentsOf: modelURL, configuration: config)
        }.value

        let vnModel = try VNCoreMLModel(for: mlModel)

        if FileManager.default.fileExists(atPath: metaURL.path) {
            let data = try Data(contentsOf: metaURL)
            let speciesList = try JSONDecoder().decode([FloraSpeciesMeta].self, from: data)
            for species in speciesList {
                speciesMeta[species.key] = species
            }
            logger.info("Loaded \(speciesList.count) species for \(pack.kind.rawValue)")
        }

        await MainActor.run {
            loadedModels[pack.kind] = vnModel
            isModelLoaded = !loadedModels.isEmpty
            loadingError = nil
        }
    }

    func unloadPack(_ kind: FloraPack.Kind) {
        loadedModels.removeValue(forKey: kind)
        isModelLoaded = !loadedModels.isEmpty
    }

    func unloadAll() {
        loadedModels.removeAll()
        speciesMeta.removeAll()
        isModelLoaded = false
    }

    // MARK: - Classification

    func classify(image: CGImage, topK: Int = 5) async throws -> [FloraClassification] {
        guard !loadedModels.isEmpty else { throw FloraError.noModelsLoaded }

        var allResults: [FloraClassification] = []
        for (packKind, vnModel) in loadedModels {
            let results = try await runInference(image: image, model: vnModel, packKind: packKind)
            allResults.append(contentsOf: results)
        }

        let grouped = Dictionary(grouping: allResults, by: \.speciesKey)
        let merged = grouped.compactMap { (_, group) in
            group.max(by: { $0.confidence < $1.confidence })
        }
        return Array(merged.sorted { $0.confidence > $1.confidence }.prefix(topK))
    }

    func classify(uiImage: UIImage, topK: Int = 5) async throws -> [FloraClassification] {
        guard let cgImage = uiImage.cgImage else { throw FloraError.invalidImage }
        return try await classify(image: cgImage, topK: topK)
    }

    // MARK: - Vision Inference

    private func runInference(
        image: CGImage,
        model: VNCoreMLModel,
        packKind: FloraPack.Kind
    ) async throws -> [FloraClassification] {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNCoreMLRequest(model: model) { [weak self] request, error in
                if let error {
                    continuation.resume(throwing: FloraError.visionError(error.localizedDescription))
                    return
                }
                guard let observations = request.results as? [VNClassificationObservation] else {
                    continuation.resume(throwing: FloraError.unexpectedResults)
                    return
                }

                let top = Array(observations.prefix(10))

                // If confidences exceed 1.0 the model output is raw logits — apply softmax
                let needsSoftmax = top.contains { $0.confidence > 1.0 }
                let normalizedConf: [Float]
                if needsSoftmax {
                    let logits = top.map { $0.confidence }
                    let maxLogit = logits.max() ?? 0
                    let exps = logits.map { exp($0 - maxLogit) }
                    let sumExps = exps.reduce(0, +)
                    normalizedConf = exps.map { $0 / sumExps }
                } else {
                    normalizedConf = top.map { $0.confidence }
                }

                let results = zip(top, normalizedConf).map { obs, conf in
                    self?.makeClassification(speciesKey: obs.identifier, confidence: conf, packKind: packKind)
                        ?? FloraClassification(
                            speciesKey: obs.identifier,
                            commonName: Self.humanReadable(obs.identifier),
                            scientificName: "",
                            confidence: conf,
                            packSource: packKind
                        )
                }
                continuation.resume(returning: results)
            }
            request.imageCropAndScaleOption = .centerCrop

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: FloraError.visionError(error.localizedDescription))
            }
        }
    }

    /// Converts a model class label like "phalaris_arundinacea_l." into "Phalaris arundinacea"
    static func humanReadable(_ identifier: String) -> String {
        let words = identifier
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .punctuationCharacters)
            .split(separator: " ")
            .map(String.init)
        let binomial = words.prefix(2).joined(separator: " ")
        guard !binomial.isEmpty else { return identifier }
        return binomial.prefix(1).uppercased() + binomial.dropFirst().lowercased()
    }

    private func makeClassification(speciesKey: String, confidence: Float, packKind: FloraPack.Kind) -> FloraClassification {
        // Try lookup by raw key first, then by normalized latin name
        let meta = speciesMeta[speciesKey] ?? speciesMeta[Self.normalizeLatinKey(speciesKey)]
        return FloraClassification(
            speciesKey: speciesKey,
            commonName: meta?.commonName ?? Self.humanReadable(speciesKey),
            scientificName: meta?.scientificName ?? "",
            confidence: confidence,
            packSource: packKind
        )
    }

    // MARK: - Safety

    func isToxic(speciesKey: String) -> Bool { speciesMeta[speciesKey]?.toxic ?? false }
    func speciesInfo(for key: String) -> FloraSpeciesMeta? { speciesMeta[key] }
}

// MARK: - Errors

enum FloraError: LocalizedError {
    case modelNotFound(String)
    case noModelsLoaded
    case invalidImage
    case visionError(String)
    case unexpectedResults
    case packDownloadFailed(String)
    case packCorrupted(String)

    var errorDescription: String? {
        switch self {
        case .modelNotFound(let p):    return "Flora model not found for pack: \(p). Try re-downloading."
        case .noModelsLoaded:          return "No flora models loaded. Download at least one species pack."
        case .invalidImage:            return "Could not process the image for classification."
        case .visionError(let d):      return "Vision framework error: \(d)"
        case .unexpectedResults:       return "Unexpected classification results."
        case .packDownloadFailed(let p): return "Failed to download flora pack: \(p)"
        case .packCorrupted(let p):    return "Flora pack is corrupted: \(p). Delete and re-download."
        }
    }
}

// MARK: - Latin Key Normalization (appended)
extension FloraClassifier {
    /// Normalizes a latin name to match model class label format.
    /// "Phalaris arundinacea L." → "phalaris_arundinacea_l."
    static func normalizeLatinKey(_ latin: String) -> String {
        latin
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
    }
}
