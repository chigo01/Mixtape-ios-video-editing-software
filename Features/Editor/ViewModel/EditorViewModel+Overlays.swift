//
//  EditorViewModel+Overlays.swift
//  Mixtape
//

import SwiftUI
import UIKit
import AVFoundation
import Photos

extension EditorViewModel {
    // MARK: Media overlays

    func addOverlayClips(from media: [MediaItem]) {
        let supportedMedia = media.filter {
            $0.asset.mediaType == .video || $0.asset.mediaType == .image
        }
        guard !supportedMedia.isEmpty else { return }

        registerUndoIfNeeded()
        var insertionTime = timelinePosition
        var added: [EditorOverlayClip] = []
        var nextLane = (overlayClips.map(\.laneIndex).max() ?? -1) + 1
        var nextZIndex = (overlayClips.map(\.zIndex).max() ?? -1) + 1
        for item in supportedMedia {
            let clip = EditorOverlayClip(
                asset: item.asset,
                timelineStart: insertionTime,
                laneIndex: nextLane,
                zIndex: nextZIndex
            )
            overlayClips.append(clip)
            added.append(clip)
            insertionTime += clip.duration
            nextLane += 1
            nextZIndex += 1
        }

        if let first = added.first {
            selectedOverlayClipID = first.id
            selectedClipID = nil
            selectedTextOverlayID = nil
            selectedAudioClipID = nil
        }
        invalidateComposition()
        scheduleSave()
        Task { await alignPlaybackToTimeline() }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func sendSelectedOverlayBackward() {
        moveSelectedOverlayLayer(by: -1)
    }

    func bringSelectedOverlayForward() {
        moveSelectedOverlayLayer(by: 1)
    }

    private func moveSelectedOverlayLayer(by offset: Int) {
        guard let selectedOverlayClip,
              let currentIndex = orderedOverlayLanes.firstIndex(where: {
                  $0.laneIndex == selectedOverlayClip.laneIndex
              }) else { return }
        let destinationIndex = currentIndex + offset
        guard orderedOverlayLanes.indices.contains(destinationIndex) else { return }

        let selectedLane = orderedOverlayLanes[currentIndex]
        let adjacentLane = orderedOverlayLanes[destinationIndex]
        registerUndoIfNeeded()
        for index in overlayClips.indices {
            if overlayClips[index].laneIndex == selectedLane.laneIndex {
                overlayClips[index].zIndex = adjacentLane.zIndex
            } else if overlayClips[index].laneIndex == adjacentLane.laneIndex {
                overlayClips[index].zIndex = selectedLane.zIndex
            }
        }
        invalidateComposition()
        scheduleSave()
        Task { await alignPlaybackToTimeline() }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    func deleteSelectedOverlayClip() {
        guard let id = selectedOverlayClipID else { return }
        registerUndoIfNeeded()
        overlayClips.removeAll { $0.id == id }
        selectedTimelineItems.remove(.overlay(id))
        pruneSequenceStructure()
        selectedOverlayClipID = overlayClips.first?.id
        invalidateComposition()
        scheduleSave()
        Task { await alignPlaybackToTimeline() }
    }

    func duplicateSelectedOverlayClip() {
        guard let id = selectedOverlayClipID,
              let index = overlayClips.firstIndex(where: { $0.id == id }) else { return }
        registerUndoIfNeeded()
        let source = overlayClips[index]
        let copy = EditorOverlayClip(
            asset: source.asset,
            originalDuration: source.originalDuration,
            trimStart: source.trimStart,
            trimEnd: source.trimEnd,
            timelineStart: source.timelineEnd,
            laneIndex: source.laneIndex,
            zIndex: source.zIndex,
            speed: source.speed,
            playback: source.playback,
            scale: source.scale,
            xOffset: source.xOffset,
            yOffset: source.yOffset,
            opacity: source.opacity,
            volume: source.volume,
            cropAspect: source.cropAspect,
            reframeMode: source.reframeMode,
            rotationQuarterTurns: source.rotationQuarterTurns,
            straightenDegrees: source.straightenDegrees,
            isFlippedHorizontally: source.isFlippedHorizontally,
            isFlippedVertically: source.isFlippedVertically,
            reframeScale: source.reframeScale,
            reframeXOffset: source.reframeXOffset,
            reframeYOffset: source.reframeYOffset,
            colorAdjustment: source.colorAdjustment,
            effects: source.effects,
            compositing: source.compositing,
            keyframes: source.keyframes,
            motionTracks: source.motionTracks.map { track in
                var copy = track
                copy.id = UUID()
                return copy
            },
            stabilization: source.stabilization,
            attachedClipID: source.attachedClipID,
            attachedTrackID: source.attachedTrackID,
            attachRotation: source.attachRotation,
            attachScale: source.attachScale
        )
        overlayClips.insert(copy, at: index + 1)
        selectedOverlayClipID = copy.id
        timelinePosition = copy.timelineStart
        invalidateComposition()
        scheduleSave()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task { await alignPlaybackToTimeline() }
    }

    /// Replaces an overlay's source while retaining its timing, grade, crop,
    /// transform, layer order, opacity, audio, and keyframe edits.
    func replaceSelectedOverlayClip(with media: MediaItem) {
        guard let id = selectedOverlayClipID,
              let index = overlayClips.firstIndex(where: { $0.id == id }) else { return }
        registerUndoIfNeeded()
        let old = overlayClips[index]
        let rawDuration = media.asset.mediaType == .video
            ? media.asset.duration
            : EditorClip.photoDefaultDuration
        let minimumSpan = EditorClip.minimumSourceSpan(speed: old.speed)
        let sourceSpan = min(old.trimEnd - old.trimStart, rawDuration)
        let start = min(old.trimStart, max(0, rawDuration - minimumSpan))
        let end = min(rawDuration, max(start + minimumSpan, start + sourceSpan))
        overlayClips[index] = EditorOverlayClip(
            id: old.id,
            asset: media.asset,
            originalDuration: rawDuration,
            trimStart: start,
            trimEnd: end,
            timelineStart: old.timelineStart,
            laneIndex: old.laneIndex,
            zIndex: old.zIndex,
            speed: old.speed,
            playback: .forward,
            scale: old.scale,
            xOffset: old.xOffset,
            yOffset: old.yOffset,
            opacity: old.opacity,
            volume: old.volume,
            cropAspect: old.cropAspect,
            reframeMode: old.reframeMode,
            rotationQuarterTurns: old.rotationQuarterTurns,
            straightenDegrees: old.straightenDegrees,
            isFlippedHorizontally: old.isFlippedHorizontally,
            isFlippedVertically: old.isFlippedVertically,
            reframeScale: old.reframeScale,
            reframeXOffset: old.reframeXOffset,
            reframeYOffset: old.reframeYOffset,
            colorAdjustment: old.colorAdjustment,
            effects: old.effects,
            compositing: old.compositing,
            keyframes: old.keyframes,
            attachedClipID: old.attachedClipID,
            attachedTrackID: old.attachedTrackID,
            attachRotation: old.attachRotation,
            attachScale: old.attachScale
        )
        timelinePosition = min(max(old.timelineStart, timelinePosition), overlayClips[index].timelineEnd)
        invalidateComposition()
        scheduleSave()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task { await alignPlaybackToTimeline() }
    }

    func splitSelectedOverlayAtPlayhead() {
        guard let id = selectedOverlayClipID,
              let index = overlayClips.firstIndex(where: { $0.id == id }) else { return }
        let clip = overlayClips[index]
        let minimumTimelineSpan = EditorOverlayClip.minimumSpan / TimeInterval(max(clip.speed, 0.001))
        guard timelinePosition > clip.timelineStart + minimumTimelineSpan,
              timelinePosition < clip.timelineEnd - minimumTimelineSpan else { return }

        guard let parts = clip.split(atTimelineTime: timelinePosition - clip.timelineStart) else {
            return
        }
        registerUndoIfNeeded()
        overlayClips[index] = parts.left
        overlayClips.insert(parts.right, at: index + 1)
        remapSequenceMembershipAfterSplit(
            original: .overlay(parts.left.id),
            right: .overlay(parts.right.id)
        )
        selectedOverlayClipID = parts.right.id
        invalidateComposition()
        scheduleSave()
        Task { await alignPlaybackToTimeline() }
    }

    func setOverlayTrim(clipID: UUID, trimStart: TimeInterval, trimEnd: TimeInterval) {
        if overlayTrimUndoSnapshot == nil {
            overlayTrimUndoSnapshot = currentSnapshot()
        }
        guard let index = overlayClips.firstIndex(where: { $0.id == clipID }) else { return }
        var clip = overlayClips[index]
        let minimumSpan = EditorClip.minimumSourceSpan(speed: clip.speed)

        let requestedStart = clip.playback.isReverse
            ? clip.originalDuration - trimEnd
            : trimStart
        let requestedEnd = clip.playback.isReverse
            ? clip.originalDuration - trimStart
            : trimEnd

        if clip.isPhoto {
            let start = max(0, min(requestedStart, requestedEnd - minimumSpan))
            let end = max(requestedEnd, start + minimumSpan)
            clip.originalDuration = end
            clip.trimStart = start
            clip.trimEnd = end
        } else {
            let start = min(max(0, requestedStart), clip.originalDuration - minimumSpan)
            let end = max(min(clip.originalDuration, requestedEnd), start + minimumSpan)
            clip.trimStart = start
            clip.trimEnd = end
        }

        overlayClips[index] = clip
        invalidateComposition()
    }

    func commitOverlayTrim(clipID: UUID) {
        if let before = overlayTrimUndoSnapshot,
           let index = overlayClips.firstIndex(where: { $0.id == clipID }),
           let baseline = before.overlayClips.first(where: { $0.id == clipID }) {
            let sourceDelta = overlayClips[index].playback.isReverse
                ? baseline.trimEnd - overlayClips[index].trimEnd
                : overlayClips[index].trimStart - baseline.trimStart
            overlayClips[index].timelineStart = max(
                0,
                baseline.timelineStart
                    + sourceDelta / TimeInterval(max(overlayClips[index].speed, 0.001))
            )
        }
        let before = overlayTrimUndoSnapshot
        overlayTrimUndoSnapshot = nil
        commitOverlayUndoSnapshot(before)
        Task { await alignPlaybackToTimeline() }
    }

    func setOverlayTimelineStart(clipID: UUID, timelineStart: TimeInterval) {
        if overlayMoveUndoSnapshot == nil {
            overlayMoveUndoSnapshot = currentSnapshot()
        }
        guard let index = overlayClips.firstIndex(where: { $0.id == clipID }) else { return }
        overlayClips[index].timelineStart = snappedTime(timelineStart, excluding: clipID)
        invalidateComposition()
    }

    func setOverlayLaneIndex(clipID: UUID, laneIndex: Int) {
        if overlayMoveUndoSnapshot == nil {
            overlayMoveUndoSnapshot = currentSnapshot()
        }
        guard let index = overlayClips.firstIndex(where: { $0.id == clipID }) else { return }
        let destination = max(0, laneIndex)
        guard overlayClips[index].laneIndex != destination else { return }
        let destinationZIndex = overlayClips
            .filter { $0.id != clipID && $0.laneIndex == destination }
            .map(\.zIndex)
            .min()
        overlayClips[index].laneIndex = destination
        overlayClips[index].zIndex = destinationZIndex ?? destination
        invalidateComposition()
    }

    func commitOverlayMove() {
        let before = overlayMoveUndoSnapshot
        overlayMoveUndoSnapshot = nil
        commitOverlayUndoSnapshot(before)
        clearSnapGuide()
        Task { await alignPlaybackToTimeline() }
    }

    func beginOverlayPositionDrag(id: UUID) {
        if overlayTransformUndoSnapshot == nil {
            overlayTransformUndoSnapshot = currentSnapshot()
        }
        guard overlayPositionDragOrigin == nil,
              let clip = overlayClips.first(where: { $0.id == id }) else { return }
        overlayPositionDragOrigin = (clip.xOffset, clip.yOffset)
    }

    func updateOverlayPositionDrag(id: UUID, translation: CGSize, canvasSize: CGSize) {
        guard let origin = overlayPositionDragOrigin,
              canvasSize.width > 0,
              canvasSize.height > 0,
              let index = overlayClips.firstIndex(where: { $0.id == id }) else { return }
        overlayClips[index].xOffset = min(
            max(origin.x + translation.width / canvasSize.width, -0.75),
            0.75
        )
        overlayClips[index].yOffset = min(
            max(origin.y + translation.height / canvasSize.height, -0.75),
            0.75
        )
        invalidateComposition()
    }

    func setOverlayScale(id: UUID, scale: CGFloat) {
        if overlayTransformUndoSnapshot == nil {
            overlayTransformUndoSnapshot = currentSnapshot()
        }
        guard let index = overlayClips.firstIndex(where: { $0.id == id }) else { return }
        overlayClips[index].scale = min(max(scale, 0.15), 1.5)
        invalidateComposition()
    }

    func setOverlaySpeed(clipID: UUID, speed: Float) {
        if speedUndoSnapshot == nil {
            speedUndoSnapshot = currentSnapshot()
        }
        guard let index = overlayClips.firstIndex(where: { $0.id == clipID }) else { return }
        overlayClips[index].speed = min(max(speed, 0.25), 3)
        timelinePosition = min(timelinePosition, totalDuration)
        invalidateComposition()
    }

    func commitOverlaySpeed(clipID: UUID, speed: Float) {
        setOverlaySpeed(clipID: clipID, speed: speed)
        finalizeSpeedEditUndo()
        speedUndoSnapshot = currentSnapshot()
        Task { await alignPlaybackToTimeline() }
    }

    func setOverlayVolume(clipID: UUID, volume: Float) {
        if volumeUndoSnapshot == nil {
            volumeUndoSnapshot = currentSnapshot()
        }
        guard let index = overlayClips.firstIndex(where: { $0.id == clipID }) else { return }
        overlayClips[index].volume = min(max(volume, 0), 1)
        invalidateComposition()
    }

    func commitOverlayVolume(clipID: UUID, volume: Float) {
        setOverlayVolume(clipID: clipID, volume: volume)
        finalizeVolumeEditUndo()
        volumeUndoSnapshot = currentSnapshot()
        Task { await alignPlaybackToTimeline() }
    }

    func setOverlayOpacity(id: UUID, opacity: Double) {
        if overlayTransformUndoSnapshot == nil {
            overlayTransformUndoSnapshot = currentSnapshot()
        }
        guard let index = overlayClips.firstIndex(where: { $0.id == id }) else { return }
        overlayClips[index].opacity = min(max(opacity, 0.05), 1)
        invalidateComposition()
    }

    var selectedCompositing: EditorOverlayCompositing? {
        selectedOverlayClip?.compositing ?? selectedClip?.compositing
    }

    func updateSelectedCompositing(
        _ update: (inout EditorOverlayCompositing) -> Void
    ) {
        if overlayCompositingUndoSnapshot == nil {
            overlayCompositingUndoSnapshot = currentSnapshot()
        }
        guard var settings = selectedCompositing else { return }
        update(&settings)
        settings.sanitize()
        if let id = selectedOverlayClipID,
           let index = overlayClips.firstIndex(where: { $0.id == id }) {
            guard settings != overlayClips[index].compositing else { return }
            overlayClips[index].compositing = settings
        } else if let id = selectedClipID,
                  let index = clips.firstIndex(where: { $0.id == id }) {
            guard settings != clips[index].compositing else { return }
            clips[index].compositing = settings
        } else { return }
        invalidateComposition()
        scheduleOverlayCompositingPreviewRefresh()
    }

    func resetSelectedCompositing() {
        updateSelectedCompositing { $0 = .standard }
    }

    func commitOverlayCompositing() {
        finalizeOverlayCompositingUndo()
        Task { await alignPlaybackToTimeline() }
    }

    func finalizeOverlayCompositingUndo() {
        overlayCompositingPreviewTask?.cancel()
        overlayCompositingPreviewTask = nil
        let before = overlayCompositingUndoSnapshot
        overlayCompositingUndoSnapshot = nil
        commitOverlayUndoSnapshot(before)
    }

    private func scheduleOverlayCompositingPreviewRefresh() {
        overlayCompositingPreviewTask?.cancel()
        overlayCompositingPreviewTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(90))
            guard !Task.isCancelled, let self else { return }
            await self.alignPlaybackToTimeline()
        }
    }

    func resetSelectedOverlayTransform() {
        guard let id = selectedOverlayClipID,
              let index = overlayClips.firstIndex(where: { $0.id == id }) else { return }
        registerUndoIfNeeded()
        overlayClips[index].scale = 0.55
        overlayClips[index].xOffset = 0
        overlayClips[index].yOffset = 0
        invalidateComposition()
        scheduleSave()
        Task { await alignPlaybackToTimeline() }
    }

    func commitOverlayTransform() {
        overlayPositionDragOrigin = nil
        finalizeOverlayTransform()
        Task { await alignPlaybackToTimeline() }
    }

    func finalizeOverlayTransform() {
        let before = overlayTransformUndoSnapshot
        overlayTransformUndoSnapshot = nil
        commitOverlayUndoSnapshot(before)
    }

    private func commitOverlayUndoSnapshot(_ before: EditorTimelineSnapshot?) {
        if let before, before != currentSnapshot() {
            undoManager.pushUndoState(before)
            refreshUndoState()
            scheduleSave()
        }
    }
}
