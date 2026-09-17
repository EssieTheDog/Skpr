import SwiftUI
import Combine
import AVFoundation
import CoreImage
import Photos
import PhotosUI

/// Owns the capture session: finds the back camera, wires it into a session,
/// takes photos, and saves them to the user's Photos library.
final class CameraController: NSObject, ObservableObject {
    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.denniscrothers.Skpr.camera-session")
    private var isConfigured = false
    private let photoOutput = AVCapturePhotoOutput()

    private let videoOutput = AVCaptureVideoDataOutput()
    private let videoQueue = DispatchQueue(label: "com.denniscrothers.Skpr.video-frames")
    private nonisolated(unsafe) let ciContext = CIContext()
    private nonisolated(unsafe) var lastLightingCheck = Date.distantPast

    @Published var lastCapturedImage: UIImage?
    @Published var isCapturing = false
    @Published var saveError: String?
    /// A short, human-readable heads-up about the current lighting (too
    /// dark, blown out, backlit), updated live from the preview feed.
    /// nil means lighting looks fine -- no banner shown.
    @Published var lightingWarning: String?

    func configureIfNeeded() {
        guard !isConfigured else { return }
        isConfigured = true
        sessionQueue.async {
            self.session.beginConfiguration()
            self.session.sessionPreset = .photo

            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let input = try? AVCaptureDeviceInput(device: device),
                  self.session.canAddInput(input) else {
                self.session.commitConfiguration()
                return
            }
            self.session.addInput(input)

            if self.session.canAddOutput(self.photoOutput) {
                self.session.addOutput(self.photoOutput)
            }

            self.videoOutput.alwaysDiscardsLateVideoFrames = true
            self.videoOutput.setSampleBufferDelegate(self, queue: self.videoQueue)
            if self.session.canAddOutput(self.videoOutput) {
                self.session.addOutput(self.videoOutput)
            }

            self.session.commitConfiguration()
        }
    }

    func start() {
        sessionQueue.async {
            if !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }

    func stop() {
        sessionQueue.async {
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }

    func capturePhoto() {
        isCapturing = true
        let settings = AVCapturePhotoSettings()
        sessionQueue.async {
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    /// Tap-to-focus: locks focus (and exposure) onto whatever the user
    /// tapped in the preview -- e.g. tapping directly on the eyes when the
    /// default autofocus picked a different part of a close-up face.
    /// `point` is in the capture device's normalized (0...1) coordinate
    /// space, already converted from the tap's on-screen location by
    /// AVCaptureVideoPreviewLayer.
    func focus(atDevicePoint point: CGPoint) {
        sessionQueue.async {
            guard let device = (self.session.inputs.first as? AVCaptureDeviceInput)?.device else { return }
            do {
                try device.lockForConfiguration()
                if device.isFocusPointOfInterestSupported {
                    device.focusPointOfInterest = point
                    device.focusMode = .autoFocus
                }
                if device.isExposurePointOfInterestSupported {
                    device.exposurePointOfInterest = point
                    device.exposureMode = .autoExpose
                }
                device.unlockForConfiguration()
            } catch {
                // Locking failed (rare) -- focus/exposure just stay as they were.
            }
        }
    }

    private nonisolated func saveToPhotoLibrary(data: Data) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async {
                    self.saveError = "Photo library access is off, so the photo wasn't saved. Turn it on in Settings to save your pet's photos."
                }
                return
            }

            PHPhotoLibrary.shared().performChanges({
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: data, options: nil)
            }) { success, error in
                if !success {
                    DispatchQueue.main.async {
                        self.saveError = error?.localizedDescription ?? "Couldn't save the photo."
                    }
                }
            }
        }
    }
}

extension CameraController: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput,
                      didFinishProcessingPhoto photo: AVCapturePhoto,
                      error: Error?) {
        DispatchQueue.main.async { self.isCapturing = false }

        if let error {
            DispatchQueue.main.async { self.saveError = error.localizedDescription }
            return
        }

        guard let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else { return }

        DispatchQueue.main.async {
            self.lastCapturedImage = image
        }

        saveToPhotoLibrary(data: data)
    }
}

