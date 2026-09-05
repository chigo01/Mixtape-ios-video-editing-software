//
//  EditorTextOverlay.swift
//  Mixtape
//
//  Created by Favour Baruch on 14/05/2026.
//

import SwiftUI

// MARK: - Stickers and reusable graphics

/// A portable graphic source. Imported images are copied into Mixtape's Application Support
/// folder before this path is stored, so projects never depend on a temporary Photos picker URL.
enum EditorGraphicSource: Codable, Hashable {
    case emoji(String)
    case symbol(String)
    case image(path: String)

    var catalogID: String {
        switch self {
        case let .emoji(value): return "emoji:\(value)"
        case let .symbol(name): return "symbol:\(name)"
        case let .image(path): return "image:\(path)"
        }
    }

    var displayName: String {
        switch self {
        case let .emoji(value): return value
        case let .symbol(name): return name.replacingOccurrences(of: ".", with: " ").capitalized
        case let .image(path): return URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        }
    }

    init?(catalogID: String) {
        if catalogID.hasPrefix("emoji:") {
            self = .emoji(String(catalogID.dropFirst("emoji:".count)))
        } else if catalogID.hasPrefix("symbol:") {
            self = .symbol(String(catalogID.dropFirst("symbol:".count)))
        } else if catalogID.hasPrefix("image:") {
            let path = String(catalogID.dropFirst("image:".count))
            guard FileManager.default.fileExists(atPath: path) else { return nil }
            self = .image(path: path)
        } else {
            return nil
        }
    }
}

enum EditorGraphicBlendMode: String, Codable, CaseIterable, Identifiable, Hashable {
    case normal, multiply, screen, overlay, softLight, difference
    var id: String { rawValue }
    var title: String {
        switch self {
        case .normal: return "Normal"
        case .multiply: return "Multiply"
        case .screen: return "Screen"
        case .overlay: return "Overlay"
        case .softLight: return "Soft Light"
        case .difference: return "Difference"
        }
    }
    var swiftUIValue: BlendMode {
        switch self {
        case .normal: return .normal
        case .multiply: return .multiply
        case .screen: return .screen
        case .overlay: return .overlay
        case .softLight: return .softLight
        case .difference: return .difference
        }
    }
    var coreAnimationFilterName: String? {
        self == .normal ? nil : "\(rawValue)BlendMode"
    }
}

enum EditorGraphicAnimation: String, Codable, CaseIterable, Identifiable, Hashable {
    case none, pop, pulse, float, bounce, spin, wiggle
    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    /// Deterministic sampling shared by interactive preview and offline export.
    func sample(localTime: TimeInterval, duration: TimeInterval) -> (scale: Double, rotation: Double, y: Double, opacity: Double) {
        let t = max(0, localTime)
        let entrance = min(1, t / 0.22)
        let exit = min(1, max(0, duration - t) / 0.18)
        let visibility = min(entrance, exit)
        switch self {
        case .none: return (1, 0, 0, visibility)
        case .pop:
            let overshoot = entrance < 1 ? 1 + sin(entrance * .pi) * 0.16 : 1
            return (max(0.05, entrance) * overshoot, 0, 0, exit)
        case .pulse: return (1 + sin(t * .pi * 2.4) * 0.08, 0, 0, visibility)
        case .float: return (1, 0, sin(t * .pi * 1.3) * 10, visibility)
        case .bounce: return (1, 0, -abs(sin(t * .pi * 2.1)) * 16, visibility)
        case .spin: return (1, t * 90, 0, visibility)
        case .wiggle: return (1, sin(t * .pi * 5) * 7, 0, visibility)
        }
    }
}

struct EditorGraphicOverlay: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var source: EditorGraphicSource
    var title: String
    var startTime: TimeInterval
    var endTime: TimeInterval
    /// Offsets and size use the same 390pt reference canvas as text overlays.
    var xOffset: CGFloat = 0
    var yOffset: CGFloat = 0
    var size: CGFloat = 132
    var scale: CGFloat = 1
    var rotationDegrees: Double = 0
    var opacity: Double = 1
    var tintRGB: UInt32? = nil
    var blendMode: EditorGraphicBlendMode = .normal
    var animation: EditorGraphicAnimation = .pop
    var isFlippedHorizontally = false
    var isFlippedVertically = false

    var duration: TimeInterval { max(0, endTime - startTime) }
    func isVisible(at time: TimeInterval) -> Bool { time >= startTime && time < endTime }
}

