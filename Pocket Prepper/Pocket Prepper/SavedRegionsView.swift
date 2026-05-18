import SwiftUI
import MapLibre

struct SavedRegionsView: View {
    @StateObject private var mapManager = OfflineMapManager.shared
    @State private var regionToDelete: MapRegion? = nil

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if mapManager.savedRegions.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "map")
                        .font(.system(size: 32))
                        .foregroundColor(.gray.opacity(0.4))
                    Text("NO SAVED REGIONS")
                        .font(.system(.caption, design: .monospaced).weight(.bold))
                        .foregroundColor(.gray)
                    Text("Download map areas from the map view")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.gray.opacity(0.6))
                }
            } else {
                List {
                    ForEach(mapManager.savedRegions) { region in
                        SavedRegionRow(
                            region: region,
                            progress: mapManager.downloadProgress[region.id],
                            isDownloading: mapManager.downloadingRegions.contains(region.id)
                        )
                        .listRowBackground(Color.black)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                regionToDelete = region
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("SAVED REGIONS")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.black, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .preferredColorScheme(.dark)
        .confirmationDialog(
            "Delete \"\(regionToDelete?.name ?? "")\"?",
            isPresented: Binding(get: { regionToDelete != nil }, set: { if !$0 { regionToDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let region = regionToDelete {
                    mapManager.delete(region: region)
                }
                regionToDelete = nil
            }
            Button("Cancel", role: .cancel) { regionToDelete = nil }
        } message: {
            Text("This will remove the offline tiles from your device.")
        }
    }
}

struct SavedRegionRow: View {
    let region: MapRegion
    let progress: Double?
    let isDownloading: Bool

    private var formattedDate: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: region.downloadedAt)
    }

    private var sizeText: String {
        if region.estimatedSizeMB > 0 {
            return String(format: "%.0f MB", region.estimatedSizeMB)
        }
        return "Calculating…"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(region.name.uppercased())
                    .font(.system(.caption, design: .monospaced).weight(.bold))
                    .foregroundColor(.green)
                Spacer()
                if isDownloading {
                    Text("DOWNLOADING")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.orange)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.green.opacity(0.7))
                }
            }

            if isDownloading, let progress {
                ProgressView(value: progress)
                    .tint(.green)
                Text("\(Int(progress * 100))%")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.gray)
            } else {
                HStack(spacing: 16) {
                    Text(sizeText)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.gray)
                    Text(formattedDate)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.gray.opacity(0.6))
                }
            }
        }
        .padding(.vertical, 8)
    }
}
