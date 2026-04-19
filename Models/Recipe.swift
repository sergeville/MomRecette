import Foundation
import SwiftUI

// MARK: - Recipe Model

struct Recipe: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var category: Category
    var servings: Int = 4
    var prepTime: Int = 15       // minutes
    var cookTime: Int = 30       // minutes
    var ingredients: [Ingredient] = []
    var steps: [String] = []
    var imageData: Data?
    var photoFilename: String?
    var generatedImagePrompt: String?
    var generatedImageMode: String?
    var notes: String = ""
    var createdAt: Date = Date()

    var totalTime: Int { prepTime + cookTime }
    var firstLetter: String { String(name.prefix(1)).uppercased() }

    // MARK: - Ingredient

    struct Ingredient: Identifiable, Codable, Hashable {
        var id: UUID = UUID()
        var quantity: String = ""
        var name: String

        var kind: IngredientKind {
            IngredientKind.classify(name: name)
        }
    }

    struct IngredientGroup: Identifiable, Hashable {
        let kind: IngredientKind
        let ingredients: [Ingredient]

        var id: IngredientKind { kind }
        var count: Int { ingredients.count }
        var sampleNames: String {
            ingredients
                .prefix(3)
                .map(\.name)
                .joined(separator: ", ")
        }
    }

    enum IngredientKind: String, CaseIterable, Hashable, Identifiable {
        case fruits
        case vegetables
        case meat
        case seafood
        case spices
        case dairy
        case grains
        case pantry
        case other

        var id: String { rawValue }

        var title: String {
            switch self {
            case .fruits: return "Fruits"
            case .vegetables: return "Légumes"
            case .meat: return "Viandes"
            case .seafood: return "Poissons"
            case .spices: return "Épices"
            case .dairy: return "Laitiers"
            case .grains: return "Céréales"
            case .pantry: return "Base"
            case .other: return "Autres"
            }
        }

        var icon: String {
            switch self {
            case .fruits: return "🍓"
            case .vegetables: return "🥕"
            case .meat: return "🥩"
            case .seafood: return "🦐"
            case .spices: return "🧂"
            case .dairy: return "🥛"
            case .grains: return "🌾"
            case .pantry: return "🫙"
            case .other: return "🍽️"
            }
        }

        var rank: Int {
            switch self {
            case .fruits: return 0
            case .vegetables: return 1
            case .meat: return 2
            case .seafood: return 3
            case .spices: return 4
            case .dairy: return 5
            case .grains: return 6
            case .pantry: return 7
            case .other: return 8
            }
        }

        fileprivate static func classify(name: String) -> IngredientKind {
            let normalized = name.foldedForMatching

            if normalized.containsAny([
                "fraise", "bleuet", "framboise", "mangue", "ananas", "pomme",
                "banane", "orange", "citron", "lime", "raisin", "poire"
            ]) {
                return .fruits
            }

            if normalized.containsAny([
                "oignon", "ail", "poivron", "champignon", "carotte", "brocoli",
                "chou", "laitue", "concombre", "epinard", "courgette", "celeri",
                "tomate", "citronnelle", "legumes", "echalote", "coriandre"
            ]) {
                return .vegetables
            }

            if normalized.containsAny([
                "boeuf", "bœuf", "porc", "poulet", "dinde", "veau", "agneau",
                "jambon", "bacon", "saucisse", "viande"
            ]) {
                return .meat
            }

            if normalized.containsAny([
                "crevette", "crevettes", "petoncle", "pétoncle", "poisson",
                "saumon", "thon", "morue", "fruits de mer"
            ]) {
                return .seafood
            }

            if normalized.containsAny([
                "sel", "poivre", "cannelle", "origan", "basilic", "paprika",
                "cumin", "cari", "curcuma", "vanille", "girofle", "epice",
                "épice", "sauce soja", "sauce de poisson", "pate de cari"
            ]) {
                return .spices
            }

            if normalized.containsAny([
                "lait", "beurre", "creme", "crème", "fromage", "gruyere",
                "gruyère", "yogourt", "yaourt"
            ]) {
                return .dairy
            }

            if normalized.containsAny([
                "farine", "gruau", "avoine", "riz", "vermicelle", "pates",
                "pâtes", "pain", "chapelure"
            ]) {
                return .grains
            }

            if normalized.containsAny([
                "sucre", "cassonade", "sirop", "huile", "bouillon", "tofu",
                "oeuf", "œuf", "abaisse", "poudre a pate", "poudre à pate",
                "pate de tomate", "pâte de tomate", "lait de coco"
            ]) {
                return .pantry
            }

            return .other
        }
    }

    // MARK: - Category

    enum Category: String, Codable, CaseIterable, Identifiable {
        case soupes        = "Soupes"
        case entrees       = "Entrées"
        case plats         = "Plats"
        case desserts      = "Desserts"
        case sauces        = "Sauces"
        case fondues       = "Fondues"
        case salades       = "Salades"
        case patisseries   = "Pâtisseries"
        case autres        = "Autres"

        var id: String { rawValue }

        var color: Color {
            switch self {
            case .soupes:      return Color(red: 0.80, green: 0.45, blue: 0.25)
            case .entrees:     return Color(red: 0.35, green: 0.65, blue: 0.45)
            case .plats:       return Color(red: 0.70, green: 0.25, blue: 0.25)
            case .desserts:    return Color(red: 0.85, green: 0.45, blue: 0.60)
            case .sauces:      return Color(red: 0.45, green: 0.55, blue: 0.80)
            case .fondues:     return Color(red: 0.60, green: 0.40, blue: 0.75)
            case .salades:     return Color(red: 0.35, green: 0.70, blue: 0.40)
            case .patisseries: return Color(red: 0.90, green: 0.65, blue: 0.25)
            case .autres:      return Color(red: 0.55, green: 0.55, blue: 0.55)
            }
        }

        var icon: String {
            switch self {
            case .soupes:      return "🍲"
            case .entrees:     return "🥗"
            case .plats:       return "🍽️"
            case .desserts:    return "🍰"
            case .sauces:      return "🫙"
            case .fondues:     return "🫕"
            case .salades:     return "🥬"
            case .patisseries: return "🥐"
            case .autres:      return "🍴"
            }
        }
    }
}

