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
    let sharedQueueSequence: Int?
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

struct RecipeSyncQueue: Codable {
    struct Operation: Codable, Identifiable {
        enum Kind: String, Codable {
            case upsertRecipe
            case deleteRecipe
            case replaceGroceryList
            case clearGroceryList
        }

        let id: UUID
        var sequence: Int?
        let createdAt: Date
        let sourceDeviceID: String
        let sourceDeviceName: String
        let kind: Kind
        let recipe: Recipe?
        let recipeID: UUID?
        let groceryList: GroceryList?
        let generatedImages: [RecipeSyncPackage.StoredFile]
        let livePhotos: [RecipeSyncPackage.StoredFile]

        init(
            id: UUID = UUID(),
            sequence: Int? = nil,
            createdAt: Date = Date(),
            sourceDeviceID: String,
            sourceDeviceName: String,
            kind: Kind,
            recipe: Recipe? = nil,
            recipeID: UUID? = nil,
            groceryList: GroceryList? = nil,
            generatedImages: [RecipeSyncPackage.StoredFile] = [],
            livePhotos: [RecipeSyncPackage.StoredFile] = []
        ) {
            self.id = id
            self.sequence = sequence
            self.createdAt = createdAt
            self.sourceDeviceID = sourceDeviceID
            self.sourceDeviceName = sourceDeviceName
            self.kind = kind
            self.recipe = recipe
            self.recipeID = recipeID
            self.groceryList = groceryList
            self.generatedImages = generatedImages
            self.livePhotos = livePhotos
        }
    }

    let formatVersion: Int
    var lastSequence: Int
    var operations: [Operation]

    static let currentFormatVersion = 1
    static let defaultFilename = "MomRecette-Sync-Queue.json"
}

private struct RecipeSyncLocalState: Codable {
    let formatVersion: Int
    var lastAppliedQueueSequence: Int
    var hasResolvedQueueCheckpoint: Bool
    var lastSynchronizedAt: Date?
    var rememberedQueueBookmark: Data?
    var rememberedQueuePath: String?
    var pendingOperations: [RecipeSyncQueue.Operation]

    init(
        formatVersion: Int = 1,
        lastAppliedQueueSequence: Int = 0,
        hasResolvedQueueCheckpoint: Bool = false,
        lastSynchronizedAt: Date? = nil,
        rememberedQueueBookmark: Data? = nil,
        rememberedQueuePath: String? = nil,
        pendingOperations: [RecipeSyncQueue.Operation] = []
    ) {
        self.formatVersion = formatVersion
        self.lastAppliedQueueSequence = lastAppliedQueueSequence
        self.hasResolvedQueueCheckpoint = hasResolvedQueueCheckpoint
        self.lastSynchronizedAt = lastSynchronizedAt
        self.rememberedQueueBookmark = rememberedQueueBookmark
        self.rememberedQueuePath = rememberedQueuePath
        self.pendingOperations = pendingOperations
    }
}

@MainActor
class RecipeStore: ObservableObject {
    private struct SharedSyncLocations {
        let directoryURL: URL
        let queueURL: URL
        let latestBackupURL: URL
        let archivedBackupsDirectoryURL: URL
    }

    private struct PreservedBootstrapRecipe {
        let recipe: Recipe
        let generatedImages: [RecipeSyncPackage.StoredFile]
        let livePhotos: [RecipeSyncPackage.StoredFile]
    }

    struct SyncStartupNotice: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    struct SharedSyncQueueStatus {
        let rememberedQueuePath: String?
        let lastAppliedQueueSequence: Int
        let hasResolvedCheckpoint: Bool
        let lastSynchronizedAt: Date?
        let pendingOperationCount: Int
    }

    struct SharedSyncBootstrapStatus {
        let canonicalSharedSyncPath: String?
        let canonicalQueuePath: String?
        let latestBackupPath: String?
        let iCloudAvailable: Bool
        let usesLocalOverride: Bool
        let hasLocalLibraryData: Bool
        let latestBackupExists: Bool
        let requiresBootstrap: Bool
        let canRestoreFromLatestBackup: Bool
        let isAwaitingInitialSharedBackup: Bool
    }

    struct SharedSyncQueueBootstrapPayload {
        let filename: String
        let data: Data
    }

    struct SharedSyncQueueSyncResult {
        let queueURL: URL
        let pulledOperationCount: Int
        let pushedOperationCount: Int
        let lastAppliedQueueSequence: Int
        let createdQueue: Bool
        let compactedOperationCount: Int
        let retainedOperationCount: Int
    }

    struct SharedSyncBootstrapResult {
        let latestBackupURL: URL
        let localBackupURL: URL
        let restoredRecipeCount: Int
        let mergedLocalRecipeCount: Int
        let queueSyncResult: SharedSyncQueueSyncResult
    }

    enum SharedSyncQueueError: LocalizedError {
        case noRememberedQueue
        case invalidQueue
        case iCloudSharedSyncUnavailable
        case missingSharedBackup
        case invalidSharedBackup

