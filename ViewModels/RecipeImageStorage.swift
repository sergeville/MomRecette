import Foundation
import UIKit

struct RecipeImageStorage {
    struct StoredImage {
        let filename: String
        let data: Data
        let url: URL
    }

    enum StorageError: LocalizedError {
        case invalidImageData

        var errorDescription: String? {
            switch self {
            case .invalidImageData:
                return "L'image générée est invalide et n'a pas pu être enregistrée."
            }
        }
    }

    let directoryURL: URL

    func saveImage(_ data: Data, for recipe: Recipe) throws -> StoredImage {
        try writeImage(data, filename: makeFilename(for: recipe.name))
    }

    func replaceImage(_ data: Data, for recipe: Recipe, replacing existingFilename: String?) throws -> StoredImage {
        let stored = try saveImage(data, for: recipe)

        if let existingFilename, existingFilename != stored.filename {
            try? deleteImage(named: existingFilename)
        }

        return stored
    }

    func loadImage(named filename: String) -> Data? {
        let url = imageURL(for: filename)
        guard let data = try? Data(contentsOf: url), UIImage(data: data) != nil else { return nil }
        return data
    }

    func deleteImage(named filename: String) throws {
        let url = imageURL(for: filename)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    func imageURL(for filename: String) -> URL {
        directoryURL.appendingPathComponent(filename)
    }

    private func writeImage(_ data: Data, filename: String) throws -> StoredImage {
        try ensureDirectoryExists()

        guard let image = UIImage(data: data), let normalizedData = image.pngData() else {
            throw StorageError.invalidImageData
        }

        let url = imageURL(for: filename)
        try normalizedData.write(to: url, options: .atomic)
        return StoredImage(filename: filename, data: normalizedData, url: url)
    }

    private func ensureDirectoryExists() throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    private func makeFilename(for title: String) -> String {
        let timestamp = Self.timestampFormatter.string(from: Date())
        let slug = title.photoLookupKey.isEmpty ? "recipe-image" : title.photoLookupKey
        return "\(slug)-\(timestamp).png"
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return formatter
    }()
}