/// Watches the live preview feed and flags lighting problems -- too dark,
/// blown out, or backlit (subject silhouetted against a bright background)
/// -- before the user even presses the shutter.
extension CameraController: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput,
                        didOutput sampleBuffer: CMSampleBuffer,
                        from connection: AVCaptureConnection) {
        // Checking every single frame would be wasteful -- a few times a
        // second is plenty to feel "live" without burning battery.
        let now = Date()
        guard now.timeIntervalSince(lastLightingCheck) > 0.4 else { return }
        lastLightingCheck = now

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let fullExtent = ciImage.extent
        guard fullExtent.width > 0, fullExtent.height > 0 else { return }

        // The center box stands in for "roughly where the pet is" without
        // needing a full subject-detection pass on every frame.
        let centerExtent = fullExtent.insetBy(dx: fullExtent.width * 0.25, dy: fullExtent.height * 0.25)

        guard let overall = averageBrightness(of: ciImage, in: fullExtent) else { return }
        let center = averageBrightness(of: ciImage, in: centerExtent)

        var warning: String?
        if overall < 0.2 {
            warning = "Too dark — try turning on a light or moving somewhere brighter."
        } else if overall > 0.9 {
            warning = "Too bright — try moving out of direct light."
        } else if let center, (overall - center) > 0.15 {
            warning = "Backlit — try repositioning so the light isn't directly behind your pet."
        }

        DispatchQueue.main.async { self.lightingWarning = warning }
    }

    /// Renders CIAreaAverage's 1x1 output and converts it to a 0...1 luma
    /// value (standard perceptual-brightness weighting of R/G/B).
    private nonisolated func averageBrightness(of image: CIImage, in extent: CGRect) -> CGFloat? {
        guard let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: image,
            kCIInputExtentKey: CIVector(cgRect: extent)
        ]), let outputImage = filter.outputImage else { return nil }

        var bitmap = [UInt8](repeating: 0, count: 4)
        ciContext.render(outputImage,
                          toBitmap: &bitmap,
                          rowBytes: 4,
                          bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                          format: .RGBA8,
                          colorSpace: nil)

        let r = CGFloat(bitmap[0]) / 255
        let g = CGFloat(bitmap[1]) / 255
        let b = CGFloat(bitmap[2]) / 255
        return 0.299 * r + 0.587 * g + 0.114 * b
    }
}

/// Bridges AVFoundation's camera preview layer into SwiftUI, and turns taps
/// on the preview into tap-to-focus. `onTap` receives both the tap's
/// on-screen point (to position a focus reticle) and the corresponding
/// point in the capture device's coordinate space (to actually set focus).
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    var onTap: (_ viewPoint: CGPoint, _ devicePoint: CGPoint) -> Void = { _, _ in }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill

        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        view.addGestureRecognizer(tapGesture)
        context.coordinator.previewView = view

        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        context.coordinator.onTap = onTap
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onTap: onTap)
    }

    final class Coordinator: NSObject {
        var onTap: (_ viewPoint: CGPoint, _ devicePoint: CGPoint) -> Void
        weak var previewView: PreviewView?

        init(onTap: @escaping (_ viewPoint: CGPoint, _ devicePoint: CGPoint) -> Void) {
            self.onTap = onTap
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let previewView else { return }
            let viewPoint = gesture.location(in: previewView)
            let devicePoint = previewView.videoPreviewLayer.captureDevicePointConverted(fromLayerPoint: viewPoint)
            onTap(viewPoint, devicePoint)
        }
    }

    final class PreviewView: UIView {
        override static var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}

