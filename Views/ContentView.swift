import SwiftUI

// MARK: - Content View (Root)

struct ContentView: View {
    @EnvironmentObject var store: RecipeStore
    @State private var showAdd = false
    @State private var showImport = false
    @State private var showSearch = false
    @State private var showGroceryList = false
    @State private var splitSelectedRecipe: Recipe? = nil

    // iPad/Mac: sidebar-based layout
    @Environment(\.horizontalSizeClass) var hSizeClass

    private var remainingGroceryItemCount: Int? {
        guard let currentGroceryList = store.currentGroceryList else { return nil }
        return currentGroceryList.remainingItemCount
    }

    private var groceryAccessibilityLabel: String {
        if let remainingGroceryItemCount {
            return "Liste d'épicerie, \(remainingGroceryItemCount) article\(remainingGroceryItemCount > 1 ? "s" : "") restant\(remainingGroceryItemCount > 1 ? "s" : "")"
        }

        return "Liste d'épicerie"
    }

    var body: some View {
        Group {
            if hSizeClass == .regular {
                splitLayout
            } else {
                deckLayout
            }
        }
        .sheet(isPresented: $showGroceryList) {
            GroceryListView()
        }
    }

    // MARK: - iPhone Layout (Rolodex Deck)

    private var deckLayout: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar
                if showSearch {
                    SearchBar(text: $store.searchText)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                // Category filter
                CategoryFilterBar()

                Divider()

                // Deck
                RolodexDeckView()
                    .padding(.top, 16)

                Spacer()
            }
            .navigationTitle("MomRecette 🍽️")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        withAnimation {
                            showSearch.toggle()
                            if !showSearch { store.searchText = "" }
                        }
                    } label: {
                        Image(systemName: showSearch ? "xmark.circle.fill" : "magnifyingglass")
                    }

                    groceryToolbarButton

                    Menu {
                        Button { showAdd = true } label: {
                            Label("Nouvelle recette", systemImage: "plus")
                        }
                        Button { showImport = true } label: {
                            Label("Importer JSON", systemImage: "square.and.arrow.down")
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                    }
                }
            }
            .sheet(isPresented: $showAdd) {
                AddEditRecipeView()
            }
            .sheet(isPresented: $showImport) {
                ImportView()
            }
        }
    }

    // MARK: - iPad / Mac Layout (NavigationSplitView)

    private var splitLayout: some View {
        NavigationSplitView {
            SplitSidebarView()
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        groceryToolbarButton
                        Button { showAdd = true } label: { Image(systemName: "plus") }
                        Button { showImport = true } label: { Image(systemName: "square.and.arrow.down") }
                    }
                }
        } content: {
            RecipeListColumn(selectedRecipe: $splitSelectedRecipe)
        } detail: {
            if let recipe = splitSelectedRecipe {
                RecipeDetailView(recipe: recipe)
            } else {
                Text("Sélectionnez une recette").foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $showAdd) { AddEditRecipeView() }
        .sheet(isPresented: $showImport) { ImportView() }
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
}

// MARK: - Split Sidebar (extracted to help compiler)

private struct SplitSidebarView: View {
    @EnvironmentObject var store: RecipeStore

    var body: some View {
        VStack(spacing: 0) {
            SearchBar(text: $store.searchText)
                .padding(.horizontal)
                .padding(.vertical, 8)
            List {
                Section("Catégories") {
                    allCategoriesButton
                    ForEach(Recipe.Category.allCases) { cat in
                        categoryButton(cat)
                    }
                }
            }
            .listStyle(.sidebar)
        }
        .navigationTitle("MomRecette")
    }

    private var allCategoriesButton: some View {
        Button { store.selectedCategory = nil } label: {
            Label("Toutes", systemImage: "square.grid.2x2")
                .foregroundStyle(store.selectedCategory == nil ? Color.accentColor : Color.primary)
        }
    }

    private func categoryButton(_ cat: Recipe.Category) -> some View {
        Button { store.selectedCategory = (store.selectedCategory == cat) ? nil : cat } label: {
            HStack {
                Text(cat.icon + " " + cat.rawValue)
                    .foregroundStyle(store.selectedCategory == cat ? Color.accentColor : Color.primary)
                Spacer()
                Text("\(store.recipes.filter { $0.category == cat }.count)")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Category Filter Bar (iPhone)

private struct CategoryFilterBar: View {
    @EnvironmentObject var store: RecipeStore

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                FilterChip(
                    label: "Toutes",
                    isSelected: store.selectedCategory == nil
                ) { store.selectedCategory = nil }

                ForEach(Recipe.Category.allCases) { cat in
                    FilterChip(
                        label: cat.icon + " " + cat.rawValue,
                        isSelected: store.selectedCategory == cat
                    ) {
                        store.selectedCategory = (store.selectedCategory == cat) ? nil : cat
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }
}

private struct FilterChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor : Color(UIColor.secondarySystemBackground))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(Capsule())
        }
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

// MARK: - Recipe List Column (iPad/Mac)

struct RecipeListColumn: View {
    @EnvironmentObject var store: RecipeStore
    @Binding var selectedRecipe: Recipe?

    var body: some View {
        List(store.filteredRecipes, selection: $selectedRecipe) { recipe in
            RecipeRowView(recipe: recipe)
                .tag(recipe)
        }
        .navigationTitle("Recettes (\(store.filteredRecipes.count))")
    }
}

// MARK: - Recipe Row

struct RecipeRowView: View {
    let recipe: Recipe

    var body: some View {
        HStack(spacing: 14) {
            // Thumbnail
            Group {
                if let data = recipe.imageData, let ui = UIImage(data: data) {
                    Image(uiImage: ui)
                        .resizable()
                        .scaledToFill()
                } else {
                    Rectangle()
                        .fill(recipe.category.color.opacity(0.3))
                        .overlay { Text(recipe.category.icon).font(.title3) }
                }
            }
            .frame(width: 54, height: 54)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                Text(recipe.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                HStack(spacing: 8) {
                    CategoryBadge(category: recipe.category)
                    Text(recipe.totalTime.timeString)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Search Bar

struct SearchBar: View {
    @Binding var text: String

    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Rechercher...", text: $text)
                .autocorrectionDisabled()
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(UIColor.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#if DEBUG
#Preview {
    ContentView()
        .environmentObject(RecipeStore())
}
#endif
