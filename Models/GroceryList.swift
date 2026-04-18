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

        var priceMultiplier: Decimal {
            switch self {
            case .store: return 1.00
            case .iga: return 1.08
            case .stemberg: return 1.05
            case .metro: return 1.07
            case .maxi: return 0.93
            case .costco: return 0.88
            }
        }
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

    struct ReminderPayload: Equatable {
        var title: String
        var notes: String
        var isCompleted: Bool
    }

    private enum PriceMode {
        case package
        case each
        case dozen
        case kilogram
        case litre
    }

    private struct PriceBookEntry {
        let keywords: [String]
        let basePrice: Decimal
        let mode: PriceMode
    }

    private static let specificPriceBook: [PriceBookEntry] = [
        .init(keywords: ["pomme"], basePrice: 0.99, mode: .each),
        .init(keywords: ["banane"], basePrice: 0.39, mode: .each),
        .init(keywords: ["citron", "lime"], basePrice: 0.79, mode: .each),
        .init(keywords: ["oignon", "echalote"], basePrice: 0.89, mode: .each),
        .init(keywords: ["ail"], basePrice: 1.29, mode: .package),
        .init(keywords: ["tomate"], basePrice: 1.29, mode: .each),
        .init(keywords: ["carotte"], basePrice: 0.35, mode: .each),
        .init(keywords: ["poivron"], basePrice: 1.99, mode: .each),
        .init(keywords: ["champignon"], basePrice: 3.49, mode: .package),
        .init(keywords: ["beurre"], basePrice: 6.99, mode: .package),
        .init(keywords: ["lait"], basePrice: 2.99, mode: .litre),
        .init(keywords: ["creme", "crème"], basePrice: 4.79, mode: .litre),
        .init(keywords: ["fromage", "gruyere", "gruyère"], basePrice: 7.99, mode: .package),
        .init(keywords: ["yogourt", "yaourt"], basePrice: 5.49, mode: .package),
        .init(keywords: ["oeuf", "œuf"], basePrice: 4.99, mode: .dozen),
        .init(keywords: ["farine"], basePrice: 3.79, mode: .package),
        .init(keywords: ["sucre", "cassonade"], basePrice: 3.99, mode: .package),
        .init(keywords: ["riz"], basePrice: 5.99, mode: .package),
        .init(keywords: ["huile"], basePrice: 8.99, mode: .package),
        .init(keywords: ["bouillon"], basePrice: 3.49, mode: .package),
        .init(keywords: ["lait de coco"], basePrice: 2.99, mode: .package),
        .init(keywords: ["boeuf", "bœuf", "steak"], basePrice: 19.99, mode: .kilogram),
        .init(keywords: ["porc", "jambon", "saucisse"], basePrice: 11.99, mode: .kilogram),
        .init(keywords: ["poulet", "dinde"], basePrice: 13.99, mode: .kilogram),
        .init(keywords: ["crevette", "crevettes"], basePrice: 22.99, mode: .kilogram),
        .init(keywords: ["saumon", "thon", "morue", "poisson", "petoncle", "pétoncle"], basePrice: 27.99, mode: .kilogram)
    ]

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
            "Total estime: \(formattedCurrency(estimatedTotal(for: store)))",
            ""
        ]

        let lines = items.map { item in
            let status = item.isChecked ? "[x]" : "[ ]"
            return "\(status) \(item.displayName) - \(formattedCurrency(item.estimatedPrice(for: store)))"
        }

        return (header + lines).joined(separator: "\n")
    }

    func reminderListName(for store: ExportStore) -> String {
        "MomRecette - \(store.rawValue)"
    }

    func reminderMetadataPrefix(for store: ExportStore) -> String {
        "MomRecette|recipeID:\(recipeID.uuidString)|store:\(store.rawValue)"
    }

    func reminderPayloads(for store: ExportStore) -> [ReminderPayload] {
        let metadataPrefix = reminderMetadataPrefix(for: store)

        return items.map { item in
            ReminderPayload(
                title: reminderTitle(for: item, store: store),
                notes: [
                    "Recette: \(recipeName)",
                    "Magasin: \(store.rawValue)",
                    "Prix estime: \(formattedCurrency(item.estimatedPrice(for: store)))",
                    metadataPrefix
                ].joined(separator: "\n"),
                isCompleted: item.isChecked
            )
        }
    }

    func estimatedTotal(for store: ExportStore) -> Decimal {
        items.reduce(into: Decimal.zero) { total, item in
            total += item.estimatedPrice(for: store)
        }
    }

    func estimatedTotalText(for store: ExportStore) -> String {
        formattedCurrency(estimatedTotal(for: store))
    }

    private func reminderTitle(for item: Item, store: ExportStore) -> String {
        "\(item.displayName) · \(formattedCurrency(item.estimatedPrice(for: store)))"
    }

    private func formattedCurrency(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "CAD"
        formatter.locale = Locale(identifier: "fr_CA")
        return formatter.string(from: amount as NSNumber) ?? "\(amount) $"
    }
}

