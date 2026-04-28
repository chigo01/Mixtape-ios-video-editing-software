//  Effect.swift
//  Mixtape  —  Domain/Entities

import Foundation

struct Effect: Identifiable, Equatable {
    let id: UUID
    var type: EffectType
    var intensity: Float
    var startTime: TimeInterval
    var duration: TimeInterval

    init(type: EffectType, intensity: Float = 1.0) {
        self.id = UUID()
        self.type = type
        self.intensity = intensity
        self.startTime = 0
        self.duration = 0
    }
}

enum EffectType: String, CaseIterable {
    case brightness
    case contrast
    case saturation
    case warmth
    case vignette
    case blur
    case sharpen
    case fade
    case glitch
}