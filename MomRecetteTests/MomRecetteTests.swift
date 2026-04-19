import XCTest
@testable import MomRecette
import UIKit

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
        recipeImageGenerator: (any RecipeImageGenerating)? = nil
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
            recipeImageGenerator: recipeImageGenerator
        )
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
}
