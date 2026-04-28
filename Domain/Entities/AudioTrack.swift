//  AudioTrack.swift
//  Mixtape  —  Domain/Entities

import Foundation

struct AudioTrack: Identifiable, Equatable {
    let id: UUID
    var assetURL: URL
    var startTime: TimeInterval
    var duration: TimeInterval
    var volume: Float
    var isMuted: Bool
    var fadeIn: TimeInterval
    var fadeOut: TimeInterval

    init(assetURL: URL, duration: TimeInterval) {
        self.id = UUID()
        self.assetURL = assetURL
        self.startTime = 0
        self.duration = duration
        self.volume = 1.0
        self.isMuted = false
        self.fadeIn = 0
        self.fadeOut = 0
    }
}