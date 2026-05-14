//
//  MediaItem.swift
//  Mixtape
//
//  Created by Favour Baruch on 08/05/2026.
//

import Foundation
import Photos

struct MediaItem: Identifiable, Hashable {
    let id: String
    let asset: PHAsset

    var isVideo: Bool { asset.mediaType == .video }
    var isFavorite: Bool { asset.isFavorite }
    var duration: TimeInterval { asset.duration }

    var formattedDuration: String {
        let total = Int(asset.duration.rounded())
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    static func == (lhs: MediaItem, rhs: MediaItem) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
