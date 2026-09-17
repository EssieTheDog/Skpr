import SwiftUI
import Combine
import AVFoundation
import Photos

/// Owns the capture session: finds the back camera, wires it into a session,
/// takes photos, and saves them to the user's Photos library.
final class CameraController: NSObject, ObservableObject {
    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.denniscrothers.Skpr.camera-session")
    private var isConfigured = false
    private let photoOutput = AVCapturePhotoOutput()

    @Published var lastCapturedImage: UIImage?
    @Published var isCapturing = false
    @Published var saveError: String?

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

/// Bridges AVFoundation's camera preview layer into SwiftUI.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

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
    @State private var breedGuesses: [BreedGuess] = []
    @State private var showResults = false

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
                CameraPreview(session: controller.session)
                    .ignoresSafeArea()

                VStack {
                    Spacer()
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
                    .padding(.bottom, 40)
                }
            }
        }
        .onAppear { requestAccessAndStart() }
        .onDisappear { controller.stop() }
        .onChange(of: controller.lastCapturedImage) { _, image in
            guard let image else { return }
            PetClassifier.classify(image) { guesses in
                breedGuesses = guesses
                showResults = true
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
            BreedResultsView(image: controller.lastCapturedImage, guesses: breedGuesses)
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
