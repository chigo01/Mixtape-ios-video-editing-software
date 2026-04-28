//  VideoProject.swift
//  Mixtape  —  Domain/Entities

import Foundation

struct VideoProject: Identifiable, Equatable {
    let id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var duration: TimeInterval
    var aspectRatio: AspectRatio
    var timeline: Timeline
    var exportSettings: ExportSettings

    init(
        id: UUID = UUID(),
        name: String,
        aspectRatio: AspectRatio = .widescreen,
        timeline: Timeline = Timeline()
    ) {
        self.id = id
        self.name = name
        self.createdAt = Date()
        self.updatedAt = Date()
        self.duration = 0
        self.aspectRatio = aspectRatio
        self.timeline = timeline
        self.exportSettings = ExportSettings()
    }
}

enum AspectRatio: String, CaseIterable {
    case widescreen = "16:9"
    case portrait   = "9:16"
    case square     = "1:1"
    case cinema     = "21:9"

    var size: CGSize {
        switch self {
        case .widescreen: return CGSize(width: 1920, height: 1080)
        case .portrait:   return CGSize(width: 1080, height: 1920)
        case .square:     return CGSize(width: 1080, height: 1080)
        case .cinema:     return CGSize(width: 2560, height: 1080)
        }
    }
}