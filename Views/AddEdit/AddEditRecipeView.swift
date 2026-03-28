import SwiftUI

// MARK: - Add / Edit Recipe Form

struct AddEditRecipeView: View {
    @EnvironmentObject var store: RecipeStore
    @Environment(\.dismiss) var dismiss

    // Initialise with existing recipe (edit) or empty (add)
    init(recipe: Recipe? = nil) {
        if let r = recipe {
            _editingId    = State(initialValue: r.id)
            _name         = State(initialValue: r.name)
            _category     = State(initialValue: r.category)
            _servings     = State(initialValue: r.servings)
            _prepTime     = State(initialValue: r.prepTime)
            _cookTime     = State(initialValue: r.cookTime)
            _ingredients  = State(initialValue: r.ingredients)
            _steps        = State(initialValue: r.steps)
            _notes        = State(initialValue: r.notes)
            _imageData    = State(initialValue: r.imageData)
        }
    }

    @State private var editingId: UUID? = nil
    @State private var name: String = ""
    @State private var category: Recipe.Category = .plats
    @State private var servings: Int = 4
    @State private var prepTime: Int = 15
    @State private var cookTime: Int = 30
    @State private var ingredients: [Recipe.Ingredient] = [Recipe.Ingredient(name: "")]
    @State private var steps: [String] = [""]
    @State private var notes: String = ""
    @State private var imageData: Data? = nil

    @State private var nameError = false

    var isEditing: Bool { editingId != nil }

    var body: some View {
        NavigationStack {
            Form {
                // ── Photo ────────────────────────────────
                Section {
                    ImagePickerButton(imageData: $imageData)
                        .listRowInsets(.init())
                        .listRowBackground(Color.clear)
                }

                // ── Basics ───────────────────────────────
                Section("Recette") {
                    TextField("Nom de la recette", text: $name)
                        .font(.headline)
                        .overlay(alignment: .leading) {
                            if nameError {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundStyle(.red)
                                    .offset(x: -24)
                            }
                        }

                    Picker("Catégorie", selection: $category) {
                        ForEach(Recipe.Category.allCases) { cat in
                            Label(cat.rawValue, systemImage: "")
                                .tag(cat)
                        }
                    }
                }

                // ── Timing & Servings ────────────────────
                Section("Temps & Portions") {
                    Stepper("Portions: \(servings)", value: $servings, in: 1...50)
                    Stepper("Préparation: \(prepTime) min",
                            value: $prepTime, in: 0...300, step: 5)
                    Stepper("Cuisson: \(cookTime) min",
                            value: $cookTime, in: 0...480, step: 5)
                }

                // ── Ingredients ──────────────────────────
                Section {
                    ForEach($ingredients) { $ing in
                        HStack(spacing: 10) {
                            TextField("Qté", text: $ing.quantity)
                                .frame(width: 70)
                                .foregroundStyle(.secondary)
                            Divider()
                            TextField("Ingrédient", text: $ing.name)
                        }
                    }
                    .onDelete { ingredients.remove(atOffsets: $0) }
                    .onMove { ingredients.move(fromOffsets: $0, toOffset: $1) }

                    Button {
                        withAnimation { ingredients.append(Recipe.Ingredient(name: "")) }
                    } label: {
                        Label("Ajouter un ingrédient", systemImage: "plus.circle.fill")
                    }
                } header: {
                    HStack {
                        Text("Ingrédients")
                        Spacer()
                        EditButton()
                    }
                }

                // ── Steps ────────────────────────────────
                Section {
                    ForEach(Array($steps.enumerated()), id: \.offset) { i, $step in
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(i + 1).")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.top, 10)
                            TextEditor(text: $step)
                                .frame(minHeight: 60)
                        }
                    }
                    .onDelete { steps.remove(atOffsets: $0) }
                    .onMove { steps.move(fromOffsets: $0, toOffset: $1) }

                    Button {
                        withAnimation { steps.append("") }
                    } label: {
                        Label("Ajouter une étape", systemImage: "plus.circle.fill")
                    }
                } header: {
                    HStack {
                        Text("Préparation")
                        Spacer()
                        EditButton()
                    }
                }

                // ── Notes ────────────────────────────────
                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 80)
                }
            }
            .navigationTitle(isEditing ? "Modifier" : "Nouvelle recette")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { save() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Save

    private func save() {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            withAnimation { nameError = true }
            return
        }
        nameError = false

        let cleaned = Recipe(
            id: editingId ?? UUID(),
            name: name.trimmingCharacters(in: .whitespaces),
            category: category,
            servings: servings,
            prepTime: prepTime,
            cookTime: cookTime,
            ingredients: ingredients.filter { !$0.name.isEmpty },
            steps: steps.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty },
            imageData: imageData,
            notes: notes,
            createdAt: Date()
        )

        if isEditing {
            store.update(cleaned)
        } else {
            store.add(cleaned)
        }
        dismiss()
    }
}

#Preview {
    AddEditRecipeView()
        .environmentObject(RecipeStore())
}
