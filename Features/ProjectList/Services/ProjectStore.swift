//
//  ProjectStore.swift
//  Mixtape
//

import Foundation
import Photos
import UIKit

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

enum EditorTemplateStoreError: LocalizedError {
    case invalidName
    case unsupportedVersion
    case cannotEncode

    var errorDescription: String? {
        switch self {
        case .invalidName: return "Enter a name for this template."
        case .unsupportedVersion: return "This template was created by a newer Mixtape version."
        case .cannotEncode: return "The template could not be saved."
        }
    }
}

struct EditorTemplateValidation: Equatable {
    var missingMedia = 0
    var missingAudio = 0
    var missingGraphics = 0
    var missingCanvasArtwork = 0

    var issueCount: Int { missingMedia + missingAudio + missingGraphics + missingCanvasArtwork }
    var isReady: Bool { issueCount == 0 }
}

/// Versioned, local template packages. Referenced audio, imported graphics, canvas
/// artwork, and the preview thumbnail live inside the package; applying a template
/// materializes private copies so deleting the template cannot damage a project.
@MainActor
final class EditorTemplateStore {
    static let shared = EditorTemplateStore()

    private let folderName = "MixtapeTemplates"
    private let appliedAssetsFolderName = "MixtapeTemplateAppliedAssets"
    private let encoder: JSONEncoder = {
        let value = JSONEncoder()
        value.outputFormatting = [.prettyPrinted, .sortedKeys]
        value.dateEncodingStrategy = .iso8601
        return value
    }()
    private let decoder: JSONDecoder = {
        let value = JSONDecoder()
        value.dateDecodingStrategy = .iso8601
        return value
    }()

    private init() {}