enum EditorGraphicCatalog {
    static let emojis = [
        "🔥", "✨", "💫", "⭐️", "❤️", "💔", "😂", "😭", "😎", "🤯", "🥶", "😈",
        "💯", "💥", "⚡️", "🎵", "🎧", "🎤", "🎬", "📸", "🏆", "👑", "💎", "🚀",
        "🌈", "🌙", "☀️", "🌸", "🦋", "👀", "👍", "🫶", "✅", "❌", "‼️", "❓"
    ]
    static let symbols = [
        "star.fill", "heart.fill", "bolt.fill", "flame.fill", "sparkles", "crown.fill",
        "music.note", "headphones", "mic.fill", "play.fill", "camera.fill", "film.fill",
        "quote.bubble.fill", "message.fill", "location.fill", "paperplane.fill", "bell.fill",
        "checkmark.seal.fill", "exclamationmark.triangle.fill", "arrow.up.right", "scribble",
        "circle.hexagongrid.fill", "waveform", "scope", "viewfinder", "burst.fill"
    ]
}

enum EditorGraphicFavoritesStore {
    private static let key = "editor.graphic.favorite.catalogIDs.v1"
    static var ids: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: key) ?? []) }
        set { UserDefaults.standard.set(Array(newValue).sorted(), forKey: key) }
    }
    static func toggle(_ source: EditorGraphicSource) {
        var value = ids
        if value.contains(source.catalogID) { value.remove(source.catalogID) }
        else { value.insert(source.catalogID) }
        ids = value
    }
}

/// A single recognized word in a caption segment. Times are absolute timeline
/// seconds so seeking, highlighting, SRT conversion, and future transcript
/// edits all share one deterministic clock.
struct EditorCaptionWord: Identifiable, Hashable, Codable {
    let id: UUID
    var text: String
    var startTime: TimeInterval
    var endTime: TimeInterval
    var confidence: Float

    init(
        id: UUID = UUID(),
        text: String,
        startTime: TimeInterval,
        endTime: TimeInterval,
        confidence: Float = 1
    ) {
        self.id = id
        self.text = text
        self.startTime = startTime
        self.endTime = max(startTime, endTime)
        self.confidence = min(max(confidence, 0), 1)
    }
}

// MARK: - Font style presets (the "Aa" chips)

enum TextOverlayFontStyle: String, CaseIterable, Identifiable, Hashable, Codable {
    case plain
    case bold
    case italic
    case outlined
    case shadow
    case background

    var id: String { rawValue }

    var label: String {
        switch self {
        case .plain:      return "Aa"
        case .bold:       return "Aa"
        case .italic:     return "Aa"
        case .outlined:   return "Aa"
        case .shadow:     return "Aa"
        case .background: return "Aa"
        }
    }

    var font: Font {
        switch self {
        case .plain:      return .system(size: 15, weight: .regular)
        case .bold:       return .system(size: 15, weight: .bold)
        case .italic:     return .system(size: 15, weight: .regular).italic()
        case .outlined:   return .system(size: 15, weight: .semibold)
        case .shadow:     return .system(size: 15, weight: .semibold)
        case .background: return .system(size: 15, weight: .bold)
        }
    }

    /// Dark chip background for the "Aa" on white/dark bg style.
    var chipBackground: Color {
        switch self {
        case .background: return .black
        case .outlined:   return Color.white.opacity(0.06)
        default:          return Color.white.opacity(0.06)
        }
    }

    var chipForeground: Color {
        switch self {
        case .background: return .white
        default:          return .white
        }
    }
}

// MARK: - Preset colors

