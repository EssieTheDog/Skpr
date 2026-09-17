import Vision
import UIKit
import CoreML
import os

struct BreedGuess: Identifiable {
    let id = UUID()
    let label: String
    let rawIdentifier: String
    let confidence: Float
}

/// A two-stage result: species (Dog/Cat) plus specific breed guesses.
struct ClassificationResult {
    let species: BreedGuess?
    let breedGuesses: [BreedGuess]
}

enum PetClassifier {
    private static let log = Logger(subsystem: "com.denniscrothers.Skpr", category: "PetClassifier")

    /// Two independent checks run on every photo, so a miss on one doesn't
    /// sink the whole result:
    ///   1. VNRecognizeAnimalsRequest -- Apple's dedicated species detector.
    ///      Reliable when it fires, but can miss unusual poses/angles
    ///      (e.g. a dog lying on its side).
    ///   2. MobileNetV2 -- a general 1000-class classifier that includes
    ///      ~120 dog breeds and a handful of cat breeds. This always runs
    ///      now, regardless of whether stage 1 found anything. If stage 1
    ///      comes up empty but this recognizes a known breed, that's used
    ///      to confirm species too.
    static func classify(_ image: UIImage, completion: @escaping (ClassificationResult) -> Void) {
        guard let cgImage = image.cgImage else {
            log.error("classify: no cgImage on the captured UIImage")
            completion(ClassificationResult(species: nil, breedGuesses: []))
            return
        }

        let orientation = CGImagePropertyOrientation(image.imageOrientation)

        DispatchQueue.global(qos: .userInitiated).async {
            var species = detectSpecies(cgImage: cgImage, orientation: orientation)
            let breedGuesses = classifyBreed(cgImage: cgImage, orientation: orientation)

            if species == nil,
               let topBreed = breedGuesses.first,
               let inferredSpecies = PetTaxonomy.species(forRawIdentifier: topBreed.rawIdentifier) {
                log.info("stage 1 missed it, but the breed classifier recognized \(topBreed.rawIdentifier, privacy: .public) as a \(inferredSpecies, privacy: .public)")
                species = BreedGuess(label: inferredSpecies, rawIdentifier: inferredSpecies, confidence: topBreed.confidence)
            }

            log.info("species=\(species?.label ?? "none", privacy: .public) breedGuesses=\(breedGuesses.count)")
            DispatchQueue.main.async {
                completion(ClassificationResult(species: species, breedGuesses: species != nil ? breedGuesses : []))
            }
        }
    }

    private static func detectSpecies(cgImage: CGImage, orientation: CGImagePropertyOrientation) -> BreedGuess? {
        let animalRequest = VNRecognizeAnimalsRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
        do {
            try handler.perform([animalRequest])
        } catch {
            log.error("detectSpecies: handler.perform threw: \(error.localizedDescription, privacy: .public)")
            return nil
        }

        var seen = Set<String>()
        var guesses: [BreedGuess] = []
        for observation in animalRequest.results ?? [] {
            for label in observation.labels {
                guard seen.insert(label.identifier).inserted else { continue }
                guesses.append(BreedGuess(label: label.identifier, rawIdentifier: label.identifier, confidence: label.confidence))
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
                .map { BreedGuess(label: formatLabel($0.identifier), rawIdentifier: $0.identifier, confidence: $0.confidence) }
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

/// Maps MobileNetV2's raw ImageNet labels to a species, so the breed
/// classifier can confirm "this is a dog" even when Apple's separate
/// animal detector misses (e.g. an unusual pose or angle).
enum PetTaxonomy {
    static func species(forRawIdentifier raw: String) -> String? {
        for synonym in raw.split(separator: ",") {
            let normalized = normalize(String(synonym))
            if dogBreeds.contains(normalized) { return "Dog" }
            if catBreeds.contains(normalized) { return "Cat" }
        }
        return nil
    }

    private static func normalize(_ s: String) -> String {
        s.replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
    }

    private static let catBreeds: Set<String> = [
        "egyptian cat", "persian cat", "siamese cat", "tabby", "tabby cat", "tiger cat"
    ]

    // The ~120 dog-breed classes in the standard 1000-class ImageNet label
    // set (this is what MobileNetV2 was trained on).
    private static let dogBreeds: Set<String> = [
        "chihuahua", "japanese spaniel", "maltese dog", "pekinese", "shih tzu", "blenheim spaniel",
        "papillon", "toy terrier", "rhodesian ridgeback", "afghan hound", "basset", "beagle",
        "bloodhound", "bluetick", "black and tan coonhound", "walker hound", "english foxhound",
        "redbone", "borzoi", "irish wolfhound", "italian greyhound", "whippet", "ibizan hound",
        "norwegian elkhound", "otterhound", "saluki", "scottish deerhound", "weimaraner",
        "staffordshire bullterrier", "american staffordshire terrier", "bedlington terrier",
        "border terrier", "kerry blue terrier", "irish terrier", "norfolk terrier", "norwich terrier",
        "yorkshire terrier", "wire haired fox terrier", "lakeland terrier", "sealyham terrier",
        "airedale", "cairn", "australian terrier", "dandie dinmont", "boston bull",
        "miniature schnauzer", "giant schnauzer", "standard schnauzer", "scotch terrier",
        "tibetan terrier", "silky terrier", "soft coated wheaten terrier",
        "west highland white terrier", "lhasa", "flat coated retriever", "curly coated retriever",
        "golden retriever", "labrador retriever", "chesapeake bay retriever",
        "german short haired pointer", "vizsla", "english setter", "irish setter", "gordon setter",
        "brittany spaniel", "clumber", "english springer", "welsh springer spaniel", "cocker spaniel",
        "sussex spaniel", "irish water spaniel", "kuvasz", "schipperke", "groenendael", "malinois",
        "briard", "kelpie", "komondor", "old english sheepdog", "shetland sheepdog", "collie",
        "border collie", "bouvier des flandres", "rottweiler", "german shepherd", "doberman",
        "miniature pinscher", "greater swiss mountain dog", "bernese mountain dog", "appenzeller",
        "entlebucher", "boxer", "bull mastiff", "tibetan mastiff", "french bulldog", "great dane",
        "saint bernard", "eskimo dog", "malamute", "siberian husky", "affenpinscher", "basenji",
        "pug", "leonberg", "newfoundland", "great pyrenees", "samoyed", "pomeranian", "chow",
        "keeshond", "brabancon griffon", "pembroke", "cardigan", "toy poodle", "miniature poodle",
        "standard poodle", "mexican hairless", "dingo", "dhole", "african hunting dog"
    ]
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
