import SwiftUI

/// Shown right after a photo is captured: the photo itself plus Vision's
/// best guesses at what breed it is.
struct BreedResultsView: View {
    let image: UIImage?
    let guesses: [BreedGuess]
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

                VStack(alignment: .leading, spacing: 12) {
                    Text("Best guesses")
                        .font(.headline)

                    if guesses.isEmpty {
                        Text("No dog or cat detected in this photo.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(guesses) { guess in
                            HStack {
                                Text(guess.label)
                                Spacer()
                                Text("\(Int(guess.confidence * 100))%")
                                    .foregroundStyle(.secondary)
                            }
                        }
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