enum RecipeImageMode: String, CaseIterable, Codable, Identifiable {
    case recipeCard
    case dishPhoto

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recipeCard:
            return "Recipe Card"
        case .dishPhoto:
            return "Dish Photo"
        }
    }

    var shortDescription: String {
        switch self {
        case .recipeCard:
            return "Styled card with title, ingredients, and optional instructions."
        case .dishPhoto:
            return "Luxury plated dish photo with no ingredient list text."
        }
    }
}

extension Recipe {
    var ingredientGroups: [IngredientGroup] {
        let grouped = Dictionary(grouping: ingredients, by: \.kind)

        return grouped
            .map { IngredientGroup(kind: $0.key, ingredients: $0.value) }
            .sorted {
                if $0.count == $1.count {
                    return $0.kind.rank < $1.kind.rank
                }
                return $0.count > $1.count
            }
    }

    var photoLookupKeys: [String] {
        var keys: [String] = [
            id.uuidString.lowercased(),
            name.photoLookupKey
        ]

        if name.photoLookupKey.hasPrefix("the-") {
            keys.append(String(name.photoLookupKey.dropFirst(4)))
        }

        return Array(NSOrderedSet(array: keys)) as? [String] ?? keys
    }

    var ingredientCardLookupKeys: [String] {
        let keys = photoLookupKeys + photoLookupKeys.map { $0.replacingOccurrences(of: "-", with: "_") }
        return Array(NSOrderedSet(array: keys)) as? [String] ?? keys
    }

    var suggestedIngredientCardFilename: String {
        "\(name.photoLookupKey.replacingOccurrences(of: "-", with: "_")).png"
    }
}

extension Recipe.IngredientKind {
    static func kind(forIngredientNamed name: String) -> Self {
        classify(name: name)
    }

