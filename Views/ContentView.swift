import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: RecipeStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @AppStorage(MomRecetteSetup.Appearance.modeStorageKey)
    private var appearanceModeRawValue = MomRecetteSetup.Appearance.defaultMode.rawValue

    @State private var showAdd = false
    @State private var showImport = false
    @State private var showGroceryList = false
    @State private var showSettings = false
    @State private var selectedRecipeID: Recipe.ID?

    private var isRegularWorkspace: Bool {
        horizontalSizeClass == .regular
    }

    private var selectedRecipe: Recipe? {
        guard let selectedRecipeID else { return nil }
        return store.recipes.first { $0.id == selectedRecipeID }
    }

    private var remainingGroceryItemCount: Int? {
        store.currentGroceryList?.remainingItemCount
    }

    private var visibleRecipeCountLabel: String {
        "\(store.filteredRecipes.count) recette\(store.filteredRecipes.count > 1 ? "s" : "")"
    }

    private var appearanceMode: AppAppearanceMode {
        AppAppearanceMode(rawValue: appearanceModeRawValue) ?? MomRecetteSetup.Appearance.defaultMode
    }

    private var appearanceModeBinding: Binding<AppAppearanceMode> {
        Binding(
            get: { appearanceMode },
            set: { appearanceModeRawValue = $0.rawValue }
        )
    }

    var body: some View {
        Group {
            if isRegularWorkspace {
                regularWorkspace
            } else {
                phoneWorkspace
            }
        }
        .searchable(text: $store.searchText, prompt: "Rechercher une recette")
        .sheet(isPresented: $showAdd) {
            AddEditRecipeView()
        }
        .sheet(isPresented: $showImport) {
            ImportView()
        }
        .sheet(isPresented: $showGroceryList) {
            GroceryListView()
        }
        .sheet(isPresented: $showSettings) {
            AppSettingsView()
        }
        .onAppear {
            ensureRegularSelectionIfNeeded()
        }
        .onChange(of: store.filteredRecipes.map(\.id)) { _ in
            ensureRegularSelectionIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openMomRecetteSettings)) { _ in
            showSettings = true
        }
    }

    private var phoneWorkspace: some View {
        NavigationStack {
            RecipeLibraryScreen(
                isRegularWorkspace: false,
                selectedRecipeID: $selectedRecipeID
            )
            .navigationTitle("MomRecette")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: Recipe.ID.self) { recipeID in
                if let recipe = store.recipes.first(where: { $0.id == recipeID }) {
                    RecipeDetailView(recipe: recipe)
                } else {
                    RecipeSelectionPlaceholderView(
                        title: "Recette introuvable",
                        message: "La recette demandee n'est plus disponible. Revenez a la bibliotheque et choisissez-en une autre.",
                        systemImage: "fork.knife.circle"
                    )
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    appearanceToolbarMenu
                    groceryToolbarButton

                    Menu {
                        Button {
                            showAdd = true
                        } label: {
                            Label("Nouvelle recette", systemImage: "plus")
                        }

                        Button {
                            showImport = true
                        } label: {
                            Label("Importer", systemImage: "square.and.arrow.down")
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                    }
                }
            }
        }
    }

    private var regularWorkspace: some View {
        NavigationSplitView {
            SidebarNavigationView()
                .navigationTitle("MomRecette")
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        appearanceToolbarMenu
                        groceryToolbarButton

                        Button {
                            showImport = true
                        } label: {
                            Label("Importer", systemImage: "square.and.arrow.down")
                        }

                        Button {
                            showAdd = true
                        } label: {
                            Label("Nouvelle recette", systemImage: "plus")
                        }
                    }
                }
        } content: {
            RecipeLibraryScreen(
                isRegularWorkspace: true,
                selectedRecipeID: $selectedRecipeID
            )
            .navigationTitle(visibleRecipeCountLabel)
        } detail: {
            if let selectedRecipe {
                RecipeDetailView(recipe: selectedRecipe)
            } else {
                RecipeSelectionPlaceholderView(
                    title: store.selectedCollection.title,
                    message: "Selectionnez une recette dans la bibliotheque pour ouvrir son espace de travail, verifier les ingredients et lancer l'export.",
                    systemImage: store.selectedCollection.systemImage
                )
            }
        }
    }

    private var groceryToolbarButton: some View {
        Button {
            showGroceryList = true
        } label: {
            GroceryToolbarLabel(remainingItemCount: remainingGroceryItemCount)
        }
        .accessibilityLabel(groceryAccessibilityLabel)
        .help(groceryAccessibilityLabel)
    }

    private var appearanceToolbarMenu: some View {
        Menu {
            Picker("Apparence", selection: appearanceModeBinding) {
                ForEach(AppAppearanceMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.systemImage)
                        .tag(mode)
                }
            }
        } label: {
            Image(systemName: appearanceMode.systemImage)
        }
        .accessibilityLabel("Apparence")
        .help("Apparence: \(appearanceMode.title)")
    }

    private var groceryAccessibilityLabel: String {
        if let remainingGroceryItemCount {
            return "Liste d'epicerie, \(remainingGroceryItemCount) article\(remainingGroceryItemCount > 1 ? "s" : "") restant\(remainingGroceryItemCount > 1 ? "s" : "")"
        }

        return "Liste d'epicerie"
    }

    private func ensureRegularSelectionIfNeeded() {
        guard isRegularWorkspace else { return }

        let visibleIDs = Set(store.filteredRecipes.map(\.id))

        if let selectedRecipeID, visibleIDs.contains(selectedRecipeID) {
            return
        }

        selectedRecipeID = store.filteredRecipes.first?.id
    }
}

