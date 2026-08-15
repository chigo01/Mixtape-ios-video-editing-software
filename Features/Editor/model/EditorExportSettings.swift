//
//  EditorExportSettings.swift
//  Mixtape
//

import AVFoundation
import CoreGraphics
import Foundation

enum EditorExportResolution: String, CaseIterable, Identifiable {
    case p720 = "720p"
    case p1080 = "1080p"
    case p4K = "4K"

    var id: String { rawValue }

    /// Portrait export canvas (9:16).
    var canvasSize: CGSize {
        switch self {
        case .p720: return CGSize(width: 720, height: 1280)
        case .p1080: return CGSize(width: 1080, height: 1920)
        case .p4K: return CGSize(width: 2160, height: 3840)
        }
    }

    var longEdge: CGFloat {
        switch self {
        case .p720: return 1280
        case .p1080: return 1920
        case .p4K: return 3840
        }
    }

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

/// Target video bitrate tier at 1080p; scaled for 720p / 4K in `targetBitratebps(for:)`.
enum EditorExportQuality: String, CaseIterable, Identifiable {
    case efficient
    case balanced
    case high
    case maximum

    var id: String { rawValue }

    var title: String {
        switch self {
        case .efficient: return "Efficient"
        case .balanced: return "Balanced"
        case .high: return "High"
        case .maximum: return "Max"
        }
    }

    /// Reference Mbps at 1080p for UI hints.
    var referenceMbpsAt1080p: Int {
        switch self {
        case .efficient: return 6
        case .balanced: return 12
        case .high: return 20
        case .maximum: return 35
        }
    }

    func targetBitratebps(for resolution: EditorExportResolution) -> Int {
        let mbps: Double
        switch self {
        case .efficient: mbps = 6
        case .balanced: mbps = 12
        case .high: mbps = 20
        case .maximum: mbps = 35
        }
        let scaled: Double
        switch resolution {
        case .p720: scaled = mbps * 0.55
        case .p1080: scaled = mbps
        case .p4K: scaled = mbps * 2.5
        }
        return Int(scaled * 1_000_000)
    }
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
    var quality: EditorExportQuality = .balanced
    var includeHDR: Bool = false
    var format: EditorExportFormat = .mp4

    var targetVideoBitratebps: Int {
        quality.targetBitratebps(for: resolution)
    }

    var targetVideoMbpsLabel: String {
        let mbps = Double(targetVideoBitratebps) / 1_000_000
        if mbps >= 10 {
            return String(format: "%.0f Mbps", mbps)
        }
        return String(format: "%.1f Mbps", mbps)
    }

    /// Size estimate from chosen video bitrate + ~192 kbps AAC.
    func estimatedFileSizeMB(duration: TimeInterval) -> Int {
        let videoMbps = Double(targetVideoBitratebps) / 1_000_000
        let totalMbps = videoMbps + 0.192
        let megabytes = totalMbps * max(duration, 1) / 8
        return max(1, Int(megabytes.rounded()))
    }
}
