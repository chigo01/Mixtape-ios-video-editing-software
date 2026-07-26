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
    case volume
    case filter
    case text

    var id: String { rawValue }

    static var mainTools: [EditorTool] {
        allCases.filter { $0 != .duration }
    }

    var title: String {
        switch self {
        case .split: return "SPLIT"
        case .speed: return "SPEED"
        case .duration: return "DURATION"
        case .volume: return "VOLUME"
        case .filter: return "FILTER"
        case .text: return "TEXT"
        }
    }

    var systemImage: String {
        switch self {
        case .split: return "scissors"
        case .speed: return "speedometer"
        case .duration: return "timer"
        case .volume: return "speaker.wave.2.fill"
        case .filter: return "slider.horizontal.3"
        case .text: return "textformat"
        }
    }
}
