import Foundation
import CoreData

final class RecipePersistentContainer {
    enum SyncMode: Equatable {
        case localOnly
        case cloudKit(containerIdentifier: String)
    }

    enum ContainerError: LocalizedError {
        case storeLoadFailed(String)

        var errorDescription: String? {
            switch self {
            case .storeLoadFailed(let message):
                return "Impossible de charger le magasin persistant de recettes. \(message)"
            }
        }
    }

    enum EntityName {
        static let recipe = "RecipeEntity"
        static let ingredient = "IngredientEntity"
        static let step = "StepEntity"
        static let imageAsset = "RecipeImageAssetEntity"
    }

    let container: NSPersistentCloudKitContainer
    let syncMode: SyncMode
    let storeURL: URL
    let deviceIdentifier: String

    var viewContext: NSManagedObjectContext {
        container.viewContext
    }

    init(
        syncMode: SyncMode = .localOnly,
        storeURL: URL? = nil,
        fileManager: FileManager = .default
    ) throws {
        self.syncMode = syncMode
        self.storeURL = try storeURL ?? Self.makeStoreURL(fileManager: fileManager)
        deviceIdentifier = Self.resolveDeviceIdentifier()

        let model = Self.makeManagedObjectModel()
        let container = NSPersistentCloudKitContainer(
            name: "MomRecetteCloudSync",
            managedObjectModel: model
        )

        let description = NSPersistentStoreDescription(url: self.storeURL)
        description.shouldAddStoreAsynchronously = false
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

        if case .cloudKit(let containerIdentifier) = syncMode {
            description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: containerIdentifier)
        }

        container.persistentStoreDescriptions = [description]

        var loadError: Error?
        container.loadPersistentStores { _, error in
            loadError = error
        }

        if let loadError {
            throw ContainerError.storeLoadFailed(loadError.localizedDescription)
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        self.container = container
    }

    static func makeStoreURL(fileManager: FileManager = .default) throws -> URL {
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directoryURL = appSupport.appendingPathComponent("MomRecette", isDirectory: true)
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL.appendingPathComponent("RecipeStore.sqlite")
    }

    static func resolveDeviceIdentifier(userDefaults: UserDefaults = .standard) -> String {
        let defaultsKey = "MomRecette.PersistentStore.DeviceIdentifier"
        if let existing = userDefaults.string(forKey: defaultsKey), existing.isEmpty == false {
            return existing
        }

        let newIdentifier = UUID().uuidString.lowercased()
        userDefaults.set(newIdentifier, forKey: defaultsKey)
        return newIdentifier
    }

    private static func makeManagedObjectModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()

        let recipe = NSEntityDescription()
        recipe.name = EntityName.recipe
        recipe.managedObjectClassName = NSStringFromClass(NSManagedObject.self)

        let ingredient = NSEntityDescription()
        ingredient.name = EntityName.ingredient
        ingredient.managedObjectClassName = NSStringFromClass(NSManagedObject.self)

        let step = NSEntityDescription()
        step.name = EntityName.step
        step.managedObjectClassName = NSStringFromClass(NSManagedObject.self)

        let imageAsset = NSEntityDescription()
        imageAsset.name = EntityName.imageAsset
        imageAsset.managedObjectClassName = NSStringFromClass(NSManagedObject.self)

        recipe.properties = [
            attribute("id", .UUIDAttributeType),
            attribute("name", .stringAttributeType),
            attribute("categoryRawValue", .stringAttributeType),
            attribute("servings", .integer64AttributeType, defaultValue: 4),
            optionalAttribute("caloriesPerServing", .integer64AttributeType),
            attribute("prepTime", .integer64AttributeType, defaultValue: 15),
            attribute("cookTime", .integer64AttributeType, defaultValue: 30),
            attribute("notes", .stringAttributeType, defaultValue: ""),
            attribute("isFavorite", .booleanAttributeType, defaultValue: false),
            attribute("createdAt", .dateAttributeType),
            attribute("updatedAt", .dateAttributeType),
            attribute("lastModifiedByDeviceID", .stringAttributeType),
            optionalAttribute("bundlePhotoKey", .stringAttributeType),
            optionalAttribute("photoFilename", .stringAttributeType),
            optionalAttribute("generatedImagePrompt", .stringAttributeType),
            optionalAttribute("generatedImageMode", .stringAttributeType),
            optionalAttribute("recipeCardFilename", .stringAttributeType),
            optionalAttribute("generatedRecipeCardPrompt", .stringAttributeType),
            optionalAttribute("deletedAt", .dateAttributeType)
        ]

