//
//  EditorClip.swift
//  Mixtape
//
//  Created by Favour Baruch on 14/05/2026.
//

import Foundation
import Photos

/// Fixed preview stage (width ÷ height). All assets are letterboxed/pillarboxed inside this frame.
enum EditorPreviewLayout {
    /// Vertical phone-style stage (e.g. 9×16). Change here to lock a different editor canvas.
    static let aspectWidthOverHeight: CGFloat = 9 / 16
}

/// A single clip on the editor timeline.
/// that mixed photo+video timelines still produce a coherent timeline ruler.
struct EditorClip: Identifiable, Hashable {
    static let photoDefaultDuration: TimeInterval = 3.0

    let id: UUID
    let asset: PHAsset
    let originalDuration: TimeInterval

    var trimStart: TimeInterval
    var trimEnd: TimeInterval
    var speed: Float
    var volume: Float

    init(asset: PHAsset) {
        self.id = UUID()
        self.asset = asset
        let raw = asset.mediaType == .video ? asset.duration : Self.photoDefaultDuration
        self.originalDuration = raw
        self.trimStart = 0
        self.trimEnd = raw
        self.speed = 1.0
        self.volume = 1.0
    }

    var isVideo: Bool { asset.mediaType == .video }

    /// Duration after trim + speed (timeline seconds for this clip).
    var duration: TimeInterval {
        let trimmed = max(0, trimEnd - trimStart)
        return speed > 0 ? trimmed / TimeInterval(speed) : trimmed
    }

    /// Local playback time within this clip (source timeline), derived from exported `localTime * speed + trimStart`.
    func sourceTime(forExportedLocal local: TimeInterval) -> TimeInterval {
        min(
            max(trimStart + local * TimeInterval(speed), trimStart),
            trimEnd
        )
    }

    static func == (lhs: EditorClip, rhs: EditorClip) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