enum TextOverlayColor: String, CaseIterable, Identifiable, Hashable, Codable {
    case white
    case lightGray
    case gray
    case darkGray
    case black
    case yellow
    case orange
    case red
    case pink
    case purple
    case blue
    case green

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .white:     return .white
        case .lightGray: return Color(white: 0.78)
        case .gray:      return Color(white: 0.55)
        case .darkGray:  return Color(white: 0.32)
        case .black:     return .black
        case .yellow:    return Color(hue: 0.13, saturation: 0.9, brightness: 0.95)
        case .orange:    return Color(hue: 0.08, saturation: 0.9, brightness: 0.95)
        case .red:       return Color(hue: 0.0, saturation: 0.85, brightness: 0.9)
        case .pink:      return Color(hue: 0.9, saturation: 0.6, brightness: 0.95)
        case .purple:    return Color(hue: 0.78, saturation: 0.7, brightness: 0.85)
        case .blue:      return Color(hue: 0.6, saturation: 0.8, brightness: 0.9)
        case .green:     return Color(hue: 0.38, saturation: 0.75, brightness: 0.8)
        }
    }

    var uiColor: UIColor {
        UIColor(color)
    }
}

// MARK: - Alignment

enum TextOverlayHAlignment: String, CaseIterable, Identifiable, Hashable, Codable {
    case leading
    case center
    case trailing

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .leading:  return "text.alignleft"
        case .center:   return "text.aligncenter"
        case .trailing: return "text.alignright"
        }
    }

    var alignment: TextAlignment {
        switch self {
        case .leading:  return .leading
        case .center:   return .center
        case .trailing: return .trailing
        }
    }

    var frameAlignment: Alignment {
        switch self {
        case .leading:  return .leading
        case .center:   return .center
        case .trailing: return .trailing
        }
    }
}

enum TextOverlayVAlignment: String, CaseIterable, Identifiable, Hashable, Codable {
    case top
    case center
    case bottom

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .top:    return "arrow.up.to.line"
        case .center: return "arrow.up.and.down"
        case .bottom: return "arrow.down.to.line"
        }
    }

    var frameAlignment: Alignment {
        switch self {
        case .top:    return .top
        case .center: return .center
        case .bottom: return .bottom
        }
    }
}

// MARK: - Font Family

enum TextOverlayFontFamily: String, CaseIterable, Identifiable, Hashable, Codable {
    case system = "System"
    case avenirNext = "Avenir Next"
    case baskerville = "Baskerville"
    case chalkboardSE = "Chalkboard SE"
    case courierNew = "Courier New"
    case didot = "Didot"
    case futura = "Futura"
    case gillSans = "Gill Sans"
    case helveticaNeue = "Helvetica Neue"
    case hoeflerText = "Hoefler Text"
    case markerFelt = "Marker Felt"
    case menlo = "Menlo"
    case noteworthy = "Noteworthy"
    case optima = "Optima"
    case palatino = "Palatino"
    case papyrus = "Papyrus"
    case partyLET = "Party LET"
    case snellRoundhand = "Snell Roundhand"
    case timesNewRoman = "Times New Roman"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "SYSTEM"
        case .avenirNext: return "Avenir"
        case .chalkboardSE: return "Chalkboard"
        case .markerFelt: return "Marker"
        case .snellRoundhand: return "Roundhand"
        case .timesNewRoman: return "Times"
        case .helveticaNeue: return "Helvetica"
        default: return rawValue
        }
    }
}

// MARK: - Text animation

enum EditorTextAnimationPreset: String, CaseIterable, Identifiable, Hashable, Codable {
    case none
    case fade
    case slideUp
    case slideDown
    case slideLeft
    case slideRight
    case zoom
    case bounce
    case blur
    case typewriter
    case pop
    case pulse
    case wiggle

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "None"
        case .fade: return "Fade"
        case .slideUp: return "Slide Up"
        case .slideDown: return "Slide Down"
        case .slideLeft: return "Slide Left"
        case .slideRight: return "Slide Right"
        case .zoom: return "Zoom"
        case .bounce: return "Bounce"
        case .blur: return "Blur"
        case .typewriter: return "Typewriter"
        case .pop: return "Pop"
        case .pulse: return "Pulse"
        case .wiggle: return "Wiggle"
        }
    }

    var systemImage: String {
        switch self {
        case .none: return "nosign"
        case .fade: return "circle.lefthalf.filled"
        case .slideUp: return "arrow.up"
        case .slideDown: return "arrow.down"
        case .slideLeft: return "arrow.left"
        case .slideRight: return "arrow.right"
        case .zoom: return "arrow.up.left.and.arrow.down.right"
        case .bounce: return "arrow.up.and.down"
        case .blur: return "aqi.medium"
        case .typewriter: return "character.cursor.ibeam"
        case .pop: return "sparkles"
        case .pulse: return "waveform.path"
        case .wiggle: return "water.waves"
        }
    }
}

