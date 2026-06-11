//
//  EditorTimelineSnapshot.swift
//  Mixtape
//

import Foundation

/// Point-in-time editor state used by the undo/redo stack.
struct EditorTimelineSnapshot: Equatable {
    var clips: [EditorClip]
    var timelinePosition: TimeInterval
    var selectedClipID: UUID?
    var textOverlays: [EditorTextOverlay]
}
