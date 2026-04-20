import Foundation
import CoreData
import CryptoKit

struct RecipeCoreDataImportReport {
    let processedRecipeCount: Int
    let insertedRecipeCount: Int
    let updatedRecipeCount: Int
    let importedDishPhotoAssetCount: Int
    let importedRecipeCardAssetCount: Int
    let importedLivePhotoAssetCount: Int
    let bundleBackedRecipeCount: Int
    let finalRecipeCount: Int
    let warnings: [String]
}

struct RecipeCoreDataImporter {
    enum ImportError: LocalizedError {
        case missingRecipeEntity(UUID)

        var errorDescription: String? {
            switch self {
            case .missingRecipeEntity(let id):
                return "La recette Core Data \(id.uuidString) n'a pas pu etre retrouvee apres creation."
            }
        }
    }

    private enum ImageRole: String {
        case dishPhoto
        case recipeCard
    }

    private struct RecipeImageAssetInput {
        let role: ImageRole
        let filename: String?
        let prompt: String?
        let generatedModeRawValue: String?
        let data: Data
        let sourceLabel: String
    }

    private let persistentContainer: RecipePersistentContainer
    private let livePhotoDirectoryURL: URL
    private let recipeImageStorage: RecipeImageStorage
    private let fileManager: FileManager

    init(
        persistentContainer: RecipePersistentContainer,
        livePhotoDirectoryURL: URL,
        generatedImageDirectoryURL: URL,
        fileManager: FileManager = .default
    ) {
        self.persistentContainer = persistentContainer
        self.livePhotoDirectoryURL = livePhotoDirectoryURL
        self.recipeImageStorage = RecipeImageStorage(directoryURL: generatedImageDirectoryURL)
        self.fileManager = fileManager
    }

    func importLibrary(
        recipes: [Recipe],
        deletingMissingRecipes: Bool = false
    ) throws -> RecipeCoreDataImportReport {
        let context = persistentContainer.container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        var insertedRecipeCount = 0
        var updatedRecipeCount = 0
        var importedDishPhotoAssetCount = 0
        var importedRecipeCardAssetCount = 0
        var importedLivePhotoAssetCount = 0
        var bundleBackedRecipeCount = 0
        var warnings: [String] = []

        try context.performAndWait {
            if deletingMissingRecipes {
                let incomingIDs = Set(recipes.map(\.id))
                let request = NSFetchRequest<NSManagedObject>(entityName: RecipePersistentContainer.EntityName.recipe)
                let existingRecipes = try context.fetch(request)

                for existingRecipe in existingRecipes {
                    guard let existingID = existingRecipe.value(forKey: "id") as? UUID else { continue }
                    if incomingIDs.contains(existingID) == false {
                        context.delete(existingRecipe)
                    }
                }
            }

            for recipe in recipes {
                let existingRecipe = try fetchRecipeEntity(id: recipe.id, in: context)
                let recipeObject = existingRecipe ?? NSEntityDescription.insertNewObject(
                    forEntityName: RecipePersistentContainer.EntityName.recipe,
                    into: context
                )

                if existingRecipe == nil {
                    insertedRecipeCount += 1
                } else {
                    updatedRecipeCount += 1
                }

                applyRecipeFields(recipe, to: recipeObject)
                replaceOrderedChildren(for: recipeObject, recipe: recipe, in: context)

                let imageInputs = resolveImageInputs(for: recipe)
                let livePhotoInputCount = imageInputs.filter { $0.sourceLabel == "live photo" }.count
                importedLivePhotoAssetCount += livePhotoInputCount

                let hasDishPhotoAsset = imageInputs.contains { $0.role == .dishPhoto }
                if hasDishPhotoAsset == false, recipe.imageData != nil {
                    recipeObject.setValue(recipe.photoLookupKeys.first, forKey: "bundlePhotoKey")
                    bundleBackedRecipeCount += 1
                } else {
                    recipeObject.setValue(nil, forKey: "bundlePhotoKey")
                }

                let imageAssetImportResult = replaceImageAssets(
                    for: recipeObject,
                    imageInputs: imageInputs,
                    in: context
                )
                importedDishPhotoAssetCount += imageAssetImportResult.dishPhotoCount
                importedRecipeCardAssetCount += imageAssetImportResult.recipeCardCount
                warnings.append(contentsOf: imageAssetImportResult.warnings)
            }

            if context.hasChanges {
                try context.save()
            }
        }

        let finalRecipeCount = try fetchRecipeCount()

        return RecipeCoreDataImportReport(
            processedRecipeCount: recipes.count,
            insertedRecipeCount: insertedRecipeCount,
            updatedRecipeCount: updatedRecipeCount,
            importedDishPhotoAssetCount: importedDishPhotoAssetCount,
            importedRecipeCardAssetCount: importedRecipeCardAssetCount,
            importedLivePhotoAssetCount: importedLivePhotoAssetCount,
            bundleBackedRecipeCount: bundleBackedRecipeCount,
            finalRecipeCount: finalRecipeCount,
            warnings: warnings
        )
    }

