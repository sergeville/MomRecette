import SwiftUI
import UniformTypeIdentifiers

// MARK: - Import Recipes

struct ImportView: View {
    @EnvironmentObject var store: RecipeStore
    @Environment(\.dismiss) var dismiss

    @State private var showJSONFilePicker = false
    @State private var showPhotoPicker = false
    @State private var showSyncPackagePicker = false
    @State private var importResult: ImportResult? = nil
    @State private var isLoading = false
    @State private var pendingSyncPackageImport: PendingSyncPackageImport?
    @State private var exportDocument: RecipeSyncPackageDocument?
    @State private var exportFilename = ""
    @State private var pendingSyncPackageExport: RecipeStore.SyncPackageExportPayload?
    @State private var showSyncPackageExporter = false

    enum ImportResult {
        case success(Int)
        case duplicate(Int, Int)   // imported, skipped
        case photos(RecipeStore.RecipePhotoBatchImportResult)
        case syncExportPrepared(RecipeStore.SyncPackageExportPayload)
        case syncExportSaved(RecipeStore.SyncPackageExportPayload, URL)
        case syncImport(RecipeStore.SyncPackageImportResult)
        case error(String)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                VStack(spacing: 12) {
                    Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(Color.accentColor)
                    Text("Sync dans MomRecette")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Importez, exportez et deplacez votre bibliotheque\nentre appareils sans perdre vos images.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 14) {
                    Button {
                        showJSONFilePicker = true
                    } label: {
                        Label("Choisir un fichier JSON", systemImage: "doc.badge.plus")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .fileImporter(
                        isPresented: $showJSONFilePicker,
                        allowedContentTypes: [.json],
                        allowsMultipleSelection: false
                    ) { result in
                        handleImport(result: result)
                    }

                    Button {
                        showPhotoPicker = true
                    } label: {
                        Label("Choisir des photos", systemImage: "photo.stack")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(UIColor.secondarySystemBackground))
                            .foregroundStyle(.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .fileImporter(
                        isPresented: $showPhotoPicker,
                        allowedContentTypes: [.image],
                        allowsMultipleSelection: true
                    ) { result in
                        handlePhotoImport(result: result)
                    }

                    Button {
                        importSampleData()
                    } label: {
                        Label("Charger les recettes exemples", systemImage: "sparkles")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(UIColor.secondarySystemBackground))
                            .foregroundStyle(.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }

                    Divider()
                        .padding(.vertical, 4)

                    Button {
                        exportSyncPackage()
                    } label: {
                        Label("Exporter un package de sync", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(UIColor.secondarySystemBackground))
                            .foregroundStyle(.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }

                    Button {
                        showSyncPackagePicker = true
                    } label: {
                        Label("Importer un package MomRecette", systemImage: "arrow.triangle.2.circlepath")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(UIColor.secondarySystemBackground))
                            .foregroundStyle(.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .fileImporter(
                        isPresented: $showSyncPackagePicker,
                        allowedContentTypes: [.json],
                        allowsMultipleSelection: false
                    ) { result in
                        handleSyncPackageImport(result: result)
                    }
                }

                if isLoading {
                    ProgressView("Sync en cours…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let result = importResult {
                    resultView(result)
                        .transition(.scale.combined(with: .opacity))
                }

                Spacer()

                formatHintView
            }
            .padding(24)
            .navigationTitle("Sync")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
            .sheet(item: $pendingSyncPackageImport) { pendingImport in
                SyncPackageImportConfirmationSheet(
                    pendingImport: pendingImport,
                    backupDirectoryURL: store.syncBackupDirectoryURL,
                    onCancel: {
                        pendingSyncPackageImport = nil
                    },
                    onConfirm: {
                        applySyncPackageImport(pendingImport)
                    }
                )
            }
            .fileExporter(
                isPresented: $showSyncPackageExporter,
                document: exportDocument,
                contentType: .json,
                defaultFilename: exportFilename
            ) { result in
                handleSyncPackageExportResult(result)
            }
        }
    }

    @ViewBuilder
    private func resultView(_ result: ImportResult) -> some View {
        switch result {
        case .syncImport(let result):
            syncImportResultView(result)
        default:
            HStack(spacing: 14) {
                switch result {
                case .success(let n):
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("\(n) recette\(n > 1 ? "s" : "") importée\(n > 1 ? "s" : "") avec succès")
                case .duplicate(let imp, let skip):
                    Image(systemName: "info.circle.fill").foregroundStyle(.orange)
                    Text("\(imp) importée\(imp > 1 ? "s" : ""), \(skip) doublon\(skip > 1 ? "s" : "") ignoré\(skip > 1 ? "s" : "")")
                case .photos(let result):
                    Image(systemName: result.issueCount == 0 ? "photo.badge.checkmark" : "info.circle.fill")
                        .foregroundStyle(result.issueCount == 0 ? .green : .orange)
                    Text(photoImportSummary(for: result))
                case .syncExportPrepared(let result):
                    Image(systemName: "square.and.arrow.up.circle.fill").foregroundStyle(.green)
                    Text(syncExportPreparedSummary(for: result))
                case .syncExportSaved(let result, let url):
                    Image(systemName: "externaldrive.badge.checkmark").foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(syncExportSavedSummary(for: result))
                        Text(url.path)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                case .error(let msg):
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                    Text(msg).lineLimit(2)
                case .syncImport:
                    EmptyView()
                }
            }
            .font(.subheadline)
            .padding(14)
            .background(Color(UIColor.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private var formatHintView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Format JSON attendu", systemImage: "doc.text")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            Text("""
[
  {
    "name": "Tarte aux pommes",
    "category": "Desserts",
    "ingredients": [{"name": "pommes", "quantity": "3"}],
    "steps": ["Éplucher...", "Cuire..."]
  }
]
""")
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.secondary)
            .padding(10)
            .background(Color(UIColor.tertiarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Label("Pour les photos, utilisez des noms de fichiers qui correspondent aux recettes. MomRecette normalise ensuite le nom et sauvegarde l'image dans le dossier live de l'app.", systemImage: "photo")
                .font(.caption)
                .foregroundStyle(.secondary)

            Label("Le package de sync contient les recettes, la liste d'epicerie, les photos live et les images generees. Importer un package remplace la bibliotheque locale apres une sauvegarde automatique.", systemImage: "arrow.triangle.2.circlepath")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func handleImport(result: Result<[URL], Error>) {
        switch result {
        case .failure(let err):
            withAnimation { importResult = .error(err.localizedDescription) }
        case .success(let urls):
            guard let url = urls.first else { return }
            isLoading = true

            let accessed = url.startAccessingSecurityScopedResource()
            defer {
                if accessed {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            do {
                let data = try Data(contentsOf: url)
                importJSON(data)
            } catch {
                withAnimation { importResult = .error("Impossible de lire le fichier: \(error.localizedDescription)") }
            }
            isLoading = false
        }
    }

    private func handlePhotoImport(result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            withAnimation { importResult = .error(error.localizedDescription) }
        case .success(let urls):
            guard !urls.isEmpty else { return }
            isLoading = true
            let photoImportResult = store.importRecipePhotos(from: urls)
            withAnimation { importResult = .photos(photoImportResult) }
            isLoading = false
        }
    }

    private func handleSyncPackageImport(result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            withAnimation { importResult = .error(error.localizedDescription) }
        case .success(let urls):
            guard let url = urls.first else { return }
            isLoading = true

            let accessed = url.startAccessingSecurityScopedResource()
            defer {
                if accessed {
                    url.stopAccessingSecurityScopedResource()
                }
                isLoading = false
            }

            do {
                let data = try Data(contentsOf: url)
                let package = try RecipeSyncPackage.decoder.decode(RecipeSyncPackage.self, from: data)
                pendingSyncPackageImport = PendingSyncPackageImport(
                    filename: url.lastPathComponent,
                    data: data,
                    package: package
                )
            } catch {
                withAnimation { importResult = .error(error.localizedDescription) }
            }
        }
    }

    private func exportSyncPackage() {
        isLoading = true
        defer { isLoading = false }

        do {
            let payload = try store.prepareSyncPackageExport()
            pendingSyncPackageExport = payload
            exportFilename = payload.filename
            exportDocument = RecipeSyncPackageDocument(data: payload.data)
            showSyncPackageExporter = true
            withAnimation { importResult = .syncExportPrepared(payload) }
        } catch {
            withAnimation { importResult = .error(error.localizedDescription) }
        }
    }

    private func applySyncPackageImport(_ pendingImport: PendingSyncPackageImport) {
        pendingSyncPackageImport = nil
        isLoading = true
        defer { isLoading = false }

        do {
            let report = try store.importSyncPackage(from: pendingImport.data)
            withAnimation { importResult = .syncImport(report) }
        } catch {
            withAnimation { importResult = .error(error.localizedDescription) }
        }
    }

    private func importJSON(_ data: Data) {
        var incoming: [Recipe] = []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if let arr = try? decoder.decode([Recipe].self, from: data) {
            incoming = arr
        } else if let one = try? decoder.decode(Recipe.self, from: data) {
            incoming = [one]
        } else {
            if let arr = try? JSONDecoder().decode([LenientRecipe].self, from: data) {
                incoming = arr.map { $0.toRecipe() }
            } else {
                withAnimation { importResult = .error("Format JSON invalide.") }
                return
            }
        }

        let existingNames = Set(store.recipes.map { $0.name.lowercased() })
        let new = incoming.filter { !existingNames.contains($0.name.lowercased()) }
        let skipped = incoming.count - new.count

        new.forEach { store.add($0) }

        withAnimation {
            if skipped > 0 {
                importResult = .duplicate(new.count, skipped)
            } else {
                importResult = .success(new.count)
            }
        }
    }

    private func importSampleData() {
        let existingNames = Set(store.recipes.map { $0.name.lowercased() })
        let toAdd = Recipe.samples.filter { !existingNames.contains($0.name.lowercased()) }
        toAdd.forEach { store.add($0) }
        withAnimation { importResult = .success(toAdd.count) }
    }

    private func photoImportSummary(for result: RecipeStore.RecipePhotoBatchImportResult) -> String {
        var segments: [String] = []

        if result.importedCount > 0 {
            segments.append("\(result.importedCount) ajoutée\(result.importedCount > 1 ? "s" : "")")
        }

        if result.replacedCount > 0 {
            segments.append("\(result.replacedCount) remplacée\(result.replacedCount > 1 ? "s" : "")")
        }

        if result.unmatchedCount > 0 {
            segments.append("\(result.unmatchedCount) sans recette correspondante")
        }

        if result.invalidCount > 0 {
            segments.append("\(result.invalidCount) image\(result.invalidCount > 1 ? "s" : "") invalide\(result.invalidCount > 1 ? "s" : "")")
        }

        if result.failedCount > 0 {
            segments.append("\(result.failedCount) erreur\(result.failedCount > 1 ? "s" : "") de lecture")
        }

        if segments.isEmpty {
            return "Aucune photo n'a été importée."
        }

        return "Photos: " + segments.joined(separator: ", ")
    }

    private func handleSyncPackageExportResult(_ result: Result<URL, Error>) {
        guard let payload = pendingSyncPackageExport else { return }
        pendingSyncPackageExport = nil
        exportDocument = nil

        switch result {
        case .success(let url):
            withAnimation { importResult = .syncExportSaved(payload, url) }
        case .failure(let error):
            withAnimation { importResult = .error(error.localizedDescription) }
        }
    }

    private func syncExportPreparedSummary(for result: RecipeStore.SyncPackageExportPayload) -> String {
        var segments = [
            "\(result.recipeCount) recette\(result.recipeCount > 1 ? "s" : "")",
            "\(result.livePhotoCount) photo\(result.livePhotoCount > 1 ? "s" : "") live",
            "\(result.generatedImageCount) image\(result.generatedImageCount > 1 ? "s" : "") generee\(result.generatedImageCount > 1 ? "s" : "")"
        ]

        if result.groceryListIncluded {
            segments.append("liste d'epicerie incluse")
        }

        return "Package pret a enregistrer: " + segments.joined(separator: ", ")
    }

    private func syncExportSavedSummary(for result: RecipeStore.SyncPackageExportPayload) -> String {
        var segments = [
            "\(result.recipeCount) recette\(result.recipeCount > 1 ? "s" : "")",
            "\(result.livePhotoCount) photo\(result.livePhotoCount > 1 ? "s" : "") live",
            "\(result.generatedImageCount) image\(result.generatedImageCount > 1 ? "s" : "") generee\(result.generatedImageCount > 1 ? "s" : "")"
        ]

        if result.groceryListIncluded {
            segments.append("liste d'epicerie incluse")
        }

        return "Package enregistre: " + segments.joined(separator: ", ")
    }

    private func syncImportSummary(for result: RecipeStore.SyncPackageImportResult) -> String {
        var segments = [
            "\(result.recipeCount) recette\(result.recipeCount > 1 ? "s" : "") restauree\(result.recipeCount > 1 ? "s" : "")",
            "\(result.livePhotoCount) photo\(result.livePhotoCount > 1 ? "s" : "") live",
            "\(result.generatedImageCount) image\(result.generatedImageCount > 1 ? "s" : "") generee\(result.generatedImageCount > 1 ? "s" : "")"
        ]

        if result.groceryListIncluded {
            segments.append("liste d'epicerie restauree")
        }

        return "Import termine. Sauvegarde locale creee automatiquement. " + segments.joined(separator: ", ")
    }

    private func syncImportResultView(_ result: RecipeStore.SyncPackageImportResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                    .foregroundStyle(.green)
                Text(syncImportSummary(for: result))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Fichier de sauvegarde cree:")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(result.backupURL.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .padding(.leading, 36)
        }
        .font(.subheadline)
        .padding(14)
        .background(Color(UIColor.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct PendingSyncPackageImport: Identifiable {
    let id = UUID()
    let filename: String
    let data: Data
    let package: RecipeSyncPackage
}

private struct SyncPackageImportConfirmationSheet: View {
    let pendingImport: PendingSyncPackageImport
    let backupDirectoryURL: URL
    let onCancel: () -> Void
    let onConfirm: () -> Void

    private var exportDateText: String {
        Self.exportDateFormatter.string(from: pendingImport.package.exportedAt)
    }

    private var sourceDeviceKind: SourceDeviceKind {
        SourceDeviceKind(deviceName: pendingImport.package.sourceDeviceName)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Verifier le package avant import", systemImage: "arrow.triangle.2.circlepath.circle")
                        .font(.headline)
                    Text("L'import remplace la bibliotheque locale actuelle. MomRecette cree une sauvegarde automatique juste avant d'appliquer ce package.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Label(sourceDeviceKind.title, systemImage: sourceDeviceKind.systemImage)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(sourceDeviceKind.tint.opacity(0.12))
                        .foregroundStyle(sourceDeviceKind.tint)
                        .clipShape(Capsule())
                }

                VStack(spacing: 12) {
                    metadataRow(label: "Fichier", value: pendingImport.filename)
                    metadataRow(label: "Appareil source", value: pendingImport.package.sourceDeviceName)
                    metadataRow(label: "Exporte le", value: exportDateText)
                    metadataRow(label: "Recettes", value: "\(pendingImport.package.recipes.count)")
                    metadataRow(label: "Photos live", value: "\(pendingImport.package.livePhotos.count)")
                    metadataRow(label: "Images generees", value: "\(pendingImport.package.generatedImages.count)")
                    metadataRow(
                        label: "Liste d'epicerie",
                        value: pendingImport.package.groceryList == nil ? "Non incluse" : "Incluse"
                    )
                }
                .padding(16)
                .background(Color(UIColor.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(alignment: .leading, spacing: 8) {
                    Text("Utilisez cette option pour faire correspondre exactement cet appareil au package exporte depuis l'autre appareil.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("Sauvegarde automatique locale:")
                        .font(.caption.weight(.semibold))
                    Text(backupDirectoryURL.path)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                Spacer()
            }
            .padding(20)
            .navigationTitle("Confirmer l'import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler", action: onCancel)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Remplacer et importer", action: onConfirm)
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func metadataRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.subheadline.weight(.semibold))
            Spacer()
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    private static let exportDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

private enum SourceDeviceKind {
    case iphone
    case ipad
    case mac
    case generic

    init(deviceName: String) {
        let normalized = deviceName.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        if normalized.contains("iphone") {
            self = .iphone
        } else if normalized.contains("ipad") {
            self = .ipad
        } else if normalized.contains("mac") {
            self = .mac
        } else {
            self = .generic
        }
    }

    var title: String {
        switch self {
        case .iphone:
            return "Package exporte depuis iPhone"
        case .ipad:
            return "Package exporte depuis iPad"
        case .mac:
            return "Package exporte depuis Mac"
        case .generic:
            return "Package MomRecette"
        }
    }

    var systemImage: String {
        switch self {
        case .iphone:
            return "iphone"
        case .ipad:
            return "ipad"
        case .mac:
            return "laptopcomputer"
        case .generic:
            return "externaldrive.badge.icloud"
        }
    }

    var tint: Color {
        switch self {
        case .iphone:
            return .blue
        case .ipad:
            return .indigo
        case .mac:
            return .orange
        case .generic:
            return .accentColor
        }
    }
}

private struct RecipeSyncPackageDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - Lenient Import (from conversion script)

struct LenientRecipe: Codable {
    var name: String
    var category: String?
    var servings: Int?
    var caloriesPerServing: Int?
    var prepTime: Int?
    var cookTime: Int?
    var ingredients: [LenientIngredient]?
    var steps: [String]?
    var notes: String?

    struct LenientIngredient: Codable {
        var name: String
        var quantity: String?
    }

    func toRecipe() -> Recipe {
        Recipe(
            name: name,
            category: Recipe.Category(rawValue: category ?? "") ?? .autres,
            servings: servings ?? 4,
            caloriesPerServing: caloriesPerServing,
            prepTime: prepTime ?? 15,
            cookTime: cookTime ?? 30,
            ingredients: (ingredients ?? []).map {
                Recipe.Ingredient(quantity: $0.quantity ?? "", name: $0.name)
            },
            steps: steps ?? [],
            imageData: nil,
            notes: notes ?? ""
        )
    }
}

#if DEBUG
#Preview {
    ImportView()
        .environmentObject(RecipeStore())
}
#endif
