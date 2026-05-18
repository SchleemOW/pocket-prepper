import Foundation
import MapLibre
import Combine

class OfflineMapManager: NSObject, ObservableObject {
    static let shared = OfflineMapManager()

    @Published var savedRegions: [MapRegion] = []
    @Published var downloadingRegions: Set<String> = []
    @Published var downloadProgress: [String: Double] = [:]
    @Published var error: String? = nil

    static let styleURL = URL(string: "https://api.maptiler.com/maps/streets-v2/style.json?key=q9frLRLU1CFKOBlphqVL")!
    static let minZoom: Double = 3
    static let maxZoom: Double = 14

    private override init() {
        super.init()
        loadSavedRegions()
        observePackNotifications()
    }

    // MARK: - Download

    func startDownload(name: String, bounds: MLNCoordinateBounds) {
        let id = UUID().uuidString
        let newRegion = MapRegion(
            id: id,
            name: name,
            bounds: MapRegion.Bounds(
                swLat: bounds.sw.latitude,
                swLon: bounds.sw.longitude,
                neLat: bounds.ne.latitude,
                neLon: bounds.ne.longitude
            ),
            downloadedAt: Date(),
            estimatedSizeMB: 0
        )

        DispatchQueue.main.async {
            self.savedRegions.append(newRegion)
            self.persistRegions()
            self.downloadingRegions.insert(id)
            self.downloadProgress[id] = 0
        }

        let offlineRegion = MLNTilePyramidOfflineRegion(
            styleURL: OfflineMapManager.styleURL,
            bounds: bounds,
            fromZoomLevel: OfflineMapManager.minZoom,
            toZoomLevel: OfflineMapManager.maxZoom
        )

        let contextData = (try? JSONEncoder().encode(["id": id])) ?? Data()

        MLNOfflineStorage.shared.addPack(
            for: offlineRegion,
            withContext: contextData
        ) { [weak self] pack, error in
            guard let self else { return }
            if let error {
                DispatchQueue.main.async {
                    self.error = error.localizedDescription
                    self.downloadingRegions.remove(id)
                }
                return
            }
            pack?.resume()
        }
    }

    // MARK: - Delete

    func delete(region: MapRegion) {
        let packs = MLNOfflineStorage.shared.packs ?? []
        for pack in packs {
            guard let context = try? JSONDecoder().decode([String: String].self, from: pack.context),
                  context["id"] == region.id else { continue }
            MLNOfflineStorage.shared.removePack(pack, withCompletionHandler: nil)
            break
        }
        DispatchQueue.main.async {
            self.savedRegions.removeAll { $0.id == region.id }
            self.persistRegions()
        }
    }

    // MARK: - Size estimation

    func estimateSizeMB(for bounds: MLNCoordinateBounds) -> Double {
        let latDelta = bounds.ne.latitude - bounds.sw.latitude
        let lonDelta = bounds.ne.longitude - bounds.sw.longitude
        let areaDeg = latDelta * lonDelta
        return min(max(areaDeg * 8.0, 5.0), 500.0)
    }

    // MARK: - Notifications

    private func observePackNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(packProgressChanged(_:)),
            name: .MLNOfflinePackProgressChanged,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(packError(_:)),
            name: .MLNOfflinePackError,
            object: nil
        )
    }

    @objc private func packProgressChanged(_ notification: Notification) {
        guard let pack = notification.object as? MLNOfflinePack,
              let context = try? JSONDecoder().decode([String: String].self, from: pack.context),
              let id = context["id"] else { return }

        let progress = pack.progress
        let total = progress.countOfResourcesExpected
        let completed = progress.countOfResourcesCompleted
        let state = pack.state

        DispatchQueue.main.async {
            if total > 0 {
                self.downloadProgress[id] = Double(completed) / Double(total)
            }
            if state == .complete {
                self.downloadingRegions.remove(id)
                self.downloadProgress.removeValue(forKey: id)
                let sizeMB = Double(progress.countOfBytesCompleted) / 1_048_576
                if let idx = self.savedRegions.firstIndex(where: { $0.id == id }) {
                    self.savedRegions[idx].estimatedSizeMB = sizeMB
                    self.persistRegions()
                }
            }
        }
    }

    @objc private func packError(_ notification: Notification) {
        guard let pack = notification.object as? MLNOfflinePack,
              let context = try? JSONDecoder().decode([String: String].self, from: pack.context),
              let id = context["id"] else { return }
        DispatchQueue.main.async {
            self.downloadingRegions.remove(id)
            self.error = "Download failed for this region"
        }
    }

    // MARK: - Persistence

    private var regionsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("saved_map_regions.json")
    }

    private func persistRegions() {
        try? JSONEncoder().encode(savedRegions).write(to: regionsURL)
    }

    private func loadSavedRegions() {
        guard let data = try? Data(contentsOf: regionsURL),
              let regions = try? JSONDecoder().decode([MapRegion].self, from: data) else { return }
        savedRegions = regions
    }
}
