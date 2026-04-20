import Foundation
import SwiftUI
import Combine
import UIKit
import EventKit

struct RecipeSyncPackage: Codable {
    struct StoredFile: Codable {
        let filename: String
        let data: Data
    }

    let formatVersion: Int
    let exportedAt: Date
    let sourceDeviceName: String
    let recipes: [Recipe]
    let groceryList: GroceryList?
    let generatedImages: [StoredFile]
    let livePhotos: [StoredFile]

    static let currentFormatVersion = 1

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    static func defaultFilename(for _: Date) -> String {
        "MomRecette-Sync-Latest.json"
    }
}

@MainActor
class RecipeStore: ObservableObject {
    struct CloudSyncPreparationReport {
        struct FileLocation {
            let label: String
            let url: URL
            let exists: Bool
        }

        let activeSyncModeTitle: String
        let activeCloudKitContainerIdentifier: String?
        let persistentStoreURL: URL?
        let recipeCount: Int
        let favoriteCount: Int
        let generatedDishPhotoCount: Int
        let generatedRecipeCardCount: Int
        let importedLivePhotoCount: Int
        let unreferencedGeneratedImageCount: Int
        let localStorageLocations: [FileLocation]
        let recommendedStrategy: String
    }

    enum RecipeCollection: Hashable, Identifiable {
        case all
        case favorites
        case category(Recipe.Category)

        var id: String {
            switch self {
            case .all:
                return "all"
            case .favorites:
                return "favorites"
            case .category(let category):
                return "category-\(category.rawValue)"
            }
        }

        var title: String {
            switch self {
            case .all:
                return "Toutes les recettes"
            case .favorites:
                return "Favoris"
            case .category(let category):
                return category.rawValue
            }
        }

        var systemImage: String {
            switch self {
            case .all:
                return "square.grid.2x2"
            case .favorites:
                return "star.fill"
            case .category:
                return "tag"
            }
        }
    }

    struct RecipePhotoBatchImportResult {
        var importedCount = 0
        var replacedCount = 0
        var unmatchedCount = 0
        var invalidCount = 0
        var failedCount = 0

        var appliedCount: Int { importedCount + replacedCount }
        var issueCount: Int { unmatchedCount + invalidCount + failedCount }
    }

    struct SyncPackageExportResult {
        let packageURL: URL
        let recipeCount: Int
        let generatedImageCount: Int
        let livePhotoCount: Int
        let groceryListIncluded: Bool
    }

    struct SyncPackageExportPayload {
        let filename: String
        let data: Data
        let recipeCount: Int
        let generatedImageCount: Int
        let livePhotoCount: Int
        let groceryListIncluded: Bool
    }

    struct SyncPackageImportResult {
        let recipeCount: Int
        let generatedImageCount: Int
        let livePhotoCount: Int
        let groceryListIncluded: Bool
        let backupURL: URL
    }

    enum SyncPackageError: LocalizedError {
        case invalidPackage

        var errorDescription: String? {
            switch self {
            case .invalidPackage:
                return "Ce fichier n'est pas un package MomRecette valide."
            }
        }
    }

    enum ReminderExportError: LocalizedError {
        case noActiveGroceryList
        case accessDenied
        case noWritableSource

        var errorDescription: String? {
            switch self {
            case .noActiveGroceryList:
                return "Aucune liste d'epicerie active n'est disponible."
            case .accessDenied:
                return "MomRecette n'a pas acces a Rappels."
            case .noWritableSource:
                return "Aucune liste Rappels modifiable n'est disponible."
            }
        }
    }

    enum RecipeImageError: LocalizedError {
        case recipeNotFound

        var errorDescription: String? {
            switch self {
            case .recipeNotFound:
                return "La recette demandee est introuvable."
            }
        }
    }

    @Published var recipes: [Recipe] = []
    @Published var currentGroceryList: GroceryList?
    @Published var searchText: String = ""
    @Published var selectedCollection: RecipeCollection = .all

    private let saveURL: URL
    private let groceryListURL: URL
    private let livePhotoDirectoryURL: URL
    private let recipeImageStorage: RecipeImageStorage
    private let recipeImagePromptBuilder: RecipeImagePromptBuilder
    private let recipeImageGenerator: any RecipeImageGenerating
    private let persistentContainer: RecipePersistentContainer?
    private let coreDataRepository: RecipeCoreDataRepository?
    private var bundledRecipePhotos: [String: Data]
    private var liveRecipePhotos: [String: Data]
    private var livePhotoDirectorySignature: String
    private var photoRefreshTimer: Timer?
    private let remindersStore = EKEventStore()

    init(
        recipesURL: URL? = nil,
        groceryListURL: URL? = nil,
        shouldLoadSeedData: Bool = true,
        livePhotoDirectoryURL: URL? = nil,
        enablePhotoAutoRefresh: Bool = true,
        recipeImageStorage: RecipeImageStorage? = nil,
        recipeImagePromptBuilder: RecipeImagePromptBuilder = RecipeImagePromptBuilder(),
        recipeImageGenerator: (any RecipeImageGenerating)? = nil,
        persistentContainer: RecipePersistentContainer? = nil
    ) {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        saveURL = recipesURL ?? docs.appendingPathComponent("momrecette.json")
        self.groceryListURL = groceryListURL ?? docs.appendingPathComponent("momrecette-grocery-list.json")
        self.livePhotoDirectoryURL = livePhotoDirectoryURL ?? docs.appendingPathComponent("RecipePhotos", isDirectory: true)
        self.recipeImageStorage = recipeImageStorage ?? RecipeImageStorage(
            directoryURL: docs.appendingPathComponent("RecipeImages", isDirectory: true)
        )
        self.recipeImagePromptBuilder = recipeImagePromptBuilder
        self.recipeImageGenerator = recipeImageGenerator ?? OpenAIRecipeImageGenerator(promptBuilder: recipeImagePromptBuilder)
        self.persistentContainer = persistentContainer
        if let persistentContainer {
            self.coreDataRepository = RecipeCoreDataRepository(
                persistentContainer: persistentContainer,
                livePhotoDirectoryURL: self.livePhotoDirectoryURL,
                generatedImageDirectoryURL: self.recipeImageStorage.directoryURL
            )
        } else {
            self.coreDataRepository = nil
        }
        bundledRecipePhotos = Self.loadBundledRecipePhotos()
        liveRecipePhotos = Self.loadRecipePhotos(from: self.livePhotoDirectoryURL)
        livePhotoDirectorySignature = Self.recipePhotoDirectorySignature(at: self.livePhotoDirectoryURL)

        migrateToPersistentStoreIfNeeded()
        load()
        loadGroceryList()
        hydratePhotosIfAvailable()
        if shouldLoadSeedData {
            mergeMissingBundledRecipesIfNeeded()
        }

        if shouldLoadSeedData && recipes.isEmpty {
            loadBundle()
        }
        if shouldLoadSeedData && recipes.isEmpty {
            recipes = Recipe.samples
            save()
        }

        if enablePhotoAutoRefresh {
            startPhotoRefreshTimer()
        }
    }

    deinit {
        photoRefreshTimer?.invalidate()
    }

    // MARK: - Filtered

