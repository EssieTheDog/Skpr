import Vision
import UIKit
import os

struct BreedGuess: Identifiable {
    let id = UUID()
    let label: String
    let confidence: Float
}

enum PetClassifier {
    private static let log = Logger(subsystem: "com.denniscrothers.Skpr", category: "PetClassifier")

    /// Runs Apple's built-in Vision image classifier and returns the top
    /// few guesses. This uses the general-purpose classifier that ships
    /// with iOS (no custom model needed) — it recognizes many specific dog
    /// breeds among its broader set of categories.
    static func classify(_ image: UIImage, completion: @escaping ([BreedGuess]) -> Void) {
        guard let cgImage = image.cgImage else {
            log.error("classify: no cgImage on the captured UIImage")
            completion([])
            return
        }

        // UIImage's .cgImage is the RAW, unrotated pixel buffer — the actual
        // "which way is up" info lives separately in .imageOrientation.
        // Vision needs to be told that explicitly, or it'll analyze the
        // photo sideways/upside down and key on the wrong things entirely.
        let visionOrientation = CGImagePropertyOrientation(image.imageOrientation)

        let request = VNClassifyImageRequest { request, error in
            if let error {
                log.error("VNClassifyImageRequest completion error: \(error.localizedDescription, privacy: .public)")
                DispatchQueue.main.async { completion([]) }
                return
            }
            guard let results = request.results as? [VNClassificationObservation] else {
                log.error("VNClassifyImageRequest: no results, or unexpected result type")
                DispatchQueue.main.async { completion([]) }
                return
            }

            log.info("VNClassifyImageRequest returned \(results.count) raw results")

            let topGuesses = results
                .filter { $0.confidence > 0.1 }
                .prefix(5)
                .map {
                    BreedGuess(
                        label: $0.identifier.replacingOccurrences(of: "_", with: " ").capitalized,
                        confidence: $0.confidence
                    )
                }

            DispatchQueue.main.async { completion(Array(topGuesses)) }
        }

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: visionOrientation)
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
            } catch {
                log.error("handler.perform threw: \(error.localizedDescription, privacy: .public)")
                DispatchQueue.main.async { completion([]) }
            }
        }
    }
}

private extension CGImagePropertyOrientation {
    /// Standard UIImage.Orientation -> CGImagePropertyOrientation mapping.
    init(_ uiOrientation: UIImage.Orientation) {
        switch uiOrientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