    func loadAll() -> [EditorProjectTemplate] {
        guard let root = try? rootDirectory(),
              let folders = try? FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
              ) else { return [] }
        return folders.compactMap { folder in
            let url = folder.appendingPathComponent("template.json")
            guard let data = try? Data(contentsOf: url),
                  let decoded = try? decoder.decode(EditorProjectTemplate.self, from: data),
                  decoded.schemaVersion <= EditorProjectTemplate.currentSchemaVersion else { return nil }
            let template = rebasedPackagePaths(in: decoded, packageFolder: folder)
            return template
        }
        .sorted { $0.modifiedAt > $1.modifiedAt }
    }

    func save(project: EditorProject, name: String) async throws -> EditorProjectTemplate {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { throw EditorTemplateStoreError.invalidName }
        let id = UUID()
        let folder = try packageDirectory(for: id)
        let assets = folder.appendingPathComponent("Assets", isDirectory: true)
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        var packagedProject = project
        packagedProject = try packageReferencedFiles(in: packagedProject, into: assets)
        let slots = makeSlots(from: packagedProject)
        let fonts = Array(Set(packagedProject.textOverlays.map(\.fontFamily.rawValue))).sorted()
        let now = Date()
        let template = EditorProjectTemplate(
            id: id,
            schemaVersion: EditorProjectTemplate.currentSchemaVersion,
            name: cleanName,
            createdAt: now,
            modifiedAt: now,
            project: packagedProject,
            slots: slots,
            requiredFontFamilies: fonts,
            safeArea: EditorTemplateSafeArea()
        )
        let data = try encoder.encode(template)
        guard !data.isEmpty else { throw EditorTemplateStoreError.cannotEncode }
        try data.write(to: folder.appendingPathComponent("template.json"), options: .atomic)
        if let firstID = packagedProject.clips.first?.assetLocalIdentifier {
            await writePreview(assetIdentifier: firstID, to: folder.appendingPathComponent("preview.jpg"))
        }
        return template
    }

    func delete(_ template: EditorProjectTemplate) throws {
        let folder = try rootDirectory().appendingPathComponent(template.id.uuidString, isDirectory: true)
        if FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.removeItem(at: folder)
        }
    }

    func thumbnailURL(for template: EditorProjectTemplate) -> URL? {
        guard let url = try? rootDirectory()
            .appendingPathComponent(template.id.uuidString, isDirectory: true)
            .appendingPathComponent("preview.jpg"),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    func validation(for template: EditorProjectTemplate) -> EditorTemplateValidation {
        let allIDs = template.project.clips.map(\.assetLocalIdentifier)
            + template.project.overlayClips.map(\.assetLocalIdentifier)
        let found = PHAsset.fetchAssets(withLocalIdentifiers: allIDs, options: nil)
        var foundIDs = Set<String>()
        found.enumerateObjects { asset, _, _ in foundIDs.insert(asset.localIdentifier) }
        return EditorTemplateValidation(
            missingMedia: allIDs.filter { !foundIDs.contains($0) }.count,
            missingAudio: template.project.audioClips.filter {
                !FileManager.default.fileExists(atPath: $0.fileURLPath)
            }.count,
            missingGraphics: template.project.graphicOverlays.filter {
                if case let .image(path) = $0.source {
                    return !FileManager.default.fileExists(atPath: path)
                }
                return false
            }.count,
            missingCanvasArtwork: template.project.canvasSettings.backgroundImagePath.map {
                FileManager.default.fileExists(atPath: $0) ? 0 : 1
            } ?? 0
        )
    }

    func materializedProject(
        from template: EditorProjectTemplate,
        destinationProjectID: UUID
    ) throws -> EditorProject {
        guard template.schemaVersion <= EditorProjectTemplate.currentSchemaVersion else {
            throw EditorTemplateStoreError.unsupportedVersion
        }
        let root = try applicationSupportDirectory()
            .appendingPathComponent(appliedAssetsFolderName, isDirectory: true)
            .appendingPathComponent(destinationProjectID.uuidString, isDirectory: true)
            .appendingPathComponent(template.id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var project = template.project
        for index in project.audioClips.indices {
            if let copied = try copyReferencedFile(
                at: project.audioClips[index].fileURLPath,
                prefix: "audio-\(project.audioClips[index].id.uuidString)",
                into: root
            ) { project.audioClips[index].fileURLPath = copied.path }
        }
        for index in project.graphicOverlays.indices {
            if case let .image(path) = project.graphicOverlays[index].source,
               let copied = try copyReferencedFile(
                at: path,
                prefix: "graphic-\(project.graphicOverlays[index].id.uuidString)",
                into: root
               ) { project.graphicOverlays[index].source = .image(path: copied.path) }
        }
        if let path = project.canvasSettings.backgroundImagePath,
           let copied = try copyReferencedFile(at: path, prefix: "canvas", into: root) {
            project.canvasSettings.backgroundImagePath = copied.path
        }
        return project
    }

    private func makeSlots(from project: EditorProject) -> [EditorTemplateMediaSlot] {
        let ids = project.clips.map(\.assetLocalIdentifier) + project.overlayClips.map(\.assetLocalIdentifier)
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        var types: [String: PHAssetMediaType] = [:]
        fetch.enumerateObjects { asset, _, _ in types[asset.localIdentifier] = asset.mediaType }
        let primary = project.clips.enumerated().map { index, clip in
            EditorTemplateMediaSlot(
                id: UUID(), role: .primary, itemID: clip.id, order: index,
                title: "Media \(index + 1)", mediaKind: mediaKind(types[clip.assetLocalIdentifier]),
                targetDuration: savedDuration(clip)
            )
        }
        let overlays = project.overlayClips.enumerated().map { index, clip in
            EditorTemplateMediaSlot(
                id: UUID(), role: .overlay, itemID: clip.id, order: index,
                title: "Overlay \(index + 1)", mediaKind: mediaKind(types[clip.assetLocalIdentifier]),
                targetDuration: max(0, clip.trimEnd - clip.trimStart) / TimeInterval(max(clip.speed, 0.01))
            )
        }
        return primary + overlays
    }

    private func savedDuration(_ clip: SavedEditorClip) -> TimeInterval {
        let source = max(0, clip.trimEnd - clip.trimStart)
        return clip.speedRamp?.timelineDuration(forSourceDuration: source)
            ?? source / TimeInterval(max(clip.speed, 0.01))
    }

    private func mediaKind(_ type: PHAssetMediaType?) -> EditorTemplateMediaKind {
        switch type {
        case .video: return .video
        case .image: return .image
        default: return .either
        }
    }

    private func packageReferencedFiles(in source: EditorProject, into folder: URL) throws -> EditorProject {
        var project = source
        for index in project.audioClips.indices {
            if let copied = try copyReferencedFile(
                at: project.audioClips[index].fileURLPath,
                prefix: "audio-\(project.audioClips[index].id.uuidString)",
                into: folder
            ) { project.audioClips[index].fileURLPath = copied.path }
        }
        for index in project.graphicOverlays.indices {
            if case let .image(path) = project.graphicOverlays[index].source,
               let copied = try copyReferencedFile(
                at: path,
                prefix: "graphic-\(project.graphicOverlays[index].id.uuidString)",
                into: folder
               ) { project.graphicOverlays[index].source = .image(path: copied.path) }
        }
        if let path = project.canvasSettings.backgroundImagePath,
           let copied = try copyReferencedFile(at: path, prefix: "canvas", into: folder) {
            project.canvasSettings.backgroundImagePath = copied.path
        }
        return project
    }

    private func copyReferencedFile(at path: String, prefix: String, into folder: URL) throws -> URL? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        let source = URL(fileURLWithPath: path)
        let suffix = source.pathExtension.isEmpty ? "dat" : source.pathExtension
        let destination = folder.appendingPathComponent("\(prefix).\(suffix)")
        if source.standardizedFileURL == destination.standardizedFileURL { return destination }
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.copyItem(at: source, to: destination)
        return destination
    }

    private func rebasedPackagePaths(
        in source: EditorProjectTemplate,
        packageFolder: URL
    ) -> EditorProjectTemplate {
        var template = source
        let assets = packageFolder.appendingPathComponent("Assets", isDirectory: true)
        for index in template.project.audioClips.indices
        where !FileManager.default.fileExists(atPath: template.project.audioClips[index].fileURLPath) {
            if let url = packagedFile(
                prefixed: "audio-\(template.project.audioClips[index].id.uuidString)",
                in: assets
            ) { template.project.audioClips[index].fileURLPath = url.path }
        }
        for index in template.project.graphicOverlays.indices {
            guard case let .image(path) = template.project.graphicOverlays[index].source,
                  !FileManager.default.fileExists(atPath: path),
                  let url = packagedFile(
                    prefixed: "graphic-\(template.project.graphicOverlays[index].id.uuidString)",
                    in: assets
                  ) else { continue }
            template.project.graphicOverlays[index].source = .image(path: url.path)
        }
        if let path = template.project.canvasSettings.backgroundImagePath,
           !FileManager.default.fileExists(atPath: path),
           let url = packagedFile(prefixed: "canvas", in: assets) {
            template.project.canvasSettings.backgroundImagePath = url.path
        }
        return template
    }

    private func packagedFile(prefixed prefix: String, in directory: URL) -> URL? {
        try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ).first { $0.lastPathComponent.hasPrefix(prefix + ".") }
    }

    private func writePreview(assetIdentifier: String, to url: URL) async {
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [assetIdentifier], options: nil)
        guard let asset = fetch.firstObject else { return }
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .exact
        options.isNetworkAccessAllowed = true
        let image: UIImage? = await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 720, height: 720),
                contentMode: .aspectFill,
                options: options
            ) { image, _ in continuation.resume(returning: image) }
        }
        if let data = image?.jpegData(compressionQuality: 0.82) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func packageDirectory(for id: UUID) throws -> URL {
        let directory = try rootDirectory().appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func rootDirectory() throws -> URL {
        let directory = try applicationSupportDirectory().appendingPathComponent(folderName, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func applicationSupportDirectory() throws -> URL {
        try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
    }
}
