import Foundation
import CoreData

struct RecipeCoreDataRepository {
    private let persistentContainer: RecipePersistentContainer
    private let importer: RecipeCoreDataImporter

    init(
        persistentContainer: RecipePersistentContainer,
        livePhotoDirectoryURL: URL,
        generatedImageDirectoryURL: URL
    ) {
        self.persistentContainer = persistentContainer
        self.importer = RecipeCoreDataImporter(
            persistentContainer: persistentContainer,
            livePhotoDirectoryURL: livePhotoDirectoryURL,
            generatedImageDirectoryURL: generatedImageDirectoryURL
        )
    }

    func recipeCount() throws -> Int {
        try persistentContainer.viewContext.count(
            for: NSFetchRequest<NSFetchRequestResult>(entityName: RecipePersistentContainer.EntityName.recipe)
        )
    }

    func isEmpty() throws -> Bool {
        try recipeCount() == 0
    }

    func loadRecipes() throws -> [Recipe] {
        let request = NSFetchRequest<NSManagedObject>(entityName: RecipePersistentContainer.EntityName.recipe)
        request.sortDescriptors = [
            NSSortDescriptor(key: "name", ascending: true, selector: #selector(NSString.localizedCaseInsensitiveCompare(_:)))
        ]

        return try persistentContainer.viewContext.fetch(request).compactMap(recipe(from:))
    }

    @discardableResult
    func save(recipes: [Recipe]) throws -> RecipeCoreDataImportReport {
        try importer.importLibrary(recipes: recipes, deletingMissingRecipes: true)
    }

    private func recipe(from object: NSManagedObject) -> Recipe? {
        guard let id = object.value(forKey: "id") as? UUID,
              let name = object.value(forKey: "name") as? String,
              let categoryRawValue = object.value(forKey: "categoryRawValue") as? String else {
            return nil
        }

        let ingredients = (object.value(forKey: "ingredients") as? NSOrderedSet)?
            .compactMap { $0 as? NSManagedObject }
            .sorted { lhs, rhs in
                (lhs.value(forKey: "position") as? Int64 ?? 0) < (rhs.value(forKey: "position") as? Int64 ?? 0)
            }
            .compactMap(ingredient(from:)) ?? []

        let steps = (object.value(forKey: "steps") as? NSOrderedSet)?
            .compactMap { $0 as? NSManagedObject }
            .sorted { lhs, rhs in
                (lhs.value(forKey: "position") as? Int64 ?? 0) < (rhs.value(forKey: "position") as? Int64 ?? 0)
            }
            .compactMap { $0.value(forKey: "text") as? String } ?? []

        let dishPhotoAsset = primaryImageAsset(role: "dishPhoto", for: object)

        var recipe = Recipe(
            id: id,
            name: name,
            category: Recipe.Category(rawValue: categoryRawValue) ?? .autres,
            servings: Int(object.value(forKey: "servings") as? Int64 ?? 4),
            caloriesPerServing: (object.value(forKey: "caloriesPerServing") as? Int64).map(Int.init),
            prepTime: Int(object.value(forKey: "prepTime") as? Int64 ?? 15),
            cookTime: Int(object.value(forKey: "cookTime") as? Int64 ?? 30),
            ingredients: ingredients,
            steps: steps,
            imageData: dishPhotoAsset?.value(forKey: "imageData") as? Data,
            photoFilename: object.value(forKey: "photoFilename") as? String,
            generatedImagePrompt: object.value(forKey: "generatedImagePrompt") as? String,
            generatedImageMode: object.value(forKey: "generatedImageMode") as? String,
            recipeCardFilename: object.value(forKey: "recipeCardFilename") as? String,
            generatedRecipeCardPrompt: object.value(forKey: "generatedRecipeCardPrompt") as? String,
            isFavorite: object.value(forKey: "isFavorite") as? Bool ?? false,
            notes: object.value(forKey: "notes") as? String ?? "",
            createdAt: object.value(forKey: "createdAt") as? Date ?? Date(),
            updatedAt: object.value(forKey: "updatedAt") as? Date ?? Date(),
            lastModifiedByDeviceID: object.value(forKey: "lastModifiedByDeviceID") as? String
        )

        if recipe.photoFilename == nil,
           let dishFilename = dishPhotoAsset?.value(forKey: "filename") as? String,
           dishFilename.isEmpty == false,
           (object.value(forKey: "bundlePhotoKey") as? String) == nil {
            recipe.photoFilename = dishFilename
        }

        return recipe
    }

    private func ingredient(from object: NSManagedObject) -> Recipe.Ingredient? {
        guard let id = object.value(forKey: "id") as? UUID,
              let name = object.value(forKey: "name") as? String else {
            return nil
        }

        return Recipe.Ingredient(
            id: id,
            quantity: object.value(forKey: "quantity") as? String ?? "",
            name: name
        )
    }

    private func primaryImageAsset(role: String, for recipeObject: NSManagedObject) -> NSManagedObject? {
        let assets = (recipeObject.value(forKey: "imageAssets") as? Set<NSManagedObject>) ?? []
        return assets
            .filter { ($0.value(forKey: "roleRawValue") as? String) == role }
            .sorted { lhs, rhs in
                (lhs.value(forKey: "updatedAt") as? Date ?? .distantPast) >
                (rhs.value(forKey: "updatedAt") as? Date ?? .distantPast)
            }
            .first
    }
}
