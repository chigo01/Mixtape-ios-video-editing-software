//
//  EditorTimelineSnapshot.swift
//  Mixtape
//

import Foundation

/// Point-in-time editor state used by the undo/redo stack.
struct EditorTimelineSnapshot: Equatable {
    var clips: [EditorClip]
    var openingTransitionKind: EditorTransitionKind
    var openingTransitionDuration: TimeInterval
    var closingTransitionKind: EditorTransitionKind
    var closingTransitionDuration: TimeInterval
    var timelinePosition: TimeInterval
    var selectedClipID: UUID?
    var selectedAudioClipID: UUID?
    var selectedOverlayClipID: UUID?
    var textOverlays: [EditorTextOverlay]
    var audioClips: [EditorAudioClip]
    var overlayClips: [EditorOverlayClip]
}
