import Foundation
import UIKit

struct RecipeCardImageGenerator {
    static let directoryName = "RecipeIngredientCards"
    static let defaultModel = "gpt-image-1.5"
    static let defaultSize = "1536x1024"
    static let defaultQuality = "high"
    static let defaultModeration = "auto"

    enum GenerationError: LocalizedError {
        case missingAPIKey
        case invalidResponse
        case apiError(String)

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return "OPENAI_API_KEY est introuvable. Définissez la variable d'environnement ou ajoutez-la dans un fichier .env."
            case .invalidResponse:
                return "La réponse OpenAI ne contient pas d'image valide."
            case .apiError(let message):
                return message
            }
        }
    }

    private struct ImageGenerationRequest: Encodable {
        let model: String
        let prompt: String
        let size: String
        let quality: String
        let moderation: String
    }

    private struct ImageGenerationResponse: Decodable {
        struct ImageData: Decodable {
            let b64_json: String?
        }

        let data: [ImageData]
    }

    private struct APIErrorEnvelope: Decodable {
        struct APIError: Decodable {
            let message: String
        }

        let error: APIError
    }

    static func generateAndSaveCard(for recipe: Recipe) async throws -> Data {
        let apiKey = try resolvedAPIKey()
        let requestBody = ImageGenerationRequest(
            model: defaultModel,
            prompt: buildPrompt(for: recipe),
            size: defaultSize,
            quality: defaultQuality,
            moderation: defaultModeration
        )

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/images/generations")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GenerationError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if let apiError = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data) {
                throw GenerationError.apiError(apiError.error.message)
            }

            let fallback = String(data: data, encoding: .utf8) ?? "OpenAI a retourné une erreur HTTP \(httpResponse.statusCode)."
            throw GenerationError.apiError(fallback)
        }

        let decoded = try JSONDecoder().decode(ImageGenerationResponse.self, from: data)
        guard
            let imageBase64 = decoded.data.first?.b64_json,
            let imageData = Data(base64Encoded: imageBase64),
            UIImage(data: imageData) != nil
        else {
            throw GenerationError.invalidResponse
        }

        let destinationURL = ingredientCardURL(for: recipe)
        try FileManager.default.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try imageData.write(to: destinationURL, options: .atomic)
        return imageData
    }

    static func ingredientCardURL(for recipe: Recipe) -> URL {
        liveDirectoryURL().appendingPathComponent(recipe.suggestedIngredientCardFilename)
    }

    static func liveDirectoryURL() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent(directoryName, isDirectory: true)
    }

    private static func buildPrompt(for recipe: Recipe) -> String {
        let ingredientLines = recipe.ingredients.map { ingredient in
            if ingredient.quantity.isEmpty {
                return "- \(ingredient.name)"
            }
            return "- \(ingredient.quantity) \(ingredient.name)"
        }.joined(separator: "\n")

        return """
        Create a high-quality horizontal French vintage recipe card image in a panoramic landscape composition.

        Recipe title:
        \(recipe.name)

        Ingredients to visually incorporate and also render on the card:
        \(ingredientLines)

        Design requirements:
        - panoramic landscape layout with the ingredients list clearly readable
        - rustic wood table background
        - aged parchment or old-paper recipe sheet as the main focal point
        - elegant red handwritten or script-style recipe title
        - warm natural food-photography lighting
        - decorative culinary elements arranged around the card
        - coherent French cookbook aesthetic
        - make the card look premium, appetizing, and polished
        - keep the composition readable and balanced
        - include the recipe title prominently
        - include the ingredient list in French in a clean readable layout
        - output as a finished poster-like recipe card image
        """.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func resolvedAPIKey() throws -> String {
        if let value = ProcessInfo.processInfo.environment["OPENAI_API_KEY"]?.trimmedNonEmpty {
            return value
        }

        for candidate in dotenvCandidateURLs() {
            guard let content = try? String(contentsOf: candidate, encoding: .utf8) else { continue }
            if let key = parseAPIKey(from: content) {
                return key
            }
        }

        throw GenerationError.missingAPIKey
    }

    private static func parseAPIKey(from content: String) -> String? {
        for rawLine in content.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }

            if line.hasPrefix("OPENAI_API_KEY=") {
                return String(line.dropFirst("OPENAI_API_KEY=".count))
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
                    .trimmedNonEmpty
            }

            if line.hasPrefix("sk-") {
                return line.trimmedNonEmpty
            }
        }

        return nil
    }

    private static func dotenvCandidateURLs() -> [URL] {
        var urls: [URL] = [
            liveDirectoryURL().deletingLastPathComponent().appendingPathComponent(".env"),
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".env")
        ]

        #if DEBUG
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        urls.append(sourceRoot.appendingPathComponent(".env"))
        #endif

        return Array(NSOrderedSet(array: urls)) as? [URL] ?? urls
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
