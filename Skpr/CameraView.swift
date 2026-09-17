import SwiftUI
import Combine
import AVFoundation

/// Owns the capture session: finds the back camera, wires it into a session,
/// and starts/stops running on a background queue (AVFoundation requires this
/// off the main thread).
final class CameraController: NSObject, ObservableObject {
    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.denniscrothers.Skpr.camera-session")
    private var isConfigured = false

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

/// The main camera screen: live preview full-screen, with a placeholder
/// shutter button. Handles asking for camera permission the first time.
struct CameraView: View {
    @StateObject private var controller = CameraController()
    @State private var permissionDenied = false

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
                    Circle()
                        .strokeBorder(.white, lineWidth: 4)
                        .frame(width: 74, height: 74)
                        .padding(.bottom, 40)
                }
            }
        }
        .onAppear { requestAccessAndStart() }
        .onDisappear { controller.stop() }
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
