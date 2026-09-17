import SwiftUI

/// Shown right after a photo is captured: the photo, the detected species
/// (dog/cat), and MobileNetV2's best guesses at the specific breed.
struct BreedResultsView: View {
    let image: UIImage?
    let result: ClassificationResult
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal)
                }

                VStack(alignment: .leading, spacing: 16) {
                    if let species = result.species {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Detected")
                                .font(.headline)
                            HStack {
                                Text(species.label)
                                Spacer()
                                Text("\(Int(species.confidence * 100))%")
                                    .foregroundStyle(.secondary)
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Best breed guesses")
                                .font(.headline)
                            if result.breedGuesses.isEmpty {
                                Text("Couldn't narrow down a breed from this photo.")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(result.breedGuesses) { guess in
                                    HStack {
                                        Text(guess.label)
                                        Spacer()
                                        Text("\(Int(guess.confidence * 100))%")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    } else {
                        Text("No dog or cat detected in this photo.")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)

                Spacer()
            }
            .padding(.top)
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
