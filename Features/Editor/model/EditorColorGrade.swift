//
//  EditorColorGrade.swift
//  Mixtape
//
//  Non-destructive, Codable color-grade model shared by UI, preview, and export.
//

import Foundation

enum EditorFilterCategory: String, CaseIterable, Identifiable {
    case featured = "Featured"
    case cinematic = "Cinematic"
    case film = "Film"
    case portrait = "Portrait"
    case landscape = "Landscape"
    case monochrome = "B&W"
    case creative = "Creative"

    var id: String { rawValue }
}

enum EditorFilterPreset: String, Codable, CaseIterable, Identifiable {
    case original
    case vivid
    case warm
    case cool
    case cinematic
    case faded
    case mono
    case noir
    case chrome
    case natural
    case fresh
    case clean
    case goldenHour
    case portraitGlow
    case blush
    case softSkin
    case tealOrange
    case blockbuster
    case moody
    case nightDrive
    case desert
    case forest
    case ocean
    case vintageBronze
    case romance
    case retro
    case sepia
    case polaroid
    case fadedFilm
    case filmNoir
    case tokyo
    case cyberpunk
    case dreamy
    case neon
    case aqua
    case sunset
    case lavender
    case silver
    case graphite
    case highContrastBW

    var id: String { rawValue }

    var title: String {
        switch self {
        case .original: return "Original"
        case .vivid: return "Vivid"
        case .warm: return "Warm"
        case .cool: return "Cool"
        case .cinematic: return "Cinema"
        case .faded: return "Fade"
        case .mono: return "Mono"
        case .noir: return "Noir"
        case .chrome: return "Chrome"
        case .natural: return "Natural"
        case .fresh: return "Fresh"
        case .clean: return "Clean"
        case .goldenHour: return "Golden Hour"
        case .portraitGlow: return "Portrait Glow"
        case .blush: return "Blush"
        case .softSkin: return "Soft Skin"
        case .tealOrange: return "Teal & Orange"
        case .blockbuster: return "Blockbuster"
        case .moody: return "Moody"
        case .nightDrive: return "Night Drive"
        case .desert: return "Desert"
        case .forest: return "Forest"
        case .ocean: return "Ocean"
        case .vintageBronze: return "Vintage Bronze"
        case .romance: return "Romance"
        case .retro: return "Retro"
        case .sepia: return "Sepia"
        case .polaroid: return "Polaroid"
        case .fadedFilm: return "Faded Film"
        case .filmNoir: return "Film Noir"
        case .tokyo: return "Tokyo"
        case .cyberpunk: return "Cyberpunk"
        case .dreamy: return "Dreamy"
        case .neon: return "Neon"
        case .aqua: return "Aqua"
        case .sunset: return "Sunset"
        case .lavender: return "Lavender"
        case .silver: return "Silver"
        case .graphite: return "Graphite"
        case .highContrastBW: return "Hard B&W"
        }
    }

    var category: EditorFilterCategory {
        switch self {
        case .original, .vivid, .warm, .cool, .natural, .fresh, .clean:
            return .featured
        case .cinematic, .tealOrange, .blockbuster, .moody, .nightDrive:
            return .cinematic
        case .faded, .vintageBronze, .romance, .retro, .sepia, .polaroid, .fadedFilm:
            return .film
        case .goldenHour, .portraitGlow, .blush, .softSkin:
            return .portrait
        case .desert, .forest, .ocean, .aqua, .sunset:
            return .landscape
        case .mono, .noir, .filmNoir, .silver, .graphite, .highContrastBW:
            return .monochrome
        case .chrome, .tokyo, .cyberpunk, .dreamy, .neon, .lavender:
            return .creative
        }
    }

    /// Compact colors used by the filter browser when a source thumbnail is unavailable.
    var swatchRGB: [UInt32] {
        switch self {
        case .original: return [0x777777, 0x222222]
        case .vivid: return [0xFF3B76, 0xFF9E28, 0x3478F6]
        case .warm, .goldenHour, .sunset: return [0xFFD45C, 0xF47732, 0xA82A32]
        case .cool, .ocean, .aqua: return [0x4DE1E8, 0x3578D4, 0x27328C]
        case .cinematic, .tealOrange, .blockbuster: return [0x167F83, 0xD87835]
        case .faded, .fadedFilm, .polaroid: return [0xBFA98E, 0xE4D9C8]
        case .mono, .silver: return [0xF0F0F0, 0x777777]
        case .noir, .filmNoir, .graphite, .highContrastBW: return [0x9A9A9A, 0x050505]
        case .chrome, .cyberpunk, .neon: return [0x922BFF, 0x00E4FF, 0xFF2EC4]
        case .natural, .fresh, .clean: return [0x9BD0A4, 0xDCEED8, 0x6B9CB6]
        case .portraitGlow, .blush, .softSkin, .romance: return [0xF6B4AD, 0xE87989, 0xFFD1B8]
        case .moody, .nightDrive: return [0x172A42, 0x684875, 0xBE6F59]
        case .desert, .vintageBronze, .sepia, .retro: return [0xC78D4A, 0x795239, 0xE1B87B]
        case .forest: return [0x163C2B, 0x568B52, 0xB6B66A]
        case .tokyo: return [0xF54B7A, 0x552D86, 0x1FB5C7]
        case .dreamy, .lavender: return [0xD8B5FF, 0x8BBDF1, 0xF4C3DD]
        }
    }
}

