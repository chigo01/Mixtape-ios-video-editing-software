//
//  EditorViewModel+Transitions.swift
//  Mixtape
//

import SwiftUI
import UIKit
import AVFoundation
import Photos

extension EditorViewModel {
    // MARK: Transitions

    func transition(for target: EditorTransitionTarget) -> (
        kind: EditorTransitionKind,
        duration: TimeInterval
    )? {
        switch target {
        case .opening:
            guard !clips.isEmpty else { return nil }
            return (openingTransitionKind, openingTransitionDuration)
        case .closing:
            guard !clips.isEmpty else { return nil }
            return (closingTransitionKind, closingTransitionDuration)
        case .cut(let index):
            return transition(afterClipAt: index)
        }
    }

    func transition(afterClipAt index: Int) -> (kind: EditorTransitionKind, duration: TimeInterval)? {
        guard index >= 0, index < clips.count - 1 else { return nil }
        return (clips[index].transitionKind, clips[index].transitionDuration)
    }

    func maximumTransitionDuration(for target: EditorTransitionTarget) -> TimeInterval {
        switch target {
        case .opening:
            return min(2, clips.first?.duration ?? 0)
        case .closing:
            return min(2, clips.last?.duration ?? 0)
        case .cut(let index):
            return maximumTransitionDuration(afterClipAt: index)
        }
    }

    func maximumTransitionDuration(afterClipAt index: Int) -> TimeInterval {
        guard index >= 0, index < clips.count - 1 else { return 0 }
        return min(2, min(clips[index].duration, clips[index + 1].duration))
    }

    func beginTransitionEditing() {
        pausePlaybackForEdit()
        transitionUndoSnapshot = currentSnapshot()
    }

    func previewTransition(
        kind: EditorTransitionKind,
        duration: TimeInterval,
        target: EditorTransitionTarget,
        applyToAll: Bool
    ) {
        // Every preview starts from the sheet's opening state. This makes
        // "Apply to all" reversible while the sheet is still open.
        if let baseline = transitionUndoSnapshot {
            clips = baseline.clips
            openingTransitionKind = baseline.openingTransitionKind
            openingTransitionDuration = baseline.openingTransitionDuration
            closingTransitionKind = baseline.closingTransitionKind
            closingTransitionDuration = baseline.closingTransitionDuration
        }

        switch target {
        case .opening:
            guard !clips.isEmpty else { return }
            openingTransitionKind = kind
            openingTransitionDuration = kind == .none
                ? 0
                : min(max(0.1, duration), maximumTransitionDuration(for: .opening))
        case .closing:
            guard !clips.isEmpty else { return }
            closingTransitionKind = kind
            closingTransitionDuration = kind == .none
                ? 0
                : min(max(0.1, duration), maximumTransitionDuration(for: .closing))
        case .cut(let index):
            guard index >= 0, index < clips.count - 1 else { return }
            let indices = applyToAll ? Array(0..<(clips.count - 1)) : [index]
            for boundaryIndex in indices {
                let maxDuration = maximumTransitionDuration(afterClipAt: boundaryIndex)
                clips[boundaryIndex].transitionKind = kind
                clips[boundaryIndex].transitionDuration = kind == .none
                    ? 0
                    : min(max(0.1, duration), maxDuration)
            }
        }

        invalidateComposition()
        playTransitionPreview(target: target)
    }

    func commitTransitionEditing() {
        guard let before = transitionUndoSnapshot else { return }
        if before.clips != clips
            || before.openingTransitionKind != openingTransitionKind
            || before.openingTransitionDuration != openingTransitionDuration
            || before.closingTransitionKind != closingTransitionKind
            || before.closingTransitionDuration != closingTransitionDuration {
            undoManager.pushUndoState(before)
            refreshUndoState()
            scheduleSave()
        }
        transitionUndoSnapshot = nil
    }

    func cancelTransitionEditing() {
        guard let before = transitionUndoSnapshot else { return }
        clips = before.clips
        openingTransitionKind = before.openingTransitionKind
        openingTransitionDuration = before.openingTransitionDuration
        closingTransitionKind = before.closingTransitionKind
        closingTransitionDuration = before.closingTransitionDuration
        transitionUndoSnapshot = nil
        invalidateComposition()
        Task { await alignPlaybackToTimeline() }
    }

    private func playTransitionPreview(target: EditorTransitionTarget) {
        switch target {
        case .opening:
            timelinePosition = 0
        case .closing:
            timelinePosition = max(
                0,
                videoDuration - max(0.35, closingTransitionDuration)
            )
        case .cut(let index):
            let cutTime = timelineOffsetForClipIndex(index + 1)
            let duration = max(0.35, clips[index].transitionDuration)
            timelinePosition = max(0, cutTime - duration)
        }
        isPlaying = true
        Task { await ensureCompositionPlayer() }
    }
}
