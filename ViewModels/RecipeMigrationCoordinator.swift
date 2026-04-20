import Foundation

struct RecipeMigrationPlan {
    struct FileSnapshot {
        let label: String
        let sourceURL: URL
        let exists: Bool
        let itemCount: Int
    }

    let needsMigration: Bool
    let backupRootURL: URL
    let persistentStoreURL: URL
    let fileSnapshots: [FileSnapshot]
    let warnings: [String]
    let recommendedNextStep: String
}

struct RecipeMigrationBackup {
    struct CopiedItem {
        let label: String
        let sourceURL: URL
        let backupURL: URL
        let itemCount: Int
    }

    let backupRootURL: URL
    let createdAt: Date
    let copiedItems: [CopiedItem]
}

struct RecipeMigrationCoordinator {
    enum MigrationError: LocalizedError {
        case backupAlreadyExists(URL)
        case couldNotCreateBackupDirectory(URL)

        var errorDescription: String? {
            switch self {
            case .backupAlreadyExists(let url):
                return "Une sauvegarde de migration existe deja a \(url.path)."
            case .couldNotCreateBackupDirectory(let url):
                return "Impossible de creer le dossier de sauvegarde \(url.path)."
            }
        }
    }

    private let fileManager: FileManager
    private let documentsDirectoryURL: URL
    private let backupRootDirectoryURL: URL
    private let persistentStoreURL: URL

    init(
        fileManager: FileManager = .default,
        documentsDirectoryURL: URL? = nil,
        backupRootDirectoryURL: URL? = nil,
        persistentStoreURL: URL? = nil
    ) throws {
        self.fileManager = fileManager
        self.documentsDirectoryURL = try documentsDirectoryURL ?? fileManager.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        if let backupRootDirectoryURL {
            self.backupRootDirectoryURL = backupRootDirectoryURL
        } else {
            let appSupport = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            self.backupRootDirectoryURL = appSupport
                .appendingPathComponent("MomRecette", isDirectory: true)
                .appendingPathComponent("MigrationBackups", isDirectory: true)
        }

        self.persistentStoreURL = try persistentStoreURL ?? RecipePersistentContainer.makeStoreURL(fileManager: fileManager)
    }

    func makePlan(using report: RecipeStore.CloudSyncPreparationReport) -> RecipeMigrationPlan {
        let snapshots = report.localStorageLocations.map { location in
            RecipeMigrationPlan.FileSnapshot(
                label: location.label,
                sourceURL: location.url,
                exists: location.exists,
                itemCount: itemCount(at: location.url, exists: location.exists)
            )
        }

        var warnings: [String] = []

        if report.unreferencedGeneratedImageCount > 0 {
            warnings.append("\(report.unreferencedGeneratedImageCount) images generees ne sont reliees a aucune recette.")
        }

        if snapshots.contains(where: { $0.exists }) == false {
            warnings.append("Aucune donnee locale n'a ete detectee pour la migration.")
        }

        let needsMigration = fileManager.fileExists(atPath: persistentStoreURL.path) == false
            && snapshots.contains(where: { $0.exists })

        return RecipeMigrationPlan(
            needsMigration: needsMigration,
            backupRootURL: makeTimestampedBackupURL(),
            persistentStoreURL: persistentStoreURL,
            fileSnapshots: snapshots,
            warnings: warnings,
            recommendedNextStep: needsMigration
                ? "Creer une sauvegarde locale, importer les recettes dans Core Data local, puis valider avant d'activer CloudKit."
                : "La base locale Core Data existe deja. Verifier l'etat avant toute importation supplementaire."
        )
    }

    func createBackup(using report: RecipeStore.CloudSyncPreparationReport) throws -> RecipeMigrationBackup {
        let backupRootURL = makeTimestampedBackupURL()

        guard fileManager.fileExists(atPath: backupRootURL.path) == false else {
            throw MigrationError.backupAlreadyExists(backupRootURL)
        }

        do {
            try fileManager.createDirectory(at: backupRootURL, withIntermediateDirectories: true)
        } catch {
            throw MigrationError.couldNotCreateBackupDirectory(backupRootURL)
        }

        var copiedItems: [RecipeMigrationBackup.CopiedItem] = []

        for location in report.localStorageLocations where location.exists {
            let targetURL = backupRootURL.appendingPathComponent(sanitizedBackupName(for: location.label), isDirectory: location.url.hasDirectoryPath)
            try copyItem(at: location.url, to: targetURL)

            copiedItems.append(
                .init(
                    label: location.label,
                    sourceURL: location.url,
                    backupURL: targetURL,
                    itemCount: itemCount(at: location.url, exists: true)
                )
            )
        }

        return RecipeMigrationBackup(
            backupRootURL: backupRootURL,
            createdAt: Date(),
            copiedItems: copiedItems
        )
    }

    func defaultLegacyStorageLocations() -> [URL] {
        [
            documentsDirectoryURL.appendingPathComponent("momrecette.json"),
            documentsDirectoryURL.appendingPathComponent("momrecette-grocery-list.json"),
            documentsDirectoryURL.appendingPathComponent("RecipeImages", isDirectory: true),
            documentsDirectoryURL.appendingPathComponent("RecipePhotos", isDirectory: true)
        ]
    }

    private func makeTimestampedBackupURL() -> URL {
        let timestamp = Self.timestampFormatter.string(from: Date())
        let suffix = UUID().uuidString.prefix(8).lowercased()
        return backupRootDirectoryURL.appendingPathComponent("backup-\(timestamp)-\(suffix)", isDirectory: true)
    }

    private func itemCount(at url: URL, exists: Bool) -> Int {
        guard exists else { return 0 }

        if url.hasDirectoryPath {
            let contents = (try? fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )) ?? []
            return contents.filter { !$0.hasDirectoryPath }.count
        }

        return 1
    }

    private func copyItem(at sourceURL: URL, to targetURL: URL) throws {
        if fileManager.fileExists(atPath: targetURL.path) {
            try fileManager.removeItem(at: targetURL)
        }

        if sourceURL.hasDirectoryPath {
            try fileManager.createDirectory(at: targetURL, withIntermediateDirectories: true)

            let contents = try fileManager.contentsOfDirectory(
                at: sourceURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )

            for itemURL in contents {
                let childTargetURL = targetURL.appendingPathComponent(itemURL.lastPathComponent, isDirectory: itemURL.hasDirectoryPath)
                try copyItem(at: itemURL, to: childTargetURL)
            }
        } else {
            let parentURL = targetURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: parentURL, withIntermediateDirectories: true)
            try fileManager.copyItem(at: sourceURL, to: targetURL)
        }
    }

    private func sanitizedBackupName(for label: String) -> String {
        label
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "/", with: "-")
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}
