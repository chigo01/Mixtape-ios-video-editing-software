//  ExportSettings.swift
//  Mixtape  —  Domain/Entities

import Foundation

struct ExportSettings: Equatable {
    var resolution: ExportResolution
    var frameRate: Int
    var bitrate: Int
    var format: ExportFormat

    init() {
        self.resolution = .hd1080p
        self.frameRate = 30
        self.bitrate = 8_000_000
        self.format = .mp4
    }
}

enum ExportResolution: String, CaseIterable {
    case hd720p  = "1280x720"
    case hd1080p = "1920x1080"
    case uhd4k   = "3840x2160"
}

enum ExportFormat: String, CaseIterable {
    case mp4
    case mov
}