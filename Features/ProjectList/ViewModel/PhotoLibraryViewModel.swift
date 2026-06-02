//
//  PhotoLibraryViewModel.swift
//  Mixtape
//
//  Created by Favour Baruch on 08/05/2026.
//

import SwiftUI
import UIKit
import Photos
import PhotosUI

@MainActor
@Observable
final class PhotoLibraryViewModel {
    private(set) var items: [MediaItem] = []
    var selectedIDs: [String] = [] // ordered to support stacked avatars
    var filter: MediaFilter = .all
    var searchText: String = ""
    private(set) var authorizationStatus: PHAuthorizationStatus = .notDetermined
    private(set) var isLoading: Bool = false

  @ObservationIgnored
    let imageManager = PHCachingImageManager()

    var filteredItems: [MediaItem] {
        var result = items

        switch filter {
        case .all:
            break
        case .photos:
            result = result.filter { !$0.isVideo }
        case .videos:
            result = result.filter { $0.isVideo }
        case .favorites:
            result = result.filter { $0.isFavorite }
        }

        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !trimmed.isEmpty {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            result = result.filter { item in
                if item.isVideo, "video".contains(trimmed) { return true }
                if !item.isVideo, "photo".contains(trimmed) { return true }
                if item.isFavorite, "favorite".contains(trimmed) { return true }
                if let date = item.asset.creationDate {
                    return formatter.string(from: date).lowercased().contains(trimmed)
                }
                return false
            }
        }

        return result
    }

    var selectedItems: [MediaItem] {
        let lookup = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        return selectedIDs.compactMap { lookup[$0] }
    }

    var totalSelectedDuration: TimeInterval {
        selectedItems.reduce(0) { $0 + ($1.isVideo ? $1.duration : 0) }
    }

    var totalSelectedDurationString: String {
        let total = Int(totalSelectedDuration.rounded())
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    func isSelected(_ item: MediaItem) -> Bool {
        selectedIDs.contains(item.id)
    }

    func toggleSelection(_ item: MediaItem) {
        if let idx = selectedIDs.firstIndex(of: item.id) {
            selectedIDs.remove(at: idx)
        } else {
            selectedIDs.append(item.id)
        }
    }

    func clearSelection() {
        selectedIDs.removeAll()
    }

    // MARK: Authorization + Loading

    func requestAccessAndLoad() {
        let current = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        authorizationStatus = current

        switch current {
        case .authorized, .limited:
            loadAssets()
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] status in
                Task { @MainActor in
                    guard let self else { return }
                    self.authorizationStatus = status
                    if status == .authorized || status == .limited {
                        self.loadAssets()
                    }
                }
            }
        case .denied, .restricted:
            break
        @unknown default:
            break
        }
    }

    func openLimitedPicker() {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let activeScene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        guard let root = activeScene?.keyWindow?.rootViewController else { return }
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: root)
    }

    func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    private func loadAssets() {
        isLoading = true
        Task.detached(priority: .userInitiated) {
            let collected = Self.fetchAllAssets()
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.items = collected
                self.isLoading = false
            }
        }
    }

    private nonisolated static func fetchAllAssets() -> [MediaItem] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let fetch = PHAsset.fetchAssets(with: options)

        var collected: [MediaItem] = []
        collected.reserveCapacity(fetch.count)
        fetch.enumerateObjects { asset, _, _ in
            collected.append(MediaItem(id: asset.localIdentifier, asset: asset))
        }
        return collected
    }
}
