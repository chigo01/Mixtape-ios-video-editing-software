//
//  EditorUndoManager.swift
//  Mixtape
//

import Foundation

/// Snapshot-based undo/redo for timeline edits (trim, split, insert, speed).
@MainActor
final class EditorUndoManager {
    private var undoStack: [EditorTimelineSnapshot] = []
    private var redoStack: [EditorTimelineSnapshot] = []
    private let limit = 50

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    func pushUndoState(_ snapshot: EditorTimelineSnapshot) {
        undoStack.append(snapshot)
        redoStack.removeAll()
        if undoStack.count > limit {
            undoStack.removeFirst(undoStack.count - limit)
        }
    }

    func undo(replacing current: EditorTimelineSnapshot) -> EditorTimelineSnapshot? {
        guard let previous = undoStack.popLast() else { return nil }
        redoStack.append(current)
        return previous
    }

    func redo(replacing current: EditorTimelineSnapshot) -> EditorTimelineSnapshot? {
        guard let next = redoStack.popLast() else { return nil }
        undoStack.append(current)
        return next
    }

    func clear() {
        undoStack.removeAll()
        redoStack.removeAll()
    }
}
