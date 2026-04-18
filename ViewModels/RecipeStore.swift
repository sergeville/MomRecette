import Foundation
import SwiftUI
import Combine
import UIKit
import EventKit

@MainActor
class RecipeStore: ObservableObject {
    struct RecipePhotoBatchImportResult {
        var importedCount = 0
        var replacedCount = 0
        var unmatchedCount = 0
        var invalidCount = 0
        var failedCount = 0

        var appliedCount: Int { importedCount + replacedCount }
        var issueCount: Int { unmatchedCount + invalidCount + failedCount }
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

    @Published var recipes: [Recipe] = []
    @Published var currentGroceryList: GroceryList?
    @Published var searchText: String = ""
    @Published var selectedCategory: Recipe.Category? = nil

    private let saveURL: URL
    private let groceryListURL: URL
    private let livePhotoDirectoryURL: URL
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
        enablePhotoAutoRefresh: Bool = true
    ) {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        saveURL = recipesURL ?? docs.appendingPathComponent("momrecette.json")
        self.groceryListURL = groceryListURL ?? docs.appendingPathComponent("momrecette-grocery-list.json")
        self.livePhotoDirectoryURL = livePhotoDirectoryURL ?? docs.appendingPathComponent("RecipePhotos", isDirectory: true)
        bundledRecipePhotos = Self.loadBundledRecipePhotos()
        liveRecipePhotos = Self.loadRecipePhotos(from: self.livePhotoDirectoryURL)
        livePhotoDirectorySignature = Self.recipePhotoDirectorySignature(at: self.livePhotoDirectoryURL)

        load()
        loadGroceryList()
        hydratePhotosIfAvailable()

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
        recipes.append(Self.sanitizedRecipe(recipe, source: "add"))
        save()
    }

    func update(_ recipe: Recipe) {
        if let idx = recipes.firstIndex(where: { $0.id == recipe.id }) {
            recipes[idx] = Self.sanitizedRecipe(recipe, source: "update")
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
            let decoded = try JSONDecoder().decode([Recipe].self, from: data)
            recipes = Self.sanitizedRecipes(decoded, source: "saved recipes")
        } catch {
            print("RecipeStore load error: \(error)")
        }
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
        guard FileManager.default.fileExists(atPath: groceryListURL.path) else { return }

        do {
            let data = try Data(contentsOf: groceryListURL)
            currentGroceryList = try JSONDecoder().decode(GroceryList.self, from: data)
        } catch {
            print("RecipeStore load grocery list error: \(error)")
        }
    }

    private func loadBundle() {
        guard let url = Bundle.main.url(forResource: "momrecette_bundle", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let loaded = try? decoder.decode([LenientRecipe].self, from: data) {
            recipes = Self.sanitizedRecipes(loaded.map { $0.toRecipe() }, source: "bundle seed")
            hydratePhotosIfAvailable()
            save()
            print("RecipeStore: seeded \(recipes.count) recipes from bundle")
        }
    }

    func refreshRecipePhotosIfNeeded(force: Bool = false) {
        let currentSignature = Self.recipePhotoDirectorySignature(at: livePhotoDirectoryURL)
        guard force || currentSignature != livePhotoDirectorySignature else { return }

        livePhotoDirectorySignature = currentSignature
        liveRecipePhotos = Self.loadRecipePhotos(from: livePhotoDirectoryURL)
        hydratePhotosIfAvailable()
    }

    private func hydratePhotosIfAvailable() {
        guard !(bundledRecipePhotos.isEmpty && liveRecipePhotos.isEmpty) else { return }

        var didChange = false

        recipes = recipes.map { recipe in
            let sanitized = Self.sanitizedRecipe(recipe, source: "hydrate")
            guard sanitized.imageData == nil else { return sanitized }
            guard let photoData = photoData(for: sanitized) else { return sanitized }

            var updated = sanitized
            updated.imageData = photoData
            didChange = true
            return updated
        }

        if didChange {
            save()
        }
    }

    private func photoData(for recipe: Recipe) -> Data? {
        for key in recipe.photoLookupKeys {
            if let data = liveRecipePhotos[key] {
                return data
            }
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
    
    var photos: [String: Data] = [:]
    let urls = photoFileURLs(in: directoryURL)
    
    for url in urls {
        let key = url.deletingPathExtension().lastPathComponent.photoLookupKey
        guard photos[key] == nil, let data = try? Data(contentsOf: url) else { continue }
        guard let validated = validatedImageData(data, source: "live photo file", name: url.lastPathComponent) else {
            continue
        }
        photos[key] = validated
    }
    
    return photos
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

    private static func sanitizedRecipe(_ recipe: Recipe, source: String) -> Recipe {
        guard let imageData = recipe.imageData else { return recipe }
        guard let validated = validatedImageData(imageData, source: source, name: recipe.name) else {
            var sanitized = recipe
            sanitized.imageData = nil
            return sanitized
        }
        var sanitized = recipe
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
