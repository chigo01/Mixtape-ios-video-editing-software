//
//  EditorAudioLibraryItem.swift
//  Mixtape
//

import Foundation

/// Filter-chip category, shared by every source. Bundled items are tagged with these directly;
/// remote sources map their own taxonomy onto the same cases so one set of chips filters both.
enum EditorAudioLibraryCategory: String, Codable, CaseIterable, Identifiable {
    case ui
    case whoosh
    case transitions
    case cinematic
    case foley

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ui: return "UI & Notification"
        case .whoosh: return "Whoosh"
        case .transitions: return "Transitions"
        case .cinematic: return "Cinematic"
        case .foley: return "Foley"
        }
    }

    var systemImage: String {
        switch self {
        case .ui: return "bell.fill"
        case .whoosh: return "wind"
        case .transitions: return "arrow.left.arrow.right"
        case .cinematic: return "film.fill"
        case .foley: return "sparkles"
        }
    }

    /// Short, single-concept keyword used to seed a text search (both the local tag filter and
    /// a remote provider's query) — `displayName` has punctuation/spacing that makes a poor
    /// search query.
    var searchKeyword: String {
        switch self {
        case .ui: return "notification"
        case .whoosh: return "whoosh"
        case .transitions: return "transition"
        case .cinematic: return "cinematic"
        case .foley: return "foley"
        }
    }
}

/// Which catalog an item came from — drives section headers in the browser and which
/// `EditorAudioLibraryProviding` instance owns resolving/downloading it.
enum EditorAudioLibrarySource: Hashable {
    case bundled
    case freesound
}

/// A license/attribution requirement attached to a remote item. Bundled items have none (they're
/// originally synthesized for this app). `nil` on `EditorAudioLibraryItem.license` means no
/// known restriction; a non-nil license with `requiresAttribution == true` gates insertion
/// behind a confirmation showing `attributionText` (see `AudioLibraryPickerView`).
struct EditorAudioLibraryLicense: Hashable {
    let name: String
    let requiresAttribution: Bool
    let attributionText: String?
}

/// One entry in the sound library, regardless of source. Bundled items resolve to a file already
/// inside the app bundle; remote items resolve via network (see `EditorAudioLibraryProviding`).
struct EditorAudioLibraryItem: Identifiable, Hashable {
    let id: String
    let title: String
    let category: EditorAudioLibraryCategory?
    let durationSeconds: TimeInterval
    let tags: [String]
    let source: EditorAudioLibrarySource
    let license: EditorAudioLibraryLicense?
}

enum EditorAudioLibraryError: LocalizedError {
    case resourceMissing
    case requestFailed(Int)
    case downloadFailed

    var errorDescription: String? {
        switch self {
        case .resourceMissing:
            return "That sound isn't available right now."
        case .requestFailed(let code):
            return code == 401 || code == 403
                ? "The sound library rejected the request (check the API key)."
                : "Sound library search failed (\(code))."
        case .downloadFailed:
            return "Couldn't download that sound. Check your connection and try again."
        }
    }
}

/// A source of library items: search over its catalog, a fast synchronous check for whether a
/// playable local file already exists, a cheap streaming URL for audition preview (no disk
/// write), and an async resolve step that downloads + caches (if needed) a local file suitable
/// for inserting into the timeline. Bundled and remote providers both conform, so
/// `AudioLibraryViewModel` and `AudioLibraryPickerView` never need to know which they're talking
/// to.
///
/// `@MainActor`: every conformer today is only ever driven from `AudioLibraryViewModel`
/// (itself `@MainActor`). `FreesoundAudioLibraryProvider` is `@MainActor`-isolated because it
/// mutates a session-local dictionary of preview URLs — isolating the protocol here lets that
/// synchronous state stay actor-isolated instead of needing `nonisolated(unsafe)`.
/// `BundledAudioLibraryProvider`'s plain (non-isolated) methods satisfy these requirements too:
/// a non-isolated method can always stand in for an isolated one, just not the reverse.
@MainActor
protocol EditorAudioLibraryProviding {
    var sourceName: String { get }
    func search(query: String, category: EditorAudioLibraryCategory?) async throws -> [EditorAudioLibraryItem]
    func previewStreamURL(for item: EditorAudioLibraryItem) -> URL?
    func cachedLocalURL(for item: EditorAudioLibraryItem) -> URL?
    func resolveLocalURL(for item: EditorAudioLibraryItem) async throws -> URL
}

/// Reads `AudioLibrary/catalog.json` and resolves items to files copied into the app bundle
/// under `AudioLibrary/SFX/`. Every bundled sound here is synthesized (see `Tools/gen_sfx.py`)
/// — original audio, no licensing concerns, safe to ship as-is or replace with better-produced
/// assets later without touching any code that reads this catalog.
final class BundledAudioLibraryProvider: EditorAudioLibraryProviding {
    static let shared = BundledAudioLibraryProvider()

    let sourceName = "Bundled"

    private let items: [EditorAudioLibraryItem]
    private let fileNamesByID: [String: String]

    private init() {
        let entries = Self.loadCatalog()
        items = entries.map {
            EditorAudioLibraryItem(
                id: $0.id,
                title: $0.title,
                category: $0.category,
                durationSeconds: $0.durationSeconds,
                tags: $0.tags,
                source: .bundled,
                license: nil
            )
        }
        fileNamesByID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0.fileName) })
    }

    func search(query: String, category: EditorAudioLibraryCategory?) async -> [EditorAudioLibraryItem] {
        items
            .filter { category == nil || $0.category == category }
            .filter {
                query.isEmpty
                    || $0.title.localizedCaseInsensitiveContains(query)
                    || $0.tags.contains { $0.localizedCaseInsensitiveContains(query) }
            }
    }

    func previewStreamURL(for item: EditorAudioLibraryItem) -> URL? {
        cachedLocalURL(for: item)
    }

    func cachedLocalURL(for item: EditorAudioLibraryItem) -> URL? {
        guard let fileName = fileNamesByID[item.id] else { return nil }
        let name = URL(fileURLWithPath: fileName)
        return Bundle.main.url(
            forResource: name.deletingPathExtension().lastPathComponent,
            withExtension: name.pathExtension,
            subdirectory: "AudioLibrary/SFX"
        )
    }

    func resolveLocalURL(for item: EditorAudioLibraryItem) async throws -> URL {
        guard let url = cachedLocalURL(for: item) else { throw EditorAudioLibraryError.resourceMissing }
        return url
    }

    private struct CatalogEntry: Decodable {
        let id: String
        let title: String
        let category: EditorAudioLibraryCategory
        let fileName: String
        let durationSeconds: TimeInterval
        let tags: [String]
    }

    private static func loadCatalog() -> [CatalogEntry] {
        guard let url = Bundle.main.url(
            forResource: "catalog",
            withExtension: "json",
            subdirectory: "AudioLibrary"
        ), let data = try? Data(contentsOf: url) else { return [] }

        struct Manifest: Decodable { let items: [CatalogEntry] }
        return (try? JSONDecoder().decode(Manifest.self, from: data))?.items ?? []
    }
}