struct EditorTextAnimation: Hashable, Codable {
    var inPreset: EditorTextAnimationPreset
    var outPreset: EditorTextAnimationPreset
    var loopPreset: EditorTextAnimationPreset
    var inDuration: TimeInterval
    var outDuration: TimeInterval
    var loopDuration: TimeInterval
    var intensity: Double
    var characterDelay: TimeInterval

    static let none = EditorTextAnimation(
        inPreset: .none,
        outPreset: .none,
        loopPreset: .none,
        inDuration: 0.45,
        outDuration: 0.35,
        loopDuration: 1.2,
        intensity: 1,
        characterDelay: 0.055
    )

    var isAnimated: Bool {
        inPreset != .none || outPreset != .none || loopPreset != .none
    }

    func sample(localTime: TimeInterval, duration: TimeInterval) -> EditorTextAnimationSample {
        guard isAnimated, duration > 0 else { return .identity }
        let time = min(max(0, localTime), duration)
        var result = EditorTextAnimationSample.identity
        let strength = min(max(intensity, 0), 2)

        if inPreset != .none, inDuration > 0, time < min(inDuration, duration) {
            let progress = min(max(time / min(inDuration, duration), 0), 1)
            result.combine(phaseSample(for: inPreset, progress: progress, entering: true, strength: strength))
        }
        if outPreset != .none, outDuration > 0, time > max(0, duration - outDuration) {
            let progress = min(max((duration - time) / min(outDuration, duration), 0), 1)
            result.combine(phaseSample(for: outPreset, progress: progress, entering: false, strength: strength))
        }
        if loopPreset != .none {
            let period = max(loopDuration, 0.15)
            let phase = (time.truncatingRemainder(dividingBy: period)) / period
            result.combine(loopSample(for: loopPreset, phase: phase, strength: strength))
        }
        return result
    }

    func revealProgress(localTime: TimeInterval, itemCount: Int) -> Double {
        guard inPreset == .typewriter, itemCount > 0 else { return 1 }
        let revealDuration = max(0.05, Double(itemCount) * max(characterDelay, 0.015))
        return min(max(localTime / revealDuration, 0), 1)
    }

    private func phaseSample(
        for preset: EditorTextAnimationPreset,
        progress: Double,
        entering: Bool,
        strength: Double
    ) -> EditorTextAnimationSample {
        let eased = 1 - pow(1 - progress, 3)
        let hidden = 1 - eased
        let direction = entering ? hidden : -hidden
        var sample = EditorTextAnimationSample.identity
        switch preset {
        case .none, .typewriter:
            break
        case .fade:
            sample.opacity = eased
        case .slideUp:
            sample.opacity = eased
            sample.yOffset = 70 * direction * strength
        case .slideDown:
            sample.opacity = eased
            sample.yOffset = -70 * direction * strength
        case .slideLeft:
            sample.opacity = eased
            sample.xOffset = 90 * direction * strength
        case .slideRight:
            sample.opacity = eased
            sample.xOffset = -90 * direction * strength
        case .zoom:
            sample.opacity = eased
            sample.scale = 0.55 + 0.45 * eased
        case .bounce:
            sample.opacity = eased
            sample.yOffset = 55 * hidden * strength - sin(progress * .pi * 3) * 12 * hidden * strength
        case .blur:
            sample.opacity = eased
            sample.blurRadius = 14 * hidden * strength
        case .pop:
            sample.opacity = eased
            sample.scale = 0.6 + 0.4 * eased + sin(progress * .pi) * 0.16 * strength
        case .pulse, .wiggle:
            break
        }
        return sample
    }

