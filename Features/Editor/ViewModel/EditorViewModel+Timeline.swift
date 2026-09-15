//
//  EditorViewModel+Timeline.swift
//  Mixtape
//

import SwiftUI
import UIKit
import AVFoundation
import Photos

extension EditorViewModel {
    // MARK: Derived

    var totalDuration: TimeInterval {
        let video = clips.reduce(0) { $0 + $1.duration }
        let audioEnd = audioClips.map(\.timelineEnd).max() ?? 0
        let textEnd = textOverlays.map(\.endTime).max() ?? 0
        let graphicEnd = graphicOverlays.map(\.endTime).max() ?? 0
        let overlayEnd = overlayClips.map(\.timelineEnd).max() ?? 0
        return max(video, audioEnd, textEnd, graphicEnd, overlayEnd)
    }

    var videoDuration: TimeInterval {
        clips.reduce(0) { $0 + $1.duration }
    }

    var exportRange: ClosedRange<TimeInterval>? {
        guard let start = exportInPoint, let end = exportOutPoint, end > start else { return nil }
        return min(max(0, start), totalDuration)...min(max(0, end), totalDuration)
    }

    var exportDuration: TimeInterval {
        exportRange.map { max(0, $0.upperBound - $0.lowerBound) } ?? totalDuration
    }

