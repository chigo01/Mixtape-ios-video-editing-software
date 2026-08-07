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

    var id: String { rawValue }

    static var mainTools: [EditorTool] {
        allCases.filter { $0 != .duration && $0 != .opacity }
    }

    var title: String {
        switch self {
        case .split: return "SPLIT"
        case .speed: return "SPEED"
        case .duration: return "DURATION"
        case .crop: return "CROP"
        case .volume: return "VOLUME"
        case .filter: return "FILTER"
        case .text: return "TEXT"
        case .overlay: return "OVERLAY"
        case .opacity: return "OPACITY"
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
        }
    }
}