        var errorDescription: String? {
            switch self {
            case .noRememberedQueue:
                return "Aucune queue partagee memorisee pour cet appareil."
            case .invalidQueue:
                return "Le fichier de queue partagee est invalide."
            case .iCloudSharedSyncUnavailable:
                return "Le dossier SharedSync iCloud n'est pas disponible sur cet appareil."
            case .missingSharedBackup:
                return "Aucune sauvegarde partagee recente n'est disponible dans SharedSync."
            case .invalidSharedBackup:
                return "La sauvegarde partagee la plus recente est invalide."
            }
        }
    }

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
    @Published var syncStartupNotice: SyncStartupNotice?

    private let saveURL: URL
    private let groceryListURL: URL
    private let livePhotoDirectoryURL: URL
    private let recipeImageStorage: RecipeImageStorage
    private let recipeImagePromptBuilder: RecipeImagePromptBuilder
    private let recipeImageGenerator: any RecipeImageGenerating
    private let persistentContainer: RecipePersistentContainer?
    private let coreDataRepository: RecipeCoreDataRepository?
    private let deviceIdentifier: String
    private let deviceName: String
    private let syncStateURL: URL
    private let sharedSyncRootOverrideURL: URL?
    private var bundledRecipePhotos: [String: Data]
    private var liveRecipePhotos: [String: Data]
    private var livePhotoDirectorySignature: String
    private var photoRefreshTimer: Timer?
    private var syncLocalState: RecipeSyncLocalState
    private var lastAutomaticSharedQueueSyncAttemptAt: Date?
    private let remindersStore = EKEventStore()
    private let automaticSharedQueueSyncMinimumInterval: TimeInterval = 180
    private static let sharedSyncDirectoryName = "SharedSync"
    private static let sharedSyncLatestBackupFilename = "MomRecette-Latest-Backup.json"
    private static let sharedSyncArchivedBackupsDirectoryName = "Backups"
    private static let sharedSyncArchivedBackupRetentionCount = 20

