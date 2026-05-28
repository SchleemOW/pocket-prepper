import SwiftUI
import PhotosUI

// MARK: - Flora Recognition View

struct FloraRecognitionView: View {
    @StateObject private var pipeline = VisionPipeline()
    @StateObject private var packManager = FloraPackManager.shared
    @StateObject private var classifier = FloraClassifier.shared

    @State private var showPackManager = false
    @State private var showPhotosPicker = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showSpeciesDetail: FloraClassification?
    @State private var showDisclaimerAlert = false

    @AppStorage("floraDisclaimerAccepted") private var disclaimerAccepted = false

    var body: some View {
        NavigationStack {
            ZStack {
                if pipeline.isSessionRunning {
                    CameraPreviewView(session: pipeline.captureSession)
                        .ignoresSafeArea()
                } else {
                    Color.black.ignoresSafeArea()
                }

                VStack(spacing: 0) {
                    topControls
                    Spacer()

                    if !pipeline.classifications.isEmpty {
                        resultsCard
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else if pipeline.isClassifying {
                        classifyingIndicator
                    } else if let error = pipeline.errorMessage {
                        errorBanner(error)
                    }

                    bottomControls
                }
            }
            .navigationBarHidden(true)
            .onAppear {
                if !disclaimerAccepted { showDisclaimerAlert = true } else { setupCamera() }
            }
            .onDisappear { pipeline.stopSession() }
            .alert("Plant Identification Disclaimer", isPresented: $showDisclaimerAlert) {
                Button("I Understand") { disclaimerAccepted = true; setupCamera() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Plant identification is for educational purposes only. Never eat, touch, or use a plant based solely on AI identification. Some plants are deadly toxic. Always verify with a qualified expert.")
            }
            .sheet(isPresented: $showPackManager) { FloraPackManagerView() }
            .sheet(item: $showSpeciesDetail) { SpeciesDetailView(classification: $0) }
            .photosPicker(isPresented: $showPhotosPicker, selection: $selectedPhoto, matching: .images)
            // iOS 17 onChange: two-parameter closure (oldValue, newValue)
            .onChange(of: selectedPhoto) { _, newItem in
                guard let newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        await pipeline.classifyFromLibrary(image: image)
                    }
                }
            }
            .animation(.spring(response: 0.4), value: pipeline.classifications.isEmpty)
        }
    }

    private func setupCamera() {
        pipeline.checkPermission()
        if classifier.isModelLoaded {
            pipeline.startSession()
        } else {
            Task {
                try? await packManager.fetchManifest()
                await packManager.loadInstalledPacks()
                if classifier.isModelLoaded { pipeline.startSession() } else { showPackManager = true }
            }
        }
    }

    // MARK: - Top Controls

