import Combine
import Foundation
import CoreML
import CryptoKit
import SwiftUI
import ZIPFoundation
import os.log

// MARK: - Flora Pack Model

struct FloraPack: Identifiable, Codable {
    let id: String
    let kind: Kind
    let version: String
    let speciesCount: Int
    let fileSizeMB: Double
    let downloadURL: String
    let checksum: String

    enum Kind: String, Codable, CaseIterable, Identifiable {
        case australiaNZ    = "australia_nz"
        case eastAsia       = "east_asia"
        case northAmerica   = "north_america"
        case scandinavia    = "scandinavia"
        case westernEurope  = "western_europe"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .australiaNZ:   return "Australia & New Zealand"
            case .eastAsia:      return "East Asia"
            case .northAmerica:  return "North America"
            case .scandinavia:   return "Scandinavia"
            case .westernEurope: return "Western Europe"
            }
        }

        var description: String {
            switch self {
            case .australiaNZ:   return "Australian and New Zealand native flora"
            case .eastAsia:      return "Japan, Korea, China, Taiwan"
            case .northAmerica:  return "US, Canada, Mexico native and naturalized species"
            case .scandinavia:   return "Nordic flora: Sweden, Norway, Denmark, Finland, Iceland"
            case .westernEurope: return "UK, France, Germany, Benelux, Iberia, Italy"
            }
        }

        var iconName: String {
            switch self {
            case .australiaNZ:   return "sun.max"
            case .eastAsia:      return "mountain.2"
            case .northAmerica:  return "leaf"
            case .scandinavia:   return "snowflake"
            case .westernEurope: return "building.columns"
            }
        }
    }

    static var floraPacksDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("FloraModels", isDirectory: true)
    }

    var localDirectory: URL { Self.floraPacksDirectory.appendingPathComponent(kind.rawValue, isDirectory: true) }
    var modelURL: URL { localDirectory.appendingPathComponent("model.mlmodelc") }
    var metadataURL: URL { localDirectory.appendingPathComponent("species_meta.json") }
}

// MARK: - Manifest

struct FloraPackManifest: Codable {
    let manifestVersion: Int
    let packs: [FloraPack]

    static let manifestURL = URL(string: "https://github.com/SchleemOW/pocket-prepper/releases/download/flora-v1.0/flora_manifest.json")!
}

// MARK: - FloraPackManager

final class FloraPackManager: ObservableObject {
    static let shared = FloraPackManager()

    private let logger = Logger(subsystem: "schleem-digital.Pocket-Prepper", category: "FloraPackManager")
    private let fileManager = FileManager.default

    @Published var availablePacks: [FloraPack] = []
    @Published var packStates: [FloraPack.Kind: PackState] = [:]

    private var activeTasks: [FloraPack.Kind: URLSessionDownloadTask] = [:]

    enum PackState: Equatable {
        case notDownloaded
        case downloading(progress: Double)
        case compiling
        case installed(version: String)
        case failed(error: String)

        var isInstalled: Bool { if case .installed = self { return true }; return false }
        var isDownloading: Bool { if case .downloading = self { return true }; return false }
    }

    init() {
        ensureDirectoryExists()
        scanInstalledPacks()
    }