private struct SidebarNavigationView: View {
    @EnvironmentObject private var store: RecipeStore

    var body: some View {
        List {
            Section("Bibliotheque") {
                SidebarFilterButton(
                    title: "Toutes les recettes",
                    subtitle: "\(store.recipes.count)",
                    systemImage: "square.grid.2x2",
                    isSelected: store.selectedCollection == .all
                ) {
                    store.selectedCollection = .all
                }

                SidebarFilterButton(
                    title: "Favoris",
                    subtitle: "\(store.favoriteCount)",
                    systemImage: "star.fill",
                    isSelected: store.selectedCollection == .favorites
                ) {
                    store.selectedCollection = .favorites
                }
            }

            Section("Categories") {
                ForEach(Recipe.Category.allCases) { category in
                    SidebarFilterButton(
                        title: category.rawValue,
                        subtitle: "\(store.recipes.filter { $0.category == category }.count)",
                        systemImage: "tag",
                        tint: category.color,
                        trailingEmoji: category.icon,
                        isSelected: store.selectedCollection == .category(category)
                    ) {
                        store.selectedCollection = .category(category)
                    }
                }
            }

            if !store.recentRecipes.isEmpty {
                Section("Recents") {
                    ForEach(store.recentRecipes.prefix(3)) { recipe in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(recipe.name)
                                .font(.subheadline.weight(.semibold))
                            Text(recipe.category.rawValue)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }
}

private struct SidebarFilterButton: View {
    let title: String
    let subtitle: String
    let systemImage: String
    var tint: Color = .accentColor
    var trailingEmoji: String? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .foregroundStyle(isSelected ? .white : tint)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(isSelected ? .white.opacity(0.82) : .secondary)
                }

                Spacer()

                if let trailingEmoji {
                    Text(trailingEmoji)
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? tint : .clear)
            )
            .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}

private struct RecipeLibraryScreen: View {
    @EnvironmentObject private var store: RecipeStore

    let isRegularWorkspace: Bool
    @Binding var selectedRecipeID: Recipe.ID?

    var body: some View {
        Group {
            if store.filteredRecipes.isEmpty {
                LibraryEmptyStateView(scope: store.selectedCollection)
            } else if isRegularWorkspace {
                regularLibraryList
            } else {
                phoneLibraryList
            }
        }
    }

    private var phoneLibraryList: some View {
        List {
            Section {
                RecipeLibraryHeroView(scope: store.selectedCollection)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
            }

            Section("Parcourir") {
                LibraryScopeScroller(showsCategories: true)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
            }

            Section(store.selectedCollection.title) {
                ForEach(store.filteredRecipes) { recipe in
                    NavigationLink(value: recipe.id) {
                        RecipeListItemView(recipe: recipe, isCompact: false)
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        favoriteButton(for: recipe)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button {
                            store.createGroceryList(for: recipe)
                        } label: {
                            Label("Epicerie", systemImage: "cart.badge.plus")
                        }
                        .tint(.accentColor)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var regularLibraryList: some View {
        VStack(spacing: 0) {
            RecipeLibraryHeroView(scope: store.selectedCollection)
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 16)

            LibraryScopeScroller(showsCategories: false)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)

            List(selection: $selectedRecipeID) {
                ForEach(store.filteredRecipes) { recipe in
                    RecipeListItemView(recipe: recipe, isCompact: true)
                        .tag(recipe.id)
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            favoriteButton(for: recipe)
                        }
                }
            }
            .listStyle(.plain)
        }
        .background(Color(.systemGroupedBackground))
    }

    private func favoriteButton(for recipe: Recipe) -> some View {
        Button {
            store.toggleFavorite(for: recipe)
        } label: {
            Label(
                recipe.isFavorite ? "Retirer des favoris" : "Favori",
                systemImage: recipe.isFavorite ? "star.slash" : "star"
            )
        }
        .tint(recipe.isFavorite ? .gray : .yellow)
    }
}

private struct RecipeLibraryHeroView: View {
    @EnvironmentObject private var store: RecipeStore

    let scope: RecipeStore.RecipeCollection

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(scope.title)
                        .font(.title2.weight(.bold))
                    Text(heroSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Label("\(store.filteredRecipes.count)", systemImage: scope.systemImage)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(Color.accentColor.opacity(0.12))
                    )
                    .foregroundStyle(Color.accentColor)
            }

            HStack(spacing: 12) {
                LibraryStatCard(value: "\(store.recipes.count)", label: "Recettes", systemImage: "book.closed")
                LibraryStatCard(value: "\(store.favoriteCount)", label: "Favoris", systemImage: "star")
                LibraryStatCard(value: "\(store.recentRecipes.count)", label: "Recentes", systemImage: "clock")
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.98, green: 0.95, blue: 0.90),
                            Color(red: 0.95, green: 0.89, blue: 0.83)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.accentColor.opacity(0.08), lineWidth: 1)
        )
    }