    func setExportInPoint() {
        registerUndoIfNeeded()
        exportInPoint = min(timelinePosition, (exportOutPoint ?? totalDuration) - 0.1)
        normalizeExportRange()
        scheduleSave()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    func setExportOutPoint() {
        registerUndoIfNeeded()
        exportOutPoint = max(timelinePosition, (exportInPoint ?? 0) + 0.1)
        normalizeExportRange()
        scheduleSave()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    func clearExportRange() {
        guard exportInPoint != nil || exportOutPoint != nil else { return }
        registerUndoIfNeeded()
        exportInPoint = nil
        exportOutPoint = nil
        scheduleSave()
    }

    func updateCanvasSettings(_ settings: EditorCanvasSettings) {
        guard settings != canvasSettings else { return }
        registerUndoIfNeeded()
        canvasSettings = settings
        invalidateComposition()
        scheduleSave()
        Task { await alignPlaybackToTimeline() }
    }

    func normalizeExportRange() {
        exportInPoint = exportInPoint.map { min(max(0, $0), totalDuration) }
        exportOutPoint = exportOutPoint.map { min(max(0, $0), totalDuration) }
        if let start = exportInPoint, let end = exportOutPoint, end <= start {
            exportOutPoint = min(totalDuration, start + 0.1)
        }
    }

    var selectedClip: EditorClip? {
        guard let id = selectedClipID else { return nil }
        return clips.first { $0.id == id }
    }

    /// Current playhead expressed in the selected clip's normalized source time.
    /// The curve editor uses source progress because ramp control points are
    /// attached to media content rather than a duration that changes as speeds move.
    var selectedClipSourceProgress: Double? {
        guard let id = selectedClipID,
              let index = clips.firstIndex(where: { $0.id == id }) else { return nil }
        let clip = clips[index]
        let localTimeline = min(
            max(0, timelinePosition - timelineOffsetForClipIndex(index)),
            clip.duration
        )
        let sourceSpan = max(clip.trimEnd - clip.trimStart, 0)
        guard sourceSpan > 0 else { return 0 }
        return min(
            max((clip.sourceTime(forExportedLocal: localTimeline) - clip.trimStart) / sourceSpan, 0),
            1
        )
    }

    var canDeleteSelectedClip: Bool {
        selectedClipID != nil && clips.count > 1
    }

    var selectedTextOverlay: EditorTextOverlay? {
        guard let id = selectedTextOverlayID else { return nil }
        return textOverlays.first { $0.id == id }
    }

    var selectedGraphicOverlay: EditorGraphicOverlay? {
        guard let id = selectedGraphicOverlayID else { return nil }
        return graphicOverlays.first { $0.id == id }
    }

    var captionOverlays: [EditorTextOverlay] {
        textOverlays.filter(\.isCaption).sorted { $0.startTime < $1.startTime }
    }

    var selectedAudioClip: EditorAudioClip? {
        guard let id = selectedAudioClipID else { return nil }
        return audioClips.first { $0.id == id }
    }

    var sortedAudioClips: [EditorAudioClip] {
        audioClips.sorted { $0.timelineStart < $1.timelineStart }
    }

    var selectedOverlayClip: EditorOverlayClip? {
        guard let id = selectedOverlayClipID else { return nil }
        return overlayClips.first { $0.id == id }
    }

    var selectedVideoPlayback: EditorClipPlayback? {
        selectedOverlayClip?.playback ?? selectedClip?.playback
    }

    var selectedReframeClip: EditorClip? {
        selectedOverlayClip?.thumbnailClip ?? selectedClip
    }

    var selectedDurationClip: EditorClip? {
        selectedOverlayClip?.thumbnailClip ?? selectedClip
    }

    var sortedOverlayClips: [EditorOverlayClip] {
        overlayClips.sorted {
            if $0.timelineStart == $1.timelineStart { return $0.zIndex < $1.zIndex }
            return $0.timelineStart < $1.timelineStart
        }
    }

    var orderedOverlayLanes: [(laneIndex: Int, zIndex: Int)] {
        Dictionary(grouping: overlayClips, by: \.laneIndex)
            .map { laneIndex, clips in
                (laneIndex: laneIndex, zIndex: clips.map(\.zIndex).min() ?? laneIndex)
            }
            .sorted {
                if $0.zIndex == $1.zIndex { return $0.laneIndex < $1.laneIndex }
                return $0.zIndex < $1.zIndex
            }
    }

    var canSendSelectedOverlayBackward: Bool {
        guard let selectedOverlayClip else { return false }
        return orderedOverlayLanes.first?.laneIndex != selectedOverlayClip.laneIndex
    }

    var canBringSelectedOverlayForward: Bool {
        guard let selectedOverlayClip else { return false }
        return orderedOverlayLanes.last?.laneIndex != selectedOverlayClip.laneIndex
    }

    /// Clip currently under the global playhead (what the preview should show).
    var playbackInfo: (clip: EditorClip, index: Int, localTime: TimeInterval)? {
        clipAndLocalTime(at: timelinePosition)
    }

    var playbackClipID: UUID? { playbackInfo?.clip.id }

    var selectedColorMask: EditorColorMask? {
        guard let selectedColorMaskID else { return nil }
        return selectedColorAdjustment?.masks.first { $0.id == selectedColorMaskID }
    }

    var selectedColorAdjustment: EditorColorAdjustment? {
        if let id = selectedAdjustmentLayerID {
            return adjustmentLayers.first(where: { $0.id == id })?.colorAdjustment
        }
        return selectedOverlayClip?.colorAdjustment ?? selectedClip?.colorAdjustment
    }

    var selectedColorAsset: PHAsset? {
        guard selectedAdjustmentLayerID == nil else { return nil }
        return selectedOverlayClip?.asset ?? selectedClip?.asset
    }

    var selectedColorTargetID: UUID? {
        selectedAdjustmentLayerID ?? selectedOverlayClipID ?? selectedClipID
    }

    /// `MM:SS:CC` (hundredths) — HUD uses global timeline.
    var currentTimeString: String {
        formatPlaybackTime(timelinePosition)
    }

    func formatPlaybackTime(_ t: TimeInterval) -> String {
        let safe = max(0, t)
        let total = Int((safe * 100).rounded(.down))
        let minutes = total / 6000
        let seconds = (total / 100) % 60
        let hundredths = total % 100
        return String(format: "%02d:%02d:%02d", minutes, seconds, hundredths)
    }

    func timelineOffsetForClipIndex(_ index: Int) -> TimeInterval {
        guard index > 0 else { return 0 }
        return clips.prefix(index).reduce(0) { $0 + $1.duration }
    }

    func clipAndLocalTime(at timelineT: TimeInterval) -> (clip: EditorClip, index: Int, localTime: TimeInterval)? {
        guard !clips.isEmpty else { return nil }
        // Map playhead to a video clip; past the video tail, hold the last frame.
        let upperBound = videoDuration > 0 ? videoDuration : totalDuration
        let clamped = min(max(0, timelineT), upperBound)
        var acc: TimeInterval = 0
        for (i, clip) in clips.enumerated() {
            let d = clip.duration
            if d <= 0 { continue }
            if clamped < acc + d - 1e-9 || i == clips.count - 1 {
                let local = min(max(0, clamped - acc), d)
                return (clip, i, local)
            }
            acc += d
        }
        guard let last = clips.last else { return nil }
        return (last, clips.count - 1, last.duration)
    }
}
