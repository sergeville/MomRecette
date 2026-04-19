import Foundation
import UIKit

protocol RecipeImageGenerating {
    func generateImage(for recipe: Recipe, mode: RecipeImageMode, extraDetail: String?) async throws -> Data
}

struct RecipeImageIssue: LocalizedError, Identifiable {
    let id: String
    let title: String
    let message: String
    let recoverySuggestion: String
    let debugDetail: String?

    var errorDescription: String? {
        "\(title) [\(id)]"
    }

    static func from(_ error: Error) -> RecipeImageIssue {
        if let issue = error as? RecipeImageIssue {
            return issue
        }

        if let error = error as? OpenAIRecipeImageGenerator.GenerationError {
            return from(error)
        }

        if let error = error as? RecipeStore.RecipeImageError {
            return from(error)
        }

        if let error = error as? RecipeImageStorage.StorageError {
            return from(error)
        }

        return RecipeImageIssue(
            id: "IMG-UNK-001",
            title: "Image generation failed",
            message: "MomRecette could not finish generating the image.",
            recoverySuggestion: "Try again. If the problem keeps happening, keep the diagnostic ID and the debug detail.",
            debugDetail: String(describing: error)
        )
    }

    private static func from(_ error: OpenAIRecipeImageGenerator.GenerationError) -> RecipeImageIssue {
        switch error {
        case .missingAPIKey:
            return RecipeImageIssue(
                id: "IMG-KEY-001",
                title: "OpenAI key not configured",
                message: "The app could not find an `OPENAI_API_KEY`, so it cannot contact the image service.",
                recoverySuggestion: "Add `OPENAI_API_KEY` to the environment or to a local `.env` file, then try again.",
                debugDetail: nil
            )
        case .requestEncodingFailed(let detail):
            return RecipeImageIssue(
                id: "IMG-REQ-001",
                title: "Request could not be prepared",
                message: "The image request could not be encoded before it was sent.",
                recoverySuggestion: "Try again. If it keeps failing, keep the diagnostic ID for debugging.",
                debugDetail: detail
            )
        case .network(let urlError):
            return from(urlError)
        case .invalidHTTPResponse:
            return RecipeImageIssue(
                id: "IMG-RESP-001",
                title: "Unexpected server response",
                message: "The image service returned a response MomRecette could not understand.",
                recoverySuggestion: "Try again in a moment. If it repeats, keep the diagnostic ID for debugging.",
                debugDetail: nil
            )
        case .apiError(let statusCode, let message):
            return fromAPIError(statusCode: statusCode, message: message)
        case .responseDecodingFailed(let detail):
            return RecipeImageIssue(
                id: "IMG-RESP-002",
                title: "Image response could not be decoded",
                message: "The server answered, but the image payload could not be read correctly.",
                recoverySuggestion: "Try again. If the same recipe keeps failing, keep the diagnostic ID and debug detail.",
                debugDetail: detail
            )
        case .invalidImageData:
            return RecipeImageIssue(
                id: "IMG-DATA-001",
                title: "Generated image was invalid",
                message: "The service responded, but the returned image data was not usable.",
                recoverySuggestion: "Try again with a simpler style note, or switch image mode and retry.",
                debugDetail: nil
            )
        }
    }

    private static func from(_ error: RecipeStore.RecipeImageError) -> RecipeImageIssue {
        switch error {
        case .recipeNotFound:
            return RecipeImageIssue(
                id: "IMG-REC-001",
                title: "Recipe could not be found",
                message: "The selected recipe no longer exists in the current store state.",
                recoverySuggestion: "Close the sheet, reopen the recipe, and try again.",
                debugDetail: nil
            )
        }
    }

    private static func from(_ error: RecipeImageStorage.StorageError) -> RecipeImageIssue {
        switch error {
        case .invalidImageData:
            return RecipeImageIssue(
                id: "IMG-STO-001",
                title: "Image could not be saved",
                message: "MomRecette received data, but it was not a valid image to store locally.",
                recoverySuggestion: "Try again. If it keeps happening, keep the diagnostic ID for debugging.",
                debugDetail: nil
            )
        }
    }

    private static func from(_ error: URLError) -> RecipeImageIssue {
        switch error.code {
        case .notConnectedToInternet, .internationalRoamingOff, .dataNotAllowed:
            return RecipeImageIssue(
                id: "IMG-NET-001",
                title: "No internet connection",
                message: "MomRecette could not reach the image service because the device appears to be offline.",
                recoverySuggestion: "Check your network connection, then try again.",
                debugDetail: error.localizedDescription
            )
        case .timedOut:
            return RecipeImageIssue(
                id: "IMG-NET-002",
                title: "The request timed out",
                message: "The image service took too long to respond.",
                recoverySuggestion: "Try again in a moment, ideally on a stable network.",
                debugDetail: error.localizedDescription
            )
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed, .networkConnectionLost:
            return RecipeImageIssue(
                id: "IMG-NET-003",
                title: "The image service could not be reached",
                message: "MomRecette could not establish a stable connection to the image server.",
                recoverySuggestion: "Try again shortly. If the issue persists, keep the diagnostic ID.",
                debugDetail: error.localizedDescription
            )
        case .userAuthenticationRequired, .userCancelledAuthentication:
            return RecipeImageIssue(
                id: "IMG-AUTH-001",
                title: "Authentication was interrupted",
                message: "The request could not continue because authentication was not completed.",
                recoverySuggestion: "Verify your API key configuration, then try again.",
                debugDetail: error.localizedDescription
            )
        default:
            return RecipeImageIssue(
                id: "IMG-NET-999",
                title: "Network error during image generation",
                message: "MomRecette could not complete the request because of a network problem.",
                recoverySuggestion: "Try again. If it repeats, keep the diagnostic ID and debug detail.",
                debugDetail: error.localizedDescription
            )
        }
    }

