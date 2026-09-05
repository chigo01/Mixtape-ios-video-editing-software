//
//  EditorTool.swift
//  Mixtape
//
//  Created by Favour Baruch on 14/05/2026.
//

import Foundation

enum EditorTool: String, CaseIterable, Identifiable {
    case split
    case precision
    case reverse
    case freeze
    case sequence
    case speed
    case duration
    case crop
    case volume
    case filter
    case effects
    case text
    case captions
    case overlay
    case opacity
    case compositing
    case canvas
    case keyframe
    case track
    case stabilize
    case mix
    case audioEffect

    var id: String { rawValue }

    static var mainTools: [EditorTool] {
        allCases.filter {
            $0 != .duration && $0 != .precision && $0 != .reverse && $0 != .freeze
                && $0 != .opacity && $0 != .compositing
                && $0 != .filter && $0 != .keyframe && $0 != .track && $0 != .stabilize
                && $0 != .audioEffect
        }
    }

    var title: String {
        switch self {
        case .split: return "SPLIT"
        case .precision: return "PRECISION"
        case .reverse: return "REVERSE"
        case .freeze: return "FREEZE"
        case .sequence: return "SELECT"
        case .speed: return "SPEED"
        case .duration: return "DURATION"
        case .crop: return "CROP"
        case .volume: return "VOLUME"
        case .filter: return "COLOR"
        case .effects: return "EFFECTS"
        case .text: return "TEXT"
        case .captions: return "CAPTIONS"
        case .overlay: return "OVERLAY"
        case .opacity: return "OPACITY"
        case .compositing: return "COMPOSITE"
        case .canvas: return "CANVAS"
        case .keyframe: return "KEYFRAME"
        case .track: return "TRACK"
        case .stabilize: return "STABILIZE"
        case .mix: return "MIX"
        case .audioEffect: return "EFFECT"
        }
    }

    var systemImage: String {
        switch self {
        case .split: return "scissors"
        case .precision: return "arrow.left.and.right"
        case .reverse: return "backward.end.alt.fill"
        case .freeze: return "snowflake"
        case .sequence: return "checkmark.circle"
        case .speed: return "speedometer"
        case .duration: return "timer"
        case .crop: return "crop.rotate"
        case .volume: return "speaker.wave.2.fill"
        case .filter: return "slider.horizontal.3"
        case .effects: return "wand.and.stars"
        case .text: return "textformat"
        case .captions: return "captions.bubble.fill"
        case .overlay: return "rectangle.on.rectangle"
        case .opacity: return "circle.lefthalf.filled"
        case .compositing: return "square.3.layers.3d"
        case .canvas: return "rectangle.ratio.16.to.9"
        case .keyframe: return "diamond.fill"
        case .track: return "viewfinder"
        case .stabilize: return "gyroscope"
        case .mix: return "slider.vertical.3"
        case .audioEffect: return "waveform.badge.magnifyingglass"
        }
    }
}