extension GroceryList.Item {
    var displayName: String {
        let trimmedQuantity = quantity.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedQuantity.isEmpty {
            return name
        }
        return "\(trimmedQuantity) \(name)"
    }

    func estimatedPrice(for store: GroceryList.ExportStore) -> Decimal {
        let normalizedName = name.foldedForMatching
        let entry = GroceryList.specificPriceBook.first { priceBookEntry in
            normalizedName.containsAny(priceBookEntry.keywords)
        } ?? defaultEntry

        return roundedPrice(entry.basePrice * store.priceMultiplier * quantityFactor(for: entry.mode))
    }

    private var defaultEntry: GroceryList.PriceBookEntry {
        let kind = Recipe.IngredientKind.kind(forIngredientNamed: name)
        switch kind {
        case .fruits: return .init(keywords: [], basePrice: 0.99, mode: .each)
        case .vegetables: return .init(keywords: [], basePrice: 0.89, mode: .each)
        case .meat: return .init(keywords: [], basePrice: 15.99, mode: .kilogram)
        case .seafood: return .init(keywords: [], basePrice: 21.99, mode: .kilogram)
        case .spices: return .init(keywords: [], basePrice: 3.99, mode: .package)
        case .dairy: return .init(keywords: [], basePrice: 5.49, mode: .package)
        case .grains: return .init(keywords: [], basePrice: 4.29, mode: .package)
        case .pantry: return .init(keywords: [], basePrice: 4.49, mode: .package)
        case .other: return .init(keywords: [], basePrice: 4.99, mode: .package)
        }
    }

    private func quantityFactor(for mode: GroceryList.PriceMode) -> Decimal {
        switch mode {
        case .package:
            return 1
        case .each:
            return max(parsedLeadingAmount ?? 1, 1)
        case .dozen:
            return max((parsedLeadingAmount ?? 1) / 12, 0.25)
        case .kilogram:
            return max(parsedWeightInKilograms ?? 0.5, 0.25)
        case .litre:
            return max(parsedVolumeInLitres ?? 1, 0.25)
        }
    }

    private var parsedLeadingAmount: Decimal? {
        let normalized = quantity
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: "½", with: " 1/2")
            .replacingOccurrences(of: "¼", with: " 1/4")
            .replacingOccurrences(of: "¾", with: " 3/4")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let firstToken = normalized.split(separator: " ").first.map(String.init) ?? normalized
        return decimal(from: firstToken)
    }

    private var parsedWeightInKilograms: Decimal? {
        let normalized = quantity.foldedForMatching
        guard let amount = parsedLeadingAmount else { return nil }

        if normalized.contains("kg") || normalized.contains("kilo") {
            return amount
        }
        if normalized.contains("g ") || normalized.hasSuffix("g") {
            return amount / 1000
        }

        return nil
    }

    private var parsedVolumeInLitres: Decimal? {
        let normalized = quantity.foldedForMatching
        guard let amount = parsedLeadingAmount else { return nil }

        if normalized.contains("litre") || normalized.contains("l ") || normalized.hasSuffix("l") {
            return amount
        }
        if normalized.contains("ml") {
            return amount / 1000
        }
        if normalized.contains("tasse") {
            return amount * 0.25
        }
        if normalized.contains("c. a table") || normalized.contains("c a table") {
            return amount * 0.015
        }
        if normalized.contains("c. a the") || normalized.contains("c a the") {
            return amount * 0.005
        }

        return nil
    }

    private func decimal(from token: String) -> Decimal? {
        if token.contains("/") {
            let parts = token.split(separator: "/")
            guard parts.count == 2,
                  let numerator = Decimal(string: String(parts[0])),
                  let denominator = Decimal(string: String(parts[1])),
                  denominator != 0 else { return nil }
            return numerator / denominator
        }

        return Decimal(string: token)
    }

    private func roundedPrice(_ value: Decimal) -> Decimal {
        var value = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 2, .bankers)
        return rounded
    }
}
