//
//  EditorViewModel+Reframe.swift
//  Mixtape
//

import SwiftUI
import UIKit
import AVFoundation
import Photos

extension EditorViewModel {
    // MARK: Crop and reframe

    func setSelectedClipCropAspect(_ aspect: EditorCropAspect) {
        updateSelectedClipReframe { $0.cropAspect = aspect }
    }

    func setSelectedClipReframeMode(_ mode: EditorReframeMode) {
        updateSelectedClipReframe { $0.reframeMode = mode }
    }

    func rotateSelectedClipClockwise() {
        updateSelectedClipReframe {
            $0.rotationQuarterTurns = ($0.rotationQuarterTurns + 1) % 4
        }
    }

    func toggleSelectedClipHorizontalFlip() {
        updateSelectedClipReframe { $0.isFlippedHorizontally.toggle() }
    }

    func toggleSelectedClipVerticalFlip() {
        updateSelectedClipReframe { $0.isFlippedVertically.toggle() }
    }

    func setSelectedClipStraighten(_ degrees: Double) {
        updateSelectedClipReframe { $0.straightenDegrees = min(max(degrees, -45), 45) }
    }

    func setSelectedClipReframeScale(_ scale: CGFloat) {
        updateSelectedClipReframe { $0.reframeScale = min(max(scale, 0.5), 4) }
    }

    func centerSelectedClipReframe() {
        updateSelectedClipReframe {
            $0.straightenDegrees = 0
            $0.reframeScale = 1
            $0.reframeXOffset = 0
            $0.reframeYOffset = 0
        }
    }

    func beginSelectedClipReframeDrag() {
        beginReframeEditIfNeeded()
        guard reframePositionDragOrigin == nil, let clip = selectedReframeClip else { return }
        reframePositionDragOrigin = (clip.reframeXOffset, clip.reframeYOffset)
    }

    func updateSelectedClipReframeDrag(translation: CGSize, canvasSize: CGSize) {
        guard let origin = reframePositionDragOrigin,
              canvasSize.width > 0,
              canvasSize.height > 0 else { return }
        let x = min(max(origin.x + translation.width / canvasSize.width, -1), 1)
        let y = min(max(origin.y + translation.height / canvasSize.height, -1), 1)
        if let id = selectedOverlayClipID,
           let index = overlayClips.firstIndex(where: { $0.id == id }) {
            overlayClips[index].reframeXOffset = x
            overlayClips[index].reframeYOffset = y
        } else if let id = selectedClipID,
                  let index = clips.firstIndex(where: { $0.id == id }) {
            clips[index].reframeXOffset = x
            clips[index].reframeYOffset = y
        } else {
            return
        }
        invalidateComposition()
    }

    func resetSelectedClipReframe() {
        updateSelectedClipReframe {
            $0.cropAspect = .original
            $0.reframeMode = .fit
            $0.rotationQuarterTurns = 0
            $0.straightenDegrees = 0
            $0.isFlippedHorizontally = false
            $0.isFlippedVertically = false
            $0.reframeScale = 1
            $0.reframeXOffset = 0
            $0.reframeYOffset = 0
        }
    }

    func commitSelectedClipReframe() {
        reframePositionDragOrigin = nil
        finalizeReframeEditUndo()
        Task { await alignPlaybackToTimeline() }
    }

    private func updateSelectedClipReframe(_ update: (inout EditorClip) -> Void) {
        beginReframeEditIfNeeded()
        if let id = selectedOverlayClipID,
           let index = overlayClips.firstIndex(where: { $0.id == id }) {
            var proxy = overlayClips[index].thumbnailClip
            update(&proxy)
            overlayClips[index].cropAspect = proxy.cropAspect
            overlayClips[index].reframeMode = proxy.reframeMode
            overlayClips[index].rotationQuarterTurns = proxy.rotationQuarterTurns
            overlayClips[index].straightenDegrees = proxy.straightenDegrees
            overlayClips[index].isFlippedHorizontally = proxy.isFlippedHorizontally
            overlayClips[index].isFlippedVertically = proxy.isFlippedVertically
            overlayClips[index].reframeScale = proxy.reframeScale
            overlayClips[index].reframeXOffset = proxy.reframeXOffset
            overlayClips[index].reframeYOffset = proxy.reframeYOffset
        } else if let id = selectedClipID,
                  let index = clips.firstIndex(where: { $0.id == id }) {
            update(&clips[index])
        } else {
            return
        }
        invalidateComposition()
    }

    private func beginReframeEditIfNeeded() {
        if reframeUndoSnapshot == nil {
            reframeUndoSnapshot = currentSnapshot()
        }
    }

    func finalizeReframeEditUndo() {
        guard let before = reframeUndoSnapshot else { return }
        reframeUndoSnapshot = nil
        reframePositionDragOrigin = nil
        if before != currentSnapshot() {
            undoManager.pushUndoState(before)
            refreshUndoState()
            scheduleSave()
        }
    }
}
