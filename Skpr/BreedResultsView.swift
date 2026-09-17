import SwiftUI

/// Shown right after a photo is captured or picked: the photo itself, plus
/// one card per dog/cat Vision found in it -- each with its own crop (when
/// available), species, and breed guesses. A photo with two dogs shows two
/// cards instead of one blended guess.
struct BreedResultsView: View {
    let image: UIImage?
    let detections: [PetDetection]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .padding(.horizontal)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        if detections.isEmpty {
                            Text("No dog or cat detected in this photo.")
                                .foregroundStyle(.secondary)
                        } else {
                            Text(detections.count > 1 ? "\(detections.count) pets detected" : "Detected")
                                .font(.headline)

                            ForEach(detections) { detection in
                                DetectionCard(detection: detection)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.top)
                .padding(.bottom, 24)
            }
            .navigationTitle("Saved to Photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct DetectionCard: View {
    let detection: PetDetection

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let cropped = detection.croppedImage {
                Image(uiImage: cropped)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(detection.species.label)
                        .fontWeight(.semibold)
                    Spacer()
                    Text("\(Int(detection.species.confidence * 100))%")
                        .foregroundStyle(.secondary)
                }

                if detection.breedGuesses.isEmpty {
                    Text("Couldn't narrow down a breed.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(detection.breedGuesses) { guess in
                        HStack {
                            Text(guess.label)
                                .font(.subheadline)
                            Spacer()
                            Text("\(Int(guess.confidence * 100))%")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}