    init(
        recipesURL: URL? = nil,
        groceryListURL: URL? = nil,
        shouldLoadSeedData: Bool = true,
        livePhotoDirectoryURL: URL? = nil,
        enablePhotoAutoRefresh: Bool = true,
        recipeImageStorage: RecipeImageStorage? = nil,
        recipeImagePromptBuilder: RecipeImagePromptBuilder = RecipeImagePromptBuilder(),
        recipeImageGenerator: (any RecipeImageGenerating)? = nil,
        persistentContainer: RecipePersistentContainer? = nil,
        deviceIdentifier: String? = nil,
        deviceName: String? = nil,
        sharedSyncRootURL: URL? = nil
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
        self.deviceIdentifier = deviceIdentifier ?? persistentContainer?.deviceIdentifier ?? RecipePersistentContainer.resolveDeviceIdentifier()
        self.deviceName = deviceName ?? UIDevice.current.name
        self.syncStateURL = self.saveURL.deletingLastPathComponent().appendingPathComponent("momrecette-sync-state.json")
        self.syncLocalState = Self.loadSyncLocalState(from: self.syncStateURL)
        if self.syncLocalState.lastAppliedQueueSequence > 0 {
            self.syncLocalState.hasResolvedQueueCheckpoint = true
        }
        self.sharedSyncRootOverrideURL = sharedSyncRootURL
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

    var sharedSyncQueueStatus: SharedSyncQueueStatus {
        SharedSyncQueueStatus(
            rememberedQueuePath: syncLocalState.rememberedQueuePath,
            lastAppliedQueueSequence: syncLocalState.lastAppliedQueueSequence,
            hasResolvedCheckpoint: syncLocalState.hasResolvedQueueCheckpoint,
            lastSynchronizedAt: syncLocalState.lastSynchronizedAt,
            pendingOperationCount: syncLocalState.pendingOperations.count
        )
    }

    var sharedSyncBootstrapStatus: SharedSyncBootstrapStatus {
        let locations = canonicalSharedSyncLocations()
        let latestBackupExists = locations.map { FileManager.default.fileExists(atPath: $0.latestBackupURL.path) } ?? false
        let hasLocalLibraryData = recipes.isEmpty == false || currentGroceryList != nil
        let requiresBootstrap = syncLocalState.hasResolvedQueueCheckpoint == false && (hasRememberedSharedQueue || latestBackupExists)
        return SharedSyncBootstrapStatus(
            canonicalSharedSyncPath: locations?.directoryURL.path,
            canonicalQueuePath: locations?.queueURL.path,
            latestBackupPath: locations?.latestBackupURL.path,
            iCloudAvailable: locations != nil,
            usesLocalOverride: sharedSyncRootOverrideURL != nil,
            hasLocalLibraryData: hasLocalLibraryData,
            latestBackupExists: latestBackupExists,
            requiresBootstrap: requiresBootstrap,
            canRestoreFromLatestBackup: syncLocalState.hasResolvedQueueCheckpoint == false && latestBackupExists,
            isAwaitingInitialSharedBackup: requiresBootstrap && latestBackupExists == false
        )
    }

    func performAutomaticSharedQueueSyncIfNeeded(force: Bool = false) {
        let now = Date()
        if force == false,
           let lastAttempt = lastAutomaticSharedQueueSyncAttemptAt,
           now.timeIntervalSince(lastAttempt) < automaticSharedQueueSyncMinimumInterval {
            return
        }
        lastAutomaticSharedQueueSyncAttemptAt = now

        autoConfigureCanonicalSharedSyncQueueIfPossible()

        guard hasRememberedSharedQueue else {
            if canonicalSharedSyncLocations() == nil {
                syncStartupNotice = SyncStartupNotice(
                    title: "Sync iCloud indisponible",
                    message: "Le dossier SharedSync iCloud n'est pas accessible pour l'instant. Verifiez iCloud Drive puis reouvrez MomRecette."
                )
            } else {
                syncStartupNotice = SyncStartupNotice(
                    title: "Sync non configure",
                    message: "Cet appareil ne connait pas encore la queue partagee. Ouvrez Sync et activez la queue iCloud ou choisissez une queue valide."
                )
            }
            return
        }

        guard syncLocalState.hasResolvedQueueCheckpoint else {
            let bootstrapStatus = sharedSyncBootstrapStatus
            syncStartupNotice = SyncStartupNotice(
                title: "Sync en attente",
                message: startupNoticeMessage(for: bootstrapStatus)
            )
            return
        }

        do {
            _ = try synchronizeWithRememberedSharedQueue()
        } catch SharedSyncQueueError.noRememberedQueue {
            syncStartupNotice = SyncStartupNotice(
                title: "Sync non configure",
                message: "La queue partagee memorisee n'est plus disponible. Ouvrez Sync et choisissez-la de nouveau."
            )
        } catch SharedSyncQueueError.invalidQueue {
            syncStartupNotice = SyncStartupNotice(
                title: "Queue partagee invalide",
                message: "Le fichier de sync memorise ne peut pas etre lu. Ouvrez Sync et choisissez une queue valide."
            )
        } catch SharedSyncQueueError.iCloudSharedSyncUnavailable {
            syncStartupNotice = SyncStartupNotice(
                title: "Sync iCloud indisponible",
                message: "Le dossier SharedSync iCloud n'est pas accessible pour l'instant. Reessayez quand iCloud Drive sera revenu."
            )
        } catch {
            syncStartupNotice = SyncStartupNotice(
                title: "Sync interrompu",
                message: error.localizedDescription
            )
        }
    }

    func createOrRememberCanonicalSharedQueue() throws -> URL {
        guard let locations = canonicalSharedSyncLocations() else {
            throw SharedSyncQueueError.iCloudSharedSyncUnavailable
        }

        try FileManager.default.createDirectory(at: locations.archivedBackupsDirectoryURL, withIntermediateDirectories: true)
        let hadLatestBackup = FileManager.default.fileExists(atPath: locations.latestBackupURL.path)

        if FileManager.default.fileExists(atPath: locations.queueURL.path) == false {
            let queue = RecipeSyncQueue(
                formatVersion: RecipeSyncQueue.currentFormatVersion,
                lastSequence: 0,
                operations: []
            )
            try saveSharedSyncQueue(queue, to: locations.queueURL)
        }

        try rememberSharedSyncQueue(at: locations.queueURL)

        if hadLatestBackup == false, recipes.isEmpty == false || currentGroceryList != nil {
            try writeLatestSharedSyncBackup(sharedQueueSequence: syncLocalState.lastAppliedQueueSequence)
            syncLocalState.hasResolvedQueueCheckpoint = true
            saveSyncLocalState()
        }

        return locations.queueURL
    }

    func bootstrapFromLatestSharedBackup() throws -> SharedSyncBootstrapResult {
        guard let locations = canonicalSharedSyncLocations() else {
            throw SharedSyncQueueError.iCloudSharedSyncUnavailable
        }

        guard FileManager.default.fileExists(atPath: locations.latestBackupURL.path) else {
            throw SharedSyncQueueError.missingSharedBackup
        }

        let data = try Data(contentsOf: locations.latestBackupURL)
        let package: RecipeSyncPackage
        do {
            package = try RecipeSyncPackage.decoder.decode(RecipeSyncPackage.self, from: data)
        } catch {
            throw SharedSyncQueueError.invalidSharedBackup
        }

        let sharedRecipeIDs = Set(package.recipes.map(\.id))
        let preservedLocalRecipes = preserveLocalBootstrapRecipes(excludingRecipeIDs: sharedRecipeIDs)
        let localBackupURL = try createAutomaticSyncBackup()

        _ = try applySyncPackage(package, createAutomaticBackup: false)
        try rememberSharedSyncQueue(at: locations.queueURL)

        syncLocalState.lastAppliedQueueSequence = package.sharedQueueSequence ?? 0
        syncLocalState.hasResolvedQueueCheckpoint = true
        syncLocalState.lastSynchronizedAt = nil
        syncLocalState.pendingOperations.removeAll()
        saveSyncLocalState()

        var mergedLocalRecipeCount = 0
        for preservedRecipe in preservedLocalRecipes {
            try writeStoredFiles(preservedRecipe.generatedImages, into: recipeImageStorage.directoryURL)
            try writeStoredFiles(preservedRecipe.livePhotos, into: livePhotoDirectoryURL)
            add(preservedRecipe.recipe)
            mergedLocalRecipeCount += 1
        }

        let queueSyncResult = try synchronizeWithRememberedSharedQueue()
        syncStartupNotice = nil

        return SharedSyncBootstrapResult(
            latestBackupURL: locations.latestBackupURL,
            localBackupURL: localBackupURL,
            restoredRecipeCount: package.recipes.count,
            mergedLocalRecipeCount: mergedLocalRecipeCount,
            queueSyncResult: queueSyncResult
        )
    }

    func prepareSharedSyncQueueBootstrapPayload() throws -> SharedSyncQueueBootstrapPayload {
        let queue = RecipeSyncQueue(
            formatVersion: RecipeSyncQueue.currentFormatVersion,
            lastSequence: 0,
            operations: []
        )
        return SharedSyncQueueBootstrapPayload(
            filename: RecipeSyncQueue.defaultFilename,
            data: try RecipeSyncPackage.encoder.encode(queue)
        )
    }

    func rememberSharedSyncQueue(at url: URL) throws {
        let bookmark = try? url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        syncLocalState.rememberedQueueBookmark = bookmark
        syncLocalState.rememberedQueuePath = url.path
        saveSyncLocalState()
    }

    func synchronizeWithRememberedSharedQueue() throws -> SharedSyncQueueSyncResult {
        guard hasRememberedSharedQueue else {
            throw SharedSyncQueueError.noRememberedQueue
        }

        return try withRememberedSharedQueueURL { queueURL in
            let loadResult = try loadSharedSyncQueue(from: queueURL)
            var queue = loadResult.queue
            let remoteOperations = queue.operations.filter {
                ($0.sequence ?? 0) > syncLocalState.lastAppliedQueueSequence &&
                $0.sourceDeviceID != deviceIdentifier
            }

            let pulledOperationCount = try applyRemoteSharedSyncOperations(remoteOperations)
            var pushedOperationCount = 0

            for var operation in syncLocalState.pendingOperations {
                queue.lastSequence += 1
                operation.sequence = queue.lastSequence
                queue.operations.append(operation)
                pushedOperationCount += 1
            }

            let compactionResult = compactSharedSyncQueue(queue)
            queue = compactionResult.queue

            try saveSharedSyncQueue(queue, to: queueURL)

            syncLocalState.pendingOperations.removeAll()
            syncLocalState.lastAppliedQueueSequence = queue.lastSequence
            syncLocalState.hasResolvedQueueCheckpoint = true
            syncLocalState.lastSynchronizedAt = Date()
            syncLocalState.rememberedQueuePath = queueURL.path
            saveSyncLocalState()

            if loadResult.createdQueue || pulledOperationCount > 0 || pushedOperationCount > 0 {
                try? writeLatestSharedSyncBackup(sharedQueueSequence: queue.lastSequence)
            }

            return SharedSyncQueueSyncResult(
                queueURL: queueURL,
                pulledOperationCount: pulledOperationCount,
                pushedOperationCount: pushedOperationCount,
                lastAppliedQueueSequence: queue.lastSequence,
                createdQueue: loadResult.createdQueue,
                compactedOperationCount: compactionResult.compactedOperationCount,
                retainedOperationCount: queue.operations.count
            )
        }
    }

    // MARK: - CRUD

    func add(_ recipe: Recipe) {
        let stampedRecipe = stampedRecipe(recipe, fallbackCreatedAt: recipe.createdAt)
        recipes.append(Self.sanitizedRecipe(stampedRecipe, source: "add"))
        save()
        if let addedRecipe = recipes.last {
            enqueuePendingOperation(makeRecipeUpsertOperation(for: addedRecipe))
        }
    }

    func update(_ recipe: Recipe) {
        if let idx = recipes.firstIndex(where: { $0.id == recipe.id }) {
            let existing = recipes[idx]
            var candidate = stampedRecipe(recipe, fallbackCreatedAt: existing.createdAt)

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
            enqueuePendingOperation(makeRecipeUpsertOperation(for: recipes[idx]))
        }
    }

    func delete(_ recipe: Recipe) {
        enqueuePendingOperation(makeRecipeDeleteOperation(for: recipe))
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
    recipesToDelete.forEach { enqueuePendingOperation(makeRecipeDeleteOperation(for: $0)) }
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
        currentGroceryList = stampedGroceryList(GroceryList(recipe: recipe))
        saveGroceryList()
        if let currentGroceryList {
            enqueuePendingOperation(makeReplaceGroceryListOperation(currentGroceryList))
        }
    }

    func toggleFavorite(for recipe: Recipe) {
        guard let index = recipes.firstIndex(where: { $0.id == recipe.id }) else { return }
        recipes[index].isFavorite.toggle()
        recipes[index] = stampedRecipe(recipes[index], fallbackCreatedAt: recipes[index].createdAt)
        save()
        enqueuePendingOperation(makeRecipeUpsertOperation(for: recipes[index]))
    }

    func toggleGroceryItem(id: UUID) {
        guard var list = currentGroceryList,
              let index = list.items.firstIndex(where: { $0.id == id }) else { return }

        list.items[index].isChecked.toggle()
        list = stampedGroceryList(list, fallbackCreatedAt: list.createdAt)
        currentGroceryList = list
        saveGroceryList()
        enqueuePendingOperation(makeReplaceGroceryListOperation(list))
    }

    func clearGroceryList() {
        enqueuePendingOperation(makeClearGroceryListOperation())
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
        recipes[index] = stampedRecipe(recipes[index], fallbackCreatedAt: recipes[index].createdAt)
        save()
        enqueuePendingOperation(makeRecipeUpsertOperation(for: recipes[index]))
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

        return try applySyncPackage(package, createAutomaticBackup: true)
    }

    private func applySyncPackage(
        _ package: RecipeSyncPackage,
        createAutomaticBackup: Bool
    ) throws -> SyncPackageImportResult {
        let backupURL = createAutomaticBackup
            ? try createAutomaticSyncBackup()
            : syncBackupDirectoryURL

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

    private func stampedRecipe(_ recipe: Recipe, fallbackCreatedAt: Date) -> Recipe {
        var stamped = Self.sanitizedRecipe(recipe, source: "sync stamp")
        let now = Date()
        stamped.createdAt = min(stamped.createdAt, now)
        if stamped.createdAt == Date.distantPast {
            stamped.createdAt = fallbackCreatedAt
        }
        stamped.updatedAt = max(now, stamped.createdAt)
        stamped.lastModifiedByDeviceID = deviceIdentifier
        return stamped
    }

    private func stampedGroceryList(_ groceryList: GroceryList, fallbackCreatedAt: Date? = nil) -> GroceryList {
        var stamped = groceryList
        let now = Date()
        stamped.createdAt = fallbackCreatedAt ?? min(stamped.createdAt, now)
        stamped.updatedAt = max(now, stamped.createdAt)
        stamped.lastModifiedByDeviceID = deviceIdentifier
        return stamped
    }

    private func makeRecipeUpsertOperation(for recipe: Recipe) -> RecipeSyncQueue.Operation {
        RecipeSyncQueue.Operation(
            sourceDeviceID: deviceIdentifier,
            sourceDeviceName: deviceName,
            kind: .upsertRecipe,
            recipe: recipe,
            recipeID: recipe.id,
            generatedImages: storedGeneratedFiles(for: recipe),
            livePhotos: storedLivePhotoFiles(for: recipe)
        )
    }

    private func makeRecipeDeleteOperation(for recipe: Recipe) -> RecipeSyncQueue.Operation {
        RecipeSyncQueue.Operation(
            createdAt: Date(),
            sourceDeviceID: deviceIdentifier,
            sourceDeviceName: deviceName,
            kind: .deleteRecipe,
            recipeID: recipe.id
        )
    }

    private func makeReplaceGroceryListOperation(_ groceryList: GroceryList) -> RecipeSyncQueue.Operation {
        RecipeSyncQueue.Operation(
            sourceDeviceID: deviceIdentifier,
            sourceDeviceName: deviceName,
            kind: .replaceGroceryList,
            groceryList: groceryList
        )
    }

    private func makeClearGroceryListOperation() -> RecipeSyncQueue.Operation {
        RecipeSyncQueue.Operation(
            createdAt: Date(),
            sourceDeviceID: deviceIdentifier,
            sourceDeviceName: deviceName,
            kind: .clearGroceryList
        )
    }

    private func enqueuePendingOperation(_ operation: RecipeSyncQueue.Operation) {
        switch operation.kind {
        case .upsertRecipe, .deleteRecipe:
            guard let recipeID = operation.recipeID else { return }
            syncLocalState.pendingOperations.removeAll {
                ($0.kind == .upsertRecipe || $0.kind == .deleteRecipe) && $0.recipeID == recipeID
            }
        case .replaceGroceryList, .clearGroceryList:
            syncLocalState.pendingOperations.removeAll {
                $0.kind == .replaceGroceryList || $0.kind == .clearGroceryList
            }
        }

        syncLocalState.pendingOperations.append(operation)
        saveSyncLocalState()
    }

    private func loadSharedSyncQueue(from url: URL) throws -> (queue: RecipeSyncQueue, createdQueue: Bool) {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else {
            return (
                RecipeSyncQueue(
                    formatVersion: RecipeSyncQueue.currentFormatVersion,
                    lastSequence: 0,
                    operations: []
                ),
                true
            )
        }

        let data = try Data(contentsOf: url)
        if data.isEmpty {
            return (
                RecipeSyncQueue(
                    formatVersion: RecipeSyncQueue.currentFormatVersion,
                    lastSequence: 0,
                    operations: []
                ),
                true
            )
        }

        guard let queue = try? RecipeSyncPackage.decoder.decode(RecipeSyncQueue.self, from: data) else {
            throw SharedSyncQueueError.invalidQueue
        }

        return (queue, false)
    }

    private func saveSharedSyncQueue(_ queue: RecipeSyncQueue, to url: URL) throws {
        let directoryURL = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let data = try RecipeSyncPackage.encoder.encode(queue)
        try data.write(to: url, options: .atomic)
    }

    private func withRememberedSharedQueueURL<T>(_ body: (URL) throws -> T) throws -> T {
        if let bookmark = syncLocalState.rememberedQueueBookmark {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: bookmark,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            if isStale {
                try rememberSharedSyncQueue(at: url)
            }

            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            return try body(url)
        }

        guard let rememberedQueuePath = syncLocalState.rememberedQueuePath,
              rememberedQueuePath.isEmpty == false else {
            throw SharedSyncQueueError.noRememberedQueue
        }

        return try body(URL(fileURLWithPath: rememberedQueuePath))
    }

    private func applyRemoteSharedSyncOperations(_ operations: [RecipeSyncQueue.Operation]) throws -> Int {
        guard operations.isEmpty == false else { return 0 }

        var appliedCount = 0
        var didChangeRecipes = false
        var didChangeGroceryList = false

        for operation in operations.sorted(by: { ($0.sequence ?? 0) < ($1.sequence ?? 0) }) {
            switch operation.kind {
            case .upsertRecipe:
                guard let incomingRecipe = operation.recipe else { continue }

                if let localPendingOperation = latestPendingRecipeOperation(for: incomingRecipe.id) {
                    switch localPendingOperation.kind {
                    case .upsertRecipe:
                        if let pendingRecipe = localPendingOperation.recipe,
                           pendingRecipe.updatedAt >= incomingRecipe.updatedAt {
                            continue
                        }
                    case .deleteRecipe:
                        if localPendingOperation.createdAt >= incomingRecipe.updatedAt {
                            continue
                        }
                    default:
                        break
                    }
                }

                try writeStoredFiles(operation.generatedImages, into: recipeImageStorage.directoryURL)
                try writeStoredFiles(operation.livePhotos, into: livePhotoDirectoryURL)

                let sanitizedIncoming = Self.sanitizedRecipe(incomingRecipe, source: "shared queue import")
                if let currentIndex = recipes.firstIndex(where: { $0.id == sanitizedIncoming.id }) {
                    recipes[currentIndex] = sanitizedIncoming
                } else {
                    recipes.append(sanitizedIncoming)
                }
                didChangeRecipes = true
                appliedCount += 1
            case .deleteRecipe:
                guard let recipeID = operation.recipeID,
                      let index = recipes.firstIndex(where: { $0.id == recipeID }) else { continue }

                if let localPendingOperation = latestPendingRecipeOperation(for: recipeID) {
                    switch localPendingOperation.kind {
                    case .upsertRecipe:
                        if let pendingRecipe = localPendingOperation.recipe,
                           pendingRecipe.updatedAt >= operation.createdAt {
                            continue
                        }
                    case .deleteRecipe:
                        if localPendingOperation.createdAt >= operation.createdAt {
                            continue
                        }
                    default:
                        break
                    }
                }

                let currentRecipe = recipes[index]
                if let photoFilename = currentRecipe.photoFilename {
                    try? recipeImageStorage.deleteImage(named: photoFilename)
                }
                if let recipeCardFilename = currentRecipe.recipeCardFilename {
                    try? recipeImageStorage.deleteImage(named: recipeCardFilename)
                }
                recipes.remove(at: index)
                didChangeRecipes = true
                appliedCount += 1
            case .replaceGroceryList:
                guard let incomingGroceryList = operation.groceryList else { continue }
                if let localPendingOperation = latestPendingGroceryOperation() {
                    switch localPendingOperation.kind {
                    case .replaceGroceryList:
                        if let pendingGroceryList = localPendingOperation.groceryList,
                           pendingGroceryList.updatedAt >= incomingGroceryList.updatedAt {
                            continue
                        }
                    case .clearGroceryList:
                        if localPendingOperation.createdAt >= incomingGroceryList.updatedAt {
                            continue
                        }
                    default:
                        break
                    }
                }

                currentGroceryList = incomingGroceryList
                didChangeGroceryList = true
                appliedCount += 1
            case .clearGroceryList:
                if let localPendingOperation = latestPendingGroceryOperation() {
                    switch localPendingOperation.kind {
                    case .replaceGroceryList:
                        if let pendingGroceryList = localPendingOperation.groceryList,
                           pendingGroceryList.updatedAt >= operation.createdAt {
                            continue
                        }
                    case .clearGroceryList:
                        if localPendingOperation.createdAt >= operation.createdAt {
                            continue
                        }
                    default:
                        break
                    }
                }

                currentGroceryList = nil
                didChangeGroceryList = true
                appliedCount += 1
            }
        }

        if didChangeRecipes {
            recipes = Self.reconciledRecipes(Self.sanitizedRecipes(recipes, source: "shared queue reconcile"))
            save()
            livePhotoDirectorySignature = Self.recipePhotoDirectorySignature(at: livePhotoDirectoryURL)
            liveRecipePhotos = Self.loadRecipePhotos(from: livePhotoDirectoryURL)
            hydratePhotosIfAvailable()
        }

        if didChangeGroceryList {
            if currentGroceryList == nil {
                do {
                    if FileManager.default.fileExists(atPath: groceryListURL.path) {
                        try FileManager.default.removeItem(at: groceryListURL)
                    }
                } catch {
                    print("RecipeStore clear grocery list error: \(error)")
                }
            } else {
                saveGroceryList()
            }
        }

        return appliedCount
    }

    private func latestPendingRecipeOperation(for recipeID: UUID) -> RecipeSyncQueue.Operation? {
        syncLocalState.pendingOperations.last {
            ($0.kind == .upsertRecipe || $0.kind == .deleteRecipe) && $0.recipeID == recipeID
        }
    }

    private func latestPendingGroceryOperation() -> RecipeSyncQueue.Operation? {
        syncLocalState.pendingOperations.last {
            $0.kind == .replaceGroceryList || $0.kind == .clearGroceryList
        }
    }

    private func compactSharedSyncQueue(_ queue: RecipeSyncQueue) -> (queue: RecipeSyncQueue, compactedOperationCount: Int) {
        var latestRecipeSequenceByID: [UUID: Int] = [:]
        var latestGrocerySequence: Int?

        for operation in queue.operations {
            guard let sequence = operation.sequence else { continue }

            switch operation.kind {
            case .upsertRecipe, .deleteRecipe:
                guard let recipeID = operation.recipeID else { continue }
                latestRecipeSequenceByID[recipeID] = max(latestRecipeSequenceByID[recipeID] ?? 0, sequence)
            case .replaceGroceryList, .clearGroceryList:
                latestGrocerySequence = max(latestGrocerySequence ?? 0, sequence)
            }
        }

        let retainedOperations = queue.operations.filter { operation in
            guard let sequence = operation.sequence else { return false }

            switch operation.kind {
            case .upsertRecipe, .deleteRecipe:
                guard let recipeID = operation.recipeID else { return false }
                return latestRecipeSequenceByID[recipeID] == sequence
            case .replaceGroceryList, .clearGroceryList:
                return latestGrocerySequence == sequence
            }
        }

        return (
            RecipeSyncQueue(
                formatVersion: queue.formatVersion,
                lastSequence: queue.lastSequence,
                operations: retainedOperations.sorted { ($0.sequence ?? 0) < ($1.sequence ?? 0) }
            ),
            max(queue.operations.count - retainedOperations.count, 0)
        )
    }

    private func makeSyncPackage(sharedQueueSequence: Int? = nil) throws -> RecipeSyncPackage {
        RecipeSyncPackage(
            formatVersion: RecipeSyncPackage.currentFormatVersion,
            exportedAt: Date(),
            sourceDeviceName: deviceName,
            sharedQueueSequence: sharedQueueSequence,
            recipes: recipes,
            groceryList: currentGroceryList,
            generatedImages: try storedFiles(in: recipeImageStorage.directoryURL),
            livePhotos: try storedFiles(in: livePhotoDirectoryURL)
        )
    }

    private func storedGeneratedFiles(for recipe: Recipe) -> [RecipeSyncPackage.StoredFile] {
        [recipe.photoFilename, recipe.recipeCardFilename]
            .compactMap { $0 }
            .compactMap { filename in
                guard let data = recipeImageStorage.loadImage(named: filename) else { return nil }
                return RecipeSyncPackage.StoredFile(filename: filename, data: data)
            }
    }

    private func storedLivePhotoFiles(for recipe: Recipe) -> [RecipeSyncPackage.StoredFile] {
        Self.photoFileURLs(in: livePhotoDirectoryURL)
            .filter { url in
                let lookupKey = url.deletingPathExtension().lastPathComponent.photoLookupKey
                return recipe.photoLookupKeys.contains(lookupKey)
            }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return RecipeSyncPackage.StoredFile(filename: url.lastPathComponent, data: data)
            }
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

    private func writeStoredFiles(
        _ files: [RecipeSyncPackage.StoredFile],
        into directoryURL: URL
    ) throws {
        guard files.isEmpty == false else { return }
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        for file in files {
            let filename = URL(fileURLWithPath: file.filename).lastPathComponent
            guard filename.isEmpty == false else { continue }
            let destinationURL = directoryURL.appendingPathComponent(filename)
            try file.data.write(to: destinationURL, options: .atomic)
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

    private func writeLatestSharedSyncBackup(sharedQueueSequence: Int) throws {
        guard let locations = canonicalSharedSyncLocations() else {
            throw SharedSyncQueueError.iCloudSharedSyncUnavailable
        }

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: locations.archivedBackupsDirectoryURL, withIntermediateDirectories: true)

        let package = try makeSyncPackage(sharedQueueSequence: sharedQueueSequence)
        let data = try RecipeSyncPackage.encoder.encode(package)
        try data.write(to: locations.latestBackupURL, options: .atomic)

        let archivedBackupURL = locations.archivedBackupsDirectoryURL.appendingPathComponent(
            "MomRecette-Backup-\(timestampString(for: package.exportedAt)).json"
        )
        try data.write(to: archivedBackupURL, options: .atomic)
        try trimArchivedSharedBackups(in: locations.archivedBackupsDirectoryURL)
    }

    private func trimArchivedSharedBackups(in directoryURL: URL) throws {
        let fileManager = FileManager.default
        let backupURLs = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
            .filter { $0.pathExtension.lowercased() == "json" }
            .sorted {
                let lhsDate = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let rhsDate = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return lhsDate > rhsDate
            }

        guard backupURLs.count > Self.sharedSyncArchivedBackupRetentionCount else { return }

        for url in backupURLs.dropFirst(Self.sharedSyncArchivedBackupRetentionCount) {
            try? fileManager.removeItem(at: url)
        }
    }

    private func timestampString(for date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date).replacingOccurrences(of: ":", with: "-")
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
        merged.updatedAt = max(primary.updatedAt, secondary.updatedAt)
        merged.lastModifiedByDeviceID = merged.updatedAt == primary.updatedAt
            ? primary.lastModifiedByDeviceID ?? secondary.lastModifiedByDeviceID
            : secondary.lastModifiedByDeviceID ?? primary.lastModifiedByDeviceID
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

    private var hasRememberedSharedQueue: Bool {
        if let rememberedQueuePath = syncLocalState.rememberedQueuePath, rememberedQueuePath.isEmpty == false {
            return true
        }

        return syncLocalState.rememberedQueueBookmark != nil
    }

    private func startupNoticeMessage(for status: SharedSyncBootstrapStatus) -> String {
        if status.canRestoreFromLatestBackup {
            return "Une sauvegarde partagee a ete trouvee pour cet appareil. Ouvrez Sync et initialisez MomRecette depuis la sauvegarde partagee avant de reprendre la synchronisation automatique."
        }

        if status.isAwaitingInitialSharedBackup {
            if status.hasLocalLibraryData {
                return "Aucune sauvegarde partagee n'est disponible pour l'instant. Ouvrez Sync et republiez la queue partagee depuis cet appareil afin de publier la premiere sauvegarde."
            }

            return "Aucune sauvegarde partagee n'est disponible pour l'instant. Ouvrez Sync sur l'appareil source qui contient deja vos recettes afin de publier la premiere sauvegarde partagee."
        }

        return "Cet appareil ne connait pas encore son point de reprise de sync. Ouvrez Sync et initialisez-le depuis la sauvegarde partagee ou reconfigurez la queue."
    }

    private func canonicalSharedSyncLocations() -> SharedSyncLocations? {
        let rootURL: URL?
        if let sharedSyncRootOverrideURL {
            rootURL = sharedSyncRootOverrideURL
        } else {
            rootURL = FileManager.default.url(
                forUbiquityContainerIdentifier: MomRecetteSetup.CloudSync.containerIdentifier
            )?.appendingPathComponent("Documents", isDirectory: true)
        }

        guard let rootURL else { return nil }

        let directoryURL = rootURL.appendingPathComponent(Self.sharedSyncDirectoryName, isDirectory: true)
        return SharedSyncLocations(
            directoryURL: directoryURL,
            queueURL: directoryURL.appendingPathComponent(RecipeSyncQueue.defaultFilename),
            latestBackupURL: directoryURL.appendingPathComponent(Self.sharedSyncLatestBackupFilename),
            archivedBackupsDirectoryURL: directoryURL.appendingPathComponent(Self.sharedSyncArchivedBackupsDirectoryName, isDirectory: true)
        )
    }

    private func autoConfigureCanonicalSharedSyncQueueIfPossible() {
        guard hasRememberedSharedQueue == false,
              let locations = canonicalSharedSyncLocations() else {
            return
        }

        syncLocalState.rememberedQueuePath = locations.queueURL.path
        if syncLocalState.rememberedQueueBookmark == nil {
            syncLocalState.rememberedQueueBookmark = try? locations.queueURL.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        }
        saveSyncLocalState()
    }

    private func preserveLocalBootstrapRecipes(excludingRecipeIDs sharedRecipeIDs: Set<UUID>) -> [PreservedBootstrapRecipe] {
        recipes
            .filter { sharedRecipeIDs.contains($0.id) == false }
            .map { recipe in
                PreservedBootstrapRecipe(
                    recipe: recipe,
                    generatedImages: storedGeneratedFiles(for: recipe),
                    livePhotos: storedLivePhotoFiles(for: recipe)
                )
            }
    }

    private func saveSyncLocalState() {
        do {
            let data = try RecipeSyncPackage.encoder.encode(syncLocalState)
            try data.write(to: syncStateURL, options: .atomic)
        } catch {
            print("RecipeStore save sync local state error: \(error)")
        }
    }

    private static func loadSyncLocalState(from url: URL) -> RecipeSyncLocalState {
        guard let data = try? Data(contentsOf: url),
              let state = try? RecipeSyncPackage.decoder.decode(RecipeSyncLocalState.self, from: data) else {
            return RecipeSyncLocalState()
        }

        return state
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
