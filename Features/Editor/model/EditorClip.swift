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
    static let defaultAspectWidthOverHeight: CGFloat = 9 / 16
}

enum EditorCanvasFormat: String, Codable, CaseIterable, Identifiable, Hashable {
    case vertical, landscape, square, portrait, custom

    var id: String { rawValue }
    var title: String {
        switch self {
        case .vertical: return "9:16"
        case .landscape: return "16:9"
        case .square: return "1:1"
        case .portrait: return "4:5"
        case .custom: return "Custom"
        }
    }
}

enum EditorCanvasBackgroundKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case color, blur, image
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

/// Project-level canvas configuration shared by preview and offline export.
struct EditorCanvasSettings: Codable, Hashable {
    var format: EditorCanvasFormat
    var customWidth: Int
    var customHeight: Int
    var backgroundKind: EditorCanvasBackgroundKind
    /// sRGB in 0xRRGGBB form.
    var backgroundColorRGB: UInt32
    /// App-owned image file, copied from the photo picker.
    var backgroundImagePath: String?

    static let `default` = EditorCanvasSettings(
        format: .vertical,
        customWidth: 1080,
        customHeight: 1920,
        backgroundKind: .color,
        backgroundColorRGB: 0x000000,
        backgroundImagePath: nil
    )

    var aspectRatio: CGFloat {
        switch format {
        case .vertical: return 9 / 16
        case .landscape: return 16 / 9
        case .square: return 1
        case .portrait: return 4 / 5
        case .custom: return CGFloat(max(1, customWidth)) / CGFloat(max(1, customHeight))
        }
    }

    func renderSize(longEdge: CGFloat) -> CGSize {
        if format == .custom {
            return CGSize(
                width: max(2, (customWidth / 2) * 2),
                height: max(2, (customHeight / 2) * 2)
            )
        }
        let ratio = aspectRatio
        let raw: CGSize = ratio >= 1
            ? CGSize(width: longEdge, height: longEdge / ratio)
            : CGSize(width: longEdge * ratio, height: longEdge)
        // Video encoders require even dimensions.
        return CGSize(
            width: max(2, (Int(raw.width.rounded()) / 2) * 2),
            height: max(2, (Int(raw.height.rounded()) / 2) * 2)
        )
    }
}

enum EditorReframeMode: String, Codable, CaseIterable, Identifiable {
    case fit
    case fill

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum EditorCropAspect: String, Codable, CaseIterable, Identifiable {
    case original
    case vertical
    case landscape
    case square
    case portrait

    var id: String { rawValue }

    var title: String {
        switch self {
        case .original: return "Original"
        case .vertical: return "9:16"
        case .landscape: return "16:9"
        case .square: return "1:1"
        case .portrait: return "4:5"
        }
    }

    var ratio: CGFloat? {
        switch self {
        case .original: return nil
        case .vertical: return 9 / 16
        case .landscape: return 16 / 9
        case .square: return 1
        case .portrait: return 4 / 5
        }
    }
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
    var cropAspect: EditorCropAspect
    var reframeMode: EditorReframeMode
    var rotationQuarterTurns: Int
    var straightenDegrees: Double
    var isFlippedHorizontally: Bool
    var isFlippedVertically: Bool
    var reframeScale: CGFloat
    var reframeXOffset: CGFloat
    var reframeYOffset: CGFloat
    var colorAdjustment: EditorColorAdjustment
    var keyframes: EditorKeyframeTracks
    /// Transition rendered at the cut after this clip.
    var transitionKind: EditorTransitionKind
    var transitionDuration: TimeInterval

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
        volume: Float = 1.0,
        cropAspect: EditorCropAspect = .original,
        reframeMode: EditorReframeMode = .fit,
        rotationQuarterTurns: Int = 0,
        straightenDegrees: Double = 0,
        isFlippedHorizontally: Bool = false,
        isFlippedVertically: Bool = false,
        reframeScale: CGFloat = 1,
        reframeXOffset: CGFloat = 0,
        reframeYOffset: CGFloat = 0,
        colorAdjustment: EditorColorAdjustment = .neutral,
        keyframes: EditorKeyframeTracks = .empty,
        transitionKind: EditorTransitionKind = .none,
        transitionDuration: TimeInterval = 0
    ) {
        self.id = id
        self.asset = asset
        self.originalDuration = originalDuration
        self.trimStart = trimStart
        self.trimEnd = trimEnd
        self.speed = speed
        self.volume = volume
        self.cropAspect = cropAspect
        self.reframeMode = reframeMode
        self.rotationQuarterTurns = ((rotationQuarterTurns % 4) + 4) % 4
        self.straightenDegrees = min(max(straightenDegrees, -45), 45)
        self.isFlippedHorizontally = isFlippedHorizontally
        self.isFlippedVertically = isFlippedVertically
        self.reframeScale = min(max(reframeScale, 0.5), 4)
        self.reframeXOffset = min(max(reframeXOffset, -1), 1)
        self.reframeYOffset = min(max(reframeYOffset, -1), 1)
        self.colorAdjustment = colorAdjustment
        self.keyframes = keyframes
        self.transitionKind = transitionDuration > 0 ? transitionKind : .none
        self.transitionDuration = max(0, transitionDuration)
    }

