import XCTest
@testable import MomRecette
import UIKit
import CoreData

@MainActor
final class MomRecetteTests: XCTestCase {
    private func makeJPEGData() -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8))
        let image = renderer.image { context in
            UIColor.systemOrange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }

        return image.jpegData(compressionQuality: 0.85)!
    }

    private func makeImage(size: CGSize, color: UIColor = .systemOrange) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    private func makeStore(
        directory: URL? = nil,
        livePhotoDirectoryURL: URL? = nil,
        recipeImageGenerator: (any RecipeImageGenerating)? = nil,
        persistentContainer: RecipePersistentContainer? = nil,
        deviceIdentifier: String? = nil,
        deviceName: String? = nil,
        sharedSyncRootURL: URL? = nil
    ) throws -> RecipeStore {
        let directory = directory ?? FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        return RecipeStore(
            recipesURL: directory.appendingPathComponent("recipes.json"),
            groceryListURL: directory.appendingPathComponent("grocery-list.json"),
            shouldLoadSeedData: false,
            livePhotoDirectoryURL: livePhotoDirectoryURL ?? directory.appendingPathComponent("RecipePhotos"),
            enablePhotoAutoRefresh: false,
            recipeImageStorage: RecipeImageStorage(
                directoryURL: directory.appendingPathComponent("RecipeImages", isDirectory: true)
            ),
            recipeImageGenerator: recipeImageGenerator,
            persistentContainer: persistentContainer,
            deviceIdentifier: deviceIdentifier,
            deviceName: deviceName,
            sharedSyncRootURL: sharedSyncRootURL
        )
    }

    private func makePersistentContainer(storeURL: URL) throws -> RecipePersistentContainer {
        try RecipePersistentContainer(syncMode: .localOnly, storeURL: storeURL)
    }

    func testCategoryDetection() {
        let tarte = Recipe(name: "Tarte aux pommes", category: .desserts)
        XCTAssertEqual(tarte.category, .desserts)
    }

    func testTimeString() {
        XCTAssertEqual(45.timeString, "45 min")
        XCTAssertEqual(90.timeString, "1h30")
    }

    func testCreateGroceryListFromRecipeIngredients() throws {
        let store = try makeStore()
        let recipe = Recipe(
            name: "Crumble aux pommes",
            category: .desserts,
            ingredients: [
                .init(quantity: "3", name: "pommes"),
                .init(quantity: "1 tasse", name: "farine")
            ]
        )

        store.createGroceryList(for: recipe)

        XCTAssertEqual(store.currentGroceryList?.recipeName, "Crumble aux pommes")
        XCTAssertEqual(store.currentGroceryList?.items.count, 2)
        XCTAssertEqual(store.currentGroceryList?.items.first?.quantity, "3")
    }

    func testToggleGroceryItemMarksItemChecked() throws {
        let store = try makeStore()
        let recipe = Recipe(
            name: "Soupe",
            category: .soupes,
            ingredients: [.init(quantity: "1 litre", name: "bouillon")]
        )

        store.createGroceryList(for: recipe)
        let itemID = try XCTUnwrap(store.currentGroceryList?.items.first?.id)

        store.toggleGroceryItem(id: itemID)

        XCTAssertEqual(store.currentGroceryList?.items.first?.isChecked, true)
    }

    func testGroceryListExportTextIncludesStoreAndQuantities() {
        let recipe = Recipe(
            name: "Crumble aux pommes",
            category: .desserts,
            ingredients: [
                .init(quantity: "3", name: "pommes"),
                .init(quantity: "1 tasse", name: "farine")
            ]
        )

        let exportText = GroceryList(recipe: recipe).exportText(for: .iga)

        XCTAssertTrue(exportText.contains("Magasin: IGA"))
        XCTAssertTrue(exportText.contains("Recette: Crumble aux pommes"))
        XCTAssertTrue(exportText.contains("[ ] 3 pommes"))
        XCTAssertTrue(exportText.contains("[ ] 1 tasse farine"))
    }

    func testGroceryListExportTextKeepsCheckedState() {
        let recipe = Recipe(
            name: "Soupe",
            category: .soupes,
            ingredients: [.init(quantity: "1 litre", name: "bouillon")]
        )

        var groceryList = GroceryList(recipe: recipe)
        groceryList.items[0].isChecked = true

        let exportText = groceryList.exportText(for: .metro)

        XCTAssertTrue(exportText.contains("Magasin: Metro"))
        XCTAssertTrue(exportText.contains("[x] 1 litre bouillon"))
    }

    func testGroceryListEstimatedPriceUsesStoreMultiplierForCountedItems() {
        let item = GroceryList.Item(id: UUID(), quantity: "3", name: "pommes")

        let price = item.estimatedPrice(for: .iga)

        XCTAssertEqual(NSDecimalNumber(decimal: price).doubleValue, 3.21, accuracy: 0.001)
    }

    func testGroceryListExportTextIncludesEstimatedTotal() {
        let recipe = Recipe(
            name: "Crumble aux pommes",
            category: .desserts,
            ingredients: [
                .init(quantity: "3", name: "pommes"),
                .init(quantity: "1 tasse", name: "farine")
            ]
        )

        let exportText = GroceryList(recipe: recipe).exportText(for: .iga)

        XCTAssertTrue(exportText.contains("Total estime:"))
        XCTAssertTrue(exportText.contains("3 pommes -"))
        XCTAssertTrue(exportText.contains("1 tasse farine -"))
    }

    func testGroceryListReminderPayloadsIncludeStoreRecipeAndQuantity() {
        let recipe = Recipe(
            name: "Crumble aux pommes",
            category: .desserts,
            ingredients: [
                .init(quantity: "3", name: "pommes"),
                .init(quantity: "1 tasse", name: "farine")
            ]
        )

        let groceryList = GroceryList(recipe: recipe)
        let payloads = groceryList.reminderPayloads(for: .iga)

        XCTAssertEqual(payloads.count, 2)
        XCTAssertTrue(payloads[0].title.hasPrefix("3 pommes"))
        XCTAssertTrue(payloads[0].title.contains("$"))
        XCTAssertTrue(payloads[0].notes.contains("Recette: Crumble aux pommes"))
        XCTAssertTrue(payloads[0].notes.contains("Magasin: IGA"))
        XCTAssertTrue(payloads[0].notes.contains("Prix estime:"))
        XCTAssertTrue(payloads[0].notes.contains(groceryList.reminderMetadataPrefix(for: .iga)))
    }

    func testGroceryListReminderPayloadsPreserveCheckedItems() {
        let recipe = Recipe(
            name: "Soupe",
            category: .soupes,
            ingredients: [.init(quantity: "1 litre", name: "bouillon")]
        )

        var groceryList = GroceryList(recipe: recipe)
        groceryList.items[0].isChecked = true

        let payload = try? XCTUnwrap(groceryList.reminderPayloads(for: .metro).first)

        XCTAssertTrue(payload?.title.hasPrefix("1 litre bouillon") == true)
        XCTAssertTrue(payload?.title.contains("$") == true)
        XCTAssertEqual(payload?.isCompleted, true)
    }

    func testRefreshRecipePhotosLoadsLivePhoto() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let livePhotoDirectory = directory.appendingPathComponent("RecipePhotos", isDirectory: true)
    try FileManager.default.createDirectory(at: livePhotoDirectory, withIntermediateDirectories: true)
    
    let store = RecipeStore(
        recipesURL: directory.appendingPathComponent("recipes.json"),
        groceryListURL: directory.appendingPathComponent("grocery-list.json"),
        shouldLoadSeedData: false,
        livePhotoDirectoryURL: livePhotoDirectory,
        enablePhotoAutoRefresh: false
    )
    
    let recipe = Recipe(name: "Test Photo", category: .plats)
    store.add(recipe)
    XCTAssertNil(store.recipes.first?.imageData)
    
    let imageURL = livePhotoDirectory.appendingPathComponent("test-photo.jpg")
    try makeJPEGData().write(to: imageURL)
    
    store.refreshRecipePhotosIfNeeded(force: true)
    
    XCTAssertNotNil(store.recipes.first?.imageData)
    }

    func testImportRecipePhotosCopiesMatchingFilesIntoLiveDirectory() throws {
    let store = try makeStore()
    store.add(Recipe(name: "Poulet Croustillant", category: .plats))
    
    let sourceDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
    
    let sourceURL = sourceDirectory.appendingPathComponent("Poulet Croustillant.png")
    let pngData = try XCTUnwrap(makeImage(size: CGSize(width: 100, height: 100), color: .systemBlue).pngData())
    try pngData.write(to: sourceURL)
    
    let result = store.importRecipePhotos(from: [sourceURL])
    
    XCTAssertEqual(result.importedCount, 1)
    XCTAssertEqual(result.replacedCount, 0)
    XCTAssertEqual(result.issueCount, 0)
    XCTAssertNotNil(store.recipes.first?.imageData)
    }

    func testImportRecipePhotosSkipsUnmatchedAndInvalidFiles() throws {
    let store = try makeStore()
    store.add(Recipe(name: "Soupe du Jour", category: .soupes))
    
    let sourceDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
    
    let unmatchedURL = sourceDirectory.appendingPathComponent("Recette Inconnue.jpg")
    try makeJPEGData().write(to: unmatchedURL)
    
    let invalidURL = sourceDirectory.appendingPathComponent("Soupe du Jour.jpg")
    try Data([0x00, 0x01, 0x02, 0x03]).write(to: invalidURL)
    
    let result = store.importRecipePhotos(from: [unmatchedURL, invalidURL])
    
    XCTAssertEqual(result.importedCount, 0)
    XCTAssertEqual(result.unmatchedCount, 1)
    XCTAssertEqual(result.invalidCount, 1)
    XCTAssertNil(store.recipes.first?.imageData)
    }

    func testLoadDropsInvalidPersistedImageData() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let recipesURL = directory.appendingPathComponent("recipes.json")

        let recipe = Recipe(
            name: "Image corrompue",
            category: .desserts,
            imageData: Data([0x01, 0x02, 0x03, 0x04])
        )
        try JSONEncoder().encode([recipe]).write(to: recipesURL)

        let store = RecipeStore(
            recipesURL: recipesURL,
            groceryListURL: directory.appendingPathComponent("grocery-list.json"),
            shouldLoadSeedData: false,
            livePhotoDirectoryURL: directory.appendingPathComponent("RecipePhotos"),
            enablePhotoAutoRefresh: false
        )

        XCTAssertNil(try XCTUnwrap(store.recipes.first).imageData)
    }

    func testRefreshRecipePhotosSkipsInvalidLivePhoto() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let livePhotoDirectory = directory.appendingPathComponent("RecipePhotos", isDirectory: true)
        try FileManager.default.createDirectory(at: livePhotoDirectory, withIntermediateDirectories: true)

        let store = RecipeStore(
            recipesURL: directory.appendingPathComponent("recipes.json"),
            groceryListURL: directory.appendingPathComponent("grocery-list.json"),
            shouldLoadSeedData: false,
            livePhotoDirectoryURL: livePhotoDirectory,
            enablePhotoAutoRefresh: false
        )

        let recipe = Recipe(name: "Photo invalide", category: .plats)
        store.add(recipe)

        let imageURL = livePhotoDirectory.appendingPathComponent("photo-invalide.jpg")
        try Data([0x00, 0x11, 0x22, 0x33]).write(to: imageURL)

        store.refreshRecipePhotosIfNeeded(force: true)

        XCTAssertNil(store.recipes.first?.imageData)
    }

    func testRecipeImageStorageSavesLoadsAndDeletesImage() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let storage = RecipeImageStorage(directoryURL: directory)
        let recipe = Recipe(name: "Photo test", category: .plats)

        let storedImage = try storage.saveImage(makeJPEGData(), for: recipe)

        XCTAssertTrue(storedImage.filename.hasPrefix("photo-test-"))
        XCTAssertNotNil(storage.loadImage(named: storedImage.filename))

        try storage.deleteImage(named: storedImage.filename)

        XCTAssertNil(storage.loadImage(named: storedImage.filename))
    }

    func testGenerateRecipeImageUpdatesRecipeAndStoresMetadata() async throws {
        let store = try makeStore(recipeImageGenerator: MockRecipeImageGenerator(imageData: makeJPEGData()))
        let recipe = Recipe(name: "Canard confit", category: .plats)
        store.add(recipe)

        try await store.generateRecipeImage(
            for: recipe,
            mode: .dishPhoto,
            extraDetail: "golden lighting"
        )

        let updated = try XCTUnwrap(store.recipes.first)
        XCTAssertNotNil(updated.imageData)
        XCTAssertEqual(updated.generatedImageMode, RecipeImageMode.dishPhoto.rawValue)
        XCTAssertEqual(updated.photoFilename?.hasPrefix("canard-confit-"), true)
        XCTAssertTrue(updated.generatedImagePrompt?.contains("golden lighting") == true)
    }

    func testGeneratedRecipeImageTakesPrecedenceOverLiveRecipePhoto() async throws {
        let baseDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let livePhotoDirectory = baseDirectory.appendingPathComponent("RecipePhotos", isDirectory: true)
        let store = try makeStore(
            directory: baseDirectory,
            livePhotoDirectoryURL: livePhotoDirectory,
            recipeImageGenerator: MockRecipeImageGenerator(imageData: makeJPEGData())
        )
        let recipe = Recipe(name: "Boeuf braise", category: .plats)
        store.add(recipe)

        try await store.generateRecipeImage(for: recipe, mode: .dishPhoto, extraDetail: nil)

        try FileManager.default.createDirectory(at: livePhotoDirectory, withIntermediateDirectories: true)
        let livePhotoData = try XCTUnwrap(
            makeImage(size: CGSize(width: 20, height: 20), color: .systemBlue)
                .jpegData(compressionQuality: 0.85)
        )
        try livePhotoData.write(to: livePhotoDirectory.appendingPathComponent("boeuf-braise.jpg"))

        let regeneratedStore = try makeStore(
            directory: baseDirectory,
            livePhotoDirectoryURL: livePhotoDirectory,
            recipeImageGenerator: MockRecipeImageGenerator(imageData: makeJPEGData())
        )
        regeneratedStore.refreshRecipePhotosIfNeeded(force: true)

        XCTAssertEqual(regeneratedStore.recipes.first?.photoFilename, store.recipes.first?.photoFilename)
        XCTAssertEqual(regeneratedStore.recipes.first?.imageData, store.recipes.first?.imageData)
    }

    func testRecipeCardGenerationDoesNotReplaceDishPhoto() async throws {
        let store = try makeStore(
            recipeImageGenerator: MockRecipeImageGenerator(imageData: makeJPEGData())
        )
        var recipe = Recipe(name: "Tarte fine", category: .desserts)
        recipe.imageData = makeJPEGData()
        store.add(recipe)

        let originalPhotoData = try XCTUnwrap(store.recipes.first?.imageData)
        let storedRecipe = try XCTUnwrap(store.recipes.first)

        try await store.generateRecipeImage(for: storedRecipe, mode: .recipeCard, extraDetail: "parchment")

        let updated = try XCTUnwrap(store.recipes.first)
        XCTAssertEqual(updated.imageData, originalPhotoData)
        XCTAssertNil(updated.photoFilename)
        XCTAssertNotNil(updated.recipeCardFilename)
        XCTAssertTrue(updated.generatedRecipeCardPrompt?.contains("parchment") == true)
    }

    func testRecipeImageIssueMapsMissingAPIKeyToStableDiagnosticID() {
        let issue = RecipeImageIssue.from(OpenAIRecipeImageGenerator.GenerationError.missingAPIKey)

        XCTAssertEqual(issue.id, "IMG-KEY-001")
        XCTAssertTrue(issue.message.contains("OPENAI_API_KEY"))
    }

    func testRecipeImageIssueMapsTimeoutToStableDiagnosticID() {
        let issue = RecipeImageIssue.from(
            OpenAIRecipeImageGenerator.GenerationError.network(URLError(.timedOut))
        )

        XCTAssertEqual(issue.id, "IMG-NET-002")
        XCTAssertTrue(issue.title.contains("timed out"))
    }

    func testRecipeImageIssueMapsRateLimitToStableDiagnosticID() {
        let issue = RecipeImageIssue.from(
            OpenAIRecipeImageGenerator.GenerationError.apiError(
                statusCode: 429,
                message: "Rate limit exceeded"
            )
        )

        XCTAssertEqual(issue.id, "IMG-API-429")
        XCTAssertTrue(issue.message.contains("temporarily limiting"))
    }

    func testRecipeImageIssueMapsStorageFailureToStableDiagnosticID() {
        let issue = RecipeImageIssue.from(RecipeImageStorage.StorageError.invalidImageData)

        XCTAssertEqual(issue.id, "IMG-STO-001")
        XCTAssertTrue(issue.title.contains("could not be saved"))
    }

    func testRecipePhotoImportNormalizesRemoteURLWithoutScheme() {
        let url = RecipePhotoImport.normalizedRemoteURL(from: "example.com/photo.jpg")

        XCTAssertEqual(url?.absoluteString, "https://example.com/photo.jpg")
    }

    func testRecipePhotoImportNormalizesWrappedRemoteURL() {
        let url = RecipePhotoImport.normalizedRemoteURL(from: " <https://example.com/recipe image.webp?name=creole sauce> ")

        XCTAssertEqual(url?.absoluteString, "https://example.com/recipe%20image.webp?name=creole%20sauce")
    }

    func testRecipePhotoImportRejectsUnsupportedURLScheme() {
        let url = RecipePhotoImport.normalizedRemoteURL(from: "ftp://example.com/photo.jpg")

        XCTAssertNil(url)
    }

    func testRecipePhotoImportPreparedImageDataRejectsInvalidPayload() {
        let data = RecipePhotoImport.preparedImageData(from: Data([0x00, 0x01, 0x02]))

        XCTAssertNil(data)
    }

    func testRecipePhotoImportPreparedImageDataKeepsValidImage() {
        let data = RecipePhotoImport.preparedImageData(from: makeJPEGData(), maxWidth: 1200)

        XCTAssertNotNil(data)
        XCTAssertNotNil(UIImage(data: try XCTUnwrap(data)))
    }

    func testRecipePhotoImportRenderedImageDataProducesExpectedOutputSize() throws {
        let image = makeImage(size: CGSize(width: 1200, height: 900))
        let cropSize = CGSize(width: 320, height: 180)

        let data = RecipePhotoImport.renderedImageData(
            from: image,
            cropSize: cropSize,
            zoomScale: 1.8,
            offset: CGSize(width: 40, height: -20)
        )

        let rendered = try XCTUnwrap(UIImage(data: try XCTUnwrap(data)))
        XCTAssertEqual(rendered.cgImage?.width, Int(RecipePhotoImport.cropOutputSize.width))
        XCTAssertEqual(rendered.cgImage?.height, Int(RecipePhotoImport.cropOutputSize.height))
    }

    func testRecipeDecodingDefaultsFavoriteToFalseWhenFieldIsMissing() throws {
        let json = """
        {
          "id": "\(UUID())",
          "name": "Gratin test",
          "category": "Plats",
          "servings": 4,
          "prepTime": 20,
          "cookTime": 35,
          "ingredients": [],
          "steps": [],
          "notes": ""
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(Recipe.self, from: json)

        XCTAssertFalse(decoded.isFavorite)
    }

    func testRecipeDecodingLeavesCaloriesNilWhenFieldIsMissing() throws {
        let json = """
        {
          "id": "\(UUID())",
          "name": "Gratin test",
          "category": "Plats",
          "servings": 4,
          "prepTime": 20,
          "cookTime": 35,
          "ingredients": [],
          "steps": [],
          "notes": ""
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(Recipe.self, from: json)

        XCTAssertNil(decoded.caloriesPerServing)
    }

    func testStorePersistsCaloriesPerServing() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let recipesURL = directory.appendingPathComponent("recipes.json")
        let groceryURL = directory.appendingPathComponent("grocery.json")
        let livePhotoURL = directory.appendingPathComponent("RecipePhotos")
        let recipeImagesURL = directory.appendingPathComponent("RecipeImages", isDirectory: true)

        let store = RecipeStore(
            recipesURL: recipesURL,
            groceryListURL: groceryURL,
            shouldLoadSeedData: false,
            livePhotoDirectoryURL: livePhotoURL,
            enablePhotoAutoRefresh: false,
            recipeImageStorage: RecipeImageStorage(directoryURL: recipeImagesURL)
        )
        let recipe = Recipe(name: "Pates au pesto", category: .plats, caloriesPerServing: 620)

        store.add(recipe)

        let reloaded = RecipeStore(
            recipesURL: recipesURL,
            groceryListURL: groceryURL,
            shouldLoadSeedData: false,
            livePhotoDirectoryURL: livePhotoURL,
            enablePhotoAutoRefresh: false,
            recipeImageStorage: RecipeImageStorage(directoryURL: recipeImagesURL)
        )

        XCTAssertEqual(reloaded.recipes.first?.caloriesPerServing, 620)
    }

    func testStoreMigratesLegacyJSONIntoCoreDataWhenPersistentContainerIsProvided() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let recipesURL = directory.appendingPathComponent("recipes.json")
        let groceryURL = directory.appendingPathComponent("grocery.json")
        let livePhotoURL = directory.appendingPathComponent("RecipePhotos", isDirectory: true)
        let recipeImagesURL = directory.appendingPathComponent("RecipeImages", isDirectory: true)
        let persistentStoreURL = directory.appendingPathComponent("RecipeStore.sqlite")

        let legacyRecipe = Recipe(
            name: "Migration locale",
            category: .plats,
            caloriesPerServing: 540,
            ingredients: [.init(quantity: "2", name: "pommes de terre")],
            steps: ["Cuire doucement."],
            notes: "Ancienne recette JSON"
        )
        try JSONEncoder().encode([legacyRecipe]).write(to: recipesURL)

        let persistentContainer = try makePersistentContainer(storeURL: persistentStoreURL)

        let store = RecipeStore(
            recipesURL: recipesURL,
            groceryListURL: groceryURL,
            shouldLoadSeedData: false,
            livePhotoDirectoryURL: livePhotoURL,
            enablePhotoAutoRefresh: false,
            recipeImageStorage: RecipeImageStorage(directoryURL: recipeImagesURL),
            persistentContainer: persistentContainer
        )

        XCTAssertEqual(store.recipes.count, 1)
        XCTAssertEqual(store.recipes.first?.name, "Migration locale")
        XCTAssertEqual(store.recipes.first?.caloriesPerServing, 540)
        XCTAssertEqual(store.recipes.first?.ingredients.count, 1)
        XCTAssertEqual(store.recipes.first?.steps, ["Cuire doucement."])

        let countRequest = NSFetchRequest<NSFetchRequestResult>(entityName: RecipePersistentContainer.EntityName.recipe)
        XCTAssertEqual(try persistentContainer.viewContext.count(for: countRequest), 1)
    }

    func testStorePersistsFavoriteChangesThroughCoreDataRepository() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let persistentStoreURL = directory.appendingPathComponent("RecipeStore.sqlite")
        let firstContainer = try makePersistentContainer(storeURL: persistentStoreURL)
        let store = try makeStore(directory: directory, persistentContainer: firstContainer)
        let recipe = Recipe(name: "Favori Core Data", category: .plats)

        store.add(recipe)
        let insertedRecipe = try XCTUnwrap(store.recipes.first)
        store.toggleFavorite(for: insertedRecipe)

        let secondContainer = try makePersistentContainer(storeURL: persistentStoreURL)
        let reloaded = try makeStore(directory: directory, persistentContainer: secondContainer)

        XCTAssertEqual(reloaded.recipes.count, 1)
        XCTAssertEqual(reloaded.recipes.first?.name, "Favori Core Data")
        XCTAssertEqual(reloaded.recipes.first?.isFavorite, true)
    }

    func testStoreReconcilesDuplicateCoreDataRecipesOnLoad() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let persistentStoreURL = directory.appendingPathComponent("RecipeStore.sqlite")
        let firstContainer = try makePersistentContainer(storeURL: persistentStoreURL)
        let store = try makeStore(directory: directory, persistentContainer: firstContainer)

        store.add(Recipe(name: "Doublon Core Data", category: .plats, notes: "Version courte"))
        store.add(
            Recipe(
                name: "Doublon Core Data",
                category: .plats,
                caloriesPerServing: 480,
                ingredients: [.init(quantity: "2", name: "oeufs")],
                steps: ["Assembler", "Cuire"],
                isFavorite: true,
                notes: "Version complete pour la reconciliation"
            )
        )

        let secondContainer = try makePersistentContainer(storeURL: persistentStoreURL)
        let reloaded = try makeStore(directory: directory, persistentContainer: secondContainer)

        XCTAssertEqual(reloaded.recipes.count, 1)
        XCTAssertEqual(reloaded.recipes.first?.name, "Doublon Core Data")
        XCTAssertEqual(reloaded.recipes.first?.isFavorite, true)
        XCTAssertEqual(reloaded.recipes.first?.caloriesPerServing, 480)
        XCTAssertEqual(reloaded.recipes.first?.ingredients.count, 1)
        XCTAssertEqual(reloaded.recipes.first?.steps.count, 2)
        XCTAssertEqual(reloaded.recipes.first?.notes, "Version complete pour la reconciliation")

        let countRequest = NSFetchRequest<NSFetchRequestResult>(entityName: RecipePersistentContainer.EntityName.recipe)
        XCTAssertEqual(try secondContainer.viewContext.count(for: countRequest), 1)
    }

    func testToggleFavoriteUpdatesRecipeState() throws {
        let store = try makeStore()
        let recipe = Recipe(name: "Pates au pesto", category: .plats)
        store.add(recipe)

        store.toggleFavorite(for: recipe)
        XCTAssertEqual(store.favoriteCount, 1)
        XCTAssertEqual(store.recipes.first?.isFavorite, true)

        let updatedRecipe = try XCTUnwrap(store.recipes.first)
        store.toggleFavorite(for: updatedRecipe)
        XCTAssertEqual(store.favoriteCount, 0)
        XCTAssertEqual(store.recipes.first?.isFavorite, false)
    }

    func testLegacyRecipeCardAttachmentMigratesOutOfHeroPhotoSlot() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let recipesURL = directory.appendingPathComponent("recipes.json")

        let legacyRecipe = Recipe(
            name: "Brie fondant",
            category: .entrees,
            ingredients: [],
            steps: [],
            imageData: makeJPEGData(),
            photoFilename: "legacy-card.png",
            generatedImagePrompt: "card prompt",
            generatedImageMode: RecipeImageMode.recipeCard.rawValue
        )

        let data = try JSONEncoder().encode([legacyRecipe])
        try data.write(to: recipesURL)

        let store = RecipeStore(
            recipesURL: recipesURL,
            groceryListURL: directory.appendingPathComponent("grocery.json"),
            shouldLoadSeedData: false,
            livePhotoDirectoryURL: directory.appendingPathComponent("RecipePhotos"),
            enablePhotoAutoRefresh: false,
            recipeImageStorage: RecipeImageStorage(
                directoryURL: directory.appendingPathComponent("RecipeImages", isDirectory: true)
            )
        )

        let migrated = try XCTUnwrap(store.recipes.first)
        XCTAssertNil(migrated.photoFilename)
        XCTAssertNil(migrated.imageData)
        XCTAssertEqual(migrated.recipeCardFilename, "legacy-card.png")
        XCTAssertEqual(migrated.generatedRecipeCardPrompt, "card prompt")
    }

    func testSyncPackageRoundTripPreservesRecipesImagesAndGroceryList() throws {
        let sourceDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)

        let sourceStore = try makeStore(directory: sourceDirectory)
        let livePhotoDirectory = sourceDirectory.appendingPathComponent("RecipePhotos", isDirectory: true)
        let imageStorage = RecipeImageStorage(
            directoryURL: sourceDirectory.appendingPathComponent("RecipeImages", isDirectory: true)
        )

        let recipe = Recipe(
            name: "Sync Package",
            category: .plats,
            ingredients: [.init(quantity: "2", name: "oeufs")],
            steps: ["Battre", "Cuire"],
            notes: "Version exportable"
        )
        sourceStore.add(recipe)

        var enrichedRecipe = try XCTUnwrap(sourceStore.recipes.first)
        let dishPhoto = try imageStorage.replaceImage(
            makeImage(size: CGSize(width: 32, height: 32), color: .systemBlue).pngData()!,
            for: enrichedRecipe,
            replacing: nil
        )
        let recipeCard = try imageStorage.replaceImage(
            makeImage(size: CGSize(width: 32, height: 32), color: .systemRed).pngData()!,
            for: enrichedRecipe,
            replacing: nil
        )
        enrichedRecipe.photoFilename = dishPhoto.filename
        enrichedRecipe.imageData = dishPhoto.data
        enrichedRecipe.generatedImageMode = RecipeImageMode.dishPhoto.rawValue
        enrichedRecipe.generatedImagePrompt = "photo prompt"
        enrichedRecipe.recipeCardFilename = recipeCard.filename
        enrichedRecipe.generatedRecipeCardPrompt = "card prompt"
        sourceStore.update(enrichedRecipe)

        try FileManager.default.createDirectory(at: livePhotoDirectory, withIntermediateDirectories: true)
        try makeJPEGData().write(to: livePhotoDirectory.appendingPathComponent("sync-package.jpg"))
        sourceStore.refreshRecipePhotosIfNeeded(force: true)
        sourceStore.createGroceryList(for: try XCTUnwrap(sourceStore.recipes.first))

        let exportResult = try sourceStore.exportSyncPackageToTemporaryFile()
        let packageData = try Data(contentsOf: exportResult.packageURL)

        let destinationDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        let destinationStore = try makeStore(directory: destinationDirectory)

        let importResult = try destinationStore.importSyncPackage(from: packageData)
        let restoredRecipe = try XCTUnwrap(destinationStore.recipes.first)

        XCTAssertEqual(destinationStore.recipes.count, 1)
        XCTAssertEqual(restoredRecipe.name, "Sync Package")
        XCTAssertEqual(importResult.recipeCount, 1)
        XCTAssertTrue(importResult.groceryListIncluded)
        XCTAssertNotNil(destinationStore.currentGroceryList)
        XCTAssertEqual(destinationStore.currentGroceryList?.recipeName, "Sync Package")
        XCTAssertNotNil(destinationStore.recipeImageURL(for: restoredRecipe))
        XCTAssertNotNil(destinationStore.recipeCardImageData(for: restoredRecipe))
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: destinationDirectory
                    .appendingPathComponent("RecipePhotos/sync-package.jpg")
                    .path
            )
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: importResult.backupURL.path))
    }

    func testPrepareSyncPackageExportIncludesFilenameAndPayload() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = try makeStore(directory: directory)

        store.add(Recipe(name: "Export Payload", category: .plats))
        let payload = try store.prepareSyncPackageExport()
        let decoded = try RecipeSyncPackage.decoder.decode(RecipeSyncPackage.self, from: payload.data)

        XCTAssertEqual(payload.filename, "MomRecette-Sync-Latest.json")
        XCTAssertEqual(payload.recipeCount, 1)
        XCTAssertEqual(decoded.recipes.count, 1)
        XCTAssertEqual(decoded.recipes.first?.name, "Export Payload")
    }

    func testSharedSyncQueueRoundTripTracksLastSequenceAndLatestRecipeUpdate() throws {
        let queueDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: queueDirectory, withIntermediateDirectories: true)
        let queueURL = queueDirectory.appendingPathComponent("MomRecette-Sync-Queue.json")

        let sourceStore = try makeStore(
            directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true),
            deviceIdentifier: "device-a",
            deviceName: "Device A"
        )
        let destinationStore = try makeStore(
            directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true),
            deviceIdentifier: "device-b",
            deviceName: "Device B"
        )

        let bootstrapPayload = try sourceStore.prepareSharedSyncQueueBootstrapPayload()
        try bootstrapPayload.data.write(to: queueURL)

        try sourceStore.rememberSharedSyncQueue(at: queueURL)
        try destinationStore.rememberSharedSyncQueue(at: queueURL)

        sourceStore.add(Recipe(name: "Queue Recipe", category: .plats, notes: "Version A"))

        let sourcePush = try sourceStore.synchronizeWithRememberedSharedQueue()
        XCTAssertEqual(sourcePush.pulledOperationCount, 0)
        XCTAssertEqual(sourcePush.pushedOperationCount, 1)
        XCTAssertEqual(sourcePush.lastAppliedQueueSequence, 1)
        XCTAssertEqual(sourceStore.sharedSyncQueueStatus.pendingOperationCount, 0)

        let destinationPull = try destinationStore.synchronizeWithRememberedSharedQueue()
        XCTAssertEqual(destinationPull.pulledOperationCount, 1)
        XCTAssertEqual(destinationPull.pushedOperationCount, 0)
        XCTAssertEqual(destinationPull.lastAppliedQueueSequence, 1)
        XCTAssertEqual(destinationStore.recipes.first?.name, "Queue Recipe")
        XCTAssertEqual(destinationStore.recipes.first?.notes, "Version A")

        var updatedRecipe = try XCTUnwrap(destinationStore.recipes.first)
        updatedRecipe.notes = "Version B"
        destinationStore.update(updatedRecipe)

        let destinationPush = try destinationStore.synchronizeWithRememberedSharedQueue()
        XCTAssertEqual(destinationPush.pulledOperationCount, 0)
        XCTAssertEqual(destinationPush.pushedOperationCount, 1)
        XCTAssertEqual(destinationPush.lastAppliedQueueSequence, 2)

        let sourcePull = try sourceStore.synchronizeWithRememberedSharedQueue()
        XCTAssertEqual(sourcePull.pulledOperationCount, 1)
        XCTAssertEqual(sourcePull.pushedOperationCount, 0)
        XCTAssertEqual(sourcePull.lastAppliedQueueSequence, 2)
        XCTAssertEqual(sourceStore.recipes.first?.notes, "Version B")

        let sourceNoOp = try sourceStore.synchronizeWithRememberedSharedQueue()
        XCTAssertEqual(sourceNoOp.pulledOperationCount, 0)
        XCTAssertEqual(sourceNoOp.pushedOperationCount, 0)
        XCTAssertEqual(sourceNoOp.lastAppliedQueueSequence, 2)
    }

    func testSharedSyncQueuePropagatesRecipeDelete() throws {
        let queueDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: queueDirectory, withIntermediateDirectories: true)
        let queueURL = queueDirectory.appendingPathComponent("MomRecette-Sync-Queue.json")

        let sourceStore = try makeStore(
            directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true),
            deviceIdentifier: "device-a",
            deviceName: "Device A"
        )
        let destinationStore = try makeStore(
            directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true),
            deviceIdentifier: "device-b",
            deviceName: "Device B"
        )

        let bootstrapPayload = try sourceStore.prepareSharedSyncQueueBootstrapPayload()
        try bootstrapPayload.data.write(to: queueURL)

        try sourceStore.rememberSharedSyncQueue(at: queueURL)
        try destinationStore.rememberSharedSyncQueue(at: queueURL)

        sourceStore.add(Recipe(name: "Delete Me", category: .plats))
        _ = try sourceStore.synchronizeWithRememberedSharedQueue()
        _ = try destinationStore.synchronizeWithRememberedSharedQueue()

        let recipeToDelete = try XCTUnwrap(sourceStore.recipes.first)
        sourceStore.delete(recipeToDelete)

        let deletePush = try sourceStore.synchronizeWithRememberedSharedQueue()
        XCTAssertEqual(deletePush.pushedOperationCount, 1)
        XCTAssertEqual(deletePush.lastAppliedQueueSequence, 2)

        let deletePull = try destinationStore.synchronizeWithRememberedSharedQueue()
        XCTAssertEqual(deletePull.pulledOperationCount, 1)
        XCTAssertTrue(destinationStore.recipes.isEmpty)
    }

    func testSharedSyncQueueCompactionKeepsLatestRecipeStateForStaleDevice() throws {
        let queueDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: queueDirectory, withIntermediateDirectories: true)
        let queueURL = queueDirectory.appendingPathComponent("MomRecette-Sync-Queue.json")

        let sourceStore = try makeStore(
            directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true),
            deviceIdentifier: "device-a",
            deviceName: "Device A"
        )
        let staleDestinationStore = try makeStore(
            directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true),
            deviceIdentifier: "device-c",
            deviceName: "Device C"
        )

        let bootstrapPayload = try sourceStore.prepareSharedSyncQueueBootstrapPayload()
        try bootstrapPayload.data.write(to: queueURL)

        try sourceStore.rememberSharedSyncQueue(at: queueURL)
        try staleDestinationStore.rememberSharedSyncQueue(at: queueURL)

        sourceStore.add(Recipe(name: "Compacted Recipe", category: .plats, notes: "v1"))
        _ = try sourceStore.synchronizeWithRememberedSharedQueue()

        var recipe = try XCTUnwrap(sourceStore.recipes.first)
        recipe.notes = "v2"
        sourceStore.update(recipe)
        let secondSync = try sourceStore.synchronizeWithRememberedSharedQueue()

        XCTAssertEqual(secondSync.compactedOperationCount, 1)

        let queueData = try Data(contentsOf: queueURL)
        let queue = try RecipeSyncPackage.decoder.decode(RecipeSyncQueue.self, from: queueData)
        XCTAssertEqual(queue.lastSequence, 2)
        XCTAssertEqual(queue.operations.count, 1)
        XCTAssertEqual(queue.operations.first?.sequence, 2)
        XCTAssertEqual(queue.operations.first?.recipe?.notes, "v2")

        let stalePull = try staleDestinationStore.synchronizeWithRememberedSharedQueue()
        XCTAssertEqual(stalePull.pulledOperationCount, 1)
        XCTAssertEqual(staleDestinationStore.recipes.first?.notes, "v2")
        XCTAssertEqual(staleDestinationStore.sharedSyncQueueStatus.lastAppliedQueueSequence, 2)
    }

    func testAutomaticSharedQueueSyncShowsNoticeWhenCheckpointIsUnknown() throws {
        let queueDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: queueDirectory, withIntermediateDirectories: true)
        let queueURL = queueDirectory.appendingPathComponent("MomRecette-Sync-Queue.json")

        let store = try makeStore(
            directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true),
            deviceIdentifier: "device-a",
            deviceName: "Device A"
        )

        let bootstrapPayload = try store.prepareSharedSyncQueueBootstrapPayload()
        try bootstrapPayload.data.write(to: queueURL)
        try store.rememberSharedSyncQueue(at: queueURL)

        store.performAutomaticSharedQueueSyncIfNeeded()

        XCTAssertEqual(store.syncStartupNotice?.title, "Sync en attente")
        XCTAssertTrue(store.syncStartupNotice?.message.contains("Aucune sauvegarde partagee") == true)
    }

    func testAutomaticSharedQueueSyncPullsLatestKnownChanges() throws {
        let queueDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: queueDirectory, withIntermediateDirectories: true)
        let queueURL = queueDirectory.appendingPathComponent("MomRecette-Sync-Queue.json")

        let sourceStore = try makeStore(
            directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true),
            deviceIdentifier: "device-a",
            deviceName: "Device A"
        )
        let destinationStore = try makeStore(
            directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true),
            deviceIdentifier: "device-b",
            deviceName: "Device B"
        )

        let bootstrapPayload = try sourceStore.prepareSharedSyncQueueBootstrapPayload()
        try bootstrapPayload.data.write(to: queueURL)

        try sourceStore.rememberSharedSyncQueue(at: queueURL)
        try destinationStore.rememberSharedSyncQueue(at: queueURL)

        sourceStore.add(Recipe(name: "Auto Sync", category: .plats, notes: "v1"))
        _ = try sourceStore.synchronizeWithRememberedSharedQueue()
        _ = try destinationStore.synchronizeWithRememberedSharedQueue()

        var updatedRecipe = try XCTUnwrap(sourceStore.recipes.first)
        updatedRecipe.notes = "v2"
        sourceStore.update(updatedRecipe)
        _ = try sourceStore.synchronizeWithRememberedSharedQueue()

        destinationStore.performAutomaticSharedQueueSyncIfNeeded()

        XCTAssertEqual(destinationStore.recipes.first?.notes, "v2")
        XCTAssertNil(destinationStore.syncStartupNotice)
        XCTAssertEqual(destinationStore.sharedSyncQueueStatus.lastAppliedQueueSequence, 2)
    }

    func testAutomaticSharedQueueSyncAutoDiscoversCanonicalQueuePath() throws {
        let sharedSyncRootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: sharedSyncRootURL, withIntermediateDirectories: true)

        let sourceStore = try makeStore(
            directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true),
            deviceIdentifier: "device-a",
            deviceName: "Device A",
            sharedSyncRootURL: sharedSyncRootURL
        )
        _ = try sourceStore.createOrRememberCanonicalSharedQueue()

        let destinationStore = try makeStore(
            directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true),
            deviceIdentifier: "device-b",
            deviceName: "Device B",
            sharedSyncRootURL: sharedSyncRootURL
        )

        destinationStore.performAutomaticSharedQueueSyncIfNeeded(force: true)

        XCTAssertTrue(destinationStore.sharedSyncQueueStatus.rememberedQueuePath?.hasSuffix("SharedSync/MomRecette-Sync-Queue.json") == true)
        XCTAssertEqual(destinationStore.syncStartupNotice?.title, "Sync en attente")
        XCTAssertTrue(destinationStore.syncStartupNotice?.message.contains("Aucune sauvegarde partagee") == true)
        XCTAssertTrue(destinationStore.sharedSyncBootstrapStatus.isAwaitingInitialSharedBackup)
    }

    func testCreateCanonicalSharedQueueOnEmptyStoreDoesNotPretendBootstrapIsAvailable() throws {
        let sharedSyncRootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: sharedSyncRootURL, withIntermediateDirectories: true)

        let store = try makeStore(
            directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true),
            deviceIdentifier: "device-a",
            deviceName: "Device A",
            sharedSyncRootURL: sharedSyncRootURL
        )

        _ = try store.createOrRememberCanonicalSharedQueue()
        store.performAutomaticSharedQueueSyncIfNeeded(force: true)

        XCTAssertFalse(store.sharedSyncBootstrapStatus.canRestoreFromLatestBackup)
        XCTAssertTrue(store.sharedSyncBootstrapStatus.isAwaitingInitialSharedBackup)
        XCTAssertTrue(store.syncStartupNotice?.message.contains("premiere sauvegarde partagee") == true)
    }

    func testCreateCanonicalSharedQueueSeedsLatestBackupAndKnownCheckpoint() throws {
        let sharedSyncRootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: sharedSyncRootURL, withIntermediateDirectories: true)

        let store = try makeStore(
            directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true),
            deviceIdentifier: "device-a",
            deviceName: "Device A",
            sharedSyncRootURL: sharedSyncRootURL
        )
        store.add(Recipe(name: "Seeded Backup", category: .plats, notes: "baseline"))

        let queueURL = try store.createOrRememberCanonicalSharedQueue()
        let latestBackupURL = sharedSyncRootURL
            .appendingPathComponent("SharedSync", isDirectory: true)
            .appendingPathComponent("MomRecette-Latest-Backup.json")

        XCTAssertTrue(FileManager.default.fileExists(atPath: queueURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: latestBackupURL.path))
        XCTAssertTrue(store.sharedSyncQueueStatus.hasResolvedCheckpoint)

        let backupData = try Data(contentsOf: latestBackupURL)
        let backupPackage = try RecipeSyncPackage.decoder.decode(RecipeSyncPackage.self, from: backupData)
        XCTAssertEqual(backupPackage.sharedQueueSequence, 0)
        XCTAssertEqual(backupPackage.recipes.first?.name, "Seeded Backup")
    }

    func testBootstrapFromLatestSharedBackupRestoresBaselineAndPullsRemainingQueueChanges() throws {
        let sharedSyncRootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: sharedSyncRootURL, withIntermediateDirectories: true)
        let latestBackupURL = sharedSyncRootURL
            .appendingPathComponent("SharedSync", isDirectory: true)
            .appendingPathComponent("MomRecette-Latest-Backup.json")

        let sourceStore = try makeStore(
            directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true),
            deviceIdentifier: "device-a",
            deviceName: "Device A",
            sharedSyncRootURL: sharedSyncRootURL
        )
        sourceStore.add(Recipe(name: "Shared Baseline", category: .plats, notes: "v0"))
        _ = try sourceStore.createOrRememberCanonicalSharedQueue()
        let staleBaselineData = try Data(contentsOf: latestBackupURL)

        var updatedSharedRecipe = try XCTUnwrap(sourceStore.recipes.first)
        updatedSharedRecipe.notes = "v1"
        sourceStore.update(updatedSharedRecipe)
        _ = try sourceStore.synchronizeWithRememberedSharedQueue()

        try staleBaselineData.write(to: latestBackupURL, options: .atomic)

        let destinationStore = try makeStore(
            directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true),
            deviceIdentifier: "device-b",
            deviceName: "Device B",
            sharedSyncRootURL: sharedSyncRootURL
        )
        destinationStore.add(Recipe(name: "Local Only", category: .desserts, notes: "keep me"))
        destinationStore.performAutomaticSharedQueueSyncIfNeeded(force: true)

        let bootstrapResult = try destinationStore.bootstrapFromLatestSharedBackup()
        let sharedRecipe = try XCTUnwrap(destinationStore.recipes.first(where: { $0.name == "Shared Baseline" }))
        let localRecipe = try XCTUnwrap(destinationStore.recipes.first(where: { $0.name == "Local Only" }))

        XCTAssertEqual(bootstrapResult.restoredRecipeCount, 1)
        XCTAssertEqual(bootstrapResult.mergedLocalRecipeCount, 1)
        XCTAssertEqual(sharedRecipe.notes, "v1")
        XCTAssertEqual(localRecipe.notes, "keep me")
        XCTAssertTrue(destinationStore.sharedSyncQueueStatus.hasResolvedCheckpoint)
        XCTAssertEqual(destinationStore.sharedSyncQueueStatus.lastAppliedQueueSequence, 2)
        XCTAssertNil(destinationStore.syncStartupNotice)
    }

    func testResolvedSharedSyncRootOverrideURLPrefersExplicitEnvironmentPath() {
        let url = MomRecetteSetup.SharedSync.resolvedRootOverrideURL(
            environment: [
                MomRecetteSetup.SharedSync.rootOverrideEnvironmentKey: "/tmp/MomRecette-SharedSync-Override",
                "SIMULATOR_HOST_HOME": "/Users/tester"
            ],
            isSimulatorRuntime: true
        )

        XCTAssertEqual(url?.path, "/tmp/MomRecette-SharedSync-Override")
    }

    func testResolvedSharedSyncRootOverrideURLFallsBackToStableSimulatorDocumentsPath() {
        let url = MomRecetteSetup.SharedSync.resolvedRootOverrideURL(
            environment: ["SIMULATOR_HOST_HOME": "/Users/tester"],
            isSimulatorRuntime: true
        )

        XCTAssertEqual(url?.path, "/Users/tester/Documents/MomRecette-Simulator")
    }

    func testResolvedSharedSyncRootOverrideURLDoesNotUseSimulatorFallbackOnDeviceRuntime() {
        let url = MomRecetteSetup.SharedSync.resolvedRootOverrideURL(
            environment: ["SIMULATOR_HOST_HOME": "/Users/tester"],
            isSimulatorRuntime: false
        )

        XCTAssertNil(url)
    }

    // Manual operator validation against the real local MomRecette library.
    // Keep this out of the default XCTest suite to avoid skipped-test noise.
    func manualLocalCloudSyncMigrationImportsRealMacLibraryWhenEnabled() throws {
        let localValidationFlagURL = URL(fileURLWithPath: "/tmp/MOMRECETTE_RUN_LOCAL_SYNC_VALIDATION.flag")
        let shouldRunValidation =
            ProcessInfo.processInfo.environment["MOMRECETTE_RUN_LOCAL_SYNC_VALIDATION"] == "1" ||
            FileManager.default.fileExists(atPath: localValidationFlagURL.path)

        guard shouldRunValidation else {
            throw XCTSkip("Set MOMRECETTE_RUN_LOCAL_SYNC_VALIDATION=1 to run the real-library migration validation.")
        }

        let documentsURL = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Containers/com.villeneuves.MomRecette/Data/Documents", isDirectory: true)
        let recipesURL = documentsURL.appendingPathComponent("momrecette.json")
        guard FileManager.default.fileExists(atPath: recipesURL.path) else {
            throw XCTSkip("No live MomRecette library was found at \(recipesURL.path).")
        }

        let validationRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("MomRecette-CloudSyncValidation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: validationRoot, withIntermediateDirectories: true)
        let validationStoreURL = validationRoot.appendingPathComponent("RecipeStore.sqlite")

        let store = RecipeStore(
            recipesURL: recipesURL,
            groceryListURL: documentsURL.appendingPathComponent("momrecette-grocery-list.json"),
            shouldLoadSeedData: false,
            livePhotoDirectoryURL: documentsURL.appendingPathComponent("RecipePhotos", isDirectory: true),
            enablePhotoAutoRefresh: false,
            recipeImageStorage: RecipeImageStorage(
                directoryURL: documentsURL.appendingPathComponent("RecipeImages", isDirectory: true)
            )
        )

        let backup = try store.createCloudSyncMigrationBackup(persistentStoreURL: validationStoreURL)
        XCTAssertFalse(backup.copiedItems.isEmpty)

        let persistentContainer = try RecipePersistentContainer(
            syncMode: .localOnly,
            storeURL: validationStoreURL
        )
        let report = try store.importLibraryIntoPersistentStore(persistentContainer)

        let countRequest = NSFetchRequest<NSFetchRequestResult>(entityName: RecipePersistentContainer.EntityName.recipe)
        let importedRecipeCount = try persistentContainer.viewContext.count(for: countRequest)

        print("""
        Local cloud sync validation:
        - backup: \(backup.backupRootURL.path)
        - processed recipes: \(report.processedRecipeCount)
        - inserted recipes: \(report.insertedRecipeCount)
        - updated recipes: \(report.updatedRecipeCount)
        - imported dish photos: \(report.importedDishPhotoAssetCount)
        - imported recipe cards: \(report.importedRecipeCardAssetCount)
        - imported live photos: \(report.importedLivePhotoAssetCount)
        - bundle-backed recipes: \(report.bundleBackedRecipeCount)
        - final recipe count: \(report.finalRecipeCount)
        - validation store: \(validationStoreURL.path)
        """)

        XCTAssertEqual(report.processedRecipeCount, store.recipes.count)
        XCTAssertEqual(report.finalRecipeCount, importedRecipeCount)
        XCTAssertGreaterThan(importedRecipeCount, 0)
        XCTAssertGreaterThanOrEqual(report.importedDishPhotoAssetCount + report.bundleBackedRecipeCount, 1)
    }

    // Manual operator validation against the real production persistent store.
    // Keep this out of the default XCTest suite to avoid skipped-test noise.
    func manualLocalCloudSyncCanonicalizesProductionStoreWhenEnabled() throws {
        let canonicalizationFlagURL = URL(fileURLWithPath: "/tmp/MOMRECETTE_RUN_PRODUCTION_STORE_CANONICALIZATION.flag")
        let shouldRunValidation =
            ProcessInfo.processInfo.environment["MOMRECETTE_RUN_PRODUCTION_STORE_CANONICALIZATION"] == "1" ||
            FileManager.default.fileExists(atPath: canonicalizationFlagURL.path)

        guard shouldRunValidation else {
            throw XCTSkip("Set MOMRECETTE_RUN_PRODUCTION_STORE_CANONICALIZATION=1 to run production-store canonicalization.")
        }

        let documentsURL = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Containers/com.villeneuves.MomRecette/Data/Documents", isDirectory: true)
        let recipesURL = documentsURL.appendingPathComponent("momrecette.json")
        guard FileManager.default.fileExists(atPath: recipesURL.path) else {
            throw XCTSkip("No live MomRecette library was found at \(recipesURL.path).")
        }

        let recipeData = try Data(contentsOf: recipesURL)
        let expectedRecipes = try JSONDecoder().decode([Recipe].self, from: recipeData)

        let productionStoreURL = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/MomRecette/RecipeStore.sqlite")
        let migrationKey = "MomRecette.PersistentStore.LegacyMigration.\(productionStoreURL.path.replacingOccurrences(of: "/", with: "_"))"
        UserDefaults.standard.removeObject(forKey: migrationKey)

        let persistentContainer = try RecipePersistentContainer(
            syncMode: .localOnly,
            storeURL: productionStoreURL
        )
        let store = RecipeStore(
            recipesURL: recipesURL,
            groceryListURL: documentsURL.appendingPathComponent("momrecette-grocery-list.json"),
            shouldLoadSeedData: false,
            livePhotoDirectoryURL: documentsURL.appendingPathComponent("RecipePhotos", isDirectory: true),
            enablePhotoAutoRefresh: false,
            recipeImageStorage: RecipeImageStorage(
                directoryURL: documentsURL.appendingPathComponent("RecipeImages", isDirectory: true)
            ),
            persistentContainer: persistentContainer
        )

        let countRequest = NSFetchRequest<NSFetchRequestResult>(entityName: RecipePersistentContainer.EntityName.recipe)
        let storedCount = try persistentContainer.viewContext.count(for: countRequest)

        XCTAssertEqual(store.recipes.count, expectedRecipes.count)
        XCTAssertEqual(storedCount, expectedRecipes.count)
    }
}