    private static func fromAPIError(statusCode: Int, message: String?) -> RecipeImageIssue {
        let detail = message?.trimmedNonEmpty

        switch statusCode {
        case 400:
            return RecipeImageIssue(
                id: "IMG-API-400",
                title: "The image request was rejected",
                message: "The image service rejected the request parameters or prompt.",
                recoverySuggestion: "Try again with a shorter or simpler “More detail” note.",
                debugDetail: detail
            )
        case 401, 403:
            return RecipeImageIssue(
                id: "IMG-API-401",
                title: "Authentication failed",
                message: "The image service refused the request because the credentials were not accepted.",
                recoverySuggestion: "Verify `OPENAI_API_KEY`, then try again.",
                debugDetail: detail
            )
        case 429:
            return RecipeImageIssue(
                id: "IMG-API-429",
                title: "Rate limit reached",
                message: "The image service is temporarily limiting requests for this account.",
                recoverySuggestion: "Wait a moment, then try again.",
                debugDetail: detail
            )
        case 500...599:
            return RecipeImageIssue(
                id: "IMG-API-5XX",
                title: "The image service is temporarily unavailable",
                message: "The server failed while trying to generate the image.",
                recoverySuggestion: "Try again shortly.",
                debugDetail: detail
            )
        default:
            return RecipeImageIssue(
                id: "IMG-API-\(statusCode)",
                title: "The image service returned an error",
                message: "The server rejected the request.",
                recoverySuggestion: "Try again. If it repeats, keep the diagnostic ID and debug detail.",
                debugDetail: detail
            )
        }
    }
}

struct OpenAIRecipeImageGenerator: RecipeImageGenerating {
    enum GenerationError: LocalizedError {
        case missingAPIKey
        case requestEncodingFailed(String)
        case network(URLError)
        case invalidHTTPResponse
        case apiError(statusCode: Int, message: String?)
        case responseDecodingFailed(String)
        case invalidImageData

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return "OPENAI_API_KEY est introuvable. Définissez la variable d'environnement ou ajoutez-la dans un fichier .env."
            case .requestEncodingFailed:
                return "La requête d'image n'a pas pu être préparée."
            case .network(let error):
                return error.localizedDescription
            case .invalidHTTPResponse:
                return "La réponse réseau n'est pas valide."
            case .apiError(_, let message):
                return message ?? "OpenAI a retourné une erreur."
            case .responseDecodingFailed:
                return "La réponse OpenAI n'a pas pu être décodée."
            case .invalidImageData:
                return "La réponse OpenAI ne contient pas d'image valide."
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

    let promptBuilder: RecipeImagePromptBuilder
    let model: String
    let quality: String
    let moderation: String

    init(
        promptBuilder: RecipeImagePromptBuilder = RecipeImagePromptBuilder(),
        model: String = "gpt-image-1.5",
        quality: String = "high",
        moderation: String = "auto"
    ) {
        self.promptBuilder = promptBuilder
        self.model = model
        self.quality = quality
        self.moderation = moderation
    }

    func generateImage(for recipe: Recipe, mode: RecipeImageMode, extraDetail: String?) async throws -> Data {
        let apiKey = try resolvedAPIKey()
        let prompt = promptBuilder.buildPrompt(for: recipe, mode: mode, extraDetail: extraDetail)
        let requestBody = ImageGenerationRequest(
            model: model,
            prompt: prompt,
            size: size(for: mode),
            quality: quality,
            moderation: moderation
        )

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/images/generations")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        do {
            request.httpBody = try JSONEncoder().encode(requestBody)
        } catch {
            throw GenerationError.requestEncodingFailed(String(describing: error))
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError {
            throw GenerationError.network(error)
        } catch {
            throw error
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GenerationError.invalidHTTPResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if let apiError = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data) {
                throw GenerationError.apiError(
                    statusCode: httpResponse.statusCode,
                    message: apiError.error.message
                )
            }

            let fallback = String(data: data, encoding: .utf8)
            throw GenerationError.apiError(statusCode: httpResponse.statusCode, message: fallback)
        }

        let decoded: ImageGenerationResponse
        do {
            decoded = try JSONDecoder().decode(ImageGenerationResponse.self, from: data)
        } catch {
            throw GenerationError.responseDecodingFailed(String(describing: error))
        }

        guard
            let imageBase64 = decoded.data.first?.b64_json,
            let imageData = Data(base64Encoded: imageBase64),
            UIImage(data: imageData) != nil
        else {
            throw GenerationError.invalidImageData
        }

        return imageData
    }

    private func size(for mode: RecipeImageMode) -> String {
        switch mode {
        case .recipeCard, .dishPhoto:
            return "1536x1024"
        }
    }

    private func resolvedAPIKey() throws -> String {
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

    private func parseAPIKey(from content: String) -> String? {
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

    private func dotenvCandidateURLs() -> [URL] {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        var urls: [URL] = [
            docs.appendingPathComponent(".env"),
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

struct MockRecipeImageGenerator: RecipeImageGenerating {
    let imageData: Data

    func generateImage(for recipe: Recipe, mode: RecipeImageMode, extraDetail: String?) async throws -> Data {
        imageData
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
