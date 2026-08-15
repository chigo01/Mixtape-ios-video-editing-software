//
//  EditorTextOverlay.swift
//  Mixtape
//
//  Created by Favour Baruch on 14/05/2026.
//

import SwiftUI

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
        keyframes: EditorKeyframeTracks = .empty
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
    }

    var duration: TimeInterval { max(0, endTime - startTime) }

    /// The resolved SwiftUI Font for rendering on the preview.
    func resolvedFont() -> Font {
        let baseFont: Font
        if fontFamily == .system {
            baseFont = .system(size: fontSize, weight: .regular)
        } else {
            baseFont = .custom(fontFamily.rawValue, size: fontSize)
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
}
