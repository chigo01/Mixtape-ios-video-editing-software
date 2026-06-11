//
//  EditorExportSettings.swift
//  Mixtape
//

import AVFoundation
import Foundation

enum EditorExportResolution: String, CaseIterable, Identifiable {
    case p720 = "720p"
    case p1080 = "1080p"
    case p4K = "4K"

    var id: String { rawValue }

    var avPreset: String {
        switch self {
        case .p720: return AVAssetExportPreset1280x720
        case .p1080: return AVAssetExportPreset1920x1080
        case .p4K: return AVAssetExportPreset3840x2160
        }
    }
}

enum EditorExportFrameRate: Int, CaseIterable, Identifiable {
    case fps24 = 24
    case fps30 = 30
    case fps60 = 60
    case fps120 = 120

    var id: Int { rawValue }

    var label: String { "\(rawValue)" }
}

enum EditorExportFormat: String, CaseIterable, Identifiable {
    case mp4 = "MP4"
    case mov = "MOV"

    var id: String { rawValue }

    var fileType: AVFileType {
        switch self {
        case .mp4: return .mp4
        case .mov: return .mov
        }
    }

    var fileExtension: String {
        switch self {
        case .mp4: return "mp4"
        case .mov: return "mov"
        }
    }
}

struct EditorExportSettings: Equatable {
    var resolution: EditorExportResolution = .p1080
    var frameRate: EditorExportFrameRate = .fps30
    var format: EditorExportFormat = .mp4

    /// Rough size estimate for the settings UI (~ Mbps varies by resolution).
    func estimatedFileSizeMB(duration: TimeInterval) -> Int {
        let mbPerMinute: Double
        switch resolution {
        case .p720: mbPerMinute = 40
        case .p1080: mbPerMinute = 85
        case .p4K: mbPerMinute = 200
        }
        let minutes = max(duration, 1) / 60
        return Int((minutes * mbPerMinute).rounded())
    }
}