    private func ensureDirectoryExists() {
        let dir = FloraPack.floraPacksDirectory
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    private func scanInstalledPacks() {
        for kind in FloraPack.Kind.allCases {
            let packDir = FloraPack.floraPacksDirectory.appendingPathComponent(kind.rawValue)
            let modelPath = packDir.appendingPathComponent("model.mlmodelc")
            let versionFile = packDir.appendingPathComponent("version.txt")
            if fileManager.fileExists(atPath: modelPath.path) {
                let version = (try? String(contentsOf: versionFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)) ?? "unknown"
                packStates[kind] = .installed(version: version)
            } else {
                packStates[kind] = .notDownloaded
            }
        }
    }

    // MARK: - Manifest

    func fetchManifest() async throws {
        do {
            let (data, _) = try await URLSession.shared.data(from: FloraPackManifest.manifestURL)
            let manifest = try JSONDecoder().decode(FloraPackManifest.self, from: data)
            await MainActor.run { self.availablePacks = manifest.packs }
        } catch {
            if let bundledURL = Bundle.main.url(forResource: "flora_manifest", withExtension: "json"),
               let data = try? Data(contentsOf: bundledURL),
               let manifest = try? JSONDecoder().decode(FloraPackManifest.self, from: data) {
                await MainActor.run { self.availablePacks = manifest.packs }
            } else {
                throw FloraError.packDownloadFailed("Could not fetch or find flora pack manifest")
            }
        }
        await checkForUpdates()   // ← add this line
    }
    
    private func checkForUpdates() async {
        for pack in availablePacks {
            if case .installed(let installedVersion) = packStates[pack.kind],
               installedVersion != pack.version {
                logger.info("Flora pack \(pack.kind.rawValue) outdated: \(installedVersion) → \(pack.version)")
                await MainActor.run { packStates[pack.kind] = .notDownloaded }
            }
        }
    }

    // MARK: - Download & Install

    func downloadPack(_ pack: FloraPack) async throws {
        guard packStates[pack.kind]?.isDownloading != true else { return }
        await MainActor.run { packStates[pack.kind] = .downloading(progress: 0) }

        do {
            guard let url = URL(string: pack.downloadURL) else {
                throw FloraError.packDownloadFailed("Invalid download URL")
            }
            let (tempURL, _) = try await downloadWithProgress(url: url, packKind: pack.kind)

            let downloadedChecksum = try sha256(fileAt: tempURL)
            guard downloadedChecksum == pack.checksum else {
                try? fileManager.removeItem(at: tempURL)
                throw FloraError.packCorrupted("Checksum mismatch for \(pack.kind.rawValue)")
            }

            await MainActor.run { packStates[pack.kind] = .compiling }

            let packDir = pack.localDirectory
            if fileManager.fileExists(atPath: packDir.path) { try fileManager.removeItem(at: packDir) }
            try fileManager.createDirectory(at: packDir, withIntermediateDirectories: true)
            try await extractZip(at: tempURL, to: packDir)

            let mlpackagePath = packDir.appendingPathComponent("model.mlpackage")
            if fileManager.fileExists(atPath: mlpackagePath.path) {
                try await compileModel(at: mlpackagePath, to: pack.modelURL)
                try? fileManager.removeItem(at: mlpackagePath)
            }

            try pack.version.write(to: packDir.appendingPathComponent("version.txt"), atomically: true, encoding: .utf8)
            try? fileManager.removeItem(at: tempURL)

            await MainActor.run { packStates[pack.kind] = .installed(version: pack.version) }
            logger.info("Flora pack installed: \(pack.kind.rawValue) v\(pack.version)")

        } catch {
            await MainActor.run { packStates[pack.kind] = .failed(error: error.localizedDescription) }
            throw error
        }
    }

    func cancelDownload(_ kind: FloraPack.Kind) {
        activeTasks[kind]?.cancel()
        activeTasks.removeValue(forKey: kind)
        packStates[kind] = .notDownloaded
    }

    func deletePack(_ kind: FloraPack.Kind) throws {
        let packDir = FloraPack.floraPacksDirectory.appendingPathComponent(kind.rawValue)
        if fileManager.fileExists(atPath: packDir.path) { try fileManager.removeItem(at: packDir) }
        FloraClassifier.shared.unloadPack(kind)
        packStates[kind] = .notDownloaded
        logger.info("Flora pack deleted: \(kind.rawValue)")
    }

    // MARK: - Load into Classifier

    func loadInstalledPacks() async {
        for kind in FloraPack.Kind.allCases {
            guard case .installed = packStates[kind] else { continue }
            let pack = availablePacks.first { $0.kind == kind }
                ?? FloraPack(id: kind.rawValue, kind: kind, version: "unknown", speciesCount: 0, fileSizeMB: 0, downloadURL: "", checksum: "")
            do {
                try await FloraClassifier.shared.loadPack(pack)
            } catch {
                logger.error("Failed to load pack \(kind.rawValue): \(error.localizedDescription)")
            }
        }
    }

    var installedPackCount: Int { packStates.values.filter(\.isInstalled).count }

    func diskUsageMB() -> Double {
        var total: UInt64 = 0
        for kind in FloraPack.Kind.allCases {
            let dir = FloraPack.floraPacksDirectory.appendingPathComponent(kind.rawValue)
            if let enumerator = fileManager.enumerator(at: dir, includingPropertiesForKeys: [.fileSizeKey]) {
                for case let fileURL as URL in enumerator {
                    total += UInt64((try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
                }
            }
        }
        return Double(total) / (1024 * 1024)
    }

    // MARK: - Private Helpers

    private func downloadWithProgress(url: URL, packKind: FloraPack.Kind) async throws -> (URL, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            let delegate = DownloadProgressDelegate { [weak self] progress in
                Task { @MainActor in self?.packStates[packKind] = .downloading(progress: progress) }
            }
            let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
            let task = session.downloadTask(with: url) { tempURL, response, error in
                if let error { continuation.resume(throwing: error); return }
                guard let tempURL, let response else {
                    continuation.resume(throwing: FloraError.packDownloadFailed("No data received"))
                    return
                }
                let stableURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".zip")
                do {
                    try FileManager.default.moveItem(at: tempURL, to: stableURL)
                    continuation.resume(returning: (stableURL, response))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
            activeTasks[packKind] = task
            task.resume()
        }
    }

    private func sha256(fileAt url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func extractZip(at source: URL, to destination: URL) async throws {
        // Requires ZIPFoundation SPM package (weichsel/ZIPFoundation)
        try await Task.detached {
            try FileManager.default.unzipItem(at: source, to: destination)
        }.value
    }

    private func compileModel(at source: URL, to destination: URL) async throws {
        try await Task.detached(priority: .userInitiated) {
            let compiledURL = try MLModel.compileModel(at: source)
            try FileManager.default.moveItem(at: compiledURL, to: destination)
        }.value
    }
}

// MARK: - Download Progress Delegate

private final class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate {
    let onProgress: (Double) -> Void
    init(onProgress: @escaping (Double) -> Void) { self.onProgress = onProgress }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress(min(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite), 1.0))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
}