enum EditorHSLColor: String, Codable, CaseIterable, Identifiable {
    case red, orange, yellow, green, cyan, blue, purple, magenta

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    /// Center hue in normalized HSV space.
    var centerHue: Double {
        switch self {
        case .red: return 0
        case .orange: return 30 / 360
        case .yellow: return 60 / 360
        case .green: return 120 / 360
        case .cyan: return 180 / 360
        case .blue: return 220 / 360
        case .purple: return 275 / 360
        case .magenta: return 320 / 360
        }
    }
}

struct EditorHSLBandAdjustment: Codable, Hashable, Identifiable {
    var color: EditorHSLColor
    var hue: Double = 0
    var saturation: Double = 0
    var lightness: Double = 0

    var id: EditorHSLColor { color }
    var isNeutral: Bool {
        abs(hue) < 0.0001 && abs(saturation) < 0.0001 && abs(lightness) < 0.0001
    }
}

struct EditorHSLAdjustments: Codable, Hashable {
    var bands: [EditorHSLBandAdjustment] = EditorHSLColor.allCases.map {
        EditorHSLBandAdjustment(color: $0)
    }

    subscript(_ color: EditorHSLColor) -> EditorHSLBandAdjustment {
        get { bands.first(where: { $0.color == color }) ?? EditorHSLBandAdjustment(color: color) }
        set {
            if let index = bands.firstIndex(where: { $0.color == color }) {
                bands[index] = newValue
            } else {
                bands.append(newValue)
            }
        }
    }

    var isNeutral: Bool { bands.allSatisfy(\.isNeutral) }
}

struct EditorCurvePoint: Codable, Hashable, Identifiable {
    var x: Double
    var y: Double
    var id: Double { x }
}

enum EditorCurveChannel: String, CaseIterable, Identifiable {
    case master, red, green, blue
    var id: String { rawValue }
    var title: String { self == .master ? "RGB" : rawValue.capitalized }
}

struct EditorToneCurves: Codable, Hashable {
    static let linearPoints: [EditorCurvePoint] = [
        EditorCurvePoint(x: 0, y: 0),
        EditorCurvePoint(x: 1, y: 1)
    ]

    var master: [EditorCurvePoint] = Self.linearPoints
    var red: [EditorCurvePoint] = Self.linearPoints
    var green: [EditorCurvePoint] = Self.linearPoints
    var blue: [EditorCurvePoint] = Self.linearPoints

    subscript(_ channel: EditorCurveChannel) -> [EditorCurvePoint] {
        get {
            switch channel {
            case .master: return master
            case .red: return red
            case .green: return green
            case .blue: return blue
            }
        }
        set {
            switch channel {
            case .master: master = newValue
            case .red: red = newValue
            case .green: green = newValue
            case .blue: blue = newValue
            }
        }
    }

    var isNeutral: Bool {
        [master, red, green, blue].allSatisfy { points in
            points.count == Self.linearPoints.count
                && zip(points, Self.linearPoints).allSatisfy { pair in
                    abs(pair.0.y - pair.1.y) < 0.0001
                }
        }
    }
}

enum EditorColorWheelRange: String, CaseIterable, Identifiable {
    case lift, gamma, gain, offset
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct EditorColorWheelValue: Codable, Hashable {
    var x: Double = 0
    var y: Double = 0
    var luminance: Double = 0

    var isNeutral: Bool {
        abs(x) < 0.0001 && abs(y) < 0.0001 && abs(luminance) < 0.0001
    }
}

struct EditorColorWheels: Codable, Hashable {
    var lift = EditorColorWheelValue()
    var gamma = EditorColorWheelValue()
    var gain = EditorColorWheelValue()
    var offset = EditorColorWheelValue()

    subscript(_ range: EditorColorWheelRange) -> EditorColorWheelValue {
        get {
            switch range {
            case .lift: return lift
            case .gamma: return gamma
            case .gain: return gain
            case .offset: return offset
            }
        }
        set {
            switch range {
            case .lift: lift = newValue
            case .gamma: gamma = newValue
            case .gain: gain = newValue
            case .offset: offset = newValue
            }
        }
    }

    var isNeutral: Bool { lift.isNeutral && gamma.isNeutral && gain.isNeutral && offset.isNeutral }

