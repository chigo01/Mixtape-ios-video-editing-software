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

enum EditorReverseAudioPolicy: String, Codable, CaseIterable, Identifiable, Hashable {
    case reverse
    case mute

    var id: String { rawValue }
    var title: String { self == .reverse ? "Reverse Audio" : "Mute Audio" }
}

enum EditorFreezeAudioPolicy: String, Codable, CaseIterable, Identifiable, Hashable {
    /// The usual freeze-frame edit: music, voiceover, and other timeline lanes
    /// continue, but the selected clip's embedded source audio is silent.
    case mute
    /// Plays source audio forward from the sampled frame for the hold duration.
    /// This is intentionally explicit because it creates an editorial J-cut.
    case continueSource

    var id: String { rawValue }
    var title: String { self == .mute ? "Mute Clip Audio" : "Continue Clip Audio" }
}

// MARK: - Stackable visual effects

enum EditorEffectCategory: String, CaseIterable, Identifiable, Hashable {
    case featured, motion, light, glitch, pixel, retro, stylize, blur

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var systemImage: String {
        switch self {
        case .featured: return "sparkles"
        case .motion: return "move.3d"
        case .light: return "sun.max.fill"
        case .glitch: return "waveform.path.ecg"
        case .pixel: return "square.grid.3x3.fill"
        case .retro: return "film.stack"
        case .stylize: return "wand.and.stars"
        case .blur: return "drop.fill"
        }
    }
}

/// A render operation in a clip or adjustment-layer effect stack. Effects are
/// evaluated in array order and use the shared keyframe sampler for Amount.
enum EditorVisualEffectKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case gaussianBlur, motionBlur, bloom, sharpen, vignette, grain
    case pixelate, crystallize, comic, monochrome, sepia, hueShift
    case zoomBlur, edgeGlow, posterize, invert, falseColor, noir, chrome
    case rgbSplit, scanlines, lineScreen, dotScreen, hexPixelate
    case kaleidoscope, twirl, bump, zoomPulse, shake, strobe

    var id: String { rawValue }
    var title: String {
        switch self {
        case .gaussianBlur: return "Gaussian Blur"
        case .motionBlur: return "Motion Blur"
        case .bloom: return "Bloom"
        case .sharpen: return "Sharpen"
        case .vignette: return "Vignette"
        case .grain: return "Film Grain"
        case .pixelate: return "Pixelate"
        case .crystallize: return "Crystallize"
        case .comic: return "Comic"
        case .monochrome: return "Monochrome"
        case .sepia: return "Sepia"
        case .hueShift: return "Hue Shift"
        case .zoomBlur: return "Zoom Blur"
        case .edgeGlow: return "Edge Glow"
        case .posterize: return "Posterize"
        case .invert: return "Invert"
        case .falseColor: return "False Color"
        case .noir: return "Noir"
        case .chrome: return "Chrome"
        case .rgbSplit: return "RGB Split"
        case .scanlines: return "Scanlines"
        case .lineScreen: return "Line Screen"
        case .dotScreen: return "Dot Screen"
        case .hexPixelate: return "Hex Pixel"
        case .kaleidoscope: return "Kaleidoscope"
        case .twirl: return "Twirl"
        case .bump: return "Lens Bump"
        case .zoomPulse: return "Zoom Pulse"
        case .shake: return "Camera Shake"
        case .strobe: return "Strobe"
        }
    }

    var systemImage: String {
        switch self {
        case .gaussianBlur, .motionBlur: return "drop"
        case .bloom: return "sun.max.fill"
        case .sharpen: return "triangle"
        case .vignette: return "circle.dotted"
        case .grain: return "circle.grid.cross"
        case .pixelate, .crystallize: return "square.grid.3x3.fill"
        case .comic: return "text.bubble.fill"
        case .monochrome: return "circle.lefthalf.filled"
        case .sepia: return "photo.artframe"
        case .hueShift: return "paintpalette.fill"
        case .zoomBlur, .zoomPulse: return "scope"
        case .edgeGlow: return "scribble.variable"
        case .posterize, .falseColor: return "swatchpalette.fill"
        case .invert: return "circle.lefthalf.filled.inverse"
        case .noir: return "circle.righthalf.filled"
        case .chrome: return "circle.hexagongrid.fill"
        case .rgbSplit: return "square.3.layers.3d"
        case .scanlines, .lineScreen: return "line.3.horizontal"
        case .dotScreen: return "circle.grid.3x3.fill"
        case .hexPixelate: return "hexagon.fill"
        case .kaleidoscope: return "camera.aperture"
        case .twirl: return "tornado"
        case .bump: return "circle.circle"
        case .shake: return "move.3d"
        case .strobe: return "bolt.fill"
        }
    }

    var category: EditorEffectCategory {
        switch self {
        case .gaussianBlur, .motionBlur, .zoomBlur: return .blur
        case .bloom, .strobe: return .light
        case .pixelate, .crystallize, .hexPixelate, .dotScreen, .lineScreen: return .pixel
        case .grain, .sepia, .monochrome, .noir: return .retro
        case .rgbSplit, .scanlines, .invert: return .glitch
        case .zoomPulse, .shake: return .motion
        case .sharpen, .vignette, .comic, .hueShift, .edgeGlow, .posterize,
             .falseColor, .chrome, .kaleidoscope, .twirl, .bump:
            return .stylize
        }
    }

    var secondaryControlTitle: String? {
        switch self {
        case .motionBlur: return "Direction"
        case .vignette, .twirl, .bump: return "Radius"
        case .rgbSplit: return "Direction"
        case .scanlines, .lineScreen, .dotScreen: return "Scale"
        case .kaleidoscope: return "Segments"
        case .zoomPulse, .shake, .strobe: return "Speed"
        default: return nil
        }
    }

    var isTemporal: Bool {
        switch self {
        case .zoomPulse, .shake, .strobe: return true
        default: return false
        }
    }
}

struct EditorVisualEffect: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var kind: EditorVisualEffectKind
    var isEnabled: Bool = true
    var amount: Double = 0.65
    /// A second normalized control used where an effect needs direction/size.
    var secondaryAmount: Double = 0.5
    var amountKeyframes: EditorKeyframeTrack = .init(property: .effectAmount)

    func resolvedAmount(at localTime: TimeInterval) -> Double {
        amountKeyframes.value(at: localTime, default: min(max(amount, 0), 1))
    }

    func split(at localTime: TimeInterval) -> (left: Self, right: Self) {
        let pair = EditorKeyframeTracks(tracks: [amountKeyframes]).split(at: localTime)
        var left = self
        var right = self
        left.amountKeyframes = pair.left.track(for: .effectAmount)
        right.amountKeyframes = pair.right.track(for: .effectAmount)
        return (left, right)
    }

    func held(at localTime: TimeInterval) -> Self {
        var result = self
        result.amount = resolvedAmount(at: localTime)
        result.amountKeyframes = EditorKeyframeTrack(
            property: .effectAmount,
            keyframes: [EditorKeyframe(
                time: 0,
                value: result.amount,
                curve: .init(preset: .hold)
            )]
        )
        return result
    }
}

struct EditorEffectPreset: Identifiable, Hashable {
    let id: String
    let title: String
    let category: EditorEffectCategory
    let effects: [EditorVisualEffect]

    static let builtIn: [Self] = [
        .init(id: "dreamy", title: "Dreamy", category: .featured, effects: [
            .init(kind: .bloom, amount: 0.55), .init(kind: .gaussianBlur, amount: 0.12)
        ]),
        .init(id: "film", title: "Film", category: .featured, effects: [
            .init(kind: .grain, amount: 0.32), .init(kind: .vignette, amount: 0.28)
        ]),
        .init(id: "graphic", title: "Graphic", category: .featured, effects: [
            .init(kind: .comic, amount: 0.72), .init(kind: .sharpen, amount: 0.25)
        ]),
        .init(id: "retro", title: "Retro", category: .featured, effects: [
            .init(kind: .sepia, amount: 0.46), .init(kind: .grain, amount: 0.18)
        ]),
        .init(id: "slowZoom", title: "Slow Zoom", category: .motion, effects: [
            .init(kind: .zoomPulse, amount: 0.35, secondaryAmount: 0.12)
        ]),
        .init(id: "backOff", title: "Back Off", category: .motion, effects: [
            .init(kind: .zoomPulse, amount: 0.48, secondaryAmount: 0.34),
            .init(kind: .motionBlur, amount: 0.12, secondaryAmount: 0.5)
        ]),
        .init(id: "cameraShake", title: "Camera Shake", category: .motion, effects: [
            .init(kind: .shake, amount: 0.42, secondaryAmount: 0.55)
        ]),
        .init(id: "dynamicBlur", title: "Dynamic Blur", category: .motion, effects: [
            .init(kind: .shake, amount: 0.16, secondaryAmount: 0.65),
            .init(kind: .motionBlur, amount: 0.28, secondaryAmount: 0.08)
        ]),
        .init(id: "zoomFlash", title: "Zoom Flash", category: .motion, effects: [
            .init(kind: .zoomPulse, amount: 0.52, secondaryAmount: 0.72),
            .init(kind: .zoomBlur, amount: 0.3), .init(kind: .strobe, amount: 0.22, secondaryAmount: 0.35)
        ]),
        .init(id: "rebound", title: "Rebound", category: .motion, effects: [
            .init(kind: .zoomPulse, amount: 0.68, secondaryAmount: 0.82),
            .init(kind: .shake, amount: 0.12, secondaryAmount: 0.7)
        ]),
        .init(id: "whiteFlash", title: "White Flash", category: .light, effects: [
            .init(kind: .strobe, amount: 0.72, secondaryAmount: 0.38), .init(kind: .bloom, amount: 0.45)
        ]),
        .init(id: "neonBloom", title: "Neon Bloom", category: .light, effects: [
            .init(kind: .edgeGlow, amount: 0.58), .init(kind: .bloom, amount: 0.7),
            .init(kind: .hueShift, amount: 0.72)
        ]),
        .init(id: "heatImprint", title: "Heat Imprint", category: .light, effects: [
            .init(kind: .falseColor, amount: 0.68), .init(kind: .bloom, amount: 0.28)
        ]),
        .init(id: "softLeak", title: "Soft Leak", category: .light, effects: [
            .init(kind: .bloom, amount: 0.76), .init(kind: .hueShift, amount: 0.1),
            .init(kind: .vignette, amount: 0.18, secondaryAmount: 0.8)
        ]),
        .init(id: "offsetSlice", title: "Offset Slice", category: .glitch, effects: [
            .init(kind: .rgbSplit, amount: 0.7, secondaryAmount: 0.08),
            .init(kind: .scanlines, amount: 0.22, secondaryAmount: 0.45)
        ]),
        .init(id: "glitchQuake", title: "Glitch Quake", category: .glitch, effects: [
            .init(kind: .shake, amount: 0.35, secondaryAmount: 0.78),
            .init(kind: .rgbSplit, amount: 0.62, secondaryAmount: 0.82),
            .init(kind: .scanlines, amount: 0.34, secondaryAmount: 0.6)
        ]),
        .init(id: "signalBreak", title: "Signal Break", category: .glitch, effects: [
            .init(kind: .posterize, amount: 0.42), .init(kind: .rgbSplit, amount: 0.56),
            .init(kind: .strobe, amount: 0.15, secondaryAmount: 0.82)
        ]),
        .init(id: "digitalDamage", title: "Digital Damage", category: .glitch, effects: [
            .init(kind: .pixelate, amount: 0.24), .init(kind: .invert, amount: 0.2),
            .init(kind: .rgbSplit, amount: 0.46)
        ]),
        .init(id: "pixelArt", title: "Pixel Art", category: .pixel, effects: [
            .init(kind: .pixelate, amount: 0.48), .init(kind: .posterize, amount: 0.72),
            .init(kind: .sharpen, amount: 0.55)
        ]),
        .init(id: "pixelMosaic", title: "Pixel Mosaic", category: .pixel, effects: [
            .init(kind: .crystallize, amount: 0.38), .init(kind: .pixelate, amount: 0.18)
        ]),
        .init(id: "hexWorld", title: "Hex World", category: .pixel, effects: [
            .init(kind: .hexPixelate, amount: 0.5), .init(kind: .sharpen, amount: 0.24)
        ]),
        .init(id: "dotPrint", title: "Dot Print", category: .pixel, effects: [
            .init(kind: .dotScreen, amount: 0.58, secondaryAmount: 0.46),
            .init(kind: .monochrome, amount: 0.25)
        ]),
        .init(id: "comicPixel", title: "Comic Pixel", category: .pixel, effects: [
            .init(kind: .comic, amount: 0.62), .init(kind: .lineScreen, amount: 0.3)
        ]),
        .init(id: "nostalgic", title: "Nostalgic Light", category: .retro, effects: [
            .init(kind: .sepia, amount: 0.3), .init(kind: .grain, amount: 0.28),
            .init(kind: .bloom, amount: 0.16)
        ]),
        .init(id: "vintageDark", title: "Vintage Dark", category: .retro, effects: [
            .init(kind: .sepia, amount: 0.22), .init(kind: .grain, amount: 0.42),
            .init(kind: .vignette, amount: 0.7, secondaryAmount: 0.35)
        ]),
        .init(id: "bwNoise", title: "B&W Noise", category: .retro, effects: [
            .init(kind: .noir, amount: 0.84), .init(kind: .grain, amount: 0.58),
            .init(kind: .scanlines, amount: 0.12)
        ]),
        .init(id: "chromeFilm", title: "Chrome Film", category: .retro, effects: [
            .init(kind: .chrome, amount: 0.7), .init(kind: .grain, amount: 0.16)
        ]),
        .init(id: "thermal", title: "Thermal", category: .stylize, effects: [
            .init(kind: .falseColor, amount: 0.92), .init(kind: .posterize, amount: 0.16)
        ]),
        .init(id: "edgeNeon", title: "Edge Neon", category: .stylize, effects: [
            .init(kind: .edgeGlow, amount: 0.82), .init(kind: .hueShift, amount: 0.82)
        ]),
        .init(id: "prism", title: "Prism", category: .stylize, effects: [
            .init(kind: .kaleidoscope, amount: 0.56, secondaryAmount: 0.45),
            .init(kind: .bloom, amount: 0.18)
        ]),
        .init(id: "vortex", title: "Vortex", category: .stylize, effects: [
            .init(kind: .twirl, amount: 0.54, secondaryAmount: 0.68)
        ]),
        .init(id: "fisheye", title: "Fisheye", category: .stylize, effects: [
            .init(kind: .bump, amount: 0.62, secondaryAmount: 0.72)
        ]),
        .init(id: "chromeBlur", title: "Chrome Blur", category: .blur, effects: [
            .init(kind: .chrome, amount: 0.62), .init(kind: .gaussianBlur, amount: 0.16)
        ]),
        .init(id: "softFocus", title: "Soft Focus", category: .blur, effects: [
            .init(kind: .gaussianBlur, amount: 0.08), .init(kind: .bloom, amount: 0.38)
        ]),
        .init(id: "speedSmear", title: "Speed Smear", category: .blur, effects: [
            .init(kind: .zoomBlur, amount: 0.48), .init(kind: .motionBlur, amount: 0.22)
        ]),
        .init(id: "dreamBlur", title: "Dream Blur", category: .blur, effects: [
            .init(kind: .gaussianBlur, amount: 0.18), .init(kind: .bloom, amount: 0.65),
            .init(kind: .vignette, amount: 0.16)
        ])
    ]
}

/// A non-media timeline item that processes the fully composited program frame.
/// Overlapping layers are evaluated in z-order, then array order.
struct EditorAdjustmentLayer: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var title: String = "Adjustment Layer"
    var startTime: TimeInterval
    var endTime: TimeInterval
    var zIndex: Int = 0
    var isEnabled: Bool = true
    var colorAdjustment: EditorColorAdjustment = .neutral
    var effects: [EditorVisualEffect] = []

    var duration: TimeInterval { max(0, endTime - startTime) }
    func contains(_ time: TimeInterval) -> Bool {
        isEnabled && time >= startTime && time < endTime
    }

    init(
        id: UUID = UUID(),
        title: String = "Adjustment Layer",
        startTime: TimeInterval,
        endTime: TimeInterval,
        zIndex: Int = 0,
        isEnabled: Bool = true,
        colorAdjustment: EditorColorAdjustment = .neutral,
        effects: [EditorVisualEffect] = []
    ) {
        self.id = id
        self.title = title
        self.startTime = max(0, startTime)
        self.endTime = max(self.startTime + 0.1, endTime)
        self.zIndex = zIndex
        self.isEnabled = isEnabled
        self.colorAdjustment = colorAdjustment
        self.effects = effects
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "Adjustment Layer"
        startTime = max(0, try container.decode(TimeInterval.self, forKey: .startTime))
        endTime = max(
            startTime + 0.1,
            try container.decode(TimeInterval.self, forKey: .endTime)
        )
        zIndex = try container.decodeIfPresent(Int.self, forKey: .zIndex) ?? 0
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        colorAdjustment = try container.decodeIfPresent(
            EditorColorAdjustment.self,
            forKey: .colorAdjustment
        ) ?? .neutral
        effects = try container.decodeIfPresent([EditorVisualEffect].self, forKey: .effects) ?? []
    }
}

/// Non-destructive source treatment. The original Photos asset remains the
/// relink authority; reverse media is a deterministic, disposable render cache.
enum EditorClipPlayback: Codable, Hashable {
    case forward
    case reverse(audio: EditorReverseAudioPolicy)
    case freeze(sourceTime: TimeInterval, audio: EditorFreezeAudioPolicy)

    var isReverse: Bool {
        if case .reverse = self { return true }
        return false
    }

    var isFreezeFrame: Bool {
        if case .freeze = self { return true }
        return false
    }
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
    var speedRamp: EditorSpeedRamp?
    var playback: EditorClipPlayback
    var volume: Float
    /// Embedded source-audio boundaries. While linked, nil values follow the
    /// video trim exactly. Unlinking materializes independent source handles
    /// so J/L cuts can overlap the neighboring picture without moving it.
    var audioTrimStart: TimeInterval?
    var audioTrimEnd: TimeInterval?
    var isAudioLinked: Bool
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
    var effects: [EditorVisualEffect]
    var compositing: EditorOverlayCompositing
    var keyframes: EditorKeyframeTracks
    var motionTracks: [EditorMotionTrack]
    var stabilization: EditorStabilizationSettings
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
        speedRamp: EditorSpeedRamp? = nil,
        playback: EditorClipPlayback = .forward,
        volume: Float = 1.0,
        audioTrimStart: TimeInterval? = nil,
        audioTrimEnd: TimeInterval? = nil,
        isAudioLinked: Bool = true,
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
        effects: [EditorVisualEffect] = [],
        compositing: EditorOverlayCompositing = .standard,
        keyframes: EditorKeyframeTracks = .empty,
        motionTracks: [EditorMotionTrack] = [],
        stabilization: EditorStabilizationSettings = .disabled,
        transitionKind: EditorTransitionKind = .none,
        transitionDuration: TimeInterval = 0
    ) {
        self.id = id
        self.asset = asset
        self.originalDuration = originalDuration
        self.trimStart = trimStart
        self.trimEnd = trimEnd
        self.speed = speed
        self.speedRamp = speedRamp?.isUsable == true ? speedRamp : nil
        self.playback = playback
        self.volume = volume
        self.isAudioLinked = isAudioLinked
        let resolvedAudioStart = min(max(audioTrimStart ?? trimStart, 0), originalDuration)
        let resolvedAudioEnd = min(
            max(audioTrimEnd ?? trimEnd, resolvedAudioStart),
            originalDuration
        )
        self.audioTrimStart = isAudioLinked ? nil : resolvedAudioStart
        self.audioTrimEnd = isAudioLinked ? nil : resolvedAudioEnd
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
        self.effects = effects
        var sanitizedCompositing = compositing
        sanitizedCompositing.sanitize()
        self.compositing = sanitizedCompositing
        self.keyframes = keyframes
        self.motionTracks = motionTracks
        self.stabilization = stabilization
        self.transitionKind = transitionDuration > 0 ? transitionKind : .none
        self.transitionDuration = max(0, transitionDuration)
    }

    /// Minimum source span so a clip stays at least ~0.25s on the timeline.
    static func minimumSourceSpan(speed: Float) -> TimeInterval {
        max(0.25 * TimeInterval(max(speed, 0.001)), 0.05)
    }

    /// Splits this clip at `sourceTime` (asset seconds). Returns nil if too close to either edge.
    func split(atSourceTime sourceTime: TimeInterval) -> (left: EditorClip, right: EditorClip)? {
        let minSpan = Self.minimumSourceSpan(speed: averageSpeed)
        guard sourceTime >= trimStart + minSpan, sourceTime <= trimEnd - minSpan else { return nil }

        let sourceSpan = max(trimEnd - trimStart, 0)
        let splitSourceOffset = sourceTime - trimStart
        let splitLocalTime = timelineTime(forSourceOffset: splitSourceOffset)
        let splitKeyframes = keyframes.split(at: splitLocalTime)
        let splitEffects = effects.map { $0.split(at: splitLocalTime) }
        let splitRamps = speedRamp?.split(
            atSourceProgress: sourceSpan > 0 ? splitSourceOffset / sourceSpan : 0.5
        )
        let splitProgress = duration > 0 ? splitLocalTime / duration : 0.5
        let splitTracks = motionTracks.map { $0.split(at: splitProgress) }
        let splitStabilization = stabilization.split(at: splitProgress)

        let left = EditorClip(
            id: id,
            asset: asset,
            originalDuration: originalDuration,
            trimStart: trimStart,
            trimEnd: sourceTime,
            speed: speed,
            speedRamp: splitRamps?.left,
            playback: playback,
            volume: volume,
            audioTrimStart: isAudioLinked ? nil : effectiveAudioTrimStart,
            audioTrimEnd: isAudioLinked ? nil : min(effectiveAudioTrimEnd, sourceTime),
            isAudioLinked: isAudioLinked,
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
            effects: splitEffects.map(\.left),
            compositing: compositing,
            keyframes: splitKeyframes.left,
            motionTracks: splitTracks.map(\.left),
            stabilization: splitStabilization.left,
            transitionKind: .none,
            transitionDuration: 0
        )
        let right = EditorClip(
            asset: asset,
            originalDuration: originalDuration,
            trimStart: sourceTime,
            trimEnd: trimEnd,
            speed: speed,
            speedRamp: splitRamps?.right,
            playback: playback,
            volume: volume,
            audioTrimStart: isAudioLinked ? nil : max(effectiveAudioTrimStart, sourceTime),
            audioTrimEnd: isAudioLinked ? nil : effectiveAudioTrimEnd,
            isAudioLinked: isAudioLinked,
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
            effects: splitEffects.map(\.right),
            compositing: compositing,
            keyframes: splitKeyframes.right,
            motionTracks: splitTracks.map(\.right),
            stabilization: splitStabilization.right,
            transitionKind: transitionKind,
            transitionDuration: transitionDuration
        )
        return (left, right)
    }

    /// Splits in what the editor is displaying. A reversed clip's first
    /// timeline half comes from the upper source range, so its source halves
    /// must be returned in the opposite order.
    func split(atTimelineTime localTime: TimeInterval) -> (left: EditorClip, right: EditorClip)? {
        let splitSourceTime = displayedSourceTime(atTimelineTime: localTime)
        guard let parts = split(atSourceTime: splitSourceTime) else { return nil }
        if playback.isReverse {
            var left = parts.right
            var right = parts.left
            let clampedLocal = min(max(0, localTime), duration)
            let splitKeyframes = keyframes.split(at: clampedLocal)
            let splitEffects = effects.map { $0.split(at: clampedLocal) }
            left.keyframes = splitKeyframes.left
            right.keyframes = splitKeyframes.right
            left.effects = splitEffects.map(\.left)
            right.effects = splitEffects.map(\.right)
            let reversedSourceOffset = sourceTime(forExportedLocal: clampedLocal) - trimStart
            let sourceSpan = max(trimEnd - trimStart, 0.000_001)
            let splitRamps = speedRamp?.split(
                atSourceProgress: min(max(reversedSourceOffset / sourceSpan, 0), 1)
            )
            left.speedRamp = splitRamps?.left
            right.speedRamp = splitRamps?.right
            let progress = min(max(clampedLocal / max(duration, 0.000_001), 0), 1)
            let splitTracks = motionTracks.map { $0.split(at: progress) }
            left.motionTracks = splitTracks.map(\.left)
            right.motionTracks = splitTracks.map(\.right)
            let splitStabilization = stabilization.split(at: progress)
            left.stabilization = splitStabilization.left
            right.stabilization = splitStabilization.right
            left.transitionKind = .none
            left.transitionDuration = 0
            right.transitionKind = transitionKind
            right.transitionDuration = transitionDuration
            return (left, right)
        }
        return parts
    }

    var isVideo: Bool { asset.mediaType == .video }
    var isPhoto: Bool { asset.mediaType == .image }

    /// Duration after trim + speed (timeline seconds for this clip).
    var duration: TimeInterval {
        let trimmed = max(0, trimEnd - trimStart)
        if let speedRamp {
            return speedRamp.timelineDuration(forSourceDuration: trimmed)
        }
        return speed > 0 ? trimmed / TimeInterval(speed) : trimmed
    }

    /// Effective constant rate for UI gestures that operate in source pixels.
    /// Rendering and seeking still use the complete ramp plan.
    var averageSpeed: Float {
        let trimmed = max(0, trimEnd - trimStart)
        guard duration > 0 else { return max(speed, 0.001) }
        return Float(trimmed / duration)
    }

    var effectiveAudioTrimStart: TimeInterval {
        isAudioLinked ? trimStart : min(max(audioTrimStart ?? trimStart, 0), originalDuration)
    }

    var effectiveAudioTrimEnd: TimeInterval {
        isAudioLinked ? trimEnd : min(max(audioTrimEnd ?? trimEnd, effectiveAudioTrimStart), originalDuration)
    }

    /// Local playback time within this clip (source timeline), derived from exported `localTime * speed + trimStart`.
    func sourceTime(forExportedLocal local: TimeInterval) -> TimeInterval {
        let trimmed = max(0, trimEnd - trimStart)
        if let speedRamp {
            return min(
                max(
                    trimStart + speedRamp.sourceOffset(
                        forTimelineTime: local,
                        sourceDuration: trimmed
                    ),
                    trimStart
                ),
                trimEnd
            )
        }
        return min(
            max(trimStart + local * TimeInterval(speed), trimStart),
            trimEnd
        )
    }

    func displayedSourceTime(atTimelineTime local: TimeInterval) -> TimeInterval {
        let forward = sourceTime(forExportedLocal: local)
        guard playback.isReverse else {
            if case let .freeze(sourceTime, _) = playback { return sourceTime }
            return forward
        }
        return min(max(trimEnd - (forward - trimStart), trimStart), trimEnd)
    }

    func timelineTime(forSourceOffset sourceOffset: TimeInterval) -> TimeInterval {
        let trimmed = max(0, trimEnd - trimStart)
        if let speedRamp {
            return speedRamp.timelineTime(
                forSourceOffset: sourceOffset,
                sourceDuration: trimmed
            )
        }
        return sourceOffset / TimeInterval(max(speed, 0.001))
    }

    static func == (lhs: EditorClip, rhs: EditorClip) -> Bool {
        lhs.id == rhs.id
            && lhs.asset.localIdentifier == rhs.asset.localIdentifier
            && lhs.trimStart == rhs.trimStart
            && lhs.trimEnd == rhs.trimEnd
            && lhs.speed == rhs.speed
            && lhs.speedRamp == rhs.speedRamp
            && lhs.playback == rhs.playback
            && lhs.volume == rhs.volume
            && lhs.audioTrimStart == rhs.audioTrimStart
            && lhs.audioTrimEnd == rhs.audioTrimEnd
            && lhs.isAudioLinked == rhs.isAudioLinked
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
            && lhs.effects == rhs.effects
            && lhs.compositing == rhs.compositing
            && lhs.keyframes == rhs.keyframes
            && lhs.motionTracks == rhs.motionTracks
            && lhs.stabilization == rhs.stabilization
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
    var playback: EditorClipPlayback
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
    var effects: [EditorVisualEffect]
    var compositing: EditorOverlayCompositing
    var keyframes: EditorKeyframeTracks
    var motionTracks: [EditorMotionTrack]
    var stabilization: EditorStabilizationSettings
    var attachedClipID: UUID?
    var attachedTrackID: UUID?
    var attachRotation: Bool
    var attachScale: Bool

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
        playback: EditorClipPlayback = .forward,
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
        effects: [EditorVisualEffect] = [],
        compositing: EditorOverlayCompositing = .standard,
        keyframes: EditorKeyframeTracks = .empty,
        motionTracks: [EditorMotionTrack] = [],
        stabilization: EditorStabilizationSettings = .disabled,
        attachedClipID: UUID? = nil,
        attachedTrackID: UUID? = nil,
        attachRotation: Bool = false,
        attachScale: Bool = false
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
        self.playback = playback
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
        self.effects = effects
        var sanitizedCompositing = compositing
        sanitizedCompositing.sanitize()
        self.compositing = sanitizedCompositing
        self.keyframes = keyframes
        self.motionTracks = motionTracks
        self.stabilization = stabilization
        self.attachedClipID = attachedClipID
        self.attachedTrackID = attachedTrackID
        self.attachRotation = attachRotation
        self.attachScale = attachScale
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
            playback: playback,
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
            effects: effects
        )
    }

    func sourceTime(forTimelineLocal local: TimeInterval) -> TimeInterval {
        let clampedLocal = min(max(0, local), duration)
        switch playback {
        case .forward:
            return min(max(trimStart + clampedLocal * TimeInterval(speed), trimStart), trimEnd)
        case .reverse:
            return min(max(trimEnd - clampedLocal * TimeInterval(speed), trimStart), trimEnd)
        case let .freeze(sourceTime, _):
            return min(max(sourceTime, 0), originalDuration)
        }
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

    func applyingTrack(
        _ sample: EditorMotionTrackSample,
        seed: EditorMotionTrackSample
    ) -> EditorOverlayClip {
        var result = self
        result.xOffset = min(max(xOffset + sample.x - seed.x, -0.75), 0.75)
        result.yOffset = min(max(yOffset + sample.y - seed.y, -0.75), 0.75)
        if attachScale {
            result.scale = min(
                max(scale * (sample.scale / max(seed.scale, 0.000_001)), 0.15),
                1.5
            )
        }
        return result
    }

    func split(atSourceTime sourceTime: TimeInterval) -> (left: EditorOverlayClip, right: EditorOverlayClip)? {
        guard sourceTime >= trimStart + Self.minimumSpan,
              sourceTime <= trimEnd - Self.minimumSpan else { return nil }

        let splitLocalTime = (sourceTime - trimStart) / TimeInterval(max(speed, 0.001))
        let splitKeyframes = keyframes.split(at: splitLocalTime)
        let splitEffects = effects.map { $0.split(at: splitLocalTime) }
        let splitProgress = duration > 0 ? splitLocalTime / duration : 0.5
        let splitTracks = motionTracks.map { $0.split(at: splitProgress) }
        let splitStabilization = stabilization.split(at: splitProgress)

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
            playback: playback,
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
            effects: splitEffects.map(\.left),
            compositing: compositing,
            keyframes: splitKeyframes.left,
            motionTracks: splitTracks.map(\.left),
            stabilization: splitStabilization.left,
            attachedClipID: attachedClipID,
            attachedTrackID: attachedTrackID,
            attachRotation: attachRotation,
            attachScale: attachScale
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
            playback: playback,
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
            effects: splitEffects.map(\.right),
            compositing: compositing,
            keyframes: splitKeyframes.right,
            motionTracks: splitTracks.map(\.right),
            stabilization: splitStabilization.right,
            attachedClipID: attachedClipID,
            attachedTrackID: attachedTrackID,
            attachRotation: attachRotation,
            attachScale: attachScale
        )
        return (left, right)
    }

    func split(atTimelineTime localTime: TimeInterval) -> (left: EditorOverlayClip, right: EditorOverlayClip)? {
        guard !playback.isFreezeFrame else { return nil }
        let clampedLocal = min(max(0, localTime), duration)
        let sourceTime = sourceTime(forTimelineLocal: clampedLocal)
        guard let sourceParts = split(atSourceTime: sourceTime) else { return nil }
        guard playback.isReverse else { return sourceParts }

        var left = sourceParts.right
        var right = sourceParts.left
        left.timelineStart = timelineStart
        right.timelineStart = timelineStart + left.duration

        let splitKeyframes = keyframes.split(at: clampedLocal)
        left.keyframes = splitKeyframes.left
        right.keyframes = splitKeyframes.right
        let progress = duration > 0 ? clampedLocal / duration : 0.5
        let splitTracks = motionTracks.map { $0.split(at: progress) }
        left.motionTracks = splitTracks.map(\.left)
        right.motionTracks = splitTracks.map(\.right)
        let splitStabilization = stabilization.split(at: progress)
        left.stabilization = splitStabilization.left
        right.stabilization = splitStabilization.right
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
            && lhs.playback == rhs.playback
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
            && lhs.effects == rhs.effects
            && lhs.compositing == rhs.compositing
            && lhs.keyframes == rhs.keyframes
            && lhs.motionTracks == rhs.motionTracks
            && lhs.stabilization == rhs.stabilization
            && lhs.attachedClipID == rhs.attachedClipID
            && lhs.attachedTrackID == rhs.attachedTrackID
            && lhs.attachRotation == rhs.attachRotation
            && lhs.attachScale == rhs.attachScale
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
