//
//  MediaFilter.swift
//  Mixtape
//
//  Created by Favour Baruch on 08/05/2026.
//

import Foundation

enum MediaFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case photos = "Photos"
    case videos = "Videos"
    case favorites = "Favorites"

    var id: String { rawValue }
}