    /// Minimum source span so a clip stays at least ~0.25s on the timeline.
    static func minimumSourceSpan(speed: Float) -> TimeInterval {
        max(0.25 * TimeInterval(max(speed, 0.001)), 0.05)
    }

    /// Splits this clip at `sourceTime` (asset seconds). Returns nil if too close to either edge.
    func split(atSourceTime sourceTime: TimeInterval) -> (left: EditorClip, right: EditorClip)? {
        let minSpan = Self.minimumSourceSpan(speed: speed)
        guard sourceTime >= trimStart + minSpan, sourceTime <= trimEnd - minSpan else { return nil }

        let splitLocalTime = (sourceTime - trimStart) / TimeInterval(max(speed, 0.001))
        let splitKeyframes = keyframes.split(at: splitLocalTime)

        let left = EditorClip(
            asset: asset,
            originalDuration: originalDuration,
            trimStart: trimStart,
            trimEnd: sourceTime,
            speed: speed,
            volume: volume,
            cropAspect: cropAspect,
            reframeMode: reframeMode,
            rotationQuarterTurns: rotationQuarterTurns,
            straightenDegrees: straightenDegrees,
            isFlippedHorizontally: isFlippedHorizontally,
            isFlippedVertically: isFlippedVertically,
            reframeScale: reframeScale,
            reframeXOffset: reframeXOffset,
            reframeYOffset: reframeYOffset,
            colorAdjustment: colorAdjustment,
            keyframes: splitKeyframes.left,
            transitionKind: .none,
            transitionDuration: 0
        )
        let right = EditorClip(
            asset: asset,
            originalDuration: originalDuration,
            trimStart: sourceTime,
            trimEnd: trimEnd,
            speed: speed,
            volume: volume,
            cropAspect: cropAspect,
            reframeMode: reframeMode,
            rotationQuarterTurns: rotationQuarterTurns,
            straightenDegrees: straightenDegrees,
            isFlippedHorizontally: isFlippedHorizontally,
            isFlippedVertically: isFlippedVertically,
            reframeScale: reframeScale,
            reframeXOffset: reframeXOffset,
            reframeYOffset: reframeYOffset,
            colorAdjustment: colorAdjustment,
            keyframes: splitKeyframes.right,
            transitionKind: transitionKind,
            transitionDuration: transitionDuration
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
            && lhs.cropAspect == rhs.cropAspect
            && lhs.reframeMode == rhs.reframeMode
            && lhs.rotationQuarterTurns == rhs.rotationQuarterTurns
            && lhs.straightenDegrees == rhs.straightenDegrees
            && lhs.isFlippedHorizontally == rhs.isFlippedHorizontally
            && lhs.isFlippedVertically == rhs.isFlippedVertically
            && lhs.reframeScale == rhs.reframeScale
            && lhs.reframeXOffset == rhs.reframeXOffset
            && lhs.reframeYOffset == rhs.reframeYOffset
            && lhs.colorAdjustment == rhs.colorAdjustment
            && lhs.keyframes == rhs.keyframes
            && lhs.transitionKind == rhs.transitionKind
            && lhs.transitionDuration == rhs.transitionDuration
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// A photo or video clip composited above the primary timeline (picture-in-picture).
/// Position is stored as a normalized canvas offset so projects render consistently
/// at preview and export resolutions.
struct EditorOverlayClip: Identifiable, Hashable {
    static let minimumSpan: TimeInterval = 0.25

    let id: UUID
    let asset: PHAsset
    var originalDuration: TimeInterval
    var trimStart: TimeInterval
    var trimEnd: TimeInterval
    var timelineStart: TimeInterval
    /// Persistent logical timeline row. Split pieces retain their parent's row.
    var laneIndex: Int
    /// Back-to-front compositing order. Split pieces retain their parent's layer.
    var zIndex: Int
    var speed: Float
    var scale: CGFloat
    var xOffset: CGFloat
    var yOffset: CGFloat
    var opacity: Double
    var volume: Float
    var cropAspect: EditorCropAspect
    var reframeMode: EditorReframeMode
    var rotationQuarterTurns: Int
    var straightenDegrees: Double
    var isFlippedHorizontally: Bool
    var isFlippedVertically: Bool
    var reframeScale: CGFloat
    var reframeXOffset: CGFloat
    var reframeYOffset: CGFloat
    var colorAdjustment: EditorColorAdjustment
    var keyframes: EditorKeyframeTracks

    init(
        id: UUID = UUID(),
        asset: PHAsset,
        originalDuration: TimeInterval? = nil,
        trimStart: TimeInterval = 0,
        trimEnd: TimeInterval? = nil,
        timelineStart: TimeInterval = 0,
        laneIndex: Int = 0,
        zIndex: Int? = nil,
        speed: Float = 1,
        scale: CGFloat = 0.55,
        xOffset: CGFloat = 0,
        yOffset: CGFloat = 0,
        opacity: Double = 1,
        volume: Float = 1,
        cropAspect: EditorCropAspect = .original,
        reframeMode: EditorReframeMode = .fit,
        rotationQuarterTurns: Int = 0,
        straightenDegrees: Double = 0,
        isFlippedHorizontally: Bool = false,
        isFlippedVertically: Bool = false,
        reframeScale: CGFloat = 1,
        reframeXOffset: CGFloat = 0,
        reframeYOffset: CGFloat = 0,
        colorAdjustment: EditorColorAdjustment = .neutral,
        keyframes: EditorKeyframeTracks = .empty
    ) {
        let duration = originalDuration
            ?? (asset.mediaType == .video ? asset.duration : EditorClip.photoDefaultDuration)
        self.id = id
        self.asset = asset
        self.originalDuration = duration
        self.trimStart = min(max(0, trimStart), duration)
        self.trimEnd = min(max(trimEnd ?? duration, self.trimStart), duration)
        self.timelineStart = max(0, timelineStart)
        self.laneIndex = laneIndex
        self.zIndex = max(0, zIndex ?? laneIndex)
        self.speed = min(max(speed, 0.25), 3)
        self.scale = min(max(scale, 0.15), 1.5)
        self.xOffset = min(max(xOffset, -0.75), 0.75)
        self.yOffset = min(max(yOffset, -0.75), 0.75)
        self.opacity = min(max(opacity, 0.05), 1)
        self.volume = min(max(volume, 0), 1)
        self.cropAspect = cropAspect
        self.reframeMode = reframeMode
        self.rotationQuarterTurns = rotationQuarterTurns % 4
        self.straightenDegrees = min(max(straightenDegrees, -45), 45)
        self.isFlippedHorizontally = isFlippedHorizontally
        self.isFlippedVertically = isFlippedVertically
        self.reframeScale = min(max(reframeScale, 0.5), 4)
        self.reframeXOffset = min(max(reframeXOffset, -1), 1)
        self.reframeYOffset = min(max(reframeYOffset, -1), 1)
        self.colorAdjustment = colorAdjustment
        self.keyframes = keyframes
    }

    var duration: TimeInterval {
        let sourceDuration = max(0, trimEnd - trimStart)
        return sourceDuration / TimeInterval(max(speed, 0.001))
    }
    var timelineEnd: TimeInterval { timelineStart + duration }
    var isVideo: Bool { asset.mediaType == .video }
    var isPhoto: Bool { asset.mediaType == .image }

    var thumbnailClip: EditorClip {
        EditorClip(
            id: id,
            asset: asset,
            originalDuration: originalDuration,
            trimStart: trimStart,
            trimEnd: trimEnd,
            speed: speed,
            volume: volume,
            cropAspect: cropAspect,
            reframeMode: reframeMode,
            rotationQuarterTurns: rotationQuarterTurns,
            straightenDegrees: straightenDegrees,
            isFlippedHorizontally: isFlippedHorizontally,
            isFlippedVertically: isFlippedVertically,
            reframeScale: reframeScale,
            reframeXOffset: reframeXOffset,
            reframeYOffset: reframeYOffset,
            colorAdjustment: colorAdjustment
        )
    }

    func sourceTime(forTimelineLocal local: TimeInterval) -> TimeInterval {
        min(max(trimStart + local * TimeInterval(speed), trimStart), trimEnd)
    }

    func resolved(at timelineTime: TimeInterval) -> EditorOverlayClip {
        var result = self
        let localTime = min(max(0, timelineTime - timelineStart), duration)
        result.xOffset = CGFloat(keyframes.value(
            for: .positionX, at: localTime, default: Double(xOffset)
        ))
        result.yOffset = CGFloat(keyframes.value(
            for: .positionY, at: localTime, default: Double(yOffset)
        ))
        result.scale = CGFloat(keyframes.value(
            for: .scale, at: localTime, default: Double(scale)
        ))
        result.opacity = keyframes.value(
            for: .opacity, at: localTime, default: opacity
        )
        return result
    }

    func split(atSourceTime sourceTime: TimeInterval) -> (left: EditorOverlayClip, right: EditorOverlayClip)? {
        guard sourceTime >= trimStart + Self.minimumSpan,
              sourceTime <= trimEnd - Self.minimumSpan else { return nil }

        let splitLocalTime = (sourceTime - trimStart) / TimeInterval(max(speed, 0.001))
        let splitKeyframes = keyframes.split(at: splitLocalTime)

        let left = EditorOverlayClip(
            id: id,
            asset: asset,
            originalDuration: originalDuration,
            trimStart: trimStart,
            trimEnd: sourceTime,
            timelineStart: timelineStart,
            laneIndex: laneIndex,
            zIndex: zIndex,
            speed: speed,
            scale: scale,
            xOffset: xOffset,
            yOffset: yOffset,
            opacity: opacity,
            volume: volume,
            cropAspect: cropAspect,
            reframeMode: reframeMode,
            rotationQuarterTurns: rotationQuarterTurns,
            straightenDegrees: straightenDegrees,
            isFlippedHorizontally: isFlippedHorizontally,
            isFlippedVertically: isFlippedVertically,
            reframeScale: reframeScale,
            reframeXOffset: reframeXOffset,
            reframeYOffset: reframeYOffset,
            colorAdjustment: colorAdjustment,
            keyframes: splitKeyframes.left
        )
        let right = EditorOverlayClip(
            asset: asset,
            originalDuration: originalDuration,
            trimStart: sourceTime,
            trimEnd: trimEnd,
            timelineStart: timelineStart + left.duration,
            laneIndex: laneIndex,
            zIndex: zIndex,
            speed: speed,
            scale: scale,
            xOffset: xOffset,
            yOffset: yOffset,
            opacity: opacity,
            volume: volume,
            cropAspect: cropAspect,
            reframeMode: reframeMode,
            rotationQuarterTurns: rotationQuarterTurns,
            straightenDegrees: straightenDegrees,
            isFlippedHorizontally: isFlippedHorizontally,
            isFlippedVertically: isFlippedVertically,
            reframeScale: reframeScale,
            reframeXOffset: reframeXOffset,
            reframeYOffset: reframeYOffset,
            colorAdjustment: colorAdjustment,
            keyframes: splitKeyframes.right
        )
        return (left, right)
    }

    static func == (lhs: EditorOverlayClip, rhs: EditorOverlayClip) -> Bool {
        lhs.id == rhs.id
            && lhs.asset.localIdentifier == rhs.asset.localIdentifier
            && lhs.originalDuration == rhs.originalDuration
            && lhs.trimStart == rhs.trimStart
            && lhs.trimEnd == rhs.trimEnd
            && lhs.timelineStart == rhs.timelineStart
            && lhs.laneIndex == rhs.laneIndex
            && lhs.zIndex == rhs.zIndex
            && lhs.speed == rhs.speed
            && lhs.scale == rhs.scale
            && lhs.xOffset == rhs.xOffset
            && lhs.yOffset == rhs.yOffset
            && lhs.opacity == rhs.opacity
            && lhs.volume == rhs.volume
            && lhs.cropAspect == rhs.cropAspect
            && lhs.reframeMode == rhs.reframeMode
            && lhs.rotationQuarterTurns == rhs.rotationQuarterTurns
            && lhs.straightenDegrees == rhs.straightenDegrees
            && lhs.isFlippedHorizontally == rhs.isFlippedHorizontally
            && lhs.isFlippedVertically == rhs.isFlippedVertically
            && lhs.reframeScale == rhs.reframeScale
            && lhs.reframeXOffset == rhs.reframeXOffset
            && lhs.reframeYOffset == rhs.reframeYOffset
            && lhs.colorAdjustment == rhs.colorAdjustment
            && lhs.keyframes == rhs.keyframes
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
