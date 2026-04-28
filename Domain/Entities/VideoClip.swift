//  VideoClip.swift
//  Mixtape  —  Domain/Entities

import Foundation

struct VideoClip: Identifiable, Equatable {
    let id: UUID
    var assetURL: URL
    var startTime: TimeInterval
    var duration: TimeInterval
    var trimStart: TimeInterval
    var trimEnd: TimeInterval
    var speed: Float
    var volume: Float
    var isMuted: Bool
    var effects: [Effect]
    var transform: ClipTransform

    init(assetURL: URL, duration: TimeInterval) {
        self.id = UUID()
        self.assetURL = assetURL
        self.startTime = 0
        self.duration = duration
        self.trimStart = 0
        self.trimEnd = 0
        self.speed = 1.0
        self.volume = 1.0
        self.isMuted = false
        self.effects = []
        self.transform = ClipTransform()
    }
}

struct ClipTransform: Equatable {
    var scale: CGFloat = 1.0
    var rotation: CGFloat = 0.0
    var position: CGPoint = .zero
    var opacity: Float = 1.0
}