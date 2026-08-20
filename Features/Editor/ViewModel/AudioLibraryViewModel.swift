//
//  AudioLibraryViewModel.swift
//  Mixtape
//

import AVFoundation
import Foundation

/// Drives `AudioLibraryPickerView`: merges the always-available bundled catalog with a
/// search-driven remote provider (Freesound), favorites (persisted locally — favoriting is
/// metadata over the catalog, not a copy of any item), and single-item audition playback that
/// streams/plays independently of the project's own composition player.
@MainActor
@Observable
final class AudioLibraryViewModel {
    var searchText: String = ""
    var selectedCategory: EditorAudioLibraryCategory?

    private(set) var bundledResults: [EditorAudioLibraryItem] = []
    private(set) var remoteResults: [EditorAudioLibraryItem] = []
    private(set) var isSearchingRemote = false
    private(set) var remoteStatusMessage: String?
    private(set) var previewingItemID: String?
    private(set) var resolvingItemID: String?
    private(set) var favoriteIDs: Set<String>

    let remoteSourceName: String?

    @ObservationIgnored private let bundledProvider: EditorAudioLibraryProviding
    @ObservationIgnored private let remoteProvider: EditorAudioLibraryProviding?
    @ObservationIgnored private var previewPlayer: AVPlayer?
    @ObservationIgnored private var previewEndObserver: NSObjectProtocol?
    @ObservationIgnored private var searchGeneration = 0
    @ObservationIgnored private static let favoritesDefaultsKey = "EditorAudioLibrary.favoriteIDs"

    init(
        bundledProvider: EditorAudioLibraryProviding = BundledAudioLibraryProvider.shared,
        remoteProvider: EditorAudioLibraryProviding? = FreesoundAudioLibraryProvider.shared
    ) {
        self.bundledProvider = bundledProvider
        self.remoteProvider = remoteProvider
        self.remoteSourceName = remoteProvider?.sourceName
        self.favoriteIDs = Set(
            UserDefaults.standard.stringArray(forKey: Self.favoritesDefaultsKey) ?? []
        )
    }

    var availableCategories: [EditorAudioLibraryCategory] {
        let present = Set(bundledResults.compactMap(\.category))
        return EditorAudioLibraryCategory.allCases.filter { present.contains($0) }
    }

    func selectCategory(_ category: EditorAudioLibraryCategory?) {
        selectedCategory = category
        searchText = category?.searchKeyword ?? ""
    }

    /// Re-runs both providers for the current `searchText`/`selectedCategory`. Bundled search is
    /// local and instant; remote search only fires with non-empty text, since Freesound has no
    /// "browse everything" mode worth hitting on every sheet open. Called from the view via
    /// `.task(id:)` keyed on search text + category, which gives free debouncing/cancellation —
    /// no `didSet` on these `@Observable` properties (unsupported by the macro).
    func refresh() async {
        searchGeneration += 1
        let generation = searchGeneration

        async let bundled = (try? bundledProvider.search(query: searchText, category: selectedCategory)) ?? []

        guard let remoteProvider else {
            bundledResults = await bundled
            return
        }

        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            bundledResults = await bundled
            remoteResults = []
            remoteStatusMessage = nil
            isSearchingRemote = false
            return
        }

        isSearchingRemote = true
        remoteStatusMessage = nil
        do {
            let remote = try await remoteProvider.search(query: searchText, category: selectedCategory)
            bundledResults = await bundled
            guard generation == searchGeneration else { return }
            remoteResults = remote
            remoteStatusMessage = remote.isEmpty ? "No matches on \(remoteProvider.sourceName)." : nil
        } catch {
            bundledResults = await bundled
            guard generation == searchGeneration else { return }
            remoteResults = []
            remoteStatusMessage = (error as? LocalizedError)?.errorDescription ?? "Search failed."
        }
        guard generation == searchGeneration else { return }
        isSearchingRemote = false
    }

    func isFavorite(_ item: EditorAudioLibraryItem) -> Bool {
        favoriteIDs.contains(item.id)
    }

    func toggleFavorite(_ item: EditorAudioLibraryItem) {
        if !favoriteIDs.insert(item.id).inserted {
            favoriteIDs.remove(item.id)
        }
        UserDefaults.standard.set(Array(favoriteIDs), forKey: Self.favoritesDefaultsKey)
    }

    func isCached(_ item: EditorAudioLibraryItem) -> Bool {
        provider(for: item).cachedLocalURL(for: item) != nil
    }

    func togglePreview(_ item: EditorAudioLibraryItem) {
        if previewingItemID == item.id {
            stopPreview()
            return
        }
        guard let url = provider(for: item).previewStreamURL(for: item) else { return }
        stopPreview()

        let player = AVPlayer(url: url)
        previewPlayer = player
        previewingItemID = item.id
        previewEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.stopPreview() }
        }
        player.play()
    }

    func stopPreview() {
        previewPlayer?.pause()
        previewPlayer = nil
        if let observer = previewEndObserver {
            NotificationCenter.default.removeObserver(observer)
            previewEndObserver = nil
        }
        previewingItemID = nil
    }

    /// Downloads/caches (if needed) and returns a local file URL ready to hand to
    /// `EditorViewModel.insertAudioLibraryItem`. Marks `resolvingItemID` so the row can show a
    /// spinner for the (usually brief) remote-download case.
    func resolvedLocalURL(for item: EditorAudioLibraryItem) async throws -> URL {
        resolvingItemID = item.id
        defer { resolvingItemID = nil }
        return try await provider(for: item).resolveLocalURL(for: item)
    }

    private func provider(for item: EditorAudioLibraryItem) -> EditorAudioLibraryProviding {
        switch item.source {
        case .bundled: return bundledProvider
        case .freesound: return remoteProvider ?? bundledProvider
        }
    }
}
