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
    static let photoMinimumDuration: TimeInterval = 0.5
    static let photoMaximumDuration: TimeInterval = 30.0

    let id: UUID
    let asset: PHAsset
    var originalDuration: TimeInterval

    var trimStart: TimeInterval
    var trimEnd: TimeInterval
    var speed: Float
    var volume: Float

    init(asset: PHAsset) {
        let raw = asset.mediaType == .video ? asset.duration : Self.photoDefaultDuration
        self.init(
            asset: asset,
            originalDuration: raw,
            trimStart: 0,
            trimEnd: raw
        )
    }

    init(
        id: UUID = UUID(),
        asset: PHAsset,
        originalDuration: TimeInterval,
        trimStart: TimeInterval,
        trimEnd: TimeInterval,
        speed: Float = 1.0,
        volume: Float = 1.0
    ) {
        self.id = id
        self.asset = asset
        self.originalDuration = originalDuration
        self.trimStart = trimStart
        self.trimEnd = trimEnd
        self.speed = speed
        self.volume = volume
    }

    /// Minimum source span so a clip stays at least ~0.25s on the timeline.
    static func minimumSourceSpan(speed: Float) -> TimeInterval {
        max(0.25 * TimeInterval(max(speed, 0.001)), 0.05)
    }

    /// Splits this clip at `sourceTime` (asset seconds). Returns nil if too close to either edge.
    func split(atSourceTime sourceTime: TimeInterval) -> (left: EditorClip, right: EditorClip)? {
        let minSpan = Self.minimumSourceSpan(speed: speed)
        guard sourceTime >= trimStart + minSpan, sourceTime <= trimEnd - minSpan else { return nil }

        let left = EditorClip(
            asset: asset,
            originalDuration: originalDuration,
            trimStart: trimStart,
            trimEnd: sourceTime,
            speed: speed,
            volume: volume
        )
        let right = EditorClip(
            asset: asset,
            originalDuration: originalDuration,
            trimStart: sourceTime,
            trimEnd: trimEnd,
            speed: speed,
            volume: volume
        )
        return (left, right)
    }

    var isVideo: Bool { asset.mediaType == .video }
    var isPhoto: Bool { asset.mediaType == .image }

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

    static func == (lhs: EditorClip, rhs: EditorClip) -> Bool {
        lhs.id == rhs.id
            && lhs.asset.localIdentifier == rhs.asset.localIdentifier
            && lhs.trimStart == rhs.trimStart
            && lhs.trimEnd == rhs.trimEnd
            && lhs.speed == rhs.speed
            && lhs.volume == rhs.volume
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