    private enum CodingKeys: String, CodingKey { case lift, gamma, gain, offset }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lift = try c.decodeIfPresent(EditorColorWheelValue.self, forKey: .lift) ?? .init()
        gamma = try c.decodeIfPresent(EditorColorWheelValue.self, forKey: .gamma) ?? .init()
        gain = try c.decodeIfPresent(EditorColorWheelValue.self, forKey: .gain) ?? .init()
        offset = try c.decodeIfPresent(EditorColorWheelValue.self, forKey: .offset) ?? .init()
    }
}

/// All values are intentionally normalized so the UI and renderer share one stable contract.
struct EditorColorAdjustment: Codable, Hashable {
    var preset: EditorFilterPreset = .original
    var presetIntensity: Double = 1
    var brightness: Double = 0
    var exposure: Double = 0
    var contrast: Double = 0
    var saturation: Double = 0
    var brilliance: Double = 0
    var vibrance: Double = 0
    var dehaze: Double = 0
    var highlights: Double = 0
    var shadows: Double = 0
    var whites: Double = 0
    var blacks: Double = 0
    var temperature: Double = 0
    var tint: Double = 0
    var hue: Double = 0
    var fade: Double = 0
    var sharpness: Double = 0
    var clarity: Double = 0
    var grain: Double = 0
    var vignette: Double = 0
    var hsl = EditorHSLAdjustments()
    var curves = EditorToneCurves()
    var wheels = EditorColorWheels()

    static let neutral = EditorColorAdjustment()

    var isNeutral: Bool {
        preset == .original
            && abs(brightness) < 0.0001
            && abs(exposure) < 0.0001
            && abs(contrast) < 0.0001
            && abs(saturation) < 0.0001
            && abs(brilliance) < 0.0001
            && abs(vibrance) < 0.0001
            && abs(dehaze) < 0.0001
            && abs(highlights) < 0.0001
            && abs(shadows) < 0.0001
            && abs(whites) < 0.0001
            && abs(blacks) < 0.0001
            && abs(temperature) < 0.0001
            && abs(tint) < 0.0001
            && abs(hue) < 0.0001
            && fade < 0.0001
            && sharpness < 0.0001
            && clarity < 0.0001
            && grain < 0.0001
            && vignette < 0.0001
            && hsl.isNeutral
            && curves.isNeutral
            && wheels.isNeutral
    }

    private enum CodingKeys: String, CodingKey {
        case preset, presetIntensity, brightness, exposure, contrast, saturation, brilliance
        case vibrance, dehaze
        case highlights, shadows, whites, blacks, temperature, tint, hue, fade
        case sharpness, clarity, grain, vignette, hsl, curves, wheels
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        preset = try c.decodeIfPresent(EditorFilterPreset.self, forKey: .preset) ?? .original
        presetIntensity = try c.decodeIfPresent(Double.self, forKey: .presetIntensity) ?? 1
        brightness = try c.decodeIfPresent(Double.self, forKey: .brightness) ?? 0
        exposure = try c.decodeIfPresent(Double.self, forKey: .exposure) ?? 0
        contrast = try c.decodeIfPresent(Double.self, forKey: .contrast) ?? 0
        saturation = try c.decodeIfPresent(Double.self, forKey: .saturation) ?? 0
        brilliance = try c.decodeIfPresent(Double.self, forKey: .brilliance) ?? 0
        vibrance = try c.decodeIfPresent(Double.self, forKey: .vibrance) ?? 0
        dehaze = try c.decodeIfPresent(Double.self, forKey: .dehaze) ?? 0
        highlights = try c.decodeIfPresent(Double.self, forKey: .highlights) ?? 0
        shadows = try c.decodeIfPresent(Double.self, forKey: .shadows) ?? 0
        whites = try c.decodeIfPresent(Double.self, forKey: .whites) ?? 0
        blacks = try c.decodeIfPresent(Double.self, forKey: .blacks) ?? 0
        temperature = try c.decodeIfPresent(Double.self, forKey: .temperature) ?? 0
        tint = try c.decodeIfPresent(Double.self, forKey: .tint) ?? 0
        hue = try c.decodeIfPresent(Double.self, forKey: .hue) ?? 0
        fade = try c.decodeIfPresent(Double.self, forKey: .fade) ?? 0
        sharpness = try c.decodeIfPresent(Double.self, forKey: .sharpness) ?? 0
        clarity = try c.decodeIfPresent(Double.self, forKey: .clarity) ?? 0
        grain = try c.decodeIfPresent(Double.self, forKey: .grain) ?? 0
        vignette = try c.decodeIfPresent(Double.self, forKey: .vignette) ?? 0
        hsl = try c.decodeIfPresent(EditorHSLAdjustments.self, forKey: .hsl) ?? .init()
        curves = try c.decodeIfPresent(EditorToneCurves.self, forKey: .curves) ?? .init()
        wheels = try c.decodeIfPresent(EditorColorWheels.self, forKey: .wheels) ?? .init()
    }
}
