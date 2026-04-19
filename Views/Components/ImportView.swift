import SwiftUI
import UniformTypeIdentifiers

// MARK: - Import Recipes

struct ImportView: View {
    @EnvironmentObject var store: RecipeStore
    @Environment(\.dismiss) var dismiss

    @State private var showJSONFilePicker = false
    @State private var showPhotoPicker = false
    @State private var importResult: ImportResult? = nil
    @State private var isLoading = false

    enum ImportResult {
        case success(Int)
        case duplicate(Int, Int)   // imported, skipped
        case photos(RecipeStore.RecipePhotoBatchImportResult)
        case error(String)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                VStack(spacing: 12) {
                    Image(systemName: "square.and.arrow.down.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(Color.accentColor)
                    Text("Importer dans MomRecette")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Importez un fichier JSON de recettes\nou plusieurs photos nommées comme vos recettes.")
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
                }

                if isLoading {
                    ProgressView("Importation en cours…")
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
            .navigationTitle("Importation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func resultView(_ result: ImportResult) -> some View {
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
            case .error(let msg):
                Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                Text(msg).lineLimit(2)
            }
        }
        .font(.subheadline)
        .padding(14)
        .background(Color(UIColor.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
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
}

// MARK: - Lenient Import (from conversion script)

struct LenientRecipe: Codable {
    var name: String
    var category: String?
    var servings: Int?
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
