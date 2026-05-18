import SwiftUI
import MapLibre

// MARK: - Main Map View

struct MapsRootView: View {
    @StateObject private var mapManager = OfflineMapManager.shared
    @State private var showDownloadSheet = false
    @State private var showSavedRegions = false
    @State private var currentBounds: MLNCoordinateBounds? = nil
    @State private var regionName = ""

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Color.black.ignoresSafeArea()

                MapLibreView(currentBounds: $currentBounds, savedRegions: mapManager.savedRegions)
                    .ignoresSafeArea(edges: .bottom)

                // Bottom controls
                HStack(spacing: 12) {
                    Button {
                        showSavedRegions = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "square.3.layers.3d")
                                .font(.system(size: 12))
                            Text("SAVED (\(mapManager.savedRegions.count))")
                                .font(.system(.caption2, design: .monospaced).weight(.bold))
                        }
                        .foregroundColor(.green)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.black.opacity(0.85))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.green.opacity(0.4), lineWidth: 1)
                        )
                        .cornerRadius(6)
                    }

                    Spacer()

                    Button {
                        regionName = ""
                        showDownloadSheet = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.down.circle")
                                .font(.system(size: 12))
                            Text("DOWNLOAD AREA")
                                .font(.system(.caption2, design: .monospaced).weight(.bold))
                        }
                        .foregroundColor(.black)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.green)
                        .cornerRadius(6)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .navigationTitle("MAPS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .navigationDestination(isPresented: $showSavedRegions) {
                SavedRegionsView()
            }
            .sheet(isPresented: $showDownloadSheet) {
                DownloadAreaSheet(
                    bounds: currentBounds,
                    regionName: $regionName,
                    onConfirm: { name, bounds in
                        mapManager.startDownload(name: name, bounds: bounds)
                        showDownloadSheet = false
                    }
                )
                .presentationDetents([.height(360)])
                .presentationDragIndicator(.visible)
            }
            .alert("Error", isPresented: Binding(
                get: { mapManager.error != nil },
                set: { if !$0 { mapManager.error = nil } }
            )) {
                Button("OK") { mapManager.error = nil }
            } message: {
                Text(mapManager.error ?? "")
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - MapLibre UIViewRepresentable

struct MapLibreView: UIViewRepresentable {
    @Binding var currentBounds: MLNCoordinateBounds?
    var savedRegions: [MapRegion]

    func makeUIView(context: Context) -> MLNMapView {
        let mapView = MLNMapView(frame: .zero, styleURL: OfflineMapManager.styleURL)
        mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        mapView.logoView.isHidden = true
        mapView.delegate = context.coordinator

        mapView.setCenter(
            CLLocationCoordinate2D(latitude: 55.0, longitude: 15.0),
            zoomLevel: 4,
            animated: false
        )

        mapView.showsUserLocation = true
        mapView.userTrackingMode = .none

        return mapView
    }

    func updateUIView(_ mapView: MLNMapView, context: Context) {
        // Update overlays whenever savedRegions changes
        context.coordinator.updateRegionOverlays(on: mapView, regions: savedRegions)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, MLNMapViewDelegate {
        var parent: MapLibreView
        private var currentOverlays: [MLNPolygon] = []

        init(_ parent: MapLibreView) {
            self.parent = parent
        }

        func mapView(_ mapView: MLNMapView, regionDidChangeAnimated animated: Bool) {
            DispatchQueue.main.async {
                self.parent.currentBounds = mapView.visibleCoordinateBounds
            }
        }

        func mapViewDidFinishLoadingMap(_ mapView: MLNMapView) {
            DispatchQueue.main.async {
                self.parent.currentBounds = mapView.visibleCoordinateBounds
                self.updateRegionOverlays(on: mapView, regions: self.parent.savedRegions)
            }
        }

        // Draw a green rectangle for each downloaded region
        func updateRegionOverlays(on mapView: MLNMapView, regions: [MapRegion]) {
            mapView.removeAnnotations(currentOverlays)
            currentOverlays = []

            for region in regions where !OfflineMapManager.shared.downloadingRegions.contains(region.id) {
                let sw = CLLocationCoordinate2D(latitude: region.bounds.swLat, longitude: region.bounds.swLon)
                let nw = CLLocationCoordinate2D(latitude: region.bounds.neLat, longitude: region.bounds.swLon)
                let ne = CLLocationCoordinate2D(latitude: region.bounds.neLat, longitude: region.bounds.neLon)
                let se = CLLocationCoordinate2D(latitude: region.bounds.swLat, longitude: region.bounds.neLon)

                var coords = [sw, nw, ne, se]
                let polygon = MLNPolygon(coordinates: &coords, count: UInt(coords.count))
                polygon.title = region.name
                currentOverlays.append(polygon)
            }

            mapView.addAnnotations(currentOverlays)
        }

        // Style the polygon fill
        func mapView(_ mapView: MLNMapView, fillColorForPolygonAnnotation annotation: MLNPolygon) -> UIColor {
            return UIColor.systemGreen.withAlphaComponent(0.15)
        }

        // Style the polygon stroke
        private func mapView(_ mapView: MLNMapView, strokeColorForPolygonAnnotation annotation: MLNPolygon) -> UIColor {
            return UIColor.systemGreen.withAlphaComponent(0.7)
        }

        private func mapView(_ mapView: MLNMapView, lineWidthForPolygonAnnotation annotation: MLNPolygon) -> CGFloat {
            return 1.5
        }

        // Show region name as callout on tap
        func mapView(_ mapView: MLNMapView, viewFor annotation: MLNAnnotation) -> MLNAnnotationView? {
            return nil // use default callout
        }

        func mapView(_ mapView: MLNMapView, annotationCanShowCallout annotation: MLNAnnotation) -> Bool {
            return annotation.title != nil
        }
    }
}

// MARK: - Download Sheet

struct DownloadAreaSheet: View {
    let bounds: MLNCoordinateBounds?
    @Binding var regionName: String
    let onConfirm: (String, MLNCoordinateBounds) -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var nameFocused: Bool

    private var estimatedSize: Double {
        guard let bounds else { return 0 }
        return OfflineMapManager.shared.estimateSizeMB(for: bounds)
    }

    private var estimatedSizeText: String {
        guard bounds != nil else { return "—" }
        return String(format: "~%.0f MB", estimatedSize)
    }

    // Warn if area is very large (MapLibre caps at ~6000 tiles which is roughly 300MB at z14)
    private var isTooLarge: Bool {
        estimatedSize > 300
    }

    private var trimmedName: String {
        regionName.trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 20) {
                Text("DOWNLOAD THIS AREA")
                    .font(.system(.caption, design: .monospaced).weight(.bold))
                    .foregroundColor(.green)

                VStack(alignment: .leading, spacing: 8) {
                    Text("NAME THIS REGION")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.gray)

                    TextField("e.g. Stockholm, Cabin area", text: $regionName)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(10)
                        .background(Color.white.opacity(0.07))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.green.opacity(0.3), lineWidth: 1)
                        )
                        .focused($nameFocused)
                        .onAppear { nameFocused = true }
                }

                HStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("ZOOM LEVELS")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(.gray)
                        Text("z3 – z14")
                            .font(.system(.caption, design: .monospaced).weight(.bold))
                            .foregroundColor(.white)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("EST. SIZE")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(.gray)
                        Text(estimatedSizeText)
                            .font(.system(.caption, design: .monospaced).weight(.bold))
                            .foregroundColor(isTooLarge ? .orange : .white)
                    }
                }

                // Warning for oversized areas
                if isTooLarge {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 11))
                            .foregroundColor(.orange)
                        Text("Area too large — zoom in before downloading.")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(.orange)
                    }
                } else {
                    Text("Download on Wi-Fi recommended. Tiles stored on-device, fully offline.")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.gray)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 12) {
                    Button("CANCEL") { dismiss() }
                        .font(.system(.caption, design: .monospaced).weight(.bold))
                        .foregroundColor(.gray)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )

                    Button("DOWNLOAD") {
                        guard let bounds, !trimmedName.isEmpty, !isTooLarge else { return }
                        onConfirm(trimmedName, bounds)
                    }
                    .font(.system(.caption, design: .monospaced).weight(.bold))
                    .foregroundColor((trimmedName.isEmpty || isTooLarge) ? .gray : .black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background((trimmedName.isEmpty || isTooLarge) ? Color.gray.opacity(0.3) : Color.green)
                    .cornerRadius(6)
                    .disabled(trimmedName.isEmpty || isTooLarge)
                }
            }
            .padding(24)
        }
    }
}
