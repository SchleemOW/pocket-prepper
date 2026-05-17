import Foundation
import Combine

@MainActor
class ModuleManager: ObservableObject {
    static let shared = ModuleManager()

    @Published var enabledModuleIDs: Set<String> = []
    @Published var downloadProgress: [String: Double] = [:]
    @Published var downloadingIDs: Set<String> = []
    @Published var errorMessages: [String: String] = [:]

    private let enabledKey = "enabledModuleIDs"

    init() {
        let saved = UserDefaults.standard.stringArray(forKey: enabledKey) ?? []
        enabledModuleIDs = Set(saved)
    }

    // MARK: - Persistence

    func toggleEnabled(_ module: Module) {
        if enabledModuleIDs.contains(module.id) {
            enabledModuleIDs.remove(module.id)
        } else {
            enabledModuleIDs.insert(module.id)
        }
        UserDefaults.standard.set(Array(enabledModuleIDs), forKey: enabledKey)
    }

    // MARK: - Download

    func download(_ module: Module) async {
        guard !downloadingIDs.contains(module.id) else { return }
        guard let url = URL(string: module.downloadURL) else { return }

        downloadingIDs.insert(module.id)
        downloadProgress[module.id] = 0
        errorMessages.removeValue(forKey: module.id)

        let destination = documentsURL(for: module.dbFileName)

        do {
            // Use a delegate-based download for reliable progress + redirect handling
            let delegate = DownloadDelegate { progress in
                Task { @MainActor in
                    self.downloadProgress[module.id] = progress
                }
            }
            let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
            let (tempURL, response) = try await session.download(from: url)

            // Check HTTP status
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                errorMessages[module.id] = "Download failed: HTTP \(http.statusCode)"
                downloadingIDs.remove(module.id)
                return
            }

            // Move to final location
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: tempURL, to: destination)

            // Verify file exists and has content
            let attrs = try FileManager.default.attributesOfItem(atPath: destination.path)
            let size = attrs[.size] as? Int64 ?? 0

            if size > 1000 {
                downloadProgress[module.id] = 1.0
                enabledModuleIDs.insert(module.id)
                UserDefaults.standard.set(Array(enabledModuleIDs), forKey: enabledKey)
                print("Downloaded \(module.dbFileName): \(size / 1024)KB")
            } else {
                try? FileManager.default.removeItem(at: destination)
                errorMessages[module.id] = "Download incomplete"
            }

        } catch {
            errorMessages[module.id] = error.localizedDescription
            print("Download error for \(module.id): \(error)")
        }

        downloadingIDs.remove(module.id)
    }

    func deleteModule(_ module: Module) {
        let url = documentsURL(for: module.dbFileName)
        try? FileManager.default.removeItem(at: url)
        enabledModuleIDs.remove(module.id)
        UserDefaults.standard.set(Array(enabledModuleIDs), forKey: enabledKey)
    }

    // MARK: - Helpers

    func documentsURL(for filename: String) -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(filename)
    }

    var downloadedModules: [Module] {
        Module.all.filter { $0.isDownloaded }
    }

    var totalDownloadedMB: Double {
        downloadedModules.reduce(0) { $0 + $1.sizeMB }
    }
}

// MARK: - Download delegate for progress tracking

class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let onProgress: (Double) -> Void

    init(onProgress: @escaping (Double) -> Void) {
        self.onProgress = onProgress
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        if totalBytesExpectedToWrite > 0 {
            onProgress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // Handled by the async download call
    }
}
