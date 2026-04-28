//  VideoTrack.swift
//  Mixtape  —  Domain/Entities

import Foundation

struct VideoTrack: Identifiable, Equatable {
    let id: UUID
    var clips: [VideoClip]
    var isMuted: Bool
    var volume: Float

    init() {
        self.id = UUID()
        self.clips = []
        self.isMuted = false
        self.volume = 1.0
    }
}