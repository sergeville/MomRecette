import SwiftUI

// MARK: - Recipe Detail Sheet

struct RecipeDetailView: View {
    private enum IngredientPanel: String, CaseIterable, Identifiable {
        case text = "Texte"
        case card = "Carte"

        var id: String { rawValue }
    }

    @EnvironmentObject var store: RecipeStore
    @Environment(\.dismiss) var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var showEdit = false
    @State private var showDeleteAlert = false
    @State private var showGroceryList = false
    @State private var showGenerateImageSheet = false
    @State private var ingredientPanel: IngredientPanel = .text
    @State private var ingredientCardData: Data?
    @State private var ingredientCardSourceName: String?
    @State private var isGeneratingIngredientCard = false
    @State private var ingredientCardError: String?

    let recipe: Recipe

    private var current: Recipe {
        store.recipes.first { $0.id == recipe.id } ?? recipe
    }

    private var heroHeight: CGFloat {
        horizontalSizeClass == .regular ? 420 : 360
    }

    private var featuredIngredientGroups: [Recipe.IngredientGroup] {
        Array(current.ingredientGroups.prefix(3))
    }

    private var ingredientCardLookupSignature: String {
        current.ingredientCardLookupKeys.joined(separator: "|")
    }

    private var ingredientCardImage: UIImage? {
        guard let ingredientCardData else { return nil }
        return UIImage(data: ingredientCardData)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // ── Hero Photo ──────────────────────────
                    heroImage

                    // ── Info Bar ────────────────────────────
                    infoBar
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)

                    ingredientOverview
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)

                    groceryListButton
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)

                    Divider()

                    // ── Ingredients ─────────────────────────
                    Section {
                        VStack(alignment: .leading, spacing: 16) {
                            Picker("Affichage des ingrédients", selection: $ingredientPanel) {
                                ForEach(IngredientPanel.allCases) { panel in
                                    Text(panel.rawValue).tag(panel)
                                }
                            }
                            .pickerStyle(.segmented)

                            if ingredientPanel == .text {
                                ingredientTextPanel
                            } else {
                                ingredientCardPanel
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)
                    } header: {
                        sectionHeader("Ingrédients", icon: "list.bullet")
                    }

                    Divider()

                    // ── Steps ───────────────────────────────
                    Section {
                        VStack(alignment: .leading, spacing: 16) {
                            ForEach(Array(current.steps.enumerated()), id: \.offset) { i, step in
                                HStack(alignment: .top, spacing: 14) {
                                    ZStack {
                                        Circle()
                                            .fill(current.category.color)
                                            .frame(width: 28, height: 28)
                                        Text("\(i + 1)")
                                            .font(.caption)
                                            .fontWeight(.bold)
                                            .foregroundStyle(.white)
                                    }
                                    Text(step)
                                        .font(.body)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Spacer()
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)
                    } header: {
                        sectionHeader("Préparation", icon: "checklist")
                    }

                    // ── Notes ───────────────────────────────
                    if !current.notes.isEmpty {
                        Divider()
                        Section {
                            Text(current.notes)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .italic()
                                .padding(.horizontal, 20)
                                .padding(.bottom, 16)
                        } header: {
                            sectionHeader("Notes", icon: "note.text")
                        }
                    }

                    Spacer(minLength: 40)
                }
            }
            .ignoresSafeArea(edges: .top)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Fermer") { dismiss() }
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    GenerateRecipeImageButton {
                        showGenerateImageSheet = true
                    }

                    Menu {
                        Button { showEdit = true } label: {
                            Label("Modifier", systemImage: "pencil")
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
                GenerateRecipeImageSheet(recipe: current)
            }
            .sheet(isPresented: $showEdit) {
                AddEditRecipeView(recipe: current)
            }
            .sheet(isPresented: $showGroceryList) {
                GroceryListView()
            }
            .alert("Supprimer cette recette ?", isPresented: $showDeleteAlert) {
                Button("Supprimer", role: .destructive) {
                    store.delete(current)
                    dismiss()
                }
                Button("Annuler", role: .cancel) {}
            }
            .task(id: ingredientCardLookupSignature) {
                loadIngredientCardIfAvailable()
                if ingredientPanel == .card {
                    await generateIngredientCardIfNeeded()
                }
            }
            .onChange(of: ingredientPanel) { panel in
                guard panel == .card else { return }
                Task {
                    await generateIngredientCardIfNeeded()
                }
            }
        }
    }

    // MARK: - Sub-Views

    @ViewBuilder
    private var heroImage: some View {
        ZStack(alignment: .bottomLeading) {
            if let data = current.imageData, let ui = UIImage(data: data) {
                posterPhoto(ui)
            } else {
                fallbackHeroPoster
            }

            heroOverlayContent
        }
        .frame(height: heroHeight)
    }

    private func posterPhoto(_ image: UIImage) -> some View {
        ZStack {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(height: heroHeight)
                .scaleEffect(1.06)
                .saturation(1.08)
                .clipped()

            LinearGradient(
                colors: [
                    .black.opacity(0.06),
                    .clear,
                    .black.opacity(0.58)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            RadialGradient(
                colors: [.clear, .black.opacity(0.22)],
                center: .center,
                startRadius: 70,
                endRadius: 340
            )
        }
        .overlay(alignment: .topTrailing) {
            Text("Photo du plat")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.95))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(.black.opacity(0.24))
                )
                .overlay(
                    Capsule()
                        .stroke(.white.opacity(0.18), lineWidth: 1)
                )
                .padding(18)
        }
    }

    private var fallbackHeroPoster: some View {
        ZStack {
            LinearGradient(
                colors: [
                    current.category.color.opacity(0.94),
                    current.category.color.opacity(0.68),
                    Color.white.opacity(0.22)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.white.opacity(0.18))
                .frame(width: 220, height: 220)
                .blur(radius: 12)
                .offset(x: -120, y: -90)

            Circle()
                .fill(current.category.color.opacity(0.25))
                .frame(width: 180, height: 180)
                .blur(radius: 8)
                .offset(x: 120, y: -70)

            VStack(spacing: 18) {
                if !featuredIngredientGroups.isEmpty {
                    HStack(spacing: 16) {
                        ForEach(featuredIngredientGroups) { group in
                            VStack(spacing: 8) {
                                Text(group.kind.icon)
                                    .font(.system(size: 34))
                                    .frame(width: 70, height: 70)
                                    .background(
                                        Circle()
                                            .fill(Color.white.opacity(0.22))
                                    )
                                Text(group.kind.title)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white.opacity(0.95))
                            }
                        }
                    }
                } else {
                    Text(current.category.icon)
                        .font(.system(size: 86))
                        .padding(24)
                        .background(
                            Circle()
                                .fill(Color.white.opacity(0.18))
                        )
                }

                if !featuredIngredientGroups.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(featuredIngredientGroups) { group in
                            Text(group.sampleNames)
                                .font(.caption)
                                .lineLimit(1)
                                .foregroundStyle(.white.opacity(0.95))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule()
                                        .fill(Color.black.opacity(0.12))
                                )
                        }
                    }
                    .padding(.horizontal, 24)
                }
            }
            .padding(.top, 24)
        }
        .frame(height: heroHeight)
    }

    private var heroOverlayContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            CategoryBadge(category: current.category)
            Text(current.name)
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundStyle(.white)

            Text("Une présentation plus proche d'une affiche culinaire.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.88))

            if !featuredIngredientGroups.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(featuredIngredientGroups) { group in
                            HStack(spacing: 8) {
                                Text(group.kind.icon)
                                Text(group.sampleNames)
                                    .lineLimit(1)
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.96))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(.black.opacity(0.24))
                            )
                            .overlay(
                                Capsule()
                                    .stroke(.white.opacity(0.16), lineWidth: 1)
                            )
                        }
                    }
                }
            }
        }
        .padding(20)
    }

    private var infoBar: some View {
        HStack(spacing: 0) {
            infoCell(icon: "clock", label: "Prép.", value: current.prepTime.timeString)
            Divider().frame(height: 40)
            infoCell(icon: "flame", label: "Cuisson", value: current.cookTime.timeString)
            Divider().frame(height: 40)
            infoCell(icon: "person.2", label: "Portions", value: "\(current.servings)")
            Divider().frame(height: 40)
            infoCell(icon: "list.bullet", label: "Ingrédients", value: "\(current.ingredients.count)")
        }
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(UIColor.secondarySystemBackground))
        )
    }

    @ViewBuilder
    private var ingredientOverview: some View {
        if !current.ingredientGroups.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    sectionTitle("Vue rapide des ingrédients", icon: "square.grid.2x2")
                    Spacer()
                    Text("\(current.ingredients.count) au total")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("Repérez rapidement les grandes familles comme les fruits, légumes, viandes et épices avant de lire les quantités.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 155), spacing: 12)],
                    spacing: 12
                ) {
                    ForEach(current.ingredientGroups) { group in
                        ingredientGroupCard(group)
                    }
                }
            }
        }
    }

    private var ingredientTextPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(current.ingredients) { ing in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Circle()
                        .fill(current.category.color)
                        .frame(width: 6, height: 6)
                        .padding(.top, 7)
                    Group {
                        if !ing.quantity.isEmpty {
                            Text(ing.quantity).fontWeight(.semibold)
                            + Text(" ") + Text(ing.name)
                        } else {
                            Text(ing.name)
                        }
                    }
                    .font(.body)
                    Spacer()
                }
            }
        }
    }

    @ViewBuilder
    private var ingredientCardPanel: some View {
        if let ingredientCardImage {
            VStack(alignment: .leading, spacing: 10) {
                Image(uiImage: ingredientCardImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(current.category.color.opacity(0.12), lineWidth: 1)
                    )

                if let ingredientCardSourceName {
                    Text("Carte chargée: \(ingredientCardSourceName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } else if isGeneratingIngredientCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Génération de la carte panoramique en cours...")
                        .font(.headline)
                }

                Text("La carte est générée via l'API Images OpenAI en format paysage `1536x1024`, puis enregistrée localement pour les prochains affichages.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(UIColor.secondarySystemBackground))
            )
        } else {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.title3)
                        .foregroundStyle(current.category.color)
                    Text("Aucune carte d'ingrédients trouvée")
                        .font(.headline)
                }

                Text("Cette vue génère automatiquement une carte panoramique à partir de la recette et l'enregistre sous `\(current.suggestedIngredientCardFilename)`.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("Sources prises en charge: bundle `RecipeIngredientCards/` et `Documents/RecipeIngredientCards/`. Vous pouvez aussi déposer votre propre image dans ce dossier pour remplacer la génération.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let ingredientCardError {
                    Text(ingredientCardError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Button {
                    Task {
                        await generateIngredientCardIfNeeded(force: true)
                    }
                } label: {
                    Label("Générer la carte", systemImage: "sparkles.rectangle.stack")
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(UIColor.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(current.category.color.opacity(0.12), lineWidth: 1)
            )
        }
    }

    private var groceryListButton: some View {
        Button {
            store.createGroceryList(for: current)
            showGroceryList = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "cart.badge.plus")
                    .font(.title3)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Créer la liste d'épicerie")
                        .font(.headline)
                    Text("Générez une liste à cocher à partir de cette recette.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.85))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: [current.category.color, current.category.color.opacity(0.78)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func ingredientGroupCard(_ group: Recipe.IngredientGroup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(group.kind.icon)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.kind.title)
                        .font(.headline)
                    Text("\(group.count) ingrédient\(group.count > 1 ? "s" : "")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Text(group.sampleNames)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(3)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(UIColor.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(current.category.color.opacity(0.14), lineWidth: 1)
        )
    }

    private func infoCell(icon: String, label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(current.category.color)
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }

    private func sectionTitle(_ title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(current.category.color)
            Text(title)
                .font(.headline)
        }
    }

    private func sectionHeader(_ title: String, icon: String) -> some View {
        sectionTitle(title, icon: icon)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func loadIngredientCardIfAvailable() {
        let resolved = Self.resolveIngredientCard(for: current)
        ingredientCardData = resolved?.data
        ingredientCardSourceName = resolved?.fileName
        if resolved != nil {
            ingredientCardError = nil
        }
    }

    private static func resolveIngredientCard(for recipe: Recipe) -> (data: Data, fileName: String)? {
        for key in recipe.ingredientCardLookupKeys {
            for ext in Self.supportedIngredientCardExtensions {
                let liveURL = RecipeCardImageGenerator.liveDirectoryURL().appendingPathComponent("\(key).\(ext)")
                if let resolved = loadIngredientCard(from: liveURL) {
                    return resolved
                }
            }
        }

        for key in recipe.ingredientCardLookupKeys {
            for ext in Self.supportedIngredientCardExtensions {
                if let bundledURL = Bundle.main.url(forResource: key, withExtension: ext, subdirectory: RecipeCardImageGenerator.directoryName),
                   let resolved = loadIngredientCard(from: bundledURL) {
                    return resolved
                }
            }
        }

        return nil
    }

    private static func loadIngredientCard(from url: URL) -> (data: Data, fileName: String)? {
        guard let data = try? Data(contentsOf: url), UIImage(data: data) != nil else { return nil }
        return (data, url.lastPathComponent)
    }

    private static let supportedIngredientCardExtensions = ["png", "jpg", "jpeg", "webp"]

    private func generateIngredientCardIfNeeded(force: Bool = false) async {
        guard ingredientPanel == .card else { return }
        if isGeneratingIngredientCard { return }
        if ingredientCardData != nil && !force { return }

        isGeneratingIngredientCard = true
        ingredientCardError = nil

        do {
            let imageData = try await RecipeCardImageGenerator.generateAndSaveCard(for: current)
            ingredientCardData = imageData
            ingredientCardSourceName = RecipeCardImageGenerator.ingredientCardURL(for: current).lastPathComponent
        } catch {
            ingredientCardError = error.localizedDescription
        }

        isGeneratingIngredientCard = false
    }
}

#if DEBUG
#Preview {
    RecipeDetailView(recipe: Recipe.samples[0])
        .environmentObject(RecipeStore())
}
#endif
