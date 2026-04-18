import Foundation

struct GroceryList: Codable, Equatable {
    enum ExportStore: String, CaseIterable, Identifiable {
        case store = "Magasin"
        case iga = "IGA"
        case stemberg = "Stemberg"
        case metro = "Metro"
        case maxi = "Maxi"
        case costco = "Costco"

        var id: String { rawValue }
    }

    var recipeID: UUID
    var recipeName: String
    var createdAt: Date = Date()
    var items: [Item]

    struct Item: Identifiable, Codable, Equatable {
        var id: UUID
        var quantity: String
        var name: String
        var isChecked: Bool = false
    }

    init(recipe: Recipe) {
        recipeID = recipe.id
        recipeName = recipe.name
        items = recipe.ingredients
            .filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { ingredient in
                Item(
                    id: ingredient.id,
                    quantity: ingredient.quantity,
                    name: ingredient.name
                )
            }
    }

    var remainingItemCount: Int {
        items.filter { !$0.isChecked }.count
    }

    func exportText(for store: ExportStore) -> String {
        let header = [
            "Liste d'epicerie MomRecette",
            "Magasin: \(store.rawValue)",
            "Recette: \(recipeName)",
            ""
        ]

        let lines = items.map { item in
            let status = item.isChecked ? "[x]" : "[ ]"
            let quantity = item.quantity.trimmingCharacters(in: .whitespacesAndNewlines)
            if quantity.isEmpty {
                return "\(status) \(item.name)"
            }
            return "\(status) \(quantity) \(item.name)"
        }

        return (header + lines).joined(separator: "\n")
    }
}
