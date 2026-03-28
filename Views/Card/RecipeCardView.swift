import SwiftUI

// MARK: - Rolodex Card

struct RecipeCardView: View {
    let recipe: Recipe
    var isTop: Bool = true

    private var cardImage: Image {
        if let data = recipe.imageData, let ui = UIImage(data: data) {
            return Image(uiImage: ui)
        }
        return Image(systemName: "fork.knife")
    }

    private var hasPhoto: Bool {
        recipe.imageData != nil
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Background card
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(UIColor.systemBackground))
                .shadow(color: .black.opacity(0.18), radius: 16, x: 0, y: 8)

            VStack(spacing: 0) {
                // ── Photo / Placeholder ─────────────────────
                ZStack {
                    if hasPhoto, let data = recipe.imageData, let ui = UIImage(data: data) {
                        Image(uiImage: ui)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity)
                            .frame(height: 280)
                            .clipped()
                    } else {
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        recipe.category.color.opacity(0.7),
                                        recipe.category.color.opacity(0.4)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(maxWidth: .infinity)
                            .frame(height: 280)
                            .overlay {
                                VStack(spacing: 8) {
                                    Text(recipe.category.icon)
                                        .font(.system(size: 72))
                                    Text("Ajouter une photo")
                                        .font(.caption)
                                        .foregroundStyle(.white.opacity(0.8))
                                }
                            }
                    }

                    // Gradient overlay for readability
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.4)],
                        startPoint: .center,
                        endPoint: .bottom
                    )
                }
                .clipShape(UnevenRoundedRectangle(
                    topLeadingRadius: 20,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 20
                ))

                // ── Card Info ───────────────────────────────
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        CategoryBadge(category: recipe.category)
                        Spacer()
                        Image(systemName: "clock")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(recipe.totalTime.timeString)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Text(recipe.name)
                        .font(.title2)
                        .fontWeight(.bold)
                        .lineLimit(2)
                        .foregroundStyle(.primary)

                    HStack(spacing: 16) {
                        Label("\(recipe.servings) portions", systemImage: "person.2")
                        Label("\(recipe.ingredients.count) ingrédients", systemImage: "list.bullet")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
        }
        .frame(width: cardWidth, height: cardHeight)
    }

    private var cardWidth: CGFloat { 340 }
    private var cardHeight: CGFloat { 420 }
}

// MARK: - Category Badge

struct CategoryBadge: View {
    let category: Recipe.Category

    var body: some View {
        HStack(spacing: 4) {
            Text(category.icon)
                .font(.caption2)
            Text(category.rawValue)
                .font(.caption2)
                .fontWeight(.semibold)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(category.color.opacity(0.15))
        .foregroundStyle(category.color)
        .clipShape(Capsule())
    }
}

// MARK: - Preview

#Preview {
    RecipeCardView(recipe: Recipe.samples[0])
        .padding()
}
