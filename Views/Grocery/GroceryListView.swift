import SwiftUI

struct GroceryListView: View {
    @EnvironmentObject var store: RecipeStore
    @Environment(\.dismiss) var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedStore: GroceryList.ExportStore = .store

    private var groceryList: GroceryList? {
        store.currentGroceryList
    }

    private var gridColumns: [GridItem] {
        let minimumWidth: CGFloat = horizontalSizeClass == .regular ? 170 : 145
        return [GridItem(.adaptive(minimum: minimumWidth), spacing: 12)]
    }

    var body: some View {
        NavigationStack {
            Group {
                if let groceryList {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            groceryHeader(groceryList)

                            ingredientFamilyStrip(groceryList)

                            storeSelectionStrip

                            VStack(alignment: .leading, spacing: 12) {
                                Text("Articles")
                                    .font(.headline)

                                LazyVGrid(columns: gridColumns, spacing: 12) {
                                    ForEach(groceryList.items) { item in
                                        groceryItemCard(item)
                                    }
                                }
                            }
                        }
                        .padding(20)
                    }
                    .background(Color(.systemGroupedBackground))
                } else {
                    VStack(spacing: 14) {
                        Image(systemName: "cart")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text("Aucune liste active")
                            .font(.headline)
                        Text("Créez une liste d'épicerie depuis une recette pour commencer.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(24)
                }
            }
            .navigationTitle("Liste d'épicerie")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Fermer") { dismiss() }
                }
                if groceryList != nil {
                    ToolbarItemGroup(placement: .navigationBarTrailing) {
                        if let groceryList {
                            ShareLink(
                                item: groceryList.exportText(for: selectedStore),
                                subject: Text("Liste d'epicerie - \(selectedStore.rawValue)")
                            ) {
                                Label("Exporter", systemImage: "square.and.arrow.up")
                            }
                            .accessibilityLabel("Exporter la liste d'epicerie")
                            .help("Partager la liste d'epicerie")
                        }

                        Button("Effacer") {
                            store.clearGroceryList()
                            dismiss()
                        }
                    }
                }
            }
        }
    }

    private var storeSelectionStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Exporter pour")
                .font(.headline)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(GroceryList.ExportStore.allCases) { exportStore in
                        Button {
                            selectedStore = exportStore
                        } label: {
                            Text(exportStore.rawValue)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule()
                                        .fill(selectedStore == exportStore ? Color.accentColor : Color(.secondarySystemBackground))
                                )
                                .foregroundStyle(selectedStore == exportStore ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func groceryHeader(_ groceryList: GroceryList) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(groceryList.recipeName)
                .font(.title3.weight(.bold))

            HStack(spacing: 12) {
                groceryStat("\(groceryList.items.count)", label: "articles")
                groceryStat("\(groceryList.remainingItemCount)", label: "restants")
                groceryStat("\(groceryList.items.filter(\.isChecked).count)", label: "pris")
            }

            Text("Le partage inclut les quantites et le magasin selectionne.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    @ViewBuilder
    private func ingredientFamilyStrip(_ groceryList: GroceryList) -> some View {
        let families = Dictionary(grouping: groceryList.items) { item in
            Recipe.IngredientKind.kind(forIngredientNamed: item.name)
        }
            .map { (kind: $0.key, count: $0.value.count) }
            .sorted { lhs, rhs in
                if lhs.count == rhs.count {
                    return lhs.kind.rank < rhs.kind.rank
                }
                return lhs.count > rhs.count
            }

        if !families.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(families.prefix(5)), id: \.kind) { family in
                        HStack(spacing: 8) {
                            Text(family.kind.icon)
                            Text(family.kind.title)
                                .font(.caption.weight(.semibold))
                            Text("\(family.count)")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(Color(.secondarySystemBackground))
                        )
                    }
                }
            }
        }
    }

    private func groceryItemCard(_ item: GroceryList.Item) -> some View {
        let kind = Recipe.IngredientKind.kind(forIngredientNamed: item.name)

        return Button {
            store.toggleGroceryItem(id: item.id)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    Text(Recipe.IngredientKind.icon(forIngredientNamed: item.name))
                        .font(.system(size: 34))
                        .frame(width: 58, height: 58)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(kindTint(kind).opacity(0.18))
                        )

                    Spacer()

                    Image(systemName: item.isChecked ? "checkmark.circle.fill" : "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(item.isChecked ? .green : kindTint(kind))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(item.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(item.isChecked ? .secondary : .primary)
                        .strikethrough(item.isChecked, color: .secondary)
                        .lineLimit(3)

                    if !item.quantity.isEmpty {
                        Text(item.quantity)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)

                Text(item.isChecked ? "Déjà pris" : "À acheter")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(item.isChecked ? .green : kindTint(kind))
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 180, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 22)
                    .fill(Color(.systemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22)
                    .stroke(item.isChecked ? Color.green.opacity(0.25) : kindTint(kind).opacity(0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func groceryStat(_ value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.headline)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func kindTint(_ kind: Recipe.IngredientKind) -> Color {
        switch kind {
        case .fruits: return .orange
        case .vegetables: return .green
        case .meat: return .red
        case .seafood: return .blue
        case .spices: return .brown
        case .dairy: return .mint
        case .grains: return .yellow
        case .pantry: return .indigo
        case .other: return .gray
        }
    }
}

#Preview {
    GroceryListView()
        .environmentObject(RecipeStore())
}
