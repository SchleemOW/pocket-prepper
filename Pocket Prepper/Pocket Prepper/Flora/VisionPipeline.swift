import Combine
import AVFoundation
import CoreImage
import SwiftUI
import os.log

// MARK: - VisionPipeline

final class VisionPipeline: NSObject, ObservableObject {
    private let logger = Logger(subsystem: "schleem-digital.Pocket-Prepper", category: "VisionPipeline")

    @Published var cameraPermission: CameraPermission = .unknown
    @Published var isSessionRunning = false
    @Published var capturedImage: UIImage?
    @Published var classifications: [FloraClassification] = []
    @Published var isClassifying = false
    @Published var errorMessage: String?

    enum CameraPermission { case unknown, granted, denied, restricted }

    let captureSession = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "schleem.flora.session", qos: .userInitiated)
    private let photoOutput = AVCapturePhotoOutput()
    private var videoDeviceInput: AVCaptureDeviceInput?

    private let classificationCooldown: TimeInterval = 0.5
    private var lastClassificationTime: Date = .distantPast

    // MARK: - Permissions

    func checkPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            cameraPermission = .granted
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                // Capture granted value directly — avoids Swift 6 self capture warning
                Task { @MainActor [weak self] in
                    self?.cameraPermission = granted ? .granted : .denied
                }
            }
        case .denied:
            cameraPermission = .denied
        case .restricted:
            cameraPermission = .restricted
        @unknown default:
            cameraPermission = .denied
        }
    }

    // MARK: - Session Lifecycle

    func startSession() {
        guard cameraPermission == .granted else { checkPermission(); return }
        sessionQueue.async { [weak self] in self?.configureSession() }
    }

    func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self, self.captureSession.isRunning else { return }
            self.captureSession.stopRunning()
            Task { @MainActor [weak self] in self?.isSessionRunning = false }
        }
    }

    // MARK: - Session Configuration

    private func configureSession() {
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .photo

        guard let videoDevice = bestCamera(),
              let input = try? AVCaptureDeviceInput(device: videoDevice) else {
            logger.error("No suitable camera device found")
            captureSession.commitConfiguration()
            return
        }

        if captureSession.canAddInput(input) {
            captureSession.addInput(input)
            videoDeviceInput = input
        }

        if captureSession.canAddOutput(photoOutput) {
            captureSession.addOutput(photoOutput)
            photoOutput.maxPhotoQualityPrioritization = .balanced
        }

        captureSession.commitConfiguration()
        captureSession.startRunning()
        Task { @MainActor [weak self] in self?.isSessionRunning = true }
        logger.info("Camera session started")
    }

    private func bestCamera() -> AVCaptureDevice? {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
            ?? AVCaptureDevice.default(for: .video)
    }

    // MARK: - Capture

    func captureAndClassify() {
        guard isSessionRunning, !isClassifying else { return }
        let now = Date()
        guard now.timeIntervalSince(lastClassificationTime) >= classificationCooldown else { return }
        lastClassificationTime = now

        let settings = AVCapturePhotoSettings()
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    func classifyFromLibrary(image: UIImage) async {
        await MainActor.run {
            capturedImage = image
            isClassifying = true
            errorMessage = nil
        }
        do {
            let results = try await FloraClassifier.shared.classify(uiImage: image, topK: 5)
            await MainActor.run {
                classifications = results
                isClassifying = false
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isClassifying = false
            }
        }
    }

    func clearResults() {
        capturedImage = nil
        classifications = []
        errorMessage = nil
    }

    // MARK: - Focus

    func focusOnPoint(_ point: CGPoint, in previewLayer: AVCaptureVideoPreviewLayer) {
        guard let device = videoDeviceInput?.device else { return }
        let devicePoint = previewLayer.captureDevicePointConverted(fromLayerPoint: point)
        sessionQueue.async {
            try? device.lockForConfiguration()
            if device.isFocusPointOfInterestSupported { device.focusPointOfInterest = devicePoint; device.focusMode = .autoFocus }
            if device.isExposurePointOfInterestSupported { device.exposurePointOfInterest = devicePoint; device.exposureMode = .autoExpose }
            device.unlockForConfiguration()
        }
    }

    func toggleTorch() {
        guard let device = videoDeviceInput?.device, device.hasTorch else { return }
        sessionQueue.async {
            try? device.lockForConfiguration()
            device.torchMode = device.torchMode == .on ? .off : .on
            device.unlockForConfiguration()
        }
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension VisionPipeline: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error {
            Task { @MainActor [weak self] in
                self?.errorMessage = "Capture failed: \(error.localizedDescription)"
                self?.isClassifying = false
            }
            return
        }
        guard let imageData = photo.fileDataRepresentation(),
              let uiImage = UIImage(data: imageData) else {
            Task { @MainActor [weak self] in
                self?.errorMessage = "Could not process captured photo"
                self?.isClassifying = false
            }
            return
        }
        Task { @MainActor [weak self] in
            self?.capturedImage = uiImage
            self?.isClassifying = true
        }
        Task {
            do {
                let results = try await FloraClassifier.shared.classify(uiImage: uiImage, topK: 5)
                await MainActor.run { [weak self] in
                    self?.classifications = results
                    self?.isClassifying = false
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.errorMessage = error.localizedDescription
                    self?.isClassifying = false
                }
            }
        }
    }
}

// MARK: - Camera Preview

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {}
}

final class CameraPreviewUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}
