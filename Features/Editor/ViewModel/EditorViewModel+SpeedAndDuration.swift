//
//  EditorViewModel+SpeedAndDuration.swift
//  Mixtape
//

import SwiftUI
import UIKit
import AVFoundation
import Photos

extension EditorViewModel {
    func finalizeSpeedEditUndo() {
        guard let before = speedUndoSnapshot else { return }
        if before != currentSnapshot() {
            undoManager.pushUndoState(before)
            refreshUndoState()
            scheduleSave()
        }
        speedUndoSnapshot = nil
    }

    // MARK: Speed

    func setSpeed(clipID: UUID, speed: Float) {
        guard let idx = clips.firstIndex(where: { $0.id == clipID }) else { return }
        if speedUndoSnapshot == nil { speedUndoSnapshot = currentSnapshot() }
        var clip = clips[idx]
        clip.speed = min(max(speed, 0.25), 3.0)
        clip.speedRamp = nil
        clips[idx] = clip
        timelinePosition = min(timelinePosition, totalDuration)
        invalidateComposition()
    }

    func commitSpeed(clipID: UUID, speed: Float) {
        setSpeed(clipID: clipID, speed: speed)
        finalizeSpeedEditUndo()
        speedUndoSnapshot = currentSnapshot()
        Task { await alignPlaybackToTimeline() }
    }

    func beginSpeedRampInteraction() {
        pausePlaybackForEdit()
    }

    func scrubSpeedRamp(to progress: Double, clipID: UUID) {
        guard let index = clips.firstIndex(where: { $0.id == clipID }) else { return }
        pausePlaybackForEdit()
        let clip = clips[index]
        let offset = min(max(progress, 0), 1) * max(0, clip.trimEnd - clip.trimStart)
        timelinePosition = min(totalDuration, timelineOffsetForClipIndex(index) + clip.timelineTime(forSourceOffset: offset))
        // Seek the current composition during the gesture; rebuild edited curves on release.
        if compositionFingerprint != nil {
            player?.seek(
                to: CMTime(seconds: timelinePosition, preferredTimescale: 600),
                toleranceBefore: .zero,
                toleranceAfter: .zero
            )
        }
    }

    func applySpeedRampPreset(_ preset: EditorSpeedRampPreset, clipID: UUID) {
        updateSpeedRamp(clipID: clipID) { _ in preset.ramp }
        commitSpeedRampEdit()
    }

    func enableSpeedRamp(clipID: UUID) {
        updateSpeedRamp(clipID: clipID) { current in
            current ?? EditorSpeedRamp(
                points: [
                    EditorSpeedRampPoint(position: 0, speed: 1),
                    EditorSpeedRampPoint(position: 0.5, speed: 1),
                    EditorSpeedRampPoint(position: 1, speed: 1)
                ],
                interpolation: .smooth
            )
        }
        commitSpeedRampEdit()
    }

    func setSpeedRampInterpolation(
        _ interpolation: EditorSpeedRampInterpolation,
        clipID: UUID
    ) {
        updateSpeedRamp(clipID: clipID) { current in
            EditorSpeedRamp(
                points: current?.points ?? EditorSpeedRampPreset.montage.ramp.points,
                interpolation: interpolation
            )
        }
        commitSpeedRampEdit()
    }

    func setSpeedRampPoint(
        clipID: UUID,
        index: Int,
        position: Double,
        speed: Float
    ) {
        updateSpeedRamp(clipID: clipID) { current in
            var ramp = current ?? EditorSpeedRampPreset.montage.ramp
            ramp.movePoint(at: index, position: position, speed: speed)
            return EditorSpeedRamp(points: ramp.points, interpolation: ramp.interpolation)
        }
    }

    func addSpeedRampPoint(clipID: UUID, position: Double) {
        updateSpeedRamp(clipID: clipID) { current in
            var ramp = current ?? EditorSpeedRamp(
                points: [
                    EditorSpeedRampPoint(position: 0, speed: 1),
                    EditorSpeedRampPoint(position: 1, speed: 1)
                ]
            )
            let p = min(max(position, 0.04), 0.96)
            guard !ramp.points.contains(where: { abs($0.position - p) < 0.025 }) else {
                return ramp
            }
            ramp.points.append(
                EditorSpeedRampPoint(position: p, speed: ramp.speed(atSourceProgress: p))
            )
            return EditorSpeedRamp(points: ramp.points, interpolation: ramp.interpolation)
        }
        commitSpeedRampEdit()
    }