    private var topControls: some View {
        HStack {
            Button { pipeline.stopSession() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial, in: Circle())
            }

            Spacer()

            if !classifier.isModelLoaded {
                Button { showPackManager = true } label: {
                    Label("No packs loaded", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.yellow)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                }
            }

            Spacer()

            Button { pipeline.toggleTorch() } label: {
                Image(systemName: "flashlight.off.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial, in: Circle())
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        HStack(spacing: 40) {
            Button { showPhotosPicker = true } label: {
                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: 22))
                    .foregroundColor(.white)
                    .frame(width: 48, height: 48)
                    .background(.ultraThinMaterial, in: Circle())
            }

            Button {
                if pipeline.classifications.isEmpty { pipeline.captureAndClassify() } else { pipeline.clearResults() }
            } label: {
                ZStack {
                    Circle().strokeBorder(.white, lineWidth: 3).frame(width: 72, height: 72)
                    Circle()
                        .fill(pipeline.classifications.isEmpty ? .white : .red.opacity(0.8))
                        .frame(width: 60, height: 60)
                    if !pipeline.classifications.isEmpty {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
            }
            .disabled(!classifier.isModelLoaded || pipeline.isClassifying)

            Button { showPackManager = true } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "leaf.circle")
                        .font(.system(size: 22))
                        .foregroundColor(.white)
                        .frame(width: 48, height: 48)
                        .background(.ultraThinMaterial, in: Circle())
                    if packManager.installedPackCount > 0 {
                        Text("\(packManager.installedPackCount)")
                            .font(.caption2.weight(.bold))
                            .foregroundColor(.white)
                            .frame(width: 18, height: 18)
                            .background(.green, in: Circle())
                            .offset(x: 4, y: -4)
                    }
                }
            }
        }
        .padding(.bottom, 30)
    }

    // MARK: - Results Card

    private var resultsCard: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2).fill(.secondary).frame(width: 36, height: 4).padding(.top, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(pipeline.classifications) { result in
                        Button { showSpeciesDetail = result } label: {
                            ClassificationResultRow(result: result)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .frame(maxHeight: 280)
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }

    private var classifyingIndicator: some View {
        HStack(spacing: 10) {
            ProgressView().tint(.white)
            Text("Identifying…").font(.subheadline.weight(.medium)).foregroundColor(.white)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.bottom, 16)
    }

    private func errorBanner(_ message: String) -> some View {
        Text(message).font(.caption).foregroundColor(.white)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(.red.opacity(0.8), in: Capsule())
            .padding(.bottom, 16)
    }
}

// MARK: - Classification Result Row

struct ClassificationResultRow: View {
    let result: FloraClassification
    private var isToxic: Bool { FloraClassifier.shared.isToxic(speciesKey: result.speciesKey) }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().stroke(.quaternary, lineWidth: 3)
                Circle()
                    .trim(from: 0, to: CGFloat(result.confidence))
                    .stroke(confidenceColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(result.confidencePercent)%").font(.caption2.weight(.bold).monospacedDigit())
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(result.commonName).font(.subheadline.weight(.semibold)).foregroundColor(.primary)
                    if isToxic { Image(systemName: "exclamationmark.triangle.fill").font(.caption2).foregroundColor(.red) }
                }
                if !result.scientificName.isEmpty {
                    Text(result.scientificName).font(.caption).foregroundColor(.secondary).italic()
                }
                if let note = result.confidenceLevel.safetyNote {
                    Text(note).font(.caption2).foregroundColor(result.confidenceLevel == .low ? .red : .orange)
                }
            }

            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var confidenceColor: Color {
        switch result.confidenceLevel {
        case .high: return .green
        case .medium: return .orange
        case .low: return .red
        }
    }
}

// MARK: - Species Detail View

struct SpeciesDetailView: View {
    let classification: FloraClassification
    @Environment(\.dismiss) private var dismiss
    private var meta: FloraSpeciesMeta? { FloraClassifier.shared.speciesInfo(for: classification.speciesKey) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(classification.commonName).font(.title2.weight(.bold))
                        if !classification.scientificName.isEmpty {
                            Text(classification.scientificName).font(.body).italic().foregroundColor(.secondary)
                        }
                        if let family = meta?.family, !family.isEmpty {
                            Text("Family: \(family)").font(.subheadline).foregroundColor(.secondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Identification Confidence").font(.headline)
                        ProgressView(value: Double(classification.confidence)).tint(confidenceColor)
                        Text("\(classification.confidencePercent)% — \(classification.confidenceLevel.rawValue)")
                            .font(.subheadline).foregroundColor(.secondary)
                    }

                    if let meta { safetyTags(meta) }

                    GroupBox {
                        Label {
                            Text("Never eat, touch, or use a plant based solely on AI identification. Verify with a qualified expert.")
                                .font(.caption)
                        } icon: {
                            Image(systemName: "exclamationmark.shield.fill").foregroundColor(.orange)
                        }
                    }

                    if let notes = meta?.notes, !notes.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Notes").font(.headline)
                            Text(notes).font(.subheadline).foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Species Detail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    @ViewBuilder
    private func safetyTags(_ meta: FloraSpeciesMeta) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Properties").font(.headline)
            HStack(spacing: 8) {
                if meta.toxic    { SafetyTag(label: "TOXIC",      color: .red,   icon: "xmark.octagon.fill") }
                if meta.edible   { SafetyTag(label: "Edible*",    color: .green, icon: "fork.knife") }
                if meta.medicinal { SafetyTag(label: "Medicinal*", color: .blue,  icon: "cross.case.fill") }
            }
            if meta.edible || meta.medicinal {
                Text("* Requires expert verification. AI identification alone is not sufficient.")
                    .font(.caption2).foregroundColor(.secondary)
            }
        }
    }

