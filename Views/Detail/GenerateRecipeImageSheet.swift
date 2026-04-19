import SwiftUI

struct GenerateRecipeImageSheet: View {
    @EnvironmentObject private var store: RecipeStore
    @Environment(\.dismiss) private var dismiss

    @State private var selectedMode: RecipeImageMode = .recipeCard
    @State private var extraDetail = ""
    @State private var isGenerating = false
    @State private var generationIssue: RecipeImageIssue?

    let recipe: Recipe

    private var current: Recipe {
        store.recipes.first { $0.id == recipe.id } ?? recipe
    }

    private var previewImage: UIImage? {
        guard let data = current.imageData else { return nil }
        return UIImage(data: data)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Preview") {
                    if let previewImage {
                        Image(uiImage: previewImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    } else {
                        VStack(spacing: 10) {
                            Image(systemName: "photo")
                                .font(.system(size: 30))
                                .foregroundStyle(.secondary)
                            Text("No current image")
                                .font(.headline)
                            Text("Generate a new image and it will be attached to this recipe immediately.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                    }
                }

                Section("Mode") {
                    Picker("Image mode", selection: $selectedMode) {
                        ForEach(RecipeImageMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(selectedMode.shortDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("More detail") {
                    TextEditor(text: $extraDetail)
                        .frame(minHeight: 110)
                        .disabled(isGenerating)
                    Text("Examples: old Quebec cookbook look, close-up, golden lighting, modern white plate, restaurant luxury atmosphere.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if isGenerating {
                    Section("Status") {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text(progressTitle)
                                    .font(.headline)
                            }

                            Text(progressMessage)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }

                if let generationIssue {
                    Section("Problem details") {
                        RecipeImageIssueCard(issue: generationIssue)
                    }
                }

                Section {
                    Button {
                        Task {
                            await generateImage()
                        }
                    } label: {
                        HStack {
                            if isGenerating {
                                ProgressView()
                            }
                            Text(isGenerating ? "Generating..." : "Generate Image")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(isGenerating)
                }
            }
            .navigationTitle("Generate Image")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private func generateImage() async {
        isGenerating = true
        generationIssue = nil

        do {
            try await store.generateRecipeImage(
                for: current,
                mode: selectedMode,
                extraDetail: normalizedExtraDetail
            )
        } catch {
            generationIssue = RecipeImageIssue.from(error)
        }

        isGenerating = false
    }

    private var progressTitle: String {
        switch selectedMode {
        case .recipeCard:
            return "Generating recipe card..."
        case .dishPhoto:
            return "Generating dish photo..."
        }
    }

    private var progressMessage: String {
        switch selectedMode {
        case .recipeCard:
            return "MomRecette is building a styled landscape recipe card from the title, ingredients, and optional instructions."
        case .dishPhoto:
            return "MomRecette is generating a plated landscape dish photo using the recipe ingredients and your extra art direction."
        }
    }

    private var normalizedExtraDetail: String? {
        let trimmed = extraDetail.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct RecipeImageIssueCard: View {
    let issue: RecipeImageIssue

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(issue.title)
                        .font(.headline)
                    Text(issue.message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(issue.id)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color(UIColor.tertiarySystemFill))
                    )
            }

            Label(issue.recoverySuggestion, systemImage: "wrench.and.screwdriver")
                .font(.subheadline)

            if let debugDetail = issue.debugDetail, !debugDetail.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Debug detail")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(debugDetail)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(UIColor.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.red.opacity(0.18), lineWidth: 1)
        )
    }
}

#if DEBUG
#Preview {
    GenerateRecipeImageSheet(recipe: Recipe.samples[0])
        .environmentObject(RecipeStore())
}
#endif
