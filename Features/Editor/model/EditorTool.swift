//
//  EditorTool.swift
//  Mixtape
//
//  Created by Favour Baruch on 14/05/2026.
//

import Foundation

enum EditorTool: String, CaseIterable, Identifiable {
    case split
    case speed
    case duration
    case crop
    case volume
    case filter
    case text
    case overlay
    case opacity
    case canvas
    case keyframe

    var id: String { rawValue }

    static var mainTools: [EditorTool] {
        allCases.filter {
            $0 != .duration && $0 != .opacity && $0 != .filter && $0 != .keyframe
        }
    }

    var title: String {
        switch self {
        case .split: return "SPLIT"
        case .speed: return "SPEED"
        case .duration: return "DURATION"
        case .crop: return "CROP"
        case .volume: return "VOLUME"
        case .filter: return "COLOR"
        case .text: return "TEXT"
        case .overlay: return "OVERLAY"
        case .opacity: return "OPACITY"
        case .canvas: return "CANVAS"
        case .keyframe: return "KEYFRAME"
        }
    }

    var systemImage: String {
        switch self {
        case .split: return "scissors"
        case .speed: return "speedometer"
        case .duration: return "timer"
        case .crop: return "crop.rotate"
        case .volume: return "speaker.wave.2.fill"
        case .filter: return "slider.horizontal.3"
        case .text: return "textformat"
        case .overlay: return "rectangle.on.rectangle"
        case .opacity: return "circle.lefthalf.filled"
        case .canvas: return "rectangle.ratio.16.to.9"
        case .keyframe: return "diamond.fill"
        }
    }
}