    private var confidenceColor: Color {
        switch classification.confidenceLevel {
        case .high: return .green; case .medium: return .orange; case .low: return .red
        }
    }
}

struct SafetyTag: View {
    let label: String; let color: Color; let icon: String
    var body: some View {
        Label(label, systemImage: icon).font(.caption.weight(.semibold)).foregroundColor(color)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(color.opacity(0.12), in: Capsule())
    }
}

// MARK: - Flora Pack Manager View

struct FloraPackManagerView: View {
    @StateObject private var packManager = FloraPackManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Download species packs for your region. Each pack includes a Core ML model and species metadata.")
                        .font(.caption).foregroundColor(.secondary).listRowBackground(Color.clear)
                }
                Section("Available Packs") {
                    ForEach(FloraPack.Kind.allCases) { kind in
                        PackRow(
                            kind: kind,
                            state: packManager.packStates[kind] ?? .notDownloaded,
                            pack: packManager.availablePacks.first { $0.kind == kind },
                            onDownload: {
                                if let pack = packManager.availablePacks.first(where: { $0.kind == kind }) {
                                    Task { try? await packManager.downloadPack(pack) }
                                }
                            },
                            onDelete: { try? packManager.deletePack(kind) },
                            onCancel: { packManager.cancelDownload(kind) }
                        )
                    }
                }
                Section("Storage") {
                    HStack { Text("Disk Usage"); Spacer(); Text(String(format: "%.1f MB", packManager.diskUsageMB())).foregroundColor(.secondary) }
                    HStack { Text("Packs Installed"); Spacer(); Text("\(packManager.installedPackCount) / \(FloraPack.Kind.allCases.count)").foregroundColor(.secondary) }
                }
            }
            .navigationTitle("Species Packs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { try? await packManager.fetchManifest() }
        }
    }
}

struct PackRow: View {
    let kind: FloraPack.Kind
    let state: FloraPackManager.PackState
    let pack: FloraPack?
    let onDownload: () -> Void
    let onDelete: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: kind.iconName).font(.title3).foregroundColor(.accentColor).frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(kind.displayName).font(.subheadline.weight(.medium))
                Text(kind.description).font(.caption2).foregroundColor(.secondary)
                if let pack { Text("\(pack.speciesCount) species · \(String(format: "%.0f", pack.fileSizeMB)) MB").font(.caption2).foregroundColor(.secondary) }
            }
            Spacer()
            stateButton
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var stateButton: some View {
        switch state {
        case .notDownloaded:
            Button { onDownload() } label: { Image(systemName: "arrow.down.circle").font(.title3) }
        case .downloading(let progress):
            HStack(spacing: 8) {
                ProgressView(value: progress).frame(width: 40)
                Button { onCancel() } label: { Image(systemName: "xmark.circle.fill").foregroundColor(.secondary) }
            }
        case .compiling:
            HStack(spacing: 6) { ProgressView(); Text("Compiling").font(.caption2).foregroundColor(.secondary) }
        case .installed(let version):
            Menu {
                Text("v\(version)")
                Button(role: .destructive) { onDelete() } label: { Label("Delete Pack", systemImage: "trash") }
            } label: { Image(systemName: "checkmark.circle.fill").font(.title3).foregroundColor(.green) }
        case .failed:
            Button { onDownload() } label: {
                VStack(spacing: 2) {
                    Image(systemName: "exclamationmark.circle").foregroundColor(.red)
                    Text("Retry").font(.caption2).foregroundColor(.red)
                }
            }
        }
    }
}