    private func loopSample(
        for preset: EditorTextAnimationPreset,
        phase: Double,
        strength: Double
    ) -> EditorTextAnimationSample {
        var sample = EditorTextAnimationSample.identity
        let wave = sin(phase * .pi * 2)
        switch preset {
        case .pulse, .pop, .zoom:
            sample.scale = 1 + 0.07 * wave * strength
        case .bounce:
            sample.yOffset = -10 * abs(wave) * strength
        case .wiggle:
            sample.rotationDegrees = 3.5 * wave * strength
        case .fade:
            sample.opacity = 0.82 + 0.18 * (wave + 1) / 2
        case .blur:
            sample.blurRadius = 2.5 * (wave + 1) / 2 * strength
        case .slideUp, .slideDown:
            sample.yOffset = 5 * wave * strength
        case .slideLeft, .slideRight:
            sample.xOffset = 5 * wave * strength
        case .none, .typewriter:
            break
        }
        return sample
    }
}

struct EditorTextAnimationSample: Hashable {
    var opacity: Double
    var scale: Double
    var xOffset: Double
    var yOffset: Double
    var rotationDegrees: Double
    var blurRadius: Double
    var revealProgress: Double

    static let identity = EditorTextAnimationSample(
        opacity: 1,
        scale: 1,
        xOffset: 0,
        yOffset: 0,
        rotationDegrees: 0,
        blurRadius: 0,
        revealProgress: 1
    )

    mutating func combine(_ other: EditorTextAnimationSample) {
        opacity *= other.opacity
        scale *= other.scale
        xOffset += other.xOffset
        yOffset += other.yOffset
        rotationDegrees += other.rotationDegrees
        blurRadius = max(blurRadius, other.blurRadius)
        revealProgress = min(revealProgress, other.revealProgress)
    }
}

// MARK: - Text overlay model

struct EditorTextOverlay: Identifiable, Hashable {
    let id: UUID
    var text: String
    var startTime: TimeInterval
    var endTime: TimeInterval

    // Style properties
    var fontSize: CGFloat
    var fontFamily: TextOverlayFontFamily
    var fontStyle: TextOverlayFontStyle
    var textColor: TextOverlayColor
    var opacity: Double
    var horizontalAlignment: TextOverlayHAlignment
    var verticalAlignment: TextOverlayVAlignment
    var xOffset: CGFloat
    var yOffset: CGFloat
    var keyframes: EditorKeyframeTracks
    var animation: EditorTextAnimation
    var attachedClipID: UUID?
    var attachedTrackID: UUID?
    var attachRotation: Bool
    var attachScale: Bool
    /// Non-empty only for transcript-backed text. Keeping captions in the
    /// normal text-overlay model gives them existing trim/move, undo,
    /// persistence, preview, and export behavior without a parallel renderer.
    var captionWords: [EditorCaptionWord]
    var captionHighlightColor: TextOverlayColor
    var captionLocaleIdentifier: String?
    /// Display-only rotation contributed by an attached planar track.
    var trackedRotationDegrees: Double

    init(
        id: UUID = UUID(),
        text: String,
        startTime: TimeInterval,
        endTime: TimeInterval,
        fontSize: CGFloat = 36,
        fontFamily: TextOverlayFontFamily = .system,
        fontStyle: TextOverlayFontStyle = .plain,
        textColor: TextOverlayColor = .white,
        opacity: Double = 1.0,
        horizontalAlignment: TextOverlayHAlignment = .center,
        verticalAlignment: TextOverlayVAlignment = .center,
        xOffset: CGFloat = 0,
        yOffset: CGFloat = 0,
        keyframes: EditorKeyframeTracks = .empty,
        animation: EditorTextAnimation = .none,
        attachedClipID: UUID? = nil,
        attachedTrackID: UUID? = nil,
        attachRotation: Bool = false,
        attachScale: Bool = false,
        captionWords: [EditorCaptionWord] = [],
        captionHighlightColor: TextOverlayColor = .yellow,
        captionLocaleIdentifier: String? = nil,
        trackedRotationDegrees: Double = 0
    ) {
        self.id = id
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
        self.fontSize = fontSize
        self.fontFamily = fontFamily
        self.fontStyle = fontStyle
        self.textColor = textColor
        self.opacity = opacity
        self.horizontalAlignment = horizontalAlignment
        self.verticalAlignment = verticalAlignment
        self.xOffset = xOffset
        self.yOffset = yOffset
        self.keyframes = keyframes
        self.animation = animation
        self.attachedClipID = attachedClipID
        self.attachedTrackID = attachedTrackID
        self.attachRotation = attachRotation
        self.attachScale = attachScale
        self.captionWords = captionWords
        self.captionHighlightColor = captionHighlightColor
        self.captionLocaleIdentifier = captionLocaleIdentifier
        self.trackedRotationDegrees = trackedRotationDegrees
    }

