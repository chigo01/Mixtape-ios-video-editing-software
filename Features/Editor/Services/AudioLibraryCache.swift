//
//  AudioLibraryCache.swift
//  Mixtape
//

import Foundation

/// Shared on-disk cache for downloaded remote library sounds, keyed by a caller-supplied stable
/// id (e.g. a Freesound sound id). Independent of any single project: a sound inserted into two
/// different projects downloads once and both projects' `EditorAudioClip.fileURL` point at the
/// same cached file — so cache files are never deleted when a clip is removed from one project
/// (`EditorViewModel.releaseAudioFileIfUnused` explicitly skips this directory). Bounded by
/// `budgetBytes`; oldest-accessed files are evicted first when the budget is exceeded.
///
/// Trade-off: because eviction is time/size-based rather than reference-counted across all
/// saved projects, a project that sits unopened long enough could reopen missing a
/// library-sourced clip if its cache file was evicted meanwhile. `EditorAudioClip` already
/// drops any clip whose backing file is gone on project load (`SavedAudioClip.toAudioClip()`),
/// the same fallback already used for a missing imported-audio file — so this isn't a new
/// failure mode, just the existing one applied to one more file source. A full missing-media
/// relink flow is tracked as Phase 5 Priority 31 in `Features/Editor/README.md`.
actor AudioLibraryCache {
    static let shared = AudioLibraryCache()

    private let directory: URL
    private let budgetBytes: Int64 = 300 * 1024 * 1024

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        directory = base.appendingPathComponent("MixtapeAudioLibraryCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    nonisolated func cachedFileURL(id: String, pathExtension: String) -> URL? {
        let url = fileURL(id: id, pathExtension: pathExtension)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    nonisolated private func fileURL(id: String, pathExtension: String) -> URL {
        directory.appendingPathComponent(id).appendingPathExtension(pathExtension)
    }

    /// Downloads `remoteURL` if not already cached, touches its access date either way, and
    /// enforces the cache budget. Safe to call concurrently for the same id.
    func resolvedFileURL(id: String, pathExtension: String, remoteURL: URL) async throws -> URL {
        let destination = fileURL(id: id, pathExtension: pathExtension)
        let fm = FileManager.default

        if fm.fileExists(atPath: destination.path) {
            touch(destination)
            return destination
        }

        let (tempURL, response) = try await URLSession.shared.download(from: remoteURL)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            try? fm.removeItem(at: tempURL)
            throw EditorAudioLibraryError.downloadFailed
        }

        try? fm.removeItem(at: destination)
        try fm.moveItem(at: tempURL, to: destination)
        touch(destination)
        enforceBudget()
        return destination
    }

    private func touch(_ url: URL) {
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
    }

    private func enforceBudget() {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]
        ) else { return }

        let files = entries.compactMap { url -> (url: URL, date: Date, size: Int64)? in
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                  let date = values.contentModificationDate,
                  let size = values.fileSize else { return nil }
            return (url, date, Int64(size))
        }

        var totalSize = files.reduce(0) { $0 + $1.size }
        guard totalSize > budgetBytes else { return }

        for file in files.sorted(by: { $0.date < $1.date }) {
            guard totalSize > budgetBytes else { break }
            try? fm.removeItem(at: file.url)
            totalSize -= file.size
        }
    }
}