    static func icon(forIngredientNamed name: String) -> String {
        let normalized = name.foldedForMatching

        if normalized.containsAny(["amande", "noix", "noisette", "pacane", "pistache"]) {
            return "🌰"
        }
        if normalized.containsAny(["oignon", "echalote"]) {
            return "🧅"
        }
        if normalized.contains("ail") {
            return "🧄"
        }
        if normalized.containsAny(["tomate"]) {
            return "🍅"
        }
        if normalized.containsAny(["carotte"]) {
            return "🥕"
        }
        if normalized.containsAny(["brocoli"]) {
            return "🥦"
        }
        if normalized.containsAny(["citron", "lime"]) {
            return "🍋"
        }
        if normalized.containsAny(["pomme"]) {
            return "🍎"
        }
        if normalized.containsAny(["banane"]) {
            return "🍌"
        }
        if normalized.containsAny(["fraise", "framboise", "bleuet"]) {
            return "🍓"
        }
        if normalized.containsAny(["bacon"]) {
            return "🥓"
        }
        if normalized.containsAny(["boeuf", "bœuf", "steak"]) {
            return "🥩"
        }
        if normalized.containsAny(["porc", "jambon", "saucisse"]) {
            return "🍖"
        }
        if normalized.containsAny(["poulet", "dinde"]) {
            return "🍗"
        }
        if normalized.containsAny(["crevette", "crevettes"]) {
            return "🍤"
        }
        if normalized.containsAny(["poisson", "saumon", "thon", "morue", "petoncle", "pétoncle"]) {
            return "🐟"
        }
        if normalized.containsAny(["fromage", "gruyere", "gruyère"]) {
            return "🧀"
        }
        if normalized.containsAny(["beurre"]) {
            return "🧈"
        }
        if normalized.containsAny(["lait", "creme", "crème", "yogourt", "yaourt"]) {
            return "🥛"
        }
        if normalized.containsAny(["oeuf", "œuf"]) {
            return "🥚"
        }
        if normalized.containsAny(["farine", "gruau", "avoine", "riz", "vermicelle", "pates", "pâtes"]) {
            return "🌾"
        }
        if normalized.containsAny(["sucre", "cassonade", "sirop"]) {
            return "🍯"
        }
        if normalized.containsAny(["sel", "poivre", "cannelle", "origan", "basilic", "paprika", "cumin", "vanille"]) {
            return "🧂"
        }

        return classify(name: name).icon
    }
}

extension String {
    var foldedForMatching: String {
        folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    }

    var photoLookupKey: String {
        let folded = foldedForMatching.replacingOccurrences(of: "&", with: " and ")
        let pieces = folded
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return pieces.joined(separator: "-")
    }

    func containsAny(_ candidates: [String]) -> Bool {
        candidates.contains { contains($0) }
    }
}

// MARK: - Time Formatting

extension Int {
    var timeString: String {
        if self < 60 { return "\(self) min" }
        let h = self / 60
        let m = self % 60
        return m == 0 ? "\(h)h" : "\(h)h\(m)"
    }
}

// MARK: - Sample Data

