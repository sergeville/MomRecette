import Foundation
import SwiftUI
import Combine

@MainActor
class RecipeStore: ObservableObject {

    @Published var recipes: [Recipe] = []
    @Published var searchText: String = ""
    @Published var selectedCategory: Recipe.Category? = nil

    private let saveURL: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("momrecette.json")
    }()

    init() {
        load()
        if recipes.isEmpty {
            loadBundle()
        }
        if recipes.isEmpty {
            recipes = Recipe.samples
            save()
        }
    }

    // MARK: - Filtered

    var filteredRecipes: [Recipe] {
        var list = recipes
        if let cat = selectedCategory {
            list = list.filter { $0.category == cat }
        }
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            list = list.filter {
                $0.name.lowercased().contains(q) ||
                $0.category.rawValue.lowercased().contains(q) ||
                $0.ingredients.contains { $0.name.lowercased().contains(q) }
            }
        }
        return list.sorted { $0.name < $1.name }
    }

    var groupedByLetter: [(String, [Recipe])] {
        let sorted = filteredRecipes
        let grouped = Dictionary(grouping: sorted) { $0.firstLetter }
        return grouped.sorted { $0.key < $1.key }
    }

    // MARK: - CRUD

    func add(_ recipe: Recipe) {
        recipes.append(recipe)
        save()
    }

    func update(_ recipe: Recipe) {
        if let idx = recipes.firstIndex(where: { $0.id == recipe.id }) {
            recipes[idx] = recipe
            save()
        }
    }

    func delete(_ recipe: Recipe) {
        recipes.removeAll { $0.id == recipe.id }
        save()
    }

    func delete(at offsets: IndexSet, in list: [Recipe]) {
        let ids = offsets.map { list[$0].id }
        recipes.removeAll { ids.contains($0.id) }
        save()
    }

    // MARK: - Persistence

    func save() {
        do {
            let data = try JSONEncoder().encode(recipes)
            try data.write(to: saveURL, options: .atomicWrite)
        } catch {
            print("RecipeStore save error: \(error)")
        }
    }

    func load() {
        guard FileManager.default.fileExists(atPath: saveURL.path) else { return }
        do {
            let data = try Data(contentsOf: saveURL)
            recipes = try JSONDecoder().decode([Recipe].self, from: data)
        } catch {
            print("RecipeStore load error: \(error)")
        }
    }

    private func loadBundle() {
        guard let url = Bundle.main.url(forResource: "momrecette_bundle", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let loaded = try? decoder.decode([LenientRecipe].self, from: data) {
            recipes = loaded.map { $0.toRecipe() }
            save()
            print("RecipeStore: seeded \(recipes.count) recipes from bundle")
        }
    }
}
