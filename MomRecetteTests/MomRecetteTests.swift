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

    private func makeStore() throws -> RecipeStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        return RecipeStore(
            recipesURL: directory.appendingPathComponent("recipes.json"),
            groceryListURL: directory.appendingPathComponent("grocery-list.json"),
            shouldLoadSeedData: false,
            livePhotoDirectoryURL: directory.appendingPathComponent("RecipePhotos"),
            enablePhotoAutoRefresh: false
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
}