    func removeSpeedRampPoint(clipID: UUID, index: Int) {
        updateSpeedRamp(clipID: clipID) { current in
            guard var ramp = current,
                  index > 0,
                  index < ramp.points.count - 1,
                  ramp.points.count > 2 else { return current }
            ramp.points.remove(at: index)
            return EditorSpeedRamp(points: ramp.points, interpolation: ramp.interpolation)
        }
        commitSpeedRampEdit()
    }

    func clearSpeedRamp(clipID: UUID) {
        guard let index = clips.firstIndex(where: { $0.id == clipID }) else { return }
        if speedUndoSnapshot == nil { speedUndoSnapshot = currentSnapshot() }
        clips[index].speedRamp = nil
        clips[index].speed = 1
        timelinePosition = min(timelinePosition, totalDuration)
        invalidateComposition()
        commitSpeedRampEdit()
    }

    func commitSpeedRampEdit() {
        finalizeSpeedEditUndo()
        speedUndoSnapshot = currentSnapshot()
        Task { await alignPlaybackToTimeline() }
    }

    private func updateSpeedRamp(
        clipID: UUID,
        transform: (EditorSpeedRamp?) -> EditorSpeedRamp?
    ) {
        guard let index = clips.firstIndex(where: { $0.id == clipID }), clips[index].isVideo else {
            return
        }
        if speedUndoSnapshot == nil { speedUndoSnapshot = currentSnapshot() }
        let oldClip = clips[index]
        let start = timelineOffsetForClipIndex(index)
        let localTime = timelinePosition - start
        let sourceOffset = oldClip.sourceTime(forExportedLocal: localTime) - oldClip.trimStart
        let updatedRamp = transform(oldClip.speedRamp)
        guard updatedRamp != oldClip.speedRamp else { return }
        pausePlaybackForEdit()
        clips[index].speedRamp = updatedRamp
        if localTime >= 0, localTime <= oldClip.duration {
            timelinePosition = start + clips[index].timelineTime(forSourceOffset: sourceOffset)
        }
        timelinePosition = min(timelinePosition, totalDuration)
        invalidateComposition()
    }

    // MARK: Photo duration

    func setPhotoDuration(clipID: UUID, duration: TimeInterval) {
        if photoDurationUndoSnapshot == nil {
            photoDurationUndoSnapshot = currentSnapshot()
        }

        let clampedDuration = min(
            max(duration, EditorClip.photoMinimumDuration),
            EditorClip.photoMaximumDuration
        )
        if let index = overlayClips.firstIndex(where: { $0.id == clipID }),
           overlayClips[index].isPhoto {
            let sourceSpan = clampedDuration * TimeInterval(max(overlayClips[index].speed, 0.001))
            overlayClips[index].originalDuration = sourceSpan
            overlayClips[index].trimStart = 0
            overlayClips[index].trimEnd = sourceSpan
        } else if let index = clips.firstIndex(where: { $0.id == clipID }),
                  clips[index].isPhoto {
            var clip = clips[index]
            let sourceSpan = clampedDuration * TimeInterval(max(clip.speed, 0.001))
            clip.originalDuration = sourceSpan
            clip.trimStart = 0
            clip.trimEnd = sourceSpan
            clips[index] = clip
        } else {
            return
        }

        timelinePosition = min(timelinePosition, totalDuration)
        invalidateComposition()
    }

    func commitPhotoDuration(clipID: UUID, duration: TimeInterval) {
        setPhotoDuration(clipID: clipID, duration: duration)
        finalizePhotoDurationEditUndo()
        photoDurationUndoSnapshot = currentSnapshot()
        Task { await alignPlaybackToTimeline() }
    }

    func finalizePhotoDurationEditUndo() {
        guard let before = photoDurationUndoSnapshot else { return }
        if before != currentSnapshot() {
            undoManager.pushUndoState(before)
            refreshUndoState()
            scheduleSave()
        }
        photoDurationUndoSnapshot = nil
    }
}
