import Vision
import UIKit
import CoreML
import os

struct BreedGuess: Identifiable {
    let id = UUID()
    let label: String
    let confidence: Float
}

/// A two-stage result: species (Dog/Cat) from Apple's built-in detector,
/// plus specific breed guesses from the bundled MobileNetV2 model.
struct ClassificationResult {
    let species: BreedGuess?
    let breedGuesses: [BreedGuess]
}

enum PetClassifier {
    private static let log = Logger(subsystem: "com.denniscrothers.Skpr", category: "PetClassifier")

    /// Stage 1: VNRecognizeAnimalsRequest reliably tells us "Dog" or "Cat".
    /// Stage 2 (only if stage 1 found something): MobileNetV2, a general
    /// 1000-class ImageNet classifier bundled into the app, gets us breed
    /// specifics — ImageNet includes roughly 120 dog breeds and a handful
    /// of cat breeds, since it was trained on real photos of them.
    static func classify(_ image: UIImage, completion: @escaping (ClassificationResult) -> Void) {
        guard let cgImage = image.cgImage else {
            log.error("classify: no cgImage on the captured UIImage")
            completion(ClassificationResult(species: nil, breedGuesses: []))
            return
        }

        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        let animalRequest = VNRecognizeAnimalsRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation)

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([animalRequest])
            } catch {
                log.error("handler.perform threw: \(error.localizedDescription, privacy: .public)")
                DispatchQueue.main.async { completion(ClassificationResult(species: nil, breedGuesses: [])) }
                return
            }

            guard let species = topSpecies(from: animalRequest.results ?? []) else {
                log.info("VNRecognizeAnimalsRequest: no animals detected")
                DispatchQueue.main.async { completion(ClassificationResult(species: nil, breedGuesses: [])) }
                return
            }

            let breedGuesses = classifyBreed(cgImage: cgImage, orientation: orientation)
            log.info("species=\(species.label, privacy: .public) breedGuesses=\(breedGuesses.count)")
            DispatchQueue.main.async {
                completion(ClassificationResult(species: species, breedGuesses: breedGuesses))
            }
        }
    }

    private static func topSpecies(from observations: [VNRecognizedObjectObservation]) -> BreedGuess? {
        var seen = Set<String>()
        var guesses: [BreedGuess] = []
        for observation in observations {
            for label in observation.labels {
                guard seen.insert(label.identifier).inserted else { continue }
                guesses.append(BreedGuess(label: label.identifier, confidence: label.confidence))
            }
        }
        guesses.sort { $0.confidence > $1.confidence }
        return guesses.first
    }

    private static func classifyBreed(cgImage: CGImage, orientation: CGImagePropertyOrientation) -> [BreedGuess] {
        guard let model = try? VNCoreMLModel(for: MobileNetV2FP16(configuration: MLModelConfiguration()).model) else {
            log.error("classifyBreed: MobileNetV2FP16 model not found — has it been added to the Xcode project yet?")
            return []
        }

        var breedGuesses: [BreedGuess] = []
        let request = VNCoreMLRequest(model: model) { request, _ in
            guard let observations = request.results as? [VNClassificationObservation] else { return }
            breedGuesses = observations
                .prefix(3)
                .map { BreedGuess(label: formatLabel($0.identifier), confidence: $0.confidence) }
        }
        request.imageCropAndScaleOption = .centerCrop

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
        do {
            try handler.perform([request])
        } catch {
            log.error("classifyBreed: handler.perform threw: \(error.localizedDescription, privacy: .public)")
            return []
        }
        return breedGuesses
    }

    /// ImageNet labels look like "Labrador_retriever" or "tabby, tabby cat" —
    /// take the first synonym and turn underscores into spaces.
    private static func formatLabel(_ raw: String) -> String {
        let firstSynonym = raw.split(separator: ",").first.map(String.init) ?? raw
        return firstSynonym
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespaces)
            .capitalized
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
