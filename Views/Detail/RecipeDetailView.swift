import SwiftUI
import UIKit

enum RecipeWorkspaceSection: String, CaseIterable, Identifiable {
    case overview = "Apercu"
    case ingredients = "Ingredients"
    case steps = "Etapes"
    case cardExport = "Export"
    case notes = "Notes"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .overview:
            return "sparkles"
        case .ingredients:
            return "checklist"
        case .steps:
            return "list.number"
        case .cardExport:
            return "square.and.arrow.up"
        case .notes:
            return "note.text"
        }
    }
}

enum IngredientPresentation: String, CaseIterable, Identifiable {
    case checklist = "Checklist"
    case recipeCard = "Recipe Card"

    var id: String { rawValue }
}

struct RecipeDetailView: View {
    @EnvironmentObject private var store: RecipeStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var selectedSection: RecipeWorkspaceSection = MomRecetteSetup.RecipeWorkspace.defaultSection
    @State private var ingredientPresentation: IngredientPresentation = .checklist
    @State private var checkedIngredientIDs: Set<UUID> = []
    @State private var showEdit = false
    @State private var showDeleteAlert = false
    @State private var showGroceryList = false
    @State private var showGenerateImageSheet = false
    @State private var showCookingMode = false
    @State private var sharePayload: SharePayload?

    let recipe: Recipe

    private var current: Recipe {
        store.recipes.first { $0.id == recipe.id } ?? recipe
    }

    private var heroHeight: CGFloat {
        horizontalSizeClass == .regular ? 320 : 250
    }

    private var currentImage: UIImage? {
        guard let data = current.imageData else { return nil }
        return UIImage(data: data)
    }

    private var recipeCardImage: UIImage? {
        guard let data = store.recipeCardImageData(for: current) else { return nil }
        return UIImage(data: data)
    }

    private var exportImageURL: URL? {
        store.recipeImageURL(for: current)
    }

    private var recipeCardImageURL: URL? {
        store.recipeCardImageURL(for: current)
    }

    private var generatedModeTitle: String? {
        guard let rawValue = current.generatedImageMode,
              let mode = RecipeImageMode(rawValue: rawValue) else { return nil }
        return mode.title
    }

    private var preferredIngredientPresentation: IngredientPresentation {
        MomRecetteSetup.RecipeWorkspace.defaultIngredientPresentation(hasRecipeCard: recipeCardImage != nil)
    }

    private var recipeShareText: String {
        let ingredientSummary = current.ingredients.prefix(6).map(\.name).joined(separator: ", ")
        let metadataSegments = [
            "\(current.prepTime.timeString) de preparation",
            "\(current.cookTime.timeString) de cuisson",
            "\(current.servings) portions",
            current.caloriesPerServing.map { "\($0) kcal par portion" }
        ].compactMap { $0 }

        return """
        \(current.name)

        \(metadataSegments.joined(separator: ", ")).

        Ingredients: \(ingredientSummary)
        """
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                RecipeHeroHeaderView(
                    recipe: current,
                    image: currentImage,
                    height: heroHeight
                )

                VStack(alignment: .leading, spacing: 18) {
                    RecipeMetaHeaderView(recipe: current)

                    RecipeActionBar(
                        recipe: current,
                        selectedSection: $selectedSection,
                        onEdit: { showEdit = true },
                        onShare: {
                            sharePayload = SharePayload(items: [recipeShareText])
                        },
                        onToggleFavorite: { store.toggleFavorite(for: current) },
                        onOpenGrocery: {
                            store.createGroceryList(for: current)
                            showGroceryList = true
                        },
                        onOpenCooking: { showCookingMode = true }
                    )

                    WorkspaceSectionPicker(selection: $selectedSection)

                    sectionContent
                }
                .padding(.horizontal, horizontalSizeClass == .regular ? 28 : 20)
                .padding(.bottom, 28)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(current.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                GenerateRecipeImageButton {
                    showGenerateImageSheet = true
                }

                Menu {
                    Button {
                        showEdit = true
                    } label: {
                        Label("Modifier", systemImage: "pencil")
                    }

                    Button {
                        selectedSection = .cardExport
                    } label: {
                        Label("Aller a l'export", systemImage: "square.and.arrow.up")
                    }

                    Divider()

                    Button(role: .destructive) {
                        showDeleteAlert = true
                    } label: {
                        Label("Supprimer", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showGenerateImageSheet) {
            GenerateRecipeImageSheet(store: store, recipe: current)
        }
        .sheet(isPresented: $showEdit) {
            AddEditRecipeView(recipe: current)
        }
        .sheet(isPresented: $showGroceryList) {
            GroceryListView()
        }
        .fullScreenCover(isPresented: $showCookingMode) {
            CookingModeView(recipe: current)
        }
        .alert("Supprimer cette recette ?", isPresented: $showDeleteAlert) {
                Button("Supprimer", role: .destructive) {
                    store.delete(current)
                    dismiss()
                }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Cette action retire la recette et son image generee si elle existe.")
        }
        .onAppear {
            ingredientPresentation = preferredIngredientPresentation
        }
        .onChange(of: current.id) { _ in
            checkedIngredientIDs.removeAll()
            ingredientPresentation = preferredIngredientPresentation
            selectedSection = MomRecetteSetup.RecipeWorkspace.defaultSection
        }
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch selectedSection {
        case .overview:
            RecipeOverviewPanel(recipe: current)
        case .ingredients:
            IngredientChecklistPanel(
                selectedPresentation: $ingredientPresentation,
                recipe: current,
                checkedIngredientIDs: $checkedIngredientIDs,
                recipeCardImage: recipeCardImage,
                onGenerateRecipeCard: {
                    showGenerateImageSheet = true
                    ingredientPresentation = .recipeCard
                }
            )
        case .steps:
            ProcedureStepsPanel(
                recipe: current,
                onOpenCooking: { showCookingMode = true }
            )
        case .cardExport:
            RecipeExportPanel(
                recipe: current,
                dishImage: currentImage,
                recipeCardImageURL: recipeCardImageURL,
                dishImageURL: exportImageURL,
                generatedModeTitle: generatedModeTitle,
                onGenerate: { showGenerateImageSheet = true },
                onShareRecipeCard: {
                    if let recipeCardImageURL {
                        sharePayload = SharePayload(items: [recipeCardImageURL])
                    } else {
                        sharePayload = SharePayload(items: [recipeShareText])
                    }
                },
                onShareDishImage: {
                    if let exportImageURL {
                        sharePayload = SharePayload(items: [exportImageURL])
                    } else {
                        sharePayload = SharePayload(items: [recipeShareText])
                    }
                }
            )
        case .notes:
            NotesPanel(notes: current.notes)
        }
    }
}

private struct RecipeHeroHeaderView: View {
    let recipe: Recipe
    let image: UIImage?
    let height: CGFloat

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    LinearGradient(
                        colors: [
                            recipe.category.color.opacity(0.92),
                            recipe.category.color.opacity(0.62),
                            Color(red: 0.96, green: 0.88, blue: 0.80)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            }
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
            .clipped()

            LinearGradient(
                colors: [.clear, .black.opacity(0.14), .black.opacity(0.62)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    CategoryBadge(category: recipe.category)

                    Spacer()

                    Label(
                        image == nil ? "Ajoutez ou generez une photo" : "Photo du plat",
                        systemImage: image == nil ? "photo.badge.plus" : "photo"
                    )
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(.black.opacity(0.24))
                    )
                    .foregroundStyle(.white)
                }

                Spacer()

                VStack(alignment: .leading, spacing: 10) {
                    Text(recipe.name)
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("Lecture plus claire pour cuisiner maintenant, export plus calme quand vous etes pret a partager.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.88))
                }
            }
            .padding(24)
        }
    }
}

private struct RecipeMetaHeaderView: View {
    let recipe: Recipe

    private var metadataItems: [(systemImage: String, label: String, value: String)] {
        var items: [(String, String, String)] = [
            ("clock", "Preparation", recipe.prepTime.timeString),
            ("flame", "Cuisson", recipe.cookTime.timeString),
            ("person.2", "Portions", "\(recipe.servings)")
        ]

        if let caloriesPerServing = recipe.caloriesPerServing {
            items.append(("bolt.heart", "Calories / portion", "\(caloriesPerServing) kcal"))
        }

        items.append(("list.bullet", "Ingredients", "\(recipe.ingredients.count)"))
        return items
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(recipe.category.rawValue)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(recipe.category.color)
                    Text(recipe.name)
                        .font(.title2.weight(.bold))
                    Text("Espace de travail principal pour lire la recette, verifier les ingredients, suivre les etapes et ouvrir l'export seulement quand necessaire.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if recipe.isFavorite {
                    Label("Favori", systemImage: "star.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.yellow)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(Color.yellow.opacity(0.12))
                        )
                }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 12)], spacing: 12) {
                ForEach(metadataItems, id: \.label) { item in
                    RecipeMetaTile(
                        systemImage: item.systemImage,
                        label: item.label,
                        value: item.value
                    )
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }
}

private struct RecipeMetaTile: View {
    let systemImage: String
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(Color.accentColor)
            Text(value)
                .font(.headline.weight(.bold))
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.systemBackground))
        )
    }
}