extension Recipe {
    static let samples: [Recipe] = [
        Recipe(
            name: "Pouding Chômeur",
            category: .desserts,
            servings: 8,
            prepTime: 15,
            cookTime: 35,
            ingredients: [
                Ingredient(quantity: "1½ tasse", name: "farine"),
                Ingredient(quantity: "½ tasse", name: "beurre ramolli"),
                Ingredient(quantity: "1 tasse", name: "sucre"),
                Ingredient(quantity: "2", name: "œufs"),
                Ingredient(quantity: "1 tasse", name: "lait"),
                Ingredient(quantity: "2 c. à thé", name: "poudre à pâte"),
                Ingredient(quantity: "2 tasses", name: "cassonade"),
                Ingredient(quantity: "2 tasses", name: "crème 35%"),
                Ingredient(quantity: "½ tasse", name: "sirop d'érable")
            ],
            steps: [
                "Préchauffer le four à 350°F (175°C).",
                "Crémer le beurre avec le sucre. Ajouter les œufs un à un.",
                "Incorporer la farine tamisée avec la poudre à pâte en alternant avec le lait.",
                "Verser la pâte dans un plat beurré 9×13.",
                "Dans une casserole, chauffer la crème, la cassonade et le sirop d'érable jusqu'à dissolution.",
                "Verser doucement la sauce chaude sur la pâte sans mélanger.",
                "Cuire 35 minutes jusqu'à ce que le gâteau soit doré."
            ],
            notes: "Recette de grand-maman. La sauce doit être bien chaude pour couler sous la pâte."
        ),
        Recipe(
            name: "Crétons Quatre Générations",
            category: .entrees,
            servings: 12,
            prepTime: 20,
            cookTime: 180,
            ingredients: [
                Ingredient(quantity: "1 kg", name: "porc haché"),
                Ingredient(quantity: "1", name: "oignon haché fin"),
                Ingredient(quantity: "2 gousses", name: "ail émincé"),
                Ingredient(quantity: "1 tasse", name: "lait"),
                Ingredient(quantity: "1 c. à thé", name: "sel"),
                Ingredient(quantity: "½ c. à thé", name: "cannelle"),
                Ingredient(quantity: "½ c. à thé", name: "clou de girofle moulu"),
                Ingredient(quantity: "¼ c. à thé", name: "poivre")
            ],
            steps: [
                "Mélanger tous les ingrédients dans une casserole à fond épais.",
                "Cuire à feu doux pendant 3 heures en remuant régulièrement.",
                "Le liquide doit être complètement absorbé.",
                "Écraser à la fourchette pour obtenir une texture lisse.",
                "Verser dans des ramequins et réfrigérer jusqu'à prise."
            ],
            notes: "Recette transmise depuis 4 générations. Se conserve 2 semaines au frigo."
        ),
        Recipe(
            name: "Soupe Thaïlandaise",
            category: .soupes,
            servings: 4,
            prepTime: 20,
            cookTime: 25,
            ingredients: [
                Ingredient(quantity: "1 litre", name: "bouillon de poulet"),
                Ingredient(quantity: "400 ml", name: "lait de coco"),
                Ingredient(quantity: "2 c. à soupe", name: "pâte de cari rouge"),
                Ingredient(quantity: "300 g", name: "crevettes décortiquées"),
                Ingredient(quantity: "2", name: "tiges de citronnelle"),
                Ingredient(quantity: "3", name: "feuilles de lime kaffir"),
                Ingredient(quantity: "1 c. à soupe", name: "sauce de poisson"),
                Ingredient(quantity: "1 c. à soupe", name: "jus de lime"),
                Ingredient(quantity: "", name: "coriandre fraîche")
            ],
            steps: [
                "Porter le bouillon à ébullition avec la citronnelle écrasée et les feuilles de lime.",
                "Ajouter la pâte de cari et le lait de coco. Mélanger.",
                "Incorporer les crevettes et cuire 3-4 minutes.",
                "Assaisonner avec la sauce de poisson et le jus de lime.",
                "Servir garni de coriandre fraîche."
            ],
            notes: ""
        ),
        Recipe(
            name: "Tarte au Sucre",
            category: .desserts,
            servings: 8,
            prepTime: 20,
            cookTime: 40,
            ingredients: [
                Ingredient(quantity: "1", name: "abaisse de tarte"),
                Ingredient(quantity: "2 tasses", name: "cassonade"),
                Ingredient(quantity: "1 tasse", name: "crème 35%"),
                Ingredient(quantity: "2 c. à soupe", name: "farine"),
                Ingredient(quantity: "1 c. à thé", name: "vanille"),
                Ingredient(quantity: "2", name: "œufs")
            ],
            steps: [
                "Préchauffer le four à 375°F.",
                "Foncer un moule à tarte avec l'abaisse.",
                "Battre les œufs avec la cassonade, la crème, la farine et la vanille.",
                "Verser sur l'abaisse.",
                "Cuire 40 minutes jusqu'à ce que la garniture soit prise."
            ],
            notes: ""
        ),
        Recipe(
            name: "Sauce à Spaghetti de Sergio",
            category: .sauces,
            servings: 8,
            prepTime: 30,
            cookTime: 240,
            ingredients: [
                Ingredient(quantity: "1 kg", name: "bœuf haché"),
                Ingredient(quantity: "500 g", name: "porc haché"),
                Ingredient(quantity: "2 boîtes", name: "tomates en dés (796 ml)"),
                Ingredient(quantity: "1 boîte", name: "pâte de tomate (156 ml)"),
                Ingredient(quantity: "2", name: "oignons hachés"),
                Ingredient(quantity: "4 gousses", name: "ail"),
                Ingredient(quantity: "2", name: "poivrons verts"),
                Ingredient(quantity: "1 tasse", name: "champignons tranchés"),
                Ingredient(quantity: "2 c. à thé", name: "origan"),
                Ingredient(quantity: "1 c. à thé", name: "basilic")
            ],
            steps: [
                "Faire revenir les oignons et l'ail dans l'huile d'olive.",
                "Ajouter les viandes et brunir complètement. Égoutter le gras.",
                "Incorporer les poivrons et champignons. Cuire 5 minutes.",
                "Ajouter tomates, pâte de tomate, épices. Saler et poivrer.",
                "Mijoter à feu très doux pendant 4 heures en remuant occasionnellement.",
                "Rectifier l'assaisonnement avant de servir."
            ],
            notes: "La longue cuisson est le secret. Meilleure réchauffée le lendemain."
        ),
        Recipe(
            name: "Fondue Thaïe",
            category: .fondues,
            servings: 6,
            prepTime: 30,
            cookTime: 20,
            ingredients: [
                Ingredient(quantity: "1.5 litre", name: "bouillon de poulet"),
                Ingredient(quantity: "400 ml", name: "lait de coco"),
                Ingredient(quantity: "3 c. à soupe", name: "pâte de cari"),
                Ingredient(quantity: "2", name: "tiges de citronnelle"),
                Ingredient(quantity: "500 g", name: "bœuf en fines tranches"),
                Ingredient(quantity: "500 g", name: "crevettes"),
                Ingredient(quantity: "300 g", name: "tofu ferme en cubes"),
                Ingredient(quantity: "", name: "vermicelles de riz"),
                Ingredient(quantity: "", name: "légumes variés")
            ],
            steps: [
                "Préparer le bouillon: mélanger bouillon, lait de coco, pâte de cari et citronnelle.",
                "Porter à ébullition et maintenir à frémissement dans le caquelon.",
                "Disposer viandes, fruits de mer, tofu et légumes sur la table.",
                "Chaque convive fait cuire ses ingrédients dans le bouillon.",
                "Servir avec les sauces d'accompagnement."
            ],
            notes: "Servir avec sauce arachide, sauce de poisson, sambal oelek."
        ),
        Recipe(
            name: "Croquilles St-Jacques",
            category: .entrees,
            servings: 4,
            prepTime: 25,
            cookTime: 20,
            ingredients: [
                Ingredient(quantity: "500 g", name: "pétoncles"),
                Ingredient(quantity: "250 g", name: "crevettes"),
                Ingredient(quantity: "3 c. à soupe", name: "beurre"),
                Ingredient(quantity: "2 échalotes", name: "hachées fin"),
                Ingredient(quantity: "1 tasse", name: "vin blanc"),
                Ingredient(quantity: "1 tasse", name: "crème 35%"),
                Ingredient(quantity: "¼ tasse", name: "gruyère râpé"),
                Ingredient(quantity: "1 c. à soupe", name: "farine")
            ],
            steps: [
                "Faire revenir les échalotes dans le beurre.",
                "Ajouter les fruits de mer et cuire 2-3 minutes. Réserver.",
                "Déglacer avec le vin blanc. Réduire de moitié.",
                "Incorporer la crème et la farine. Épaissir à feu doux.",
                "Remettre les fruits de mer dans la sauce.",
                "Verser dans des coquilles beurrées. Parsemer de gruyère.",
                "Gratiner sous le gril 3-4 minutes."
            ],
            notes: ""
        ),
        Recipe(
            name: "Poulet aux Pommes et à l'Érable",
            category: .plats,
            servings: 4,
            prepTime: 15,
            cookTime: 45,
            ingredients: [
                Ingredient(quantity: "4", name: "poitrines de poulet"),
                Ingredient(quantity: "3", name: "pommes Cortland pelées"),
                Ingredient(quantity: "¼ tasse", name: "sirop d'érable"),
                Ingredient(quantity: "¼ tasse", name: "cidre de pomme"),
                Ingredient(quantity: "2 c. à soupe", name: "beurre"),
                Ingredient(quantity: "1 c. à thé", name: "cannelle"),
                Ingredient(quantity: "", name: "sel et poivre")
            ],
            steps: [
                "Saisir les poitrines dans le beurre. Saler et poivrer.",
                "Ajouter les pommes en quartiers autour du poulet.",
                "Mélanger le sirop d'érable, le cidre et la cannelle. Verser.",
                "Cuire au four à 375°F pendant 40 minutes.",
                "Arroser toutes les 10 minutes."
            ],
            notes: "Un classique québécois automnal."
        )
    ]
}
