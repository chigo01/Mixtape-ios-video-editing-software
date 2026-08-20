//
//  EditorOverlayCompositing.swift
//  Mixtape
//
//  Non-destructive overlay compositing authored once and consumed by both
//  editor preview and export.
//

import Foundation

enum EditorOverlayBlendMode: String, Codable, CaseIterable, Hashable, Identifiable {
    case normal
    case multiply
    case screen
    case overlay
    case softLight
    case hardLight
    case darken
    case lighten
    case colorDodge
    case colorBurn
    case difference
    case exclusion
    case hue
    case saturation
    case color
    case luminosity

    var id: String { rawValue }

    var title: String {
        switch self {
        case .normal: return "Normal"
        case .softLight: return "Soft Light"
        case .hardLight: return "Hard Light"
        case .colorDodge: return "Color Dodge"
        case .colorBurn: return "Color Burn"
        default: return rawValue.capitalized
        }
    }
}

enum EditorOverlayMaskShape: String, Codable, CaseIterable, Hashable, Identifiable {
    case none
    case ellipse
    case rectangle
    case linear
    case polygon

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var systemImage: String {
        switch self {
        case .none: return "circle.slash"
        case .ellipse: return "circle"
        case .rectangle: return "rectangle"
        case .linear: return "square.split.diagonal.2x2"
        case .polygon: return "pentagon"
        }
    }
}

struct EditorOverlayMaskPoint: Codable, Hashable, Identifiable {
    var id = UUID()
    var x: Double
    var y: Double
}

struct EditorOverlayMask: Codable, Hashable {
    var shape: EditorOverlayMaskShape = .none
    var centerX: Double = 0.5
    var centerY: Double = 0.5
    var width: Double = 0.8
    var height: Double = 0.8
    /// Normalized half-turns. `0.5` equals 90 degrees.
    var rotation: Double = 0
    var feather: Double = 0.12
    var opacity: Double = 1
    var isInverted = false
    var expansion: Double = 0
    var points: [EditorOverlayMaskPoint] = [
        .init(x: 0.28, y: 0.30),
        .init(x: 0.72, y: 0.30),
        .init(x: 0.78, y: 0.68),
        .init(x: 0.50, y: 0.80),
        .init(x: 0.22, y: 0.68)
    ]

    var isEnabled: Bool { shape != .none }

    private enum CodingKeys: String, CodingKey {
        case shape, centerX, centerY, width, height, rotation, feather
        case opacity, isInverted, expansion, points
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        shape = try c.decodeIfPresent(EditorOverlayMaskShape.self, forKey: .shape) ?? .none
        centerX = try c.decodeIfPresent(Double.self, forKey: .centerX) ?? 0.5
        centerY = try c.decodeIfPresent(Double.self, forKey: .centerY) ?? 0.5
        width = try c.decodeIfPresent(Double.self, forKey: .width) ?? 0.8
        height = try c.decodeIfPresent(Double.self, forKey: .height) ?? 0.8
        rotation = try c.decodeIfPresent(Double.self, forKey: .rotation) ?? 0
        feather = try c.decodeIfPresent(Double.self, forKey: .feather) ?? 0.12
        opacity = try c.decodeIfPresent(Double.self, forKey: .opacity) ?? 1
        isInverted = try c.decodeIfPresent(Bool.self, forKey: .isInverted) ?? false
        expansion = try c.decodeIfPresent(Double.self, forKey: .expansion) ?? 0
        points = try c.decodeIfPresent([EditorOverlayMaskPoint].self, forKey: .points) ?? Self().points
        sanitize()
    }

    mutating func sanitize() {
        centerX = min(max(centerX, 0), 1)
        centerY = min(max(centerY, 0), 1)
        width = min(max(width, 0.02), 1.5)
        height = min(max(height, 0.02), 1.5)
        rotation = min(max(rotation, -1), 1)
        feather = min(max(feather, 0), 1)
        opacity = min(max(opacity, 0), 1)
        expansion = min(max(expansion, -1), 1)
        points = Array(points.prefix(24)).map {
            var point = $0
            point.x = min(max(point.x, 0), 1)
            point.y = min(max(point.y, 0), 1)
            return point
        }
    }
}

struct EditorLumaKeySettings: Codable, Hashable {
    var isEnabled = false
    var threshold: Double = 0.5
    var softness: Double = 0.12
    var isInverted = false

    mutating func sanitize() {
        threshold = min(max(threshold, 0), 1)
        softness = min(max(softness, 0.01), 0.5)
    }
}

struct EditorLayerShadowSettings: Codable, Hashable {
    var isEnabled = false
    var opacity: Double = 0.45
    var blur: Double = 0.18
    var distance: Double = 0.04
    var angle: Double = 0.125

    mutating func sanitize() {
        opacity = min(max(opacity, 0), 1)
        blur = min(max(blur, 0), 1)
        distance = min(max(distance, 0), 0.35)
        angle = min(max(angle, -1), 1)
    }
}

struct EditorChromaKeySettings: Codable, Hashable {
    var isEnabled = false
    var red: Double = 0
    var green: Double = 1
    var blue: Double = 0
    /// Chroma distance removed around the sampled key color.
    var threshold: Double = 0.22
    /// Width of the partially transparent edge around the key.
    var softness: Double = 0.10
    /// Neutralizes reflected key color without destroying subject luminance.
    var spillSuppression: Double = 0.45
    var edgeDesaturation: Double = 0.18

    mutating func sanitize() {
        red = min(max(red, 0), 1)
        green = min(max(green, 0), 1)
        blue = min(max(blue, 0), 1)
        threshold = min(max(threshold, 0.01), 0.75)
        softness = min(max(softness, 0.001), 0.5)
        spillSuppression = min(max(spillSuppression, 0), 1)
        edgeDesaturation = min(max(edgeDesaturation, 0), 1)
    }
}

struct EditorOverlayCompositing: Codable, Hashable {
    var blendMode: EditorOverlayBlendMode = .normal
    var mask = EditorOverlayMask()
    var chromaKey = EditorChromaKeySettings()
    var lumaKey = EditorLumaKeySettings()
    var shadow = EditorLayerShadowSettings()

    static let standard = EditorOverlayCompositing()

    var requiresGPUCompositor: Bool {
        blendMode != .normal || mask.isEnabled || chromaKey.isEnabled
            || lumaKey.isEnabled || shadow.isEnabled
    }

    mutating func sanitize() {
        mask.sanitize()
        chromaKey.sanitize()
        lumaKey.sanitize()
        shadow.sanitize()
    }

    private enum CodingKeys: String, CodingKey {
        case blendMode, mask, chromaKey, lumaKey, shadow
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        blendMode = try c.decodeIfPresent(EditorOverlayBlendMode.self, forKey: .blendMode) ?? .normal
        mask = try c.decodeIfPresent(EditorOverlayMask.self, forKey: .mask) ?? .init()
        chromaKey = try c.decodeIfPresent(EditorChromaKeySettings.self, forKey: .chromaKey) ?? .init()
        lumaKey = try c.decodeIfPresent(EditorLumaKeySettings.self, forKey: .lumaKey) ?? .init()
        shadow = try c.decodeIfPresent(EditorLayerShadowSettings.self, forKey: .shadow) ?? .init()
        sanitize()
    }
}
