import SwiftUI

// MARK: - Rolodex Card

struct RecipeCardView: View {
    let recipe: Recipe
    var isTop: Bool = true

    private var hasPhoto: Bool {
        recipe.imageData != nil
    }

    private var featuredIngredientGroups: [Recipe.IngredientGroup] {
        Array(recipe.ingredientGroups.prefix(2))
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            posterBackground

            LinearGradient(
                colors: [.clear, .black.opacity(0.06), .black.opacity(0.72)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    CategoryBadge(category: recipe.category)
                    Spacer()
                    Text(hasPhoto ? "Affiche recette" : "Ajouter une photo")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.94))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(.black.opacity(0.26))
                        )
                        .overlay(
                            Capsule()
                                .stroke(.white.opacity(0.14), lineWidth: 1)
                        )
                }

                Spacer()

                if !featuredIngredientGroups.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(featuredIngredientGroups) { group in
                                HStack(spacing: 6) {
                                    Text(group.kind.icon)
                                    Text(group.kind.title)
                                }
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.96))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(.black.opacity(0.22))
                                )
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text(recipe.name)
                        .font(.title2.weight(.bold))
                        .lineLimit(2)
                        .foregroundStyle(.white)

                    HStack(spacing: 16) {
                        posterMetric("clock", recipe.totalTime.timeString)
                        posterMetric("person.2", "\(recipe.servings) portions")
                        posterMetric("list.bullet", "\(recipe.ingredients.count) ingrédients")
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.ultraThinMaterial.opacity(0.82))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(.white.opacity(0.14), lineWidth: 1)
                )
            }
            .padding(18)
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.22), radius: 22, x: 0, y: 12)
        .frame(width: cardWidth, height: cardHeight)
    }

    @ViewBuilder
    private var posterBackground: some View {
        if hasPhoto, let data = recipe.imageData, let ui = UIImage(data: data) {
            Image(uiImage: ui)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .scaleEffect(1.04)
                .saturation(1.08)
                .clipped()
        } else {
            ZStack {
                LinearGradient(
                    colors: [
                        recipe.category.color.opacity(0.92),
                        recipe.category.color.opacity(0.58),
                        .black.opacity(0.18)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                VStack(spacing: 12) {
                    Text(recipe.category.icon)
                        .font(.system(size: 82))
                    Text("Ajoutez une vraie photo du plat")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
        }
    }

    private func posterMetric(_ systemName: String, _ value: String) -> some View {
        Label(value, systemImage: systemName)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.92))
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

#if DEBUG
#Preview {
    RecipeCardView(recipe: Recipe.samples[0])
        .padding()
}
#endif
