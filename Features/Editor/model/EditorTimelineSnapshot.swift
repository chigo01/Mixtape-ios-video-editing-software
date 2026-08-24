//
//  EditorTimelineSnapshot.swift
//  Mixtape
//

import Foundation

enum EditorTimelineItemKind: String, Codable, CaseIterable, Hashable {
    case primaryClip
    case textOverlay
    case audioClip
    case overlayClip
    case sequence
}

struct EditorTimelineItemReference: Codable, Hashable, Identifiable {
    var kind: EditorTimelineItemKind
    var itemID: UUID

    var id: String { "\(kind.rawValue):\(itemID.uuidString)" }

    static func primary(_ id: UUID) -> Self { .init(kind: .primaryClip, itemID: id) }
    static func text(_ id: UUID) -> Self { .init(kind: .textOverlay, itemID: id) }
    static func audio(_ id: UUID) -> Self { .init(kind: .audioClip, itemID: id) }
    static func overlay(_ id: UUID) -> Self { .init(kind: .overlayClip, itemID: id) }
    static func sequence(_ id: UUID) -> Self { .init(kind: .sequence, itemID: id) }
}

enum EditorSequenceKind: String, Codable, CaseIterable, Hashable {
    case group
    case compound
}

/// A structural container whose leaves remain the authoritative flat timeline
/// items consumed by preview and export. Compound sequences may recursively
/// contain child sequences without copying or flattening media edits.
struct EditorSequence: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var title: String
    var kind: EditorSequenceKind
    var members: [EditorTimelineItemReference]
    var parentSequenceID: UUID?
}

struct EditorTimelineMarker: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var time: TimeInterval
}

/// Point-in-time editor state used by the undo/redo stack.
struct EditorTimelineSnapshot: Equatable {
    var clips: [EditorClip]
    var openingTransitionKind: EditorTransitionKind
    var openingTransitionDuration: TimeInterval
    var closingTransitionKind: EditorTransitionKind
    var closingTransitionDuration: TimeInterval
    var timelinePosition: TimeInterval
    var selectedClipID: UUID?
    var selectedTextOverlayID: UUID?
    var selectedAudioClipID: UUID?
    var selectedOverlayClipID: UUID?
    var textOverlays: [EditorTextOverlay]
    var audioClips: [EditorAudioClip]
    var audioTrackSettings: [Int: EditorAudioTrackSettings]
    var masterVolume: Float
    var overlayClips: [EditorOverlayClip]
    var canvasSettings: EditorCanvasSettings
    var exportInPoint: TimeInterval?
    var exportOutPoint: TimeInterval?
    var sequences: [EditorSequence]
    var markers: [EditorTimelineMarker]
    var selectedTimelineItems: Set<EditorTimelineItemReference>
    var selectedSequenceID: UUID?
    var activeSequenceID: UUID?
}