    var filteredRecipes: [Recipe] {
        var list = recipes

        switch selectedCollection {
        case .all:
            break
        case .favorites:
            list = list.filter(\.isFavorite)
        case .category(let category):
            list = list.filter { $0.category == category }
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

    var favoriteCount: Int {
        recipes.filter(\.isFavorite).count
    }

    var recentRecipes: [Recipe] {
        recipes
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(6)
            .map { $0 }
    }

    // MARK: - CRUD

    func add(_ recipe: Recipe) {
        recipes.append(Self.sanitizedRecipe(recipe, source: "add"))
        save()
    }

    func update(_ recipe: Recipe) {
        if let idx = recipes.firstIndex(where: { $0.id == recipe.id }) {
            let existing = recipes[idx]
            var candidate = recipe

            if let existingFilename = existing.photoFilename {
                let imageDidChange = existing.imageData != recipe.imageData
                let shouldClearStoredImageReference = recipe.photoFilename == existingFilename && imageDidChange
                let shouldDeleteStoredImage = recipe.photoFilename != existingFilename || shouldClearStoredImageReference

                if shouldDeleteStoredImage {
                    try? recipeImageStorage.deleteImage(named: existingFilename)
                }

                if shouldClearStoredImageReference {
                    candidate.photoFilename = nil
                    candidate.generatedImagePrompt = nil
                    candidate.generatedImageMode = nil
                }
            }

            if let existingCardFilename = existing.recipeCardFilename,
               recipe.recipeCardFilename != existingCardFilename {
                try? recipeImageStorage.deleteImage(named: existingCardFilename)
            }

            recipes[idx] = Self.sanitizedRecipe(candidate, source: "update")
            save()
        }
    }

    func delete(_ recipe: Recipe) {
        if let photoFilename = recipe.photoFilename {
            try? recipeImageStorage.deleteImage(named: photoFilename)
        }
        if let recipeCardFilename = recipe.recipeCardFilename {
            try? recipeImageStorage.deleteImage(named: recipeCardFilename)
        }
        recipes.removeAll { $0.id == recipe.id }
        save()
    }

    func delete(at offsets: IndexSet, in list: [Recipe]) {
    let ids = offsets.map { list[$0].id }
    let recipesToDelete = recipes.filter { ids.contains($0.id) }
    recipesToDelete.compactMap(\.photoFilename).forEach { filename in
        try? recipeImageStorage.deleteImage(named: filename)
    }
    recipesToDelete.compactMap(\.recipeCardFilename).forEach { filename in
        try? recipeImageStorage.deleteImage(named: filename)
    }
    recipes.removeAll { ids.contains($0.id) }
    save()
    }

    func importRecipePhotos(from urls: [URL]) -> RecipePhotoBatchImportResult {
    let fileManager = FileManager.default
    try? fileManager.createDirectory(at: livePhotoDirectoryURL, withIntermediateDirectories: true)
    
    let knownRecipeKeys = Set(recipes.flatMap(\.photoLookupKeys))
    var result = RecipePhotoBatchImportResult()
    
    for url in urls {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }
    
        let lookupKey = url.deletingPathExtension().lastPathComponent.photoLookupKey
        guard !lookupKey.isEmpty, knownRecipeKeys.contains(lookupKey) else {
            result.unmatchedCount += 1
            continue
        }
    
        guard
            let sourceData = try? Data(contentsOf: url),
            let normalizedImageData = RecipePhotoImport.preparedJPEGData(from: sourceData)
        else {
            result.invalidCount += 1
            continue
        }
    
        let existingPhotoURLs = Self.photoFileURLs(for: lookupKey, in: livePhotoDirectoryURL)
        let destinationURL = livePhotoDirectoryURL.appendingPathComponent("\(lookupKey).jpg")
    
        do {
            try normalizedImageData.write(to: destinationURL, options: .atomic)
    
            for existingURL in existingPhotoURLs where existingURL.standardizedFileURL != destinationURL.standardizedFileURL {
                try? fileManager.removeItem(at: existingURL)
            }
    
            if existingPhotoURLs.isEmpty {
                result.importedCount += 1
            } else {
                result.replacedCount += 1
            }
        } catch {
            result.failedCount += 1
        }
    }
    
    if result.appliedCount > 0 {
        refreshRecipePhotosIfNeeded(force: true)
    }
    
    return result
    }

    // MARK: - Grocery List

    func createGroceryList(for recipe: Recipe) {
        currentGroceryList = GroceryList(recipe: recipe)
        saveGroceryList()
    }

    func toggleFavorite(for recipe: Recipe) {
        guard let index = recipes.firstIndex(where: { $0.id == recipe.id }) else { return }
        recipes[index].isFavorite.toggle()
        save()
    }

    func toggleGroceryItem(id: UUID) {
        guard var list = currentGroceryList,
              let index = list.items.firstIndex(where: { $0.id == id }) else { return }

        list.items[index].isChecked.toggle()
        currentGroceryList = list
        saveGroceryList()
    }

    func clearGroceryList() {
        currentGroceryList = nil

        do {
            if FileManager.default.fileExists(atPath: groceryListURL.path) {
                try FileManager.default.removeItem(at: groceryListURL)
            }
        } catch {
            print("RecipeStore clear grocery list error: \(error)")
        }
    }

    func exportCurrentGroceryListToReminders(for store: GroceryList.ExportStore) async throws -> Int {
        guard let currentGroceryList else {
            throw ReminderExportError.noActiveGroceryList
        }

        let accessGranted = try await requestRemindersAccess()
        guard accessGranted else {
            throw ReminderExportError.accessDenied
        }

        let calendar = try remindersCalendar(named: currentGroceryList.reminderListName(for: store))
        let metadataPrefix = currentGroceryList.reminderMetadataPrefix(for: store)
        let payloads = currentGroceryList.reminderPayloads(for: store)

        let existingReminders = await reminders(in: calendar)
        for reminder in existingReminders where reminder.notes?.hasPrefix(metadataPrefix) == true {
            try remindersStore.remove(reminder, commit: false)
        }

        for payload in payloads {
            let reminder = EKReminder(eventStore: remindersStore)
            reminder.title = payload.title
            reminder.notes = payload.notes
            reminder.calendar = calendar

            if payload.isCompleted {
                reminder.isCompleted = true
                reminder.completionDate = Date()
            }

            try remindersStore.save(reminder, commit: false)
        }

        try remindersStore.commit()
        return payloads.count
    }

    func generateRecipeImage(for recipe: Recipe, mode: RecipeImageMode, extraDetail: String?) async throws {
        guard let index = recipes.firstIndex(where: { $0.id == recipe.id }) else {
            throw RecipeImageError.recipeNotFound
        }

        let currentRecipe = recipes[index]
        let imageData = try await recipeImageGenerator.generateImage(
            for: currentRecipe,
            mode: mode,
            extraDetail: extraDetail
        )
        let prompt = recipeImagePromptBuilder.buildPrompt(
            for: currentRecipe,
            mode: mode,
            extraDetail: extraDetail
        )

        var updated = currentRecipe

        switch mode {
        case .dishPhoto:
            let storedImage = try recipeImageStorage.replaceImage(
                imageData,
                for: currentRecipe,
                replacing: currentRecipe.photoFilename
            )
            updated.photoFilename = storedImage.filename
            updated.generatedImagePrompt = prompt
            updated.generatedImageMode = mode.rawValue
            updated.imageData = storedImage.data
        case .recipeCard:
            let storedCard = try recipeImageStorage.replaceImage(
                imageData,
                for: currentRecipe,
                replacing: currentRecipe.recipeCardFilename
            )
            updated.recipeCardFilename = storedCard.filename
            updated.generatedRecipeCardPrompt = prompt
        }

        recipes[index] = Self.sanitizedRecipe(updated, source: "generated image")
        save()
    }

    func recipeImageURL(for recipe: Recipe) -> URL? {
        guard let filename = recipe.photoFilename else { return nil }
        let url = recipeImageStorage.imageURL(for: filename)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func recipeCardImageData(for recipe: Recipe) -> Data? {
        guard let filename = recipe.recipeCardFilename else { return nil }
        return recipeImageStorage.loadImage(named: filename)
    }

    func recipeCardImageURL(for recipe: Recipe) -> URL? {
        guard let filename = recipe.recipeCardFilename else { return nil }
        let url = recipeImageStorage.imageURL(for: filename)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    var syncBackupDirectoryURL: URL {
        saveURL
            .deletingLastPathComponent()
            .appendingPathComponent("SyncBackups", isDirectory: true)
    }

    func exportSyncPackageToTemporaryFile() throws -> SyncPackageExportResult {
        let payload = try prepareSyncPackageExport()
        let packageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(payload.filename)

        try FileManager.default.createDirectory(
            at: packageURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try payload.data.write(to: packageURL, options: .atomic)

        return SyncPackageExportResult(
            packageURL: packageURL,
            recipeCount: payload.recipeCount,
            generatedImageCount: payload.generatedImageCount,
            livePhotoCount: payload.livePhotoCount,
            groceryListIncluded: payload.groceryListIncluded
        )
    }

    func prepareSyncPackageExport() throws -> SyncPackageExportPayload {
        let package = try makeSyncPackage()
        return SyncPackageExportPayload(
            filename: RecipeSyncPackage.defaultFilename(for: package.exportedAt),
            data: try RecipeSyncPackage.encoder.encode(package),
            recipeCount: package.recipes.count,
            generatedImageCount: package.generatedImages.count,
            livePhotoCount: package.livePhotos.count,
            groceryListIncluded: package.groceryList != nil
        )
    }

    func importSyncPackage(from data: Data) throws -> SyncPackageImportResult {
        let package: RecipeSyncPackage

        do {
            package = try RecipeSyncPackage.decoder.decode(RecipeSyncPackage.self, from: data)
        } catch {
            throw SyncPackageError.invalidPackage
        }

        let backupURL = try createAutomaticSyncBackup()

        try replaceDirectoryContents(
            at: recipeImageStorage.directoryURL,
            with: package.generatedImages
        )
        try replaceDirectoryContents(
            at: livePhotoDirectoryURL,
            with: package.livePhotos
        )

        recipes = Self.reconciledRecipes(
            Self.sanitizedRecipes(package.recipes, source: "sync package")
        )
        save()

        if let groceryList = package.groceryList {
            currentGroceryList = groceryList
            saveGroceryList()
        } else {
            clearGroceryList()
        }

        livePhotoDirectorySignature = Self.recipePhotoDirectorySignature(at: livePhotoDirectoryURL)
        liveRecipePhotos = Self.loadRecipePhotos(from: livePhotoDirectoryURL)
        hydratePhotosIfAvailable()

        return SyncPackageImportResult(
            recipeCount: package.recipes.count,
            generatedImageCount: package.generatedImages.count,
            livePhotoCount: package.livePhotos.count,
            groceryListIncluded: package.groceryList != nil,
            backupURL: backupURL
        )
    }

    func cloudSyncPreparationReport() -> CloudSyncPreparationReport {
        let fileManager = FileManager.default
        let referencedGeneratedImages = Set(
            recipes.compactMap(\.photoFilename) +
            recipes.compactMap(\.recipeCardFilename)
        )

        let generatedImageFiles = (try? fileManager.contentsOfDirectory(
            at: recipeImageStorage.directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []

        let unreferencedGeneratedImageCount = generatedImageFiles.reduce(into: 0) { count, url in
            guard url.hasDirectoryPath == false else { return }
            if referencedGeneratedImages.contains(url.lastPathComponent) == false {
                count += 1
            }
        }

        let livePhotoFiles = (try? fileManager.contentsOfDirectory(
            at: livePhotoDirectoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []

        return CloudSyncPreparationReport(
            activeSyncModeTitle: activeSyncModeTitle,
            activeCloudKitContainerIdentifier: activeCloudKitContainerIdentifier,
            persistentStoreURL: persistentContainer?.storeURL,
            recipeCount: recipes.count,
            favoriteCount: favoriteCount,
            generatedDishPhotoCount: recipes.compactMap(\.photoFilename).count,
            generatedRecipeCardCount: recipes.compactMap(\.recipeCardFilename).count,
            importedLivePhotoCount: livePhotoFiles.filter { !$0.hasDirectoryPath }.count,
            unreferencedGeneratedImageCount: unreferencedGeneratedImageCount,
            localStorageLocations: [
                .init(label: "Recipe JSON", url: saveURL, exists: fileManager.fileExists(atPath: saveURL.path)),
                .init(label: "Grocery JSON", url: groceryListURL, exists: fileManager.fileExists(atPath: groceryListURL.path)),
                .init(label: "Generated Images", url: recipeImageStorage.directoryURL, exists: fileManager.fileExists(atPath: recipeImageStorage.directoryURL.path)),
                .init(label: "Imported Live Photos", url: livePhotoDirectoryURL, exists: fileManager.fileExists(atPath: livePhotoDirectoryURL.path))
            ],
            recommendedStrategy: "Core Data + NSPersistentCloudKitContainer"
        )
    }

    private var activeSyncModeTitle: String {
        guard let persistentContainer else {
            return "JSON local"
        }

        switch persistentContainer.syncMode {
        case .localOnly:
            return "Core Data local"
        case .cloudKit:
            return "Core Data + CloudKit"
        }
    }

    private var activeCloudKitContainerIdentifier: String? {
        guard let persistentContainer else { return nil }

        if case .cloudKit(let containerIdentifier) = persistentContainer.syncMode {
            return containerIdentifier
        }

        return nil
    }

    func cloudSyncMigrationPlan(
        persistentStoreURL: URL? = nil
    ) throws -> RecipeMigrationPlan {
        let coordinator = try RecipeMigrationCoordinator(
            documentsDirectoryURL: saveURL.deletingLastPathComponent(),
            persistentStoreURL: persistentStoreURL
        )
        return coordinator.makePlan(using: cloudSyncPreparationReport())
    }

    func createCloudSyncMigrationBackup(
        persistentStoreURL: URL? = nil
    ) throws -> RecipeMigrationBackup {
        let coordinator = try RecipeMigrationCoordinator(
            documentsDirectoryURL: saveURL.deletingLastPathComponent(),
            persistentStoreURL: persistentStoreURL
        )
        return try coordinator.createBackup(using: cloudSyncPreparationReport())
    }

    func importLibraryIntoPersistentStore(
        _ persistentContainer: RecipePersistentContainer
    ) throws -> RecipeCoreDataImportReport {
        let importer = RecipeCoreDataImporter(
            persistentContainer: persistentContainer,
            livePhotoDirectoryURL: livePhotoDirectoryURL,
            generatedImageDirectoryURL: recipeImageStorage.directoryURL
        )

        return try importer.importLibrary(recipes: recipes)
    }

    // MARK: - Persistence

    func save() {
        if let coreDataRepository {
            do {
                _ = try coreDataRepository.save(recipes: recipes)
            } catch {
                print("RecipeStore Core Data save error: \(error)")
            }
            return
        }

        saveJSONStore()
    }

    func load() {
        if let coreDataRepository {
            do {
                let loadedRecipes = Self.sanitizedRecipes(
                    try coreDataRepository.loadRecipes(),
                    source: "core data store"
                )
                let reconciledRecipes = Self.reconciledRecipes(loadedRecipes)
                recipes = reconciledRecipes

                if reconciledRecipes.count != loadedRecipes.count {
                    _ = try coreDataRepository.save(recipes: reconciledRecipes)
                }
            } catch {
                print("RecipeStore Core Data load error: \(error)")
                recipes = []
            }
            return
        }

        loadJSONStore()
    }

    private func saveGroceryList() {
        guard let currentGroceryList else { return }

        do {
            let data = try JSONEncoder().encode(currentGroceryList)
            try data.write(to: groceryListURL, options: .atomicWrite)
        } catch {
            print("RecipeStore save grocery list error: \(error)")
        }
    }

    private func loadGroceryList() {
        guard FileManager.default.fileExists(atPath: groceryListURL.path) else {
            loadBundledGroceryList()
            return
        }

        do {
            let data = try Data(contentsOf: groceryListURL)
            currentGroceryList = try JSONDecoder().decode(GroceryList.self, from: data)
        } catch {
            print("RecipeStore load grocery list error: \(error)")
        }
    }

    private func loadBundledGroceryList() {
        guard let url = Bundle.main.url(forResource: "momrecette-grocery-list", withExtension: "json") else { return }

        do {
            let data = try Data(contentsOf: url)
            currentGroceryList = try JSONDecoder().decode(GroceryList.self, from: data)
            saveGroceryList()
            print("RecipeStore: seeded grocery list from bundle")
        } catch {
            print("RecipeStore load bundled grocery list error: \(error)")
        }
    }

    private func saveJSONStore() {
        do {
            let data = try JSONEncoder().encode(recipes)
            try data.write(to: saveURL, options: .atomicWrite)
        } catch {
            print("RecipeStore save error: \(error)")
        }
    }

    private func loadJSONStore() {
        guard FileManager.default.fileExists(atPath: saveURL.path) else { return }
        do {
            let data = try Data(contentsOf: saveURL)
            let decoded = try JSONDecoder().decode([Recipe].self, from: data)
            recipes = Self.sanitizedRecipes(decoded, source: "saved recipes")
        } catch {
            print("RecipeStore load error: \(error)")
        }
    }

    private func migrateToPersistentStoreIfNeeded() {
        guard let persistentContainer, let coreDataRepository else { return }
        let migrationDefaultsKey = Self.persistentMigrationDefaultsKey(for: persistentContainer.storeURL)

        do {
            if UserDefaults.standard.bool(forKey: migrationDefaultsKey) {
                return
            }

            guard FileManager.default.fileExists(atPath: saveURL.path) else {
                if try coreDataRepository.isEmpty() == false {
                    UserDefaults.standard.set(true, forKey: migrationDefaultsKey)
                }
                return
            }

            loadJSONStore()
            hydratePhotosIfAvailable()
            guard recipes.isEmpty == false else {
                UserDefaults.standard.set(true, forKey: migrationDefaultsKey)
                return
            }

            _ = try createCloudSyncMigrationBackup(persistentStoreURL: persistentContainer.storeURL)
            _ = try coreDataRepository.save(recipes: recipes)
            UserDefaults.standard.set(true, forKey: migrationDefaultsKey)
            recipes.removeAll()
        } catch {
            print("RecipeStore persistent migration error: \(error)")
        }
    }

    private func loadBundle() {
        let bundledRecipes = loadBundledRecipes()
        guard !bundledRecipes.isEmpty else { return }
        recipes = Self.sanitizedRecipes(bundledRecipes, source: "bundle seed")
        hydratePhotosIfAvailable()
        save()
        print("RecipeStore: seeded \(recipes.count) recipes from bundle")
    }

    private func mergeMissingBundledRecipesIfNeeded() {
        let bundledRecipes = loadBundledRecipes()
        guard !bundledRecipes.isEmpty else { return }
        guard !recipes.isEmpty else { return }

        let existingKeys = Set(recipes.map(Self.bundleMergeKey))
        let missingBundledRecipes = bundledRecipes.filter { !existingKeys.contains(Self.bundleMergeKey(for: $0)) }
        guard !missingBundledRecipes.isEmpty else { return }

        recipes = Self.sanitizedRecipes(recipes + missingBundledRecipes, source: "bundle merge")
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        hydratePhotosIfAvailable()
        save()
        print("RecipeStore: merged \(missingBundledRecipes.count) bundled recipes into saved library")
    }

    private func loadBundledRecipes() -> [Recipe] {
        guard let url = Bundle.main.url(forResource: "momrecette_bundle", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let loaded = try? decoder.decode([LenientRecipe].self, from: data) else { return [] }
        return loaded.map { $0.toRecipe() }
    }

    func refreshRecipePhotosIfNeeded(force: Bool = false) {
        let currentSignature = Self.recipePhotoDirectorySignature(at: livePhotoDirectoryURL)
        guard force || currentSignature != livePhotoDirectorySignature else { return }

        livePhotoDirectorySignature = currentSignature
        liveRecipePhotos = Self.loadRecipePhotos(from: livePhotoDirectoryURL)
        hydratePhotosIfAvailable()
    }

    private func hydratePhotosIfAvailable() {
        let hasStoredGeneratedImages = recipes.contains { $0.photoFilename != nil }
        guard hasStoredGeneratedImages || !(bundledRecipePhotos.isEmpty && liveRecipePhotos.isEmpty) else { return }

        var didChange = false

        recipes = recipes.map { recipe in
            let sanitized = Self.sanitizedRecipe(recipe, source: "hydrate")

            if let storedPhotoData = storedPhotoData(for: sanitized),
               sanitized.imageData != storedPhotoData {
                var updated = sanitized
                updated.imageData = storedPhotoData
                didChange = true
                return updated
            }

            if sanitized.photoFilename != nil, sanitized.imageData != nil {
                return sanitized
            }

            if let livePhotoData = livePhotoData(for: sanitized),
               sanitized.imageData != livePhotoData {
                var updated = sanitized
                updated.imageData = livePhotoData
                didChange = true
                return updated
            }

            guard sanitized.imageData == nil else { return sanitized }
            guard let photoData = bundledPhotoData(for: sanitized) else { return sanitized }

            var updated = sanitized
            updated.imageData = photoData
            didChange = true
            return updated
        }

        if didChange {
            save()
        }
    }

    private func makeSyncPackage() throws -> RecipeSyncPackage {
        RecipeSyncPackage(
            formatVersion: RecipeSyncPackage.currentFormatVersion,
            exportedAt: Date(),
            sourceDeviceName: UIDevice.current.name,
            recipes: recipes,
            groceryList: currentGroceryList,
            generatedImages: try storedFiles(in: recipeImageStorage.directoryURL),
            livePhotos: try storedFiles(in: livePhotoDirectoryURL)
        )
    }

    private func storedFiles(in directoryURL: URL) throws -> [RecipeSyncPackage.StoredFile] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: directoryURL.path) else { return [] }

        let urls = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        return try urls.compactMap { url in
            guard url.hasDirectoryPath == false else { return nil }
            let data = try Data(contentsOf: url)
            return RecipeSyncPackage.StoredFile(
                filename: url.lastPathComponent,
                data: data
            )
        }
    }

    private func createAutomaticSyncBackup() throws -> URL {
        let backupDirectoryURL = syncBackupDirectoryURL
        try FileManager.default.createDirectory(at: backupDirectoryURL, withIntermediateDirectories: true)

        let package = try makeSyncPackage()
        let backupURL = backupDirectoryURL.appendingPathComponent(
            "MomRecette-Backup-\(UUID().uuidString)-\(RecipeSyncPackage.defaultFilename(for: package.exportedAt))"
        )
        try RecipeSyncPackage.encoder.encode(package).write(to: backupURL, options: .atomic)
        return backupURL
    }

    private func replaceDirectoryContents(
        at directoryURL: URL,
        with files: [RecipeSyncPackage.StoredFile]
    ) throws {
        let fileManager = FileManager.default
        let parentDirectoryURL = directoryURL.deletingLastPathComponent()
        let stagingDirectoryURL = parentDirectoryURL
            .appendingPathComponent(".\(directoryURL.lastPathComponent)-staging-\(UUID().uuidString)", isDirectory: true)

        try fileManager.createDirectory(at: stagingDirectoryURL, withIntermediateDirectories: true)

        do {
            for file in files {
                let sanitizedFilename = URL(fileURLWithPath: file.filename).lastPathComponent
                guard !sanitizedFilename.isEmpty else { continue }
                let destinationURL = stagingDirectoryURL.appendingPathComponent(sanitizedFilename)
                try file.data.write(to: destinationURL, options: .atomic)
            }

            if fileManager.fileExists(atPath: directoryURL.path) {
                try fileManager.removeItem(at: directoryURL)
            }

            try fileManager.moveItem(at: stagingDirectoryURL, to: directoryURL)
        } catch {
            try? fileManager.removeItem(at: stagingDirectoryURL)
            throw error
        }
    }

    private func storedPhotoData(for recipe: Recipe) -> Data? {
        guard let photoFilename = recipe.photoFilename else { return nil }
        return recipeImageStorage.loadImage(named: photoFilename)
    }

    private func livePhotoData(for recipe: Recipe) -> Data? {
        for key in recipe.photoLookupKeys {
            if let data = liveRecipePhotos[key] {
                return data
            }
        }
        return nil
    }

    private func bundledPhotoData(for recipe: Recipe) -> Data? {
        for key in recipe.photoLookupKeys {
            if let data = bundledRecipePhotos[key] {
                return data
            }
        }
        return nil
    }

    private func startPhotoRefreshTimer() {
        photoRefreshTimer?.invalidate()
        photoRefreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.refreshRecipePhotosIfNeeded()
            }
        }
    }

    private func requestRemindersAccess() async throws -> Bool {
        if #available(iOS 17.0, macCatalyst 17.0, *) {
            return try await remindersStore.requestFullAccessToReminders()
        }

        return try await withCheckedThrowingContinuation { continuation in
            remindersStore.requestAccess(to: .reminder) { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    private func remindersCalendar(named name: String) throws -> EKCalendar {
        if let existingCalendar = remindersStore.calendars(for: .reminder).first(where: { $0.title == name }) {
            return existingCalendar
        }

        guard let source = remindersStore.defaultCalendarForNewReminders()?.source ?? writableReminderSource() else {
            throw ReminderExportError.noWritableSource
        }

        let calendar = EKCalendar(for: .reminder, eventStore: remindersStore)
        calendar.title = name
        calendar.source = source
        try remindersStore.saveCalendar(calendar, commit: true)
        return calendar
    }

    private func writableReminderSource() -> EKSource? {
        remindersStore.sources.first { source in
            switch source.sourceType {
            case .local, .calDAV, .exchange, .mobileMe:
                return true
            default:
                return false
            }
        }
    }

    private func reminders(in calendar: EKCalendar) async -> [EKReminder] {
        let predicate = remindersStore.predicateForReminders(in: [calendar])
        return await withCheckedContinuation { continuation in
            remindersStore.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: reminders ?? [])
            }
        }
    }

    private static func recipePhotoDirectorySignature(at directoryURL: URL) -> String {
    let fileManager = FileManager.default
    try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    
    let resourceKeys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey]
    let urls = photoFileURLs(in: directoryURL, includingPropertiesForKeys: Array(resourceKeys))
    
    return urls
        .map { url in
            let values = try? url.resourceValues(forKeys: resourceKeys)
            let modified = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
            let size = values?.fileSize ?? 0
            return "\(url.lastPathComponent):\(modified):\(size)"
        }
        .joined(separator: "|")
    }

    private static func loadRecipePhotos(from directoryURL: URL) -> [String: Data] {
    let fileManager = FileManager.default
    try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

    let resourceKeys: [URLResourceKey] = [.contentModificationDateKey]
    let urls = photoFileURLs(in: directoryURL, includingPropertiesForKeys: resourceKeys)
    var candidates: [String: (data: Data, modified: Date, extensionRank: Int)] = [:]

    for url in urls {
        let key = url.deletingPathExtension().lastPathComponent.photoLookupKey
        guard let data = try? Data(contentsOf: url) else { continue }
        guard let validated = validatedImageData(data, source: "live photo file", name: url.lastPathComponent) else {
            continue
        }

        let values = try? url.resourceValues(forKeys: Set(resourceKeys))
        let modified = values?.contentModificationDate ?? .distantPast
        let extensionRank = supportedRecipePhotoExtensions.firstIndex(of: url.pathExtension.lowercased()) ?? supportedRecipePhotoExtensions.count

        if let existing = candidates[key] {
            if existing.modified > modified {
                continue
            }
            if existing.modified == modified && existing.extensionRank <= extensionRank {
                continue
            }
        }

        candidates[key] = (validated, modified, extensionRank)
    }

    return candidates.mapValues(\.data)
    }

    private static func loadBundledRecipePhotos() -> [String: Data] {
    var photos: [String: Data] = [:]
    
    for ext in supportedRecipePhotoExtensions {
        let bundledURLs =
            (Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: "RecipePhotos") ?? []) +
            (Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: nil) ?? [])
    
        for url in sortedPhotoURLs(bundledURLs) {
            let key = url.deletingPathExtension().lastPathComponent.photoLookupKey
            guard photos[key] == nil, let data = try? Data(contentsOf: url) else { continue }
            guard let validated = validatedImageData(data, source: "bundled photo file", name: url.lastPathComponent) else {
                continue
            }
            photos[key] = validated
        }
    }
    
    return photos
    }

    private static func sanitizedRecipes(_ recipes: [Recipe], source: String) -> [Recipe] {
        recipes.map { sanitizedRecipe($0, source: source) }
    }

    private static func reconciledRecipes(_ recipes: [Recipe]) -> [Recipe] {
        var recipesByKey: [String: Recipe] = [:]

        for recipe in recipes {
            let key = bundleMergeKey(for: recipe)
            guard let existing = recipesByKey[key] else {
                recipesByKey[key] = recipe
                continue
            }

            recipesByKey[key] = mergedRecipe(existing, recipe)
        }

        return recipesByKey.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func bundleMergeKey(for recipe: Recipe) -> String {
        "\(recipe.category.rawValue.foldedForMatching)|\(recipe.name.foldedForMatching)"
    }

    private static func mergedRecipe(_ lhs: Recipe, _ rhs: Recipe) -> Recipe {
        let primary: Recipe
        let secondary: Recipe

        if recipeQualityScore(lhs) >= recipeQualityScore(rhs) {
            primary = lhs
            secondary = rhs
        } else {
            primary = rhs
            secondary = lhs
        }

        var merged = primary
        merged.servings = max(primary.servings, secondary.servings)
        merged.caloriesPerServing = primary.caloriesPerServing ?? secondary.caloriesPerServing
        merged.prepTime = max(primary.prepTime, secondary.prepTime)
        merged.cookTime = max(primary.cookTime, secondary.cookTime)
        merged.ingredients = richer(primary.ingredients, secondary.ingredients)
        merged.steps = richer(primary.steps, secondary.steps)
        merged.notes = richer(primary.notes, secondary.notes)
        merged.isFavorite = primary.isFavorite || secondary.isFavorite
        merged.photoFilename = primary.photoFilename ?? secondary.photoFilename
        merged.generatedImagePrompt = merged.photoFilename == primary.photoFilename
            ? primary.generatedImagePrompt ?? secondary.generatedImagePrompt
            : secondary.generatedImagePrompt ?? primary.generatedImagePrompt
        merged.generatedImageMode = merged.photoFilename == primary.photoFilename
            ? primary.generatedImageMode ?? secondary.generatedImageMode
            : secondary.generatedImageMode ?? primary.generatedImageMode
        merged.imageData = primary.imageData ?? secondary.imageData
        merged.recipeCardFilename = primary.recipeCardFilename ?? secondary.recipeCardFilename
        merged.generatedRecipeCardPrompt = merged.recipeCardFilename == primary.recipeCardFilename
            ? primary.generatedRecipeCardPrompt ?? secondary.generatedRecipeCardPrompt
            : secondary.generatedRecipeCardPrompt ?? primary.generatedRecipeCardPrompt
        merged.createdAt = min(primary.createdAt, secondary.createdAt)
        return merged
    }

    private static func recipeQualityScore(_ recipe: Recipe) -> Int {
        var score = 0
        score += recipe.ingredients.count * 4
        score += recipe.steps.count * 4
        score += recipe.notes.isEmpty ? 0 : min(recipe.notes.count, 40)
        score += recipe.imageData == nil ? 0 : 25
        score += recipe.photoFilename == nil ? 0 : 20
        score += recipe.recipeCardFilename == nil ? 0 : 16
        score += recipe.isFavorite ? 12 : 0
        score += recipe.caloriesPerServing == nil ? 0 : 4
        return score
    }

    private static func richer<T>(_ lhs: [T], _ rhs: [T]) -> [T] {
        lhs.count >= rhs.count ? lhs : rhs
    }

    private static func richer(_ lhs: String, _ rhs: String) -> String {
        lhs.count >= rhs.count ? lhs : rhs
    }

    private static func sanitizedRecipe(_ recipe: Recipe, source: String) -> Recipe {
        var sanitized = recipe

        if let caloriesPerServing = sanitized.caloriesPerServing, caloriesPerServing <= 0 {
            sanitized.caloriesPerServing = nil
        }

        if sanitized.generatedImageMode == RecipeImageMode.recipeCard.rawValue,
           sanitized.recipeCardFilename == nil,
           let legacyCardFilename = sanitized.photoFilename {
            sanitized.recipeCardFilename = legacyCardFilename
            sanitized.generatedRecipeCardPrompt = sanitized.generatedImagePrompt
            sanitized.photoFilename = nil
            sanitized.generatedImagePrompt = nil
            sanitized.generatedImageMode = nil
            sanitized.imageData = nil
        }

        guard let imageData = sanitized.imageData else { return sanitized }
        guard let validated = validatedImageData(imageData, source: source, name: sanitized.name) else {
            sanitized.imageData = nil
            return sanitized
        }
        sanitized.imageData = validated
        return sanitized
    }

    private static func validatedImageData(_ data: Data, source: String, name: String) -> Data? {
        guard UIImage(data: data) != nil else {
            print("RecipeStore image validation dropped invalid data from \(source): \(name)")
            return nil
        }
        return data
    }

    private static func persistentMigrationDefaultsKey(for storeURL: URL) -> String {
        "MomRecette.PersistentStore.LegacyMigration.\(storeURL.path.replacingOccurrences(of: "/", with: "_"))"
    }

    private static let supportedRecipePhotoExtensions = ["jpg", "jpeg", "png", "webp"]

    private static func photoFileURLs(
        in directoryURL: URL,
        includingPropertiesForKeys resourceKeys: [URLResourceKey]? = nil
    ) -> [URL] {
        let fileManager = FileManager.default
        let urls = (try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsHiddenFiles]
        )) ?? []

        return sortedPhotoURLs(urls.filter { supportedRecipePhotoExtensions.contains($0.pathExtension.lowercased()) })
    }

    private static func photoFileURLs(for lookupKey: String, in directoryURL: URL) -> [URL] {
        photoFileURLs(in: directoryURL).filter {
            $0.deletingPathExtension().lastPathComponent.photoLookupKey == lookupKey
        }
    }

    private static func sortedPhotoURLs(_ urls: [URL]) -> [URL] {
        urls.sorted { lhs, rhs in
            let lhsKey = lhs.deletingPathExtension().lastPathComponent.photoLookupKey
            let rhsKey = rhs.deletingPathExtension().lastPathComponent.photoLookupKey

            if lhsKey == rhsKey {
                let lhsExtensionRank = supportedRecipePhotoExtensions.firstIndex(of: lhs.pathExtension.lowercased()) ?? supportedRecipePhotoExtensions.count
                let rhsExtensionRank = supportedRecipePhotoExtensions.firstIndex(of: rhs.pathExtension.lowercased()) ?? supportedRecipePhotoExtensions.count

                if lhsExtensionRank == rhsExtensionRank {
                    return lhs.lastPathComponent < rhs.lastPathComponent
                }

                return lhsExtensionRank < rhsExtensionRank
            }

            return lhsKey < rhsKey
        }
    }
}
