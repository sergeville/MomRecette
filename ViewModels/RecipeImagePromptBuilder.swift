import Foundation

struct RecipeImagePromptBuilder {
    func buildPrompt(for recipe: Recipe, mode: RecipeImageMode, extraDetail: String?) -> String {
        switch mode {
        case .recipeCard:
            return recipeCardPrompt(for: recipe, extraDetail: extraDetail)
        case .dishPhoto:
            return dishPhotoPrompt(for: recipe, extraDetail: extraDetail)
        }
    }

    private func recipeCardPrompt(for recipe: Recipe, extraDetail: String?) -> String {
        let ingredients = ingredientLines(for: recipe)
        let instructions = shortInstructions(for: recipe)
        let extraNotes = formattedExtraDetail(extraDetail)

        return """
        Create a premium panoramic French recipe card image in landscape orientation.

        Recipe title:
        \(recipe.name)

        Ingredients that should be visually represented and rendered on the card:
        \(ingredients)

        Short preparation summary to include only if there is enough room and readability remains excellent:
        \(instructions)

        Art direction:
        - rustic yet elegant vintage cookbook presentation
        - aged parchment or textured recipe sheet as the main focal point
        - title clearly visible and beautifully typeset
        - ingredients clearly visible in a highly readable layout
        - optional short instructions only if the card still feels clean and balanced
        - warm food styling and appetizing culinary accents around the card
        - premium French-Canadian cookbook atmosphere
        - polished composition with natural lighting and strong readability
        - landscape composition suitable for a wide photo banner
        \(extraNotes)
        """.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func dishPhotoPrompt(for recipe: Recipe, extraDetail: String?) -> String {
        let ingredients = ingredientLines(for: recipe)
        let preparationCues = shortInstructions(for: recipe)
        let extraNotes = formattedExtraDetail(extraDetail)

        return """
        Create a premium landscape food photograph of the finished dish only.

        Dish name:
        \(recipe.name)

        Ingredients to use as visual guidance for the plating, garnish, textures, and colors:
        \(ingredients)

        Cooking context for styling only. Do not render this text in the image:
        \(preparationCues)

        Art direction:
        - no ingredient list text, no recipe card, no labels, no typography
        - show only the plated dish
        - glamorous 5-star restaurant presentation
        - cinematic premium food photography
        - landscape composition with a close zoom on the dish so it dominates the frame
        - appetizing textures, luxurious plating, elegant garnish, refined table setting
        - ingredients represented naturally in the plating or garnish
        - dramatic but tasteful lighting, polished restaurant atmosphere
        \(extraNotes)
        """.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func ingredientLines(for recipe: Recipe) -> String {
        let lines = recipe.ingredients.map { ingredient in
            if ingredient.quantity.isEmpty {
                return "- \(ingredient.name)"
            }
            return "- \(ingredient.quantity) \(ingredient.name)"
        }

        return lines.isEmpty ? "- No ingredients provided" : lines.joined(separator: "\n")
    }

    private func shortInstructions(for recipe: Recipe) -> String {
        let lines = recipe.steps
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(3)
            .enumerated()
            .map { index, step in
                "\(index + 1). \(step)"
            }

        return lines.isEmpty ? "No instructions provided." : lines.joined(separator: "\n")
    }

    private func formattedExtraDetail(_ extraDetail: String?) -> String {
        guard let extraDetail else { return "- no extra art direction provided" }
        let trimmed = extraDetail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "- no extra art direction provided" }
        return "- additional art direction: \(trimmed)"
    }
}