    private func applyRecipeFields(_ recipe: Recipe, to object: NSManagedObject) {
        let createdAt = max(recipe.createdAt, Date.distantPast)
        let updatedAt = max(recipe.updatedAt, createdAt)
        let lastModifiedByDeviceID = recipe.lastModifiedByDeviceID ?? persistentContainer.deviceIdentifier

        object.setValue(recipe.id, forKey: "id")
        object.setValue(recipe.name, forKey: "name")
        object.setValue(recipe.category.rawValue, forKey: "categoryRawValue")
        object.setValue(Int64(recipe.servings), forKey: "servings")
        object.setValue(recipe.caloriesPerServing.map { Int64($0) }, forKey: "caloriesPerServing")
        object.setValue(Int64(recipe.prepTime), forKey: "prepTime")
        object.setValue(Int64(recipe.cookTime), forKey: "cookTime")
        object.setValue(recipe.notes, forKey: "notes")
        object.setValue(recipe.isFavorite, forKey: "isFavorite")
        object.setValue(createdAt, forKey: "createdAt")
        object.setValue(updatedAt, forKey: "updatedAt")
        object.setValue(lastModifiedByDeviceID, forKey: "lastModifiedByDeviceID")
        object.setValue(recipe.photoFilename, forKey: "photoFilename")
        object.setValue(recipe.generatedImagePrompt, forKey: "generatedImagePrompt")
        object.setValue(recipe.generatedImageMode, forKey: "generatedImageMode")
        object.setValue(recipe.recipeCardFilename, forKey: "recipeCardFilename")
        object.setValue(recipe.generatedRecipeCardPrompt, forKey: "generatedRecipeCardPrompt")
        object.setValue(nil, forKey: "deletedAt")
    }

    private func replaceOrderedChildren(for object: NSManagedObject, recipe: Recipe, in context: NSManagedObjectContext) {
        deleteOrderedChildren(named: "ingredients", from: object, in: context)
        deleteOrderedChildren(named: "steps", from: object, in: context)

        let ingredientSet = object.mutableOrderedSetValue(forKey: "ingredients")
        for (index, ingredient) in recipe.ingredients.enumerated() {
            let ingredientObject = NSEntityDescription.insertNewObject(
                forEntityName: RecipePersistentContainer.EntityName.ingredient,
                into: context
            )
            ingredientObject.setValue(ingredient.id, forKey: "id")
            ingredientObject.setValue(recipe.id, forKey: "recipeID")
            ingredientObject.setValue(Int64(index), forKey: "position")
            ingredientObject.setValue(ingredient.quantity, forKey: "quantity")
            ingredientObject.setValue(ingredient.name, forKey: "name")
            ingredientObject.setValue(ingredient.kind.rawValue, forKey: "kindRawValue")
            ingredientObject.setValue(object, forKey: "recipe")
            ingredientSet.add(ingredientObject)
        }

        let stepSet = object.mutableOrderedSetValue(forKey: "steps")
        for (index, stepText) in recipe.steps.enumerated() {
            let stepObject = NSEntityDescription.insertNewObject(
                forEntityName: RecipePersistentContainer.EntityName.step,
                into: context
            )
            stepObject.setValue(UUID(), forKey: "id")
            stepObject.setValue(recipe.id, forKey: "recipeID")
            stepObject.setValue(Int64(index), forKey: "position")
            stepObject.setValue(stepText, forKey: "text")
            stepObject.setValue(object, forKey: "recipe")
            stepSet.add(stepObject)
        }
    }