    private var heroSubtitle: String {
        switch scope {
        case .all:
            return "Parcourez, filtrez et ouvrez rapidement chaque recette dans un espace de travail plus clair."
        case .favorites:
            return "Gardez vos recettes de reference a portee de main pour cuisiner ou exporter plus vite."
        case .category(let category):
            return "Explorez les recettes \(category.rawValue.lowercased()) avec une lecture plus nette et un flux de cuisine plus direct."
        }
    }
}

private struct LibraryStatCard: View {
    let value: String
    let label: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
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
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.72))
        )
    }
}

private struct LibraryScopeScroller: View {
    @EnvironmentObject private var store: RecipeStore
    let showsCategories: Bool

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                LibraryScopeChip(
                    title: "Toutes",
                    systemImage: "square.grid.2x2",
                    isSelected: store.selectedCollection == .all
                ) {
                    store.selectedCollection = .all
                }

                LibraryScopeChip(
                    title: "Favoris",
                    systemImage: "star.fill",
                    isSelected: store.selectedCollection == .favorites
                ) {
                    store.selectedCollection = .favorites
                }

                if showsCategories {
                    ForEach(Recipe.Category.allCases) { category in
                        LibraryScopeChip(
                            title: category.rawValue,
                            systemImage: "circle.fill",
                            tint: category.color,
                            trailingEmoji: category.icon,
                            isSelected: store.selectedCollection == .category(category)
                        ) {
                            store.selectedCollection = .category(category)
                        }
                    }
                }
            }
        }
    }
}

