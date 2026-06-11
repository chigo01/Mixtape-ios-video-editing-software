//
//  ProjectStore.swift
//  Mixtape
//

import Foundation

enum ProjectStoreError: LocalizedError {
    case encodeFailed
    case decodeFailed

    var errorDescription: String? {
        switch self {
        case .encodeFailed: return "Could not save the project file."
        case .decodeFailed: return "Could not read the project file."
        }
    }
}

/// JSON project files in Application Support (clip IDs + trim, not raw video).
@MainActor
final class ProjectStore {
    static let shared = ProjectStore()

    private let directoryName = "MixtapeProjects"
    private let fileExtension = "json"
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private init() {}

    func loadAll() throws -> [EditorProject] {
        let directory = try projectsDirectory()
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension == fileExtension }

        let projects: [EditorProject] = try urls.compactMap { url in
            let data = try Data(contentsOf: url)
            return try decoder.decode(EditorProject.self, from: data)
        }

        return projects.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    func save(_ project: EditorProject) throws {
        var project = project
        project.modifiedAt = Date()
        let data = try encoder.encode(project)
        guard !data.isEmpty else { throw ProjectStoreError.encodeFailed }

        let url = try fileURL(for: project.id)
        try data.write(to: url, options: .atomic)
    }

    func delete(id: UUID) throws {
        let url = try fileURL(for: id)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private func projectsDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appendingPathComponent(directoryName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    private func fileURL(for id: UUID) throws -> URL {
        try projectsDirectory().appendingPathComponent("\(id.uuidString).\(fileExtension)")
    }
}