private struct RecipeActionBar: View {
    let recipe: Recipe
    @Binding var selectedSection: RecipeWorkspaceSection
    let onEdit: () -> Void
    let onShare: () -> Void
    let onToggleFavorite: () -> Void
    let onOpenGrocery: () -> Void
    let onOpenCooking: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ActionPillButton(title: "Modifier", systemImage: "pencil", style: .secondary, action: onEdit)
                ActionPillButton(title: "Partager", systemImage: "square.and.arrow.up", style: .secondary, action: onShare)
                ActionPillButton(
                    title: recipe.isFavorite ? "Favori" : "Ajouter aux favoris",
                    systemImage: recipe.isFavorite ? "star.fill" : "star",
                    style: recipe.isFavorite ? .highlight : .secondary,
                    action: onToggleFavorite
                )
                ActionPillButton(title: "Epicerie", systemImage: "cart.badge.plus", style: .accent, action: onOpenGrocery)
                ActionPillButton(title: "Cuisson", systemImage: "play.circle", style: .secondary, action: onOpenCooking)
                ActionPillButton(
                    title: "Export",
                    systemImage: "square.and.arrow.up",
                    style: selectedSection == .cardExport ? .highlight : .secondary
                ) {
                    selectedSection = .cardExport
                }
            }
        }
    }
}

private struct ActionPillButton: View {
    enum Style {
        case accent
        case secondary
        case highlight

        var foreground: Color {
            switch self {
            case .accent:
                return .white
            case .secondary:
                return .primary
            case .highlight:
                return Color.accentColor
            }
        }

        var background: Color {
            switch self {
            case .accent:
                return Color.accentColor
            case .secondary:
                return Color(.secondarySystemBackground)
            case .highlight:
                return Color.accentColor.opacity(0.12)
            }
        }
    }

    let title: String
    let systemImage: String
    let style: Style
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ActionPillLabel(title: title, systemImage: systemImage, style: style)
        }
        .buttonStyle(.plain)
    }
}

private struct ActionPillLabel: View {
    let title: String
    let systemImage: String
    let style: ActionPillButton.Style

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .fill(style.background)
            )
            .foregroundStyle(style.foreground)
    }
}

private struct WorkspaceSectionPicker: View {
    @Binding var selection: RecipeWorkspaceSection

    var body: some View {
        Picker("Section", selection: $selection) {
            ForEach(RecipeWorkspaceSection.allCases) { section in
                Text(section.rawValue).tag(section)
            }
        }
        .pickerStyle(.segmented)
    }
}

private struct RecipeOverviewPanel: View {
    let recipe: Recipe

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            WorkspaceLeadCard(
                title: "Flux principal",
                message: "Passez d'abord par les ingredients et les etapes. La carte exportee reste disponible dans son onglet dedie, sans parasiter la lecture.",
                systemImage: "rectangle.stack.badge.play"
            )

            if !recipe.ingredientGroups.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeading(title: "Vue rapide des ingredients", systemImage: "square.grid.2x2")

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                        ForEach(recipe.ingredientGroups.prefix(6)) { group in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text(group.kind.icon)
                                    Text(group.kind.title)
                                        .font(.headline)
                                }

                                Text("\(group.count) ingredient\(group.count > 1 ? "s" : "")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Text(group.sampleNames)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(3)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .fill(Color(.secondarySystemGroupedBackground))
                            )
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                SectionHeading(title: "Preparation en bref", systemImage: "list.number")

                ForEach(Array(recipe.steps.prefix(3).enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(index + 1)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(
                                Circle()
                                    .fill(Color.accentColor)
                            )

                        Text(step)
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color(.secondarySystemGroupedBackground))
                    )
                }
            }
        }
    }
}