private struct LibraryScopeChip: View {
    let title: String
    let systemImage: String
    var tint: Color = .accentColor
    var trailingEmoji: String? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isSelected ? .white : tint)

                Text(title)
                    .font(.caption.weight(.semibold))

                if let trailingEmoji {
                    Text(trailingEmoji)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(isSelected ? tint : Color(UIColor.secondarySystemBackground))
            )
            .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}

private struct RecipeListItemView: View {
    let recipe: Recipe
    let isCompact: Bool

    var body: some View {
        HStack(spacing: 14) {
            thumbnail

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    Text(recipe.name)
                        .font(isCompact ? .headline : .body.weight(.semibold))
                        .lineLimit(2)

                    Spacer(minLength: 8)

                    if recipe.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                    }
                }

                HStack(spacing: 8) {
                    CategoryBadge(category: recipe.category)
                    Label(recipe.totalTime.timeString, systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Label("\(recipe.ingredients.count)", systemImage: "list.bullet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !isCompact {
                    Text(summaryLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(.vertical, isCompact ? 6 : 10)
        }
    }

    private var thumbnail: some View {
        Group {
            if let data = recipe.imageData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(recipe.category.color.opacity(0.18))
                    Text(recipe.category.icon)
                        .font(.title2)
                }
            }
        }
        .frame(width: isCompact ? 62 : 78, height: isCompact ? 62 : 84)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(recipe.category.color.opacity(0.12), lineWidth: 1)
        )
    }

    private var summaryLine: String {
        let ingredientNames = recipe.ingredients.prefix(3).map(\.name)
        if ingredientNames.isEmpty {
            return "Ajoutez des ingredients et des etapes pour completer la recette."
        }
        return ingredientNames.joined(separator: ", ")
    }
}

private struct LibraryEmptyStateView: View {
    @EnvironmentObject private var store: RecipeStore

    let scope: RecipeStore.RecipeCollection

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "book.closed.circle")
                .font(.system(size: 54))
                .foregroundStyle(.secondary)

            Text(emptyTitle)
                .font(.title3.weight(.bold))

            Text(emptyMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)

            if !store.searchText.isEmpty {
                Button("Effacer la recherche") {
                    store.searchText = ""
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
        .background(Color(.systemGroupedBackground))
    }

    private var emptyTitle: String {
        switch scope {
        case .all:
            return "Aucune recette visible"
        case .favorites:
            return "Aucun favori pour l'instant"
        case .category(let category):
            return "Aucune recette dans \(category.rawValue)"
        }
    }

    private var emptyMessage: String {
        if !store.searchText.isEmpty {
            return "Ajustez la recherche ou changez de section pour retrouver des recettes correspondantes."
        }

        switch scope {
        case .all:
            return "Ajoutez une nouvelle recette ou importez votre bibliotheque pour demarrer."
        case .favorites:
            return "Marquez des recettes avec l'etoile pour construire une selection rapide."
        case .category:
            return "Essayez une autre categorie ou ajoutez une recette dans cette famille."
        }
    }
}

private struct RecipeSelectionPlaceholderView: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: systemImage)
                .font(.system(size: 44))
                .foregroundStyle(Color.accentColor)

            Text(title)
                .font(.title3.weight(.bold))

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(28)
        .background(
            LinearGradient(
                colors: [
                    Color(.systemGroupedBackground),
                    Color(.secondarySystemGroupedBackground)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}

private struct GroceryToolbarLabel: View {
    let remainingItemCount: Int?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: remainingItemCount == nil ? "cart" : "cart.fill")

            if let remainingItemCount {
                Text("\(remainingItemCount)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, remainingItemCount >= 10 ? 5 : 4)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(remainingItemCount == 0 ? Color.green : Color.accentColor)
                    )
                    .offset(x: 10, y: -8)
            }
        }
    }
}

#if DEBUG
#Preview {
    ContentView()
        .environmentObject(RecipeStore())
}
#endif
