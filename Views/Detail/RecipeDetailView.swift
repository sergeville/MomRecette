import SwiftUI

// MARK: - Recipe Detail Sheet

struct RecipeDetailView: View {
    @EnvironmentObject var store: RecipeStore
    @Environment(\.dismiss) var dismiss
    @State private var showEdit = false
    @State private var showDeleteAlert = false

    let recipe: Recipe

    private var current: Recipe {
        store.recipes.first { $0.id == recipe.id } ?? recipe
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // ── Hero Photo ──────────────────────────
                    heroImage

                    // ── Info Bar ────────────────────────────
                    infoBar
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)

                    Divider()

                    // ── Ingredients ─────────────────────────
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(current.ingredients) { ing in
                                HStack(alignment: .firstTextBaseline, spacing: 10) {
                                    Circle()
                                        .fill(current.category.color)
                                        .frame(width: 6, height: 6)
                                        .padding(.top, 7)
                                    Group {
                                        if !ing.quantity.isEmpty {
                                            Text(ing.quantity).fontWeight(.semibold)
                                            + Text(" ") + Text(ing.name)
                                        } else {
                                            Text(ing.name)
                                        }
                                    }
                                    .font(.body)
                                    Spacer()
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)
                    } header: {
                        sectionHeader("Ingrédients", icon: "list.bullet")
                    }

                    Divider()

                    // ── Steps ───────────────────────────────
                    Section {
                        VStack(alignment: .leading, spacing: 16) {
                            ForEach(Array(current.steps.enumerated()), id: \.offset) { i, step in
                                HStack(alignment: .top, spacing: 14) {
                                    ZStack {
                                        Circle()
                                            .fill(current.category.color)
                                            .frame(width: 28, height: 28)
                                        Text("\(i + 1)")
                                            .font(.caption)
                                            .fontWeight(.bold)
                                            .foregroundStyle(.white)
                                    }
                                    Text(step)
                                        .font(.body)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Spacer()
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)
                    } header: {
                        sectionHeader("Préparation", icon: "checklist")
                    }

                    // ── Notes ───────────────────────────────
                    if !current.notes.isEmpty {
                        Divider()
                        Section {
                            Text(current.notes)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .italic()
                                .padding(.horizontal, 20)
                                .padding(.bottom, 16)
                        } header: {
                            sectionHeader("Notes", icon: "note.text")
                        }
                    }

                    Spacer(minLength: 40)
                }
            }
            .ignoresSafeArea(edges: .top)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Fermer") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button { showEdit = true } label: {
                            Label("Modifier", systemImage: "pencil")
                        }
                        Divider()
                        Button(role: .destructive) {
                            showDeleteAlert = true
                        } label: {
                            Label("Supprimer", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showEdit) {
                AddEditRecipeView(recipe: current)
            }
            .alert("Supprimer cette recette ?", isPresented: $showDeleteAlert) {
                Button("Supprimer", role: .destructive) {
                    store.delete(current)
                    dismiss()
                }
                Button("Annuler", role: .cancel) {}
            }
        }
    }

    // MARK: - Sub-Views

    @ViewBuilder
    private var heroImage: some View {
        ZStack(alignment: .bottomLeading) {
            if let data = current.imageData, let ui = UIImage(data: data) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 300)
                    .clipped()
            } else {
                Rectangle()
                    .fill(LinearGradient(
                        colors: [current.category.color, current.category.color.opacity(0.5)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(height: 300)
                    .overlay {
                        Text(current.category.icon)
                            .font(.system(size: 80))
                    }
            }

            // Gradient + title overlay
            LinearGradient(
                colors: [.clear, .black.opacity(0.65)],
                startPoint: .center,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 6) {
                CategoryBadge(category: current.category)
                Text(current.name)
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
            }
            .padding(20)
        }
        .frame(height: 300)
    }

    private var infoBar: some View {
        HStack(spacing: 0) {
            infoCell(icon: "clock", label: "Prép.", value: current.prepTime.timeString)
            Divider().frame(height: 40)
            infoCell(icon: "flame", label: "Cuisson", value: current.cookTime.timeString)
            Divider().frame(height: 40)
            infoCell(icon: "person.2", label: "Portions", value: "\(current.servings)")
            Divider().frame(height: 40)
            infoCell(icon: "list.bullet", label: "Ingrédients", value: "\(current.ingredients.count)")
        }
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(UIColor.secondarySystemBackground))
        )
    }

    private func infoCell(icon: String, label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(current.category.color)
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }

    private func sectionHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(current.category.color)
            Text(title)
                .font(.headline)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

#Preview {
    RecipeDetailView(recipe: Recipe.samples[0])
        .environmentObject(RecipeStore())
}