    private func replaceImageAssets(
        for object: NSManagedObject,
        imageInputs: [RecipeImageAssetInput],
        in context: NSManagedObjectContext
    ) -> (dishPhotoCount: Int, recipeCardCount: Int, warnings: [String]) {
        let existingAssets = object.mutableSetValue(forKey: "imageAssets")
        for case let existingObject as NSManagedObject in existingAssets {
            context.delete(existingObject)
        }
        existingAssets.removeAllObjects()

        var dishPhotoCount = 0
        var recipeCardCount = 0
        var warnings: [String] = []

        for input in imageInputs {
            let imageObject = NSEntityDescription.insertNewObject(
                forEntityName: RecipePersistentContainer.EntityName.imageAsset,
                into: context
            )
            imageObject.setValue(UUID(), forKey: "id")
            imageObject.setValue(object.value(forKey: "id"), forKey: "recipeID")
            imageObject.setValue(input.role.rawValue, forKey: "roleRawValue")
            imageObject.setValue(input.filename, forKey: "filename")
            imageObject.setValue(input.prompt, forKey: "prompt")
            imageObject.setValue(input.generatedModeRawValue, forKey: "generatedModeRawValue")
            imageObject.setValue(Self.sha256Hex(of: input.data), forKey: "contentHash")
            imageObject.setValue(input.data, forKey: "imageData")
            imageObject.setValue(Date(), forKey: "createdAt")
            imageObject.setValue(Date(), forKey: "updatedAt")
            imageObject.setValue(nil, forKey: "deletedAt")
            imageObject.setValue(object, forKey: "recipe")
            existingAssets.add(imageObject)

            switch input.role {
            case .dishPhoto:
                dishPhotoCount += 1
            case .recipeCard:
                recipeCardCount += 1
            }

            if input.data.isEmpty {
                warnings.append("Image asset \(input.sourceLabel) was empty for recipe \(object.value(forKey: "name") as? String ?? "unknown").")
            }
        }

        return (dishPhotoCount, recipeCardCount, warnings)
    }

    private func resolveImageInputs(for recipe: Recipe) -> [RecipeImageAssetInput] {
        var inputs: [RecipeImageAssetInput] = []

        if let filename = recipe.photoFilename,
           let storedDishData = recipeImageStorage.loadImage(named: filename) ?? recipe.imageData {
            inputs.append(
                RecipeImageAssetInput(
                    role: .dishPhoto,
                    filename: filename,
                    prompt: recipe.generatedImagePrompt,
                    generatedModeRawValue: recipe.generatedImageMode,
                    data: storedDishData,
                    sourceLabel: "generated dish photo"
                )
            )
        } else if let livePhoto = firstLivePhoto(for: recipe) {
            inputs.append(
                RecipeImageAssetInput(
                    role: .dishPhoto,
                    filename: livePhoto.filename,
                    prompt: nil,
                    generatedModeRawValue: nil,
                    data: livePhoto.data,
                    sourceLabel: "live photo"
                )
            )
        }

        if let filename = recipe.recipeCardFilename,
           let recipeCardData = recipeImageStorage.loadImage(named: filename) {
            inputs.append(
                RecipeImageAssetInput(
                    role: .recipeCard,
                    filename: filename,
                    prompt: recipe.generatedRecipeCardPrompt,
                    generatedModeRawValue: RecipeImageMode.recipeCard.rawValue,
                    data: recipeCardData,
                    sourceLabel: "generated recipe card"
                )
            )
        }

        return inputs
    }

    private func firstLivePhoto(for recipe: Recipe) -> (filename: String, data: Data)? {
        let urls = (try? fileManager.contentsOfDirectory(
            at: livePhotoDirectoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []

        let matchingURL = urls.first { url in
            guard url.hasDirectoryPath == false else { return false }
            let lookupKey = url.deletingPathExtension().lastPathComponent.photoLookupKey
            return recipe.photoLookupKeys.contains(lookupKey)
        }

        guard let matchingURL,
              let data = try? Data(contentsOf: matchingURL) else { return nil }

        return (matchingURL.lastPathComponent, data)
    }

    private func fetchRecipeEntity(id: UUID, in context: NSManagedObjectContext) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: RecipePersistentContainer.EntityName.recipe)
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        return try context.fetch(request).first
    }

    private func fetchRecipeCount() throws -> Int {
        try persistentContainer.viewContext.count(
            for: NSFetchRequest<NSFetchRequestResult>(entityName: RecipePersistentContainer.EntityName.recipe)
        )
    }

    private func deleteOrderedChildren(named key: String, from object: NSManagedObject, in context: NSManagedObjectContext) {
        let children = object.mutableOrderedSetValue(forKey: key)
        for case let child as NSManagedObject in children {
            context.delete(child)
        }
        children.removeAllObjects()
    }

    private static func sha256Hex(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
