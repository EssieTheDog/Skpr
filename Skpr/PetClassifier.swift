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

/// One detected pet in a photo: its species, a crop of just that animal
/// (when Vision could localize it), and breed guesses for that crop.
struct PetDetection: Identifiable {
    let id = UUID()
    let species: BreedGuess
    let breedGuesses: [BreedGuess]
    let croppedImage: UIImage?
}

enum PetClassifier {
    private static let log = Logger(subsystem: "com.denniscrothers.Skpr", category: "PetClassifier")

    /// Detects every dog/cat Vision can find in the photo -- each gets its
    /// own crop and its own breed guess, so a photo with two dogs comes back
    /// as two separate results instead of one blended guess.
    ///
    /// Pipeline per photo:
    ///  1. Render the UIImage into a single upright CGImage once, so every
    ///     downstream step works in plain top-left pixel coordinates instead
    ///     of juggling UIImage.Orientation everywhere.
    ///  2. VNRecognizeAnimalsRequest finds each animal's bounding box and
    ///     species (Dog/Cat). This can return zero, one, or several boxes.
    ///  3. For each box, crop out just that animal (with a little padding)
    ///     and run MobileNetV2 on the crop for a breed-specific guess.
    ///  4. If Vision found nothing at all (e.g. an unusual pose it missed),
    ///     fall back to running MobileNetV2 on the whole photo once, and
    ///     infer species from its top guess via PetTaxonomy.
    static func classify(_ image: UIImage, completion: @escaping ([PetDetection]) -> Void) {
        guard let uprightCGImage = uprightCGImage(from: image) else {
            log.error("classify: couldn't render an upright CGImage")
            completion([])
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let observations = detectAnimals(in: uprightCGImage)

            guard !observations.isEmpty else {
                log.info("VNRecognizeAnimalsRequest: no animals detected -- trying whole-image breed classifier as a fallback")
                let wholeImageGuesses = classifyBreed(cgImage: uprightCGImage)
                var detections: [PetDetection] = []
                if let topBreed = wholeImageGuesses.first,
                   let inferredSpecies = PetTaxonomy.species(forRawIdentifier: topBreed.rawIdentifier) {
                    let species = BreedGuess(label: inferredSpecies, rawIdentifier: inferredSpecies, confidence: topBreed.confidence)
                    detections = [PetDetection(species: species, breedGuesses: wholeImageGuesses, croppedImage: nil)]
                }
                log.info("fallback detections=\(detections.count)")
                DispatchQueue.main.async { completion(detections) }
                return
            }

            let imageSize = CGSize(width: uprightCGImage.width, height: uprightCGImage.height)
            var detections: [PetDetection] = []
            for observation in observations {
                guard let topLabel = observation.labels.first else { continue }
                let species = BreedGuess(label: topLabel.identifier, rawIdentifier: topLabel.identifier, confidence: topLabel.confidence)

                let cropRect = paddedPixelRect(for: observation.boundingBox, imageSize: imageSize, padding: 0.15)
                var breedGuesses: [BreedGuess] = []
                var croppedImage: UIImage?
                if let cropRect, let cropped = uprightCGImage.cropping(to: cropRect) {
                    breedGuesses = classifyBreed(cgImage: cropped)
                    croppedImage = UIImage(cgImage: cropped)
                } else {
                    // Cropping math failed for some reason -- classify the
                    // whole frame rather than dropping this detection.
                    breedGuesses = classifyBreed(cgImage: uprightCGImage)
                }

                detections.append(PetDetection(species: species, breedGuesses: breedGuesses, croppedImage: croppedImage))
            }

            log.info("detections=\(detections.count)")
            DispatchQueue.main.async { completion(detections) }
        }
    }

    private static func uprightCGImage(from image: UIImage) -> CGImage? {
        // image.size/draw already account for UIImage.Orientation, so
        // rendering through UIGraphicsImageRenderer gives a plain, upright
        // bitmap -- no manual CGImagePropertyOrientation math needed
        // anywhere past this point.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        let upright = renderer.image { _ in image.draw(at: .zero) }
        return upright.cgImage
    }

    private static func detectAnimals(in cgImage: CGImage) -> [VNRecognizedObjectObservation] {
        let request = VNRecognizeAnimalsRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)
        do {
            try handler.perform([request])
        } catch {
            log.error("detectAnimals: handler.perform threw: \(error.localizedDescription, privacy: .public)")
            return []
        }
        return request.results ?? []
    }

    private static func classifyBreed(cgImage: CGImage) -> [BreedGuess] {
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

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)
        do {
            try handler.perform([request])
        } catch {
            log.error("classifyBreed: handler.perform threw: \(error.localizedDescription, privacy: .public)")
            return []
        }
        return breedGuesses
    }

    /// Vision's boundingBox is normalized (0...1) with the origin at the
    /// BOTTOM-left. Pixel cropping needs top-left-origin pixels, so this
    /// flips Y, adds a little padding around the box (breed classifiers do
    /// better with some context rather than a razor-tight crop), and clamps
    /// to the image's actual bounds.
    private static func paddedPixelRect(for normalizedBox: CGRect, imageSize: CGSize, padding: CGFloat) -> CGRect? {
        guard imageSize.width > 0, imageSize.height > 0 else { return nil }

        let padded = normalizedBox.insetBy(
            dx: -normalizedBox.width * padding,
            dy: -normalizedBox.height * padding
        )

        let pixelRect = CGRect(
            x: padded.minX * imageSize.width,
            y: (1 - padded.maxY) * imageSize.height,
            width: padded.width * imageSize.width,
            height: padded.height * imageSize.height
        )

        let bounds = CGRect(origin: .zero, size: imageSize)
        let clamped = pixelRect.intersection(bounds)
        return clamped.isNull || clamped.width < 10 || clamped.height < 10 ? nil : clamped
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
