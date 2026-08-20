//
//  FreesoundAudioLibraryProvider.swift
//  Mixtape
//
//  Remote EditorAudioLibraryProviding backed by the Freesound API (freesound.org) — a
//  community sound-effect/field-recording database, not a music catalog: search results here
//  are SFX/foley/ambience, each individually licensed (mostly Creative Commons) by its uploader.
//

import Foundation

/// Hardcoded per explicit product decision — this key will land in git history the moment this
/// file is committed. Rotate it at https://freesound.org/apiv2/apply/ if that's ever a problem;
/// moving it to a gitignored config file later doesn't require touching anything else in this
/// file's public surface.
private enum FreesoundConfig {
    static let apiKey = "Gg3NCAOZte4yGhjU6K5KYcABbb9Y0ssH1KrqakqU"
}

@MainActor
final class FreesoundAudioLibraryProvider: EditorAudioLibraryProviding {
    static let shared = FreesoundAudioLibraryProvider()

    let sourceName = "Freesound"

    /// Preview stream URLs from the most recent search, keyed by item id — Freesound doesn't
    /// expose a stable "get sound by id" URL shape we can reconstruct offline, so a remote item
    /// is only resolvable while its search result is still in this session-local cache.
    private var previewURLsByID: [String: URL] = [:]

    private init() {}

    func search(query: String, category: EditorAudioLibraryCategory?) async throws -> [EditorAudioLibraryItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var components = URLComponents(string: "https://freesound.org/apiv2/search/text/")!
        components.queryItems = [
            URLQueryItem(name: "query", value: trimmed),
            URLQueryItem(name: "fields", value: "id,name,tags,license,username,duration,previews"),
            URLQueryItem(name: "page_size", value: "24"),
            // Keeps results short/SFX-shaped rather than full-length ambience or music beds.
            URLQueryItem(name: "filter", value: "duration:[0.1 TO 30]"),
        ]
        guard let url = components.url else { return [] }

        var request = URLRequest(url: url)
        request.setValue("Token \(FreesoundConfig.apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw EditorAudioLibraryError.downloadFailed }
        guard (200..<300).contains(http.statusCode) else { throw EditorAudioLibraryError.requestFailed(http.statusCode) }

        let decoded = try JSONDecoder().decode(SearchResponse.self, from: data)
        return decoded.results.compactMap { result in
            guard let previewURLString = result.previews["preview-hq-mp3"] ?? result.previews["preview-lq-mp3"],
                  let previewURL = URL(string: previewURLString) else { return nil }

            let item = EditorAudioLibraryItem(
                id: "freesound.\(result.id)",
                title: result.name,
                category: Self.bestGuessCategory(tags: result.tags),
                durationSeconds: result.duration,
                tags: result.tags,
                source: .freesound,
                license: Self.license(licenseURLString: result.license, username: result.username, title: result.name)
            )
            previewURLsByID[item.id] = previewURL
            return item
        }
    }

    func previewStreamURL(for item: EditorAudioLibraryItem) -> URL? {
        cachedLocalURL(for: item) ?? previewURLsByID[item.id]
    }

    func cachedLocalURL(for item: EditorAudioLibraryItem) -> URL? {
        AudioLibraryCache.shared.cachedFileURL(id: cacheKey(for: item), pathExtension: "mp3")
    }

    func resolveLocalURL(for item: EditorAudioLibraryItem) async throws -> URL {
        guard let remoteURL = previewURLsByID[item.id] else { throw EditorAudioLibraryError.resourceMissing }
        return try await AudioLibraryCache.shared.resolvedFileURL(
            id: cacheKey(for: item),
            pathExtension: "mp3",
            remoteURL: remoteURL
        )
    }

    private func cacheKey(for item: EditorAudioLibraryItem) -> String {
        "freesound_\(item.id.replacingOccurrences(of: "freesound.", with: ""))"
    }

    private struct SearchResponse: Decodable {
        let results: [Result]

        struct Result: Decodable {
            let id: Int
            let name: String
            let tags: [String]
            let license: String
            let username: String
            let duration: TimeInterval
            let previews: [String: String]
        }
    }

    private static func bestGuessCategory(tags: [String]) -> EditorAudioLibraryCategory? {
        let lowered = Set(tags.map { $0.lowercased() })
        for category in EditorAudioLibraryCategory.allCases {
            if lowered.contains(category.rawValue) || lowered.contains(category.searchKeyword) {
                return category
            }
        }
        return nil
    }

    private static func license(licenseURLString: String, username: String, title: String) -> EditorAudioLibraryLicense {
        let lower = licenseURLString.lowercased()
        if lower.contains("zero") || lower.contains("publicdomain") {
            return EditorAudioLibraryLicense(name: "CC0 — Public Domain", requiresAttribution: false, attributionText: nil)
        }

        let attributionText = "\"\(title)\" by \(username) (freesound.org)"
        let name: String
        if lower.contains("by-nc-sa") {
            name = "CC BY-NC-SA — non-commercial, attribution + share-alike required"
        } else if lower.contains("by-nc") {
            name = "CC BY-NC — non-commercial use only, attribution required"
        } else if lower.contains("by-sa") {
            name = "CC BY-SA — attribution + share-alike required"
        } else if lower.contains("sampling+") {
            name = "Sampling+ — attribution required"
        } else {
            // Covers standard CC BY and anything unrecognized — attribution is the safe default.
            name = "CC BY — attribution required"
        }
        return EditorAudioLibraryLicense(name: name, requiresAttribution: true, attributionText: attributionText)
    }
}