    var duration: TimeInterval { max(0, endTime - startTime) }

    var isCaption: Bool { !captionWords.isEmpty }

    func activeCaptionWordID(at timelineTime: TimeInterval) -> UUID? {
        captionWords.first {
            timelineTime >= $0.startTime && timelineTime < $0.endTime
        }?.id
    }

    /// The resolved SwiftUI Font for rendering on the preview.
    /// `sizeScale` maps a stored point size onto a live canvas that is not
    /// screen-width (inline preview vs fullscreen vs export).
    func resolvedFont(sizeScale: CGFloat = 1) -> Font {
        let size = max(fontSize * sizeScale, 1)
        let baseFont: Font
        if fontFamily == .system {
            baseFont = .system(size: size, weight: .regular)
        } else {
            baseFont = .custom(fontFamily.rawValue, size: size)
        }

        switch fontStyle {
        case .plain:      return baseFont
        case .bold:       return baseFont.weight(.bold)
        case .italic:     return baseFont.italic()
        case .outlined:   return baseFont.weight(.bold)
        case .shadow:     return baseFont.weight(.semibold)
        case .background: return baseFont.weight(.bold)
        }
    }

    /// Whether this overlay is visible at the given global timeline position.
    func isVisible(at time: TimeInterval) -> Bool {
        time >= startTime && time < endTime
    }

    func resolved(at timelineTime: TimeInterval) -> EditorTextOverlay {
        var result = self
        let localTime = min(max(0, timelineTime - startTime), duration)
        result.xOffset = CGFloat(keyframes.value(
            for: .textPositionX, at: localTime, default: Double(xOffset)
        ))
        result.yOffset = CGFloat(keyframes.value(
            for: .textPositionY, at: localTime, default: Double(yOffset)
        ))
        result.opacity = keyframes.value(
            for: .opacity, at: localTime, default: opacity
        )
        result.fontSize = fontSize * CGFloat(keyframes.value(
            for: .textScale, at: localTime, default: 1
        ))
        return result
    }

    func applyingTrack(
        _ sample: EditorMotionTrackSample,
        seed: EditorMotionTrackSample,
        canvasSize: CGSize
    ) -> EditorTextOverlay {
        var result = self
        result.xOffset += CGFloat(sample.x - seed.x) * canvasSize.width
        result.yOffset += CGFloat(sample.y - seed.y) * canvasSize.height
        if attachScale {
            let ratio = sample.scale / max(seed.scale, 0.000_001)
            result.fontSize = max(fontSize * CGFloat(ratio), 8)
        }
        if attachRotation {
            result.trackedRotationDegrees = (sample.rotation - seed.rotation) * 180 / .pi
        }
        return result
    }

    var isAttachedToTrack: Bool {
        attachedClipID != nil && attachedTrackID != nil
    }
}

/// Shared layout contract for live preview and export.
/// Offsets and font sizes are stored in points as if the canvas were
/// `UIScreen.main.bounds.width` wide (what `EditorTextOverlayRenderer` uses).
/// Live canvases scale those values by `canvas.width / referenceWidth`.
enum EditorTextOverlayLayout {
    static let canvasSpaceName = "textOverlayCanvas"
    static let previewPadding: CGFloat = 12

    static var referenceWidth: CGFloat {
        max(UIScreen.main.bounds.width, 1)
    }

    static func canvasScale(for canvasSize: CGSize) -> CGFloat {
        canvasSize.width / referenceWidth
    }

    static func referenceCanvasSize(aspectRatio: CGFloat) -> CGSize {
        let width = referenceWidth
        return CGSize(width: width, height: width / max(aspectRatio, 0.000_001))
    }

    static func referenceCanvasSize(matching liveCanvas: CGSize) -> CGSize {
        let width = referenceWidth
        return CGSize(
            width: width,
            height: width * liveCanvas.height / max(liveCanvas.width, 1)
        )
    }
}
