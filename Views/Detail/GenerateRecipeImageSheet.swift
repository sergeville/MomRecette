import SwiftUI

struct GenerateRecipeImageSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: RecipeStore

    @State private var selectedMode: RecipeImageMode = .recipeCard
    @State private var extraDetail = ""
    @State private var isGenerating = false
    @State private var generationIssue: RecipeImageIssue?

    let recipe: Recipe

    private var current: Recipe {
        store.recipes.first { $0.id == recipe.id } ?? recipe
    }

    private var previewImage: UIImage? {
        switch selectedMode {
        case .dishPhoto:
            guard let data = current.imageData else { return nil }
            return UIImage(data: data)
        case .recipeCard:
            guard let data = store.recipeCardImageData(for: current) else { return nil }
            return UIImage(data: data)
        }
    }

    private var previewTitle: String {
        switch selectedMode {
        case .dishPhoto:
            return "Dish Photo"
        case .recipeCard:
            return "Recipe Card"
        }
    }

    private var previewMessage: String {
        switch selectedMode {
        case .dishPhoto:
            return "This image becomes the hero recipe photo used in the main workspace."
        case .recipeCard:
            return "This image stays in the Card / Export surface and no longer replaces the dish photo."
        }
    }

    var body: some View {
        if #available(iOS 18.0, macCatalyst 18.0, *) {
            sheetContent
                .presentationSizing(.page)
                .frame(
                    minWidth: modalSizing.minimumWidth,
                    idealWidth: modalSizing.idealWidth,
                    minHeight: modalSizing.minimumHeight,
                    idealHeight: modalSizing.idealHeight
                )
        } else {
            sheetContent
                .frame(
                    minWidth: modalSizing.minimumWidth,
                    idealWidth: modalSizing.idealWidth,
                    minHeight: modalSizing.minimumHeight,
                    idealHeight: modalSizing.idealHeight
                )
                .background(sheetFrame.hidden())
        }
    }

    private var sheetContent: some View {
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
                            Text("No current \(previewTitle)")
                                .font(.headline)
                            Text(previewMessage)
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

                    Text(previewMessage)
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
#if !targetEnvironment(macCatalyst)
        .presentationDetents([.large])
#endif
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

    private var sheetFrame: some View {
        Group {
            #if targetEnvironment(macCatalyst)
            Color.clear
                .frame(
                    minWidth: modalSizing.minimumWidth,
                    idealWidth: modalSizing.idealWidth,
                    minHeight: modalSizing.minimumHeight,
                    idealHeight: modalSizing.idealHeight
                )
            #else
            Color.clear
                .frame(minHeight: 720)
            #endif
        }
    }

    private var modalSizing: (minimumWidth: CGFloat, idealWidth: CGFloat, minimumHeight: CGFloat, idealHeight: CGFloat) {
        #if targetEnvironment(macCatalyst)
        return (680, 740, 980, 1080)
        #else
        return (0, 0, 0, 0)
        #endif
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
    GenerateRecipeImageSheet(store: RecipeStore(), recipe: Recipe.samples[0])
}
#endif
