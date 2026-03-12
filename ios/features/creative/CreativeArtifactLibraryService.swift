import Foundation
import UIKit

struct ArtifactSearchResult {
    let id: String
    let mediaType: CreativeMediaType
    let prompt: String
    let createdAt: Date
}

protocol CreativeArtifactLibrarying {
    func saveArtifact(artifactId: String, result: CreativeResult) throws -> CreativeResult
    func loadLatestArtifact(preferredMediaType: CreativeMediaType?) throws -> CreativeResult?
    func searchArtifacts(query: String, mediaType: CreativeMediaType?) throws -> [ArtifactSearchResult]
    func loadArtifact(by id: String) throws -> CreativeResult?
    func deleteArtifact(id: String) throws
    func listArtifactIds() throws -> [String]
}

private struct CreativeArtifactRecord: Codable, Equatable, Identifiable {
    let id: String
    let mediaType: CreativeMediaType
    let prompt: String
    let createdAt: Date
    let imageFileName: String?
    let videoFileName: String?
    let audioFileName: String?
    let composedVideoFileName: String?
}

final class CreativeArtifactLibraryService: CreativeArtifactLibrarying {
    private let fileManager: FileManager
    private let rootURL: URL

    init(
        rootURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        if let rootURL {
            self.rootURL = rootURL
        } else {
            self.rootURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first!
                .appendingPathComponent("CreativeArtifacts", isDirectory: true)
        }
    }

    func saveArtifact(artifactId: String, result: CreativeResult) throws -> CreativeResult {
        try ensureDirectories()

        let storedImageFileName = try saveImageIfNeeded(artifactId: artifactId, image: result.image)
        let storedVideoFileName = try copyFileIfNeeded(
            artifactId: artifactId,
            sourceURL: result.videoURL,
            defaultExtension: "mp4",
            suffix: "video"
        )
        let storedAudioFileName = try saveAudioIfNeeded(artifactId: artifactId, audioData: result.audioData)
        let storedComposedVideoFileName = try copyFileIfNeeded(
            artifactId: artifactId,
            sourceURL: result.composedVideoURL,
            defaultExtension: "mp4",
            suffix: "composed"
        )

        var records = try loadRecords()
        let record = CreativeArtifactRecord(
            id: artifactId,
            mediaType: result.mediaType,
            prompt: result.prompt,
            createdAt: Date(),
            imageFileName: storedImageFileName,
            videoFileName: storedVideoFileName,
            audioFileName: storedAudioFileName,
            composedVideoFileName: storedComposedVideoFileName
        )

        records.removeAll { $0.id == artifactId }
        records.append(record)
        try persist(records: records)

        return try loadResult(from: record)
    }

    func loadLatestArtifact(preferredMediaType: CreativeMediaType? = nil) throws -> CreativeResult? {
        let records = try loadRecords()
        let matchingRecords = records
            .filter { preferredMediaType == nil || $0.mediaType == preferredMediaType }
            .sorted { $0.createdAt > $1.createdAt }

        guard let record = matchingRecords.first else { return nil }
        return try loadResult(from: record)
    }

    func searchArtifacts(query: String, mediaType: CreativeMediaType? = nil) throws -> [ArtifactSearchResult] {
        let records = try loadRecords()
        let queryLower = query.lowercased()
        return records
            .filter { record in
                let matchesType = mediaType == nil || record.mediaType == mediaType
                let matchesQuery = record.prompt.lowercased().contains(queryLower)
                return matchesType && matchesQuery
            }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(5)
            .map { ArtifactSearchResult(id: $0.id, mediaType: $0.mediaType, prompt: $0.prompt, createdAt: $0.createdAt) }
    }

    func loadArtifact(by id: String) throws -> CreativeResult? {
        let records = try loadRecords()
        guard let record = records.first(where: { $0.id == id }) else { return nil }
        return try loadResult(from: record)
    }