private struct IngredientChecklistPanel: View {
    @Binding var selectedPresentation: IngredientPresentation
    let recipe: Recipe
    @Binding var checkedIngredientIDs: Set<UUID>
    let recipeCardImage: UIImage?
    let onGenerateRecipeCard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                SectionHeading(title: "Checklist ingredients", systemImage: "checkmark.circle")
                Spacer()
                Button("Tout reinitialiser") {
                    checkedIngredientIDs.removeAll()
                }
                .font(.caption.weight(.semibold))
            }

            Picker("Presentation", selection: $selectedPresentation) {
                ForEach(IngredientPresentation.allCases) { presentation in
                    Text(presentation.rawValue).tag(presentation)
                }
            }
            .pickerStyle(.segmented)

            if selectedPresentation == .checklist {
                ForEach(recipe.ingredientGroups) { group in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(group.kind.icon)
                            Text(group.kind.title)
                                .font(.headline)
                            Spacer()
                            Text("\(group.count)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }

                        ForEach(group.ingredients) { ingredient in
                            IngredientChecklistRow(
                                ingredient: ingredient,
                                isChecked: checkedIngredientIDs.contains(ingredient.id)
                            ) {
                                if checkedIngredientIDs.contains(ingredient.id) {
                                    checkedIngredientIDs.remove(ingredient.id)
                                } else {
                                    checkedIngredientIDs.insert(ingredient.id)
                                }
                            }
                        }
                    }
                    .padding(18)
                    .background(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(Color(.secondarySystemGroupedBackground))
                    )
                }
            } else {
                RecipeCardIngredientPanel(
                    image: recipeCardImage,
                    onGenerateRecipeCard: onGenerateRecipeCard
                )
            }
        }
    }
}

private struct RecipeCardIngredientPanel: View {
    let image: UIImage?
    let onGenerateRecipeCard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            WorkspaceLeadCard(
                title: "Recipe card des ingredients",
                message: "Cette vue reste liee aux ingredients et aux etapes, sans remplacer la photo hero du plat.",
                systemImage: "text.rectangle.page"
            )

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(Color.accentColor.opacity(0.12), lineWidth: 1)
                    )
            } else {
                DetailEmptyCard(
                    title: "Aucune recipe card",
                    message: "Generez une Recipe Card pour voir ici une carte visuelle basee sur les ingredients et les etapes.",
                    systemImage: "text.rectangle.page"
                )
            }

            Button {
                onGenerateRecipeCard()
            } label: {
                Label("Generer une Recipe Card", systemImage: "wand.and.stars")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

private struct IngredientChecklistRow: View {
    let ingredient: Recipe.Ingredient
    let isChecked: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isChecked ? .green : .secondary)

                VStack(alignment: .leading, spacing: 4) {
                    Text(displayText)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(isChecked ? .secondary : .primary)
                        .strikethrough(isChecked, color: .secondary)

                    if !ingredient.quantity.isEmpty {
                        Text("Quantite: \(ingredient.quantity)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private var displayText: String {
        ingredient.name
    }
}

private struct ProcedureStepsPanel: View {
    let recipe: Recipe
    let onOpenCooking: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                SectionHeading(title: "Preparation", systemImage: "list.number")
                Spacer()
                Button {
                    onOpenCooking()
                } label: {
                    Label("Mode cuisson", systemImage: "play.circle.fill")
                        .font(.subheadline.weight(.semibold))
                }
            }

            if recipe.steps.isEmpty {
                DetailEmptyCard(
                    title: "Aucune etape",
                    message: "Ajoutez la procedure pour activer un vrai mode cuisson.",
                    systemImage: "text.badge.xmark"
                )
            } else {
                ForEach(Array(recipe.steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 14) {
                        Text("\(index + 1)")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(
                                Circle()
                                    .fill(Color.accentColor)
                            )

                        Text(step)
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer()
                    }
                    .padding(18)
                    .background(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(Color(.secondarySystemGroupedBackground))
                    )
                }
            }
        }
    }
}

private struct RecipeExportPanel: View {
    let recipe: Recipe
    let dishImage: UIImage?
    let recipeCardImageURL: URL?
    let dishImageURL: URL?
    let generatedModeTitle: String?
    let onGenerate: () -> Void
    let onShareRecipeCard: () -> Void
    let onShareDishImage: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            WorkspaceLeadCard(
                title: "Export calme",
                message: "La carte ou la photo finale vit ici comme un artefact de sortie. Le coeur de la recette reste dans les onglets Ingredients et Etapes.",
                systemImage: "square.and.arrow.up"
            )

