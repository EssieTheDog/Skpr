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

    /// Detects whether a dog (or cat) is present using Apple's built-in
    /// animal recognizer — this is a species-level detector, not a breed
    /// classifier. Apple doesn't ship an on-device breed-level model, so
    /// results are labeled "Dog" / "Cat" rather than specific breeds.
    static func classify(_ image: UIImage, completion: @escaping ([BreedGuess]) -> Void) {
        guard let cgImage = image.cgImage else {
            log.error("classify: no cgImage on the captured UIImage")
            completion([])
            return
        }

        let visionOrientation = CGImagePropertyOrientation(image.imageOrientation)
        let animalRequest = VNRecognizeAnimalsRequest()

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: visionOrientation)
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([animalRequest])
            } catch {
                log.error("handler.perform threw: \(error.localizedDescription, privacy: .public)")
                DispatchQueue.main.async { completion([]) }
                return
            }

            guard let observations = animalRequest.results else {
                log.info("VNRecognizeAnimalsRequest: no animals detected")
                DispatchQueue.main.async { completion([]) }
                return
            }

            var seen = Set<String>()
            var guesses: [BreedGuess] = []
            for observation in observations {
                for label in observation.labels {
                    guard seen.insert(label.identifier).inserted else { continue }
                    guesses.append(BreedGuess(label: label.identifier, confidence: label.confidence))
                }
            }
            guesses.sort { $0.confidence > $1.confidence }

            log.info("VNRecognizeAnimalsRequest found \(guesses.count) animal label(s)")
            DispatchQueue.main.async { completion(guesses) }
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