/// The main camera screen: live preview full-screen, a shutter button that
/// captures + saves a photo, then shows the likely dog breed.
struct CameraView: View {
    @StateObject private var controller = CameraController()
    @State private var permissionDenied = false
    @State private var detections: [PetDetection] = []
    @State private var showResults = false
    @State private var resultImage: UIImage?
    @State private var libraryItem: PhotosPickerItem?
    @State private var focusIndicatorPoint: CGPoint?
    @State private var compositionGuide: CompositionGuide = .off

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if permissionDenied {
                VStack(spacing: 12) {
                    Image(systemName: "camera.fill")
                        .font(.largeTitle)
                    Text("Camera access is off")
                        .font(.headline)
                    Text("Turn on camera access in Settings to start photographing your pet.")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .foregroundStyle(.white)
            } else {
                CameraPreview(session: controller.session) { viewPoint, devicePoint in
                    controller.focus(atDevicePoint: devicePoint)
                    withAnimation(.easeOut(duration: 0.15)) {
                        focusIndicatorPoint = viewPoint
                    }
                }
                .ignoresSafeArea()

                CompositionGuideOverlay(guide: compositionGuide)
                    .ignoresSafeArea()

                if let focusIndicatorPoint {
                    Rectangle()
                        .stroke(Color.yellow, lineWidth: 1.5)
                        .frame(width: 72, height: 72)
                        .position(focusIndicatorPoint)
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }

                if let warning = controller.lightingWarning {
                    VStack {
                        Text(warning)
                            .font(.subheadline)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(.black.opacity(0.6), in: Capsule())
                            .padding(.horizontal, 24)
                            .padding(.top, 12)
                        Spacer()
                    }
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.25), value: controller.lightingWarning)
                }

                VStack {
                    HStack {
                        Spacer()
                        Menu {
                            ForEach(CompositionGuide.allCases) { option in
                                Button {
                                    compositionGuide = option
                                } label: {
                                    if compositionGuide == option {
                                        Label(option.rawValue, systemImage: "checkmark")
                                    } else {
                                        Text(option.rawValue)
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: compositionGuide == .off ? "grid" : "grid.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.white)
                                .padding(14)
                                .background(.black.opacity(0.4), in: Circle())
                        }
                        .padding(.trailing, 20)
                        .padding(.top, 8)
                    }
                    Spacer()
                    ZStack {
                        Button(action: { controller.capturePhoto() }) {
                            ZStack {
                                Circle()
                                    .strokeBorder(.white, lineWidth: 4)
                                    .frame(width: 74, height: 74)
                                Circle()
                                    .fill(.white)
                                    .frame(width: 60, height: 60)
                                    .opacity(controller.isCapturing ? 0.4 : 1)
                            }
                        }
                        .disabled(controller.isCapturing)

                        HStack {
                            PhotosPicker(selection: $libraryItem, matching: .images) {
                                Image(systemName: "photo.on.rectangle")
                                    .font(.title2)
                                    .foregroundStyle(.white)
                                    .padding(14)
                                    .background(.black.opacity(0.4), in: Circle())
                            }
                            Spacer()
                        }
                        .padding(.leading, 30)
                    }
                    .padding(.bottom, 40)
                }
            }
        }
        .onAppear { requestAccessAndStart() }
        .onDisappear { controller.stop() }
        .onChange(of: focusIndicatorPoint) { _, newValue in
            guard newValue != nil else { return }
            Task {
                try? await Task.sleep(nanoseconds: 700_000_000)
                withAnimation(.easeIn(duration: 0.2)) { focusIndicatorPoint = nil }
            }
        }
        .onChange(of: controller.lastCapturedImage) { _, image in
            guard let image else { return }
            resultImage = image
            PetClassifier.classify(image) { result in
                detections = result
                showResults = true
            }
        }
        .onChange(of: libraryItem) { _, newItem in
            guard let newItem else { return }
            Task {
                guard let data = try? await newItem.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else { return }
                await MainActor.run { resultImage = image }
                PetClassifier.classify(image) { result in
                    detections = result
                    showResults = true
                }
                await MainActor.run { libraryItem = nil }
            }
        }
        .alert("Couldn't save photo", isPresented: Binding(
            get: { controller.saveError != nil },
            set: { if !$0 { controller.saveError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(controller.saveError ?? "")
        }
        .sheet(isPresented: $showResults) {
            BreedResultsView(image: resultImage, detections: detections)
        }
    }

    private func requestAccessAndStart() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            controller.configureIfNeeded()
            controller.start()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        controller.configureIfNeeded()
                        controller.start()
                    } else {
                        permissionDenied = true
                    }
                }
            }
        default:
            permissionDenied = true
        }
    }
}

#Preview {
    CameraView()
}