    func deleteArtifact(id: String) throws {
        var records = try loadRecords()
        guard let record = records.first(where: { $0.id == id }) else { return }

        // Delete associated files
        let fileNames = [record.imageFileName, record.videoFileName, record.audioFileName, record.composedVideoFileName]
        for fileName in fileNames.compactMap({ $0 }) {
            let fileURL = filesDirectoryURL.appendingPathComponent(fileName)
            if fileManager.fileExists(atPath: fileURL.path) {
                try fileManager.removeItem(at: fileURL)
            }
        }

        records.removeAll { $0.id == id }
        try persist(records: records)
    }

    func listArtifactIds() throws -> [String] {
        let records = try loadRecords()
        // Records are appended chronologically; enumerate for stable tiebreaking
        return records
            .enumerated()
            .sorted { lhs, rhs in
                if lhs.element.createdAt == rhs.element.createdAt {
                    return lhs.offset > rhs.offset // later index = newer
                }
                return lhs.element.createdAt > rhs.element.createdAt
            }
            .map { $0.element.id }
    }

    private func ensureDirectories() throws {
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: filesDirectoryURL, withIntermediateDirectories: true)
    }

    private func loadRecords() throws -> [CreativeArtifactRecord] {
        guard fileManager.fileExists(atPath: indexURL.path) else { return [] }
        let data = try Data(contentsOf: indexURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([CreativeArtifactRecord].self, from: data)
    }

    private func persist(records: [CreativeArtifactRecord]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(records)
        try data.write(to: indexURL, options: .atomic)
    }

    private func loadResult(from record: CreativeArtifactRecord) throws -> CreativeResult {
        let image: UIImage?
        if let imageFileName = record.imageFileName {
            let data = try Data(contentsOf: filesDirectoryURL.appendingPathComponent(imageFileName))
            image = UIImage(data: data)
        } else {
            image = nil
        }

        let audioData: Data?
        if let audioFileName = record.audioFileName {
            audioData = try Data(contentsOf: filesDirectoryURL.appendingPathComponent(audioFileName))
        } else {
            audioData = nil
        }

        let videoURL = record.videoFileName.map { filesDirectoryURL.appendingPathComponent($0) }
        let composedVideoURL = record.composedVideoFileName.map { filesDirectoryURL.appendingPathComponent($0) }

        return CreativeResult(
            mediaType: record.mediaType,
            image: image,
            videoURL: videoURL,
            audioData: audioData,
            composedVideoURL: composedVideoURL,
            prompt: record.prompt
        )
    }

    private func saveImageIfNeeded(artifactId: String, image: UIImage?) throws -> String? {
        guard let image, let data = image.pngData() else { return nil }
        let fileName = "\(artifactId)-image.png"
        try data.write(to: filesDirectoryURL.appendingPathComponent(fileName), options: .atomic)
        return fileName
    }

    private func saveAudioIfNeeded(artifactId: String, audioData: Data?) throws -> String? {
        guard let audioData else { return nil }
        let fileName = "\(artifactId)-audio.m4a"
        try audioData.write(to: filesDirectoryURL.appendingPathComponent(fileName), options: .atomic)
        return fileName
    }

    private func copyFileIfNeeded(
        artifactId: String,
        sourceURL: URL?,
        defaultExtension: String,
        suffix: String
    ) throws -> String? {
        guard let sourceURL else { return nil }
        let ext = sourceURL.pathExtension.isEmpty ? defaultExtension : sourceURL.pathExtension
        let fileName = "\(artifactId)-\(suffix).\(ext)"
        let destinationURL = filesDirectoryURL.appendingPathComponent(fileName)
        let sameFile = sourceURL.standardizedFileURL == destinationURL.standardizedFileURL

        if !sameFile, fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }

        if !sameFile {
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
        }

        return fileName
    }

    private var indexURL: URL {
        rootURL.appendingPathComponent("index.json")
    }

    private var filesDirectoryURL: URL {
        rootURL.appendingPathComponent("files", isDirectory: true)
    }
}
