//
//  EditorViewModel+ClipVolume.swift
//  Mixtape
//

import SwiftUI
import UIKit
import AVFoundation
import Photos

extension EditorViewModel {
    // MARK: Volume

    func setVolume(clipID: UUID, volume: Float) {
        guard let idx = clips.firstIndex(where: { $0.id == clipID }) else { return }
        if volumeUndoSnapshot == nil {
            volumeUndoSnapshot = currentSnapshot()
        }
        var clip = clips[idx]
        clip.volume = min(max(volume, 0), 1.0)
        clips[idx] = clip
        invalidateComposition()
    }

    func commitVolume(clipID: UUID, volume: Float) {
        setVolume(clipID: clipID, volume: volume)
        finalizeVolumeEditUndo()
        volumeUndoSnapshot = currentSnapshot()
        Task { await alignPlaybackToTimeline() }
    }

    func finalizeVolumeEditUndo() {
        guard let before = volumeUndoSnapshot else { return }
        if before != currentSnapshot() {
            undoManager.pushUndoState(before)
            refreshUndoState()
            scheduleSave()
        }
        volumeUndoSnapshot = nil
    }
}