        ingredient.properties = [
            attribute("id", .UUIDAttributeType),
            attribute("recipeID", .UUIDAttributeType),
            attribute("position", .integer64AttributeType),
            attribute("quantity", .stringAttributeType, defaultValue: ""),
            attribute("name", .stringAttributeType),
            attribute("kindRawValue", .stringAttributeType)
        ]

        step.properties = [
            attribute("id", .UUIDAttributeType),
            attribute("recipeID", .UUIDAttributeType),
            attribute("position", .integer64AttributeType),
            attribute("text", .stringAttributeType)
        ]

        let imageData = optionalAttribute("imageData", .binaryDataAttributeType)
        imageData.allowsExternalBinaryDataStorage = true

        imageAsset.properties = [
            attribute("id", .UUIDAttributeType),
            attribute("recipeID", .UUIDAttributeType),
            attribute("roleRawValue", .stringAttributeType),
            optionalAttribute("filename", .stringAttributeType),
            optionalAttribute("prompt", .stringAttributeType),
            optionalAttribute("generatedModeRawValue", .stringAttributeType),
            optionalAttribute("contentHash", .stringAttributeType),
            imageData,
            attribute("createdAt", .dateAttributeType),
            attribute("updatedAt", .dateAttributeType),
            optionalAttribute("deletedAt", .dateAttributeType)
        ]

        let recipeToIngredients = relationship(
            "ingredients",
            destination: ingredient,
            deleteRule: .cascadeDeleteRule,
            minCount: 0,
            maxCount: 0,
            isOrdered: true
        )
        let ingredientToRecipe = relationship(
            "recipe",
            destination: recipe,
            deleteRule: .nullifyDeleteRule,
            minCount: 0,
            maxCount: 1
        )
        recipeToIngredients.inverseRelationship = ingredientToRecipe
        ingredientToRecipe.inverseRelationship = recipeToIngredients

        let recipeToSteps = relationship(
            "steps",
            destination: step,
            deleteRule: .cascadeDeleteRule,
            minCount: 0,
            maxCount: 0,
            isOrdered: true
        )
        let stepToRecipe = relationship(
            "recipe",
            destination: recipe,
            deleteRule: .nullifyDeleteRule,
            minCount: 0,
            maxCount: 1
        )
        recipeToSteps.inverseRelationship = stepToRecipe
        stepToRecipe.inverseRelationship = recipeToSteps

        let recipeToImageAssets = relationship(
            "imageAssets",
            destination: imageAsset,
            deleteRule: .cascadeDeleteRule,
            minCount: 0,
            maxCount: 0,
            isOrdered: false
        )
        let imageAssetToRecipe = relationship(
            "recipe",
            destination: recipe,
            deleteRule: .nullifyDeleteRule,
            minCount: 0,
            maxCount: 1
        )
        recipeToImageAssets.inverseRelationship = imageAssetToRecipe
        imageAssetToRecipe.inverseRelationship = recipeToImageAssets

        recipe.properties.append(contentsOf: [recipeToIngredients, recipeToSteps, recipeToImageAssets])
        ingredient.properties.append(ingredientToRecipe)
        step.properties.append(stepToRecipe)
        imageAsset.properties.append(imageAssetToRecipe)

        model.entities = [recipe, ingredient, step, imageAsset]
        return model
    }

    private static func attribute(
        _ name: String,
        _ type: NSAttributeType,
        defaultValue: Any? = nil
    ) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = type
        attribute.isOptional = false
        attribute.defaultValue = defaultValue
        return attribute
    }

    private static func optionalAttribute(
        _ name: String,
        _ type: NSAttributeType
    ) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = type
        attribute.isOptional = true
        return attribute
    }

    private static func relationship(
        _ name: String,
        destination: NSEntityDescription,
        deleteRule: NSDeleteRule,
        minCount: Int,
        maxCount: Int,
        isOrdered: Bool = false
    ) -> NSRelationshipDescription {
        let relationship = NSRelationshipDescription()
        relationship.name = name
        relationship.destinationEntity = destination
        relationship.deleteRule = deleteRule
        relationship.minCount = minCount
        relationship.maxCount = maxCount
        relationship.isOrdered = isOrdered
        relationship.isOptional = minCount == 0
        return relationship
    }
}