            HStack(spacing: 12) {
                ExportArtifactStatusCard(
                    title: "Recipe Card",
                    isReady: recipeCardImageURL != nil,
                    readyText: "Prete a partager",
                    missingText: "A generer depuis Ingredients",
                    systemImage: "text.rectangle.page"
                )
                ExportArtifactStatusCard(
                    title: "Dish Photo",
                    isReady: dishImageURL != nil,
                    readyText: "Prete a partager",
                    missingText: "A generer depuis Generate Image",
                    systemImage: "fork.knife.circle"
                )
            }

            if let dishImage {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Dish Photo actuelle", systemImage: "fork.knife.circle")
                        .font(.headline)

                    Image(uiImage: dishImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .stroke(Color.accentColor.opacity(0.12), lineWidth: 1)
                        )
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Label(generatedModeTitle ?? "Dish Photo courante", systemImage: "sparkles")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Button {
                        onGenerate()
                    } label: {
                        Label("Generer", systemImage: "wand.and.stars")
                    }
                    .buttonStyle(.borderedProminent)
                }

                Text("Choisissez un mode d'image, ajoutez une direction artistique, puis remplacez immediatement la photo de recette dans cette zone.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    Button(action: onShareRecipeCard) {
                        Label(recipeCardImageURL != nil ? "Partager la card" : "Partager la recette", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button(action: onShareDishImage) {
                        Label(dishImageURL != nil ? "Partager le plat" : "Partager le texte", systemImage: dishImageURL != nil ? "photo" : "text.quote")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
        }
    }
}

private struct ExportArtifactStatusCard: View {
    let title: String
    let isReady: Bool
    let readyText: String
    let missingText: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            Text(isReady ? readyText : missingText)
                .font(.caption)
                .foregroundStyle(.secondary)
            Image(systemName: isReady ? "checkmark.circle.fill" : "clock.badge.exclamationmark")
                .foregroundStyle(isReady ? .green : .secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }
}

private struct SharePayload: Identifiable {
    let id = UUID()
    let items: [Any]
}

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct NotesPanel: View {
    let notes: String

    var body: some View {
        if notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            DetailEmptyCard(
                title: "Aucune note",
                message: "Ajoutez des commentaires, souvenirs de famille ou conseils de service pour completer la recette.",
                systemImage: "note.text.badge.plus"
            )
        } else {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeading(title: "Notes", systemImage: "note.text")
                Text(notes)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(18)
                    .background(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(Color(.secondarySystemGroupedBackground))
                    )
            }
        }
    }
}

private struct CookingModeView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var currentStepIndex = 0

    let recipe: Recipe

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(recipe.name)
                        .font(.largeTitle.weight(.bold))
                    Text("Mode cuisson concentre")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if recipe.steps.isEmpty {
                    DetailEmptyCard(
                        title: "Aucune etape disponible",
                        message: "Ajoutez des etapes a cette recette pour utiliser le mode cuisson.",
                        systemImage: "list.bullet.rectangle"
                    )
                } else {
                    Text("Etape \(currentStepIndex + 1) sur \(recipe.steps.count)")
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    Text(recipe.steps[currentStepIndex])
                        .font(.title3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(24)
                        .background(
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .fill(Color(.secondarySystemGroupedBackground))
                        )

                    HStack(spacing: 12) {
                        Button {
                            currentStepIndex = max(0, currentStepIndex - 1)
                        } label: {
                            Label("Precedente", systemImage: "chevron.left")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(currentStepIndex == 0)

                        Button {
                            currentStepIndex = min(recipe.steps.count - 1, currentStepIndex + 1)
                        } label: {
                            Label(currentStepIndex == recipe.steps.count - 1 ? "Terminer" : "Suivante", systemImage: "chevron.right")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Ingredients utiles")
                            .font(.headline)

                        ForEach(recipe.ingredients.prefix(8)) { ingredient in
                            Text(ingredient.quantity.isEmpty ? ingredient.name : "\(ingredient.quantity) \(ingredient.name)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()
            }
            .padding(24)
            .navigationTitle("Cuisson")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct WorkspaceLeadCard: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 34, height: 34)
                .background(
                    Circle()
                        .fill(Color.accentColor.opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }
}

private struct DetailEmptyCard: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }
}

private struct SectionHeading: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
            .foregroundStyle(.primary)
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        RecipeDetailView(recipe: Recipe.samples[0])
            .environmentObject(RecipeStore())
    }
}
#endif
