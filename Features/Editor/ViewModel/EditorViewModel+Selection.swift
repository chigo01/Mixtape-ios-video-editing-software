//
//  EditorViewModel+Selection.swift
//  Mixtape
//

import SwiftUI
import UIKit
import AVFoundation
import Photos

extension EditorViewModel {
    // MARK: Selection

    func selectClipForEditing(_ id: UUID) {
        if handleMultiSelection(.primary(id)) { return }
        cancelColorMaskTracking()
        selectedColorMaskID = nil
        isColorMaskEditing = false
        if selectedTool == .duration {
            finalizePhotoDurationEditUndo()
        }
        if selectedTool == .crop {
            finalizeReframeEditUndo()
        }
        if selectedTool == .filter {
            finalizeColorAdjustmentUndo()
        }
        if selectedTool == .compositing {
            finalizeOverlayCompositingUndo()
        }
        if selectedTool == .track || selectedTool == .stabilize {
            finalizeMotionTrackingUndo()
        }
        cancelMotionTracking()
        selectedMotionTrackID = nil
        selectedClipID = id
        selectedAdjustmentLayerID = nil
        selectedTextOverlayID = nil
        selectedGraphicOverlayID = nil
        selectedAudioClipID = nil
        selectedOverlayClipID = nil
        isTextEditorPresented = false
        selectedTool = nil
    }

    func selectAudioClip(_ id: UUID) {
        if handleMultiSelection(.audio(id)) { return }
        if punchInClipID != id { cancelPunchInMark() }
        if selectedTool == .duration {
            finalizePhotoDurationEditUndo()
        }
        if selectedTool == .crop {
            finalizeReframeEditUndo()
        }
        if selectedTool == .filter {
            finalizeColorAdjustmentUndo()
        }
        if selectedTool == .compositing {
            finalizeOverlayCompositingUndo()
        }
        if selectedTool == .track || selectedTool == .stabilize {
            finalizeMotionTrackingUndo()
        }
        cancelMotionTracking()
        selectedMotionTrackID = nil
        selectedAudioClipID = id
        selectedAdjustmentLayerID = nil
        selectedClipID = nil
        selectedTextOverlayID = nil
        selectedGraphicOverlayID = nil
        selectedOverlayClipID = nil
        isTextEditorPresented = false
        selectedTool = nil
    }

    func deselectAudioClip() {
        cancelPunchInMark()
        finalizeAudioVolumeEditUndo()
        selectedTool = nil
        selectedAudioClipID = nil
    }

    /// First call marks the in-point at the current playhead; the second call (on the same
    /// clip) marks the out-point and hands the range to `punchInPendingRange` for the view to
    /// present the recorder. Calling this on a different clip restarts marking there instead of
    /// carrying over stale state.
    func togglePunchInMark() {
        guard let clip = selectedAudioClip else { return }
        if punchInClipID == clip.id, let start = punchInStartTime {
            let clampedStart = max(start, clip.timelineStart)
            let clampedEnd = min(timelinePosition, clip.timelineEnd)
            punchInClipID = nil
            punchInStartTime = nil
            let rangeStart = min(clampedStart, clampedEnd)
            let rangeEnd = max(clampedStart, clampedEnd)
            guard rangeEnd - rangeStart >= EditorAudioClip.minimumSpan else { return }
            punchInPendingRange = PunchInRange(clipID: clip.id, start: rangeStart, end: rangeEnd)
        } else {
            punchInClipID = clip.id
            punchInStartTime = timelinePosition
        }
    }

    func cancelPunchInMark() {
        punchInClipID = nil
        punchInStartTime = nil
    }

    func selectOverlayClip(_ id: UUID) {
        if handleMultiSelection(.overlay(id)) { return }
        cancelColorMaskTracking()
        selectedColorMaskID = nil
        isColorMaskEditing = false
        if selectedTool == .speed {
            finalizeSpeedEditUndo()
        }
        if selectedTool == .duration {
            finalizePhotoDurationEditUndo()
        }
        if selectedTool == .volume {
            finalizeVolumeEditUndo()
        }
        if selectedTool == .crop {
            finalizeReframeEditUndo()
        }
        if selectedTool == .filter {
            finalizeColorAdjustmentUndo()
        }
        if selectedTool == .compositing {
            finalizeOverlayCompositingUndo()
        }
        if selectedTool == .track || selectedTool == .stabilize {
            finalizeMotionTrackingUndo()
        }
        cancelMotionTracking()
        selectedMotionTrackID = nil
        finalizeOverlayTransform()
        selectedOverlayClipID = id
        selectedAdjustmentLayerID = nil
        selectedClipID = nil
        selectedTextOverlayID = nil
        selectedGraphicOverlayID = nil
        selectedAudioClipID = nil
        isTextEditorPresented = false
        selectedTool = nil
    }

    func deselectOverlayClip() {
        cancelColorMaskTracking()
        if selectedTool == .speed {
            finalizeSpeedEditUndo()
        }
        if selectedTool == .duration {
            finalizePhotoDurationEditUndo()
        }
        if selectedTool == .volume {
            finalizeVolumeEditUndo()
        }
        if selectedTool == .crop {
            finalizeReframeEditUndo()
        }
        if selectedTool == .filter {
            finalizeColorAdjustmentUndo()
        }
        if selectedTool == .compositing {
            finalizeOverlayCompositingUndo()
        }
        if selectedTool == .track || selectedTool == .stabilize {
            finalizeMotionTrackingUndo()
        }
        cancelMotionTracking()
        finalizeOverlayTransform()
        selectedColorMaskID = nil
        selectedMotionTrackID = nil
        isColorMaskEditing = false
        selectedOverlayClipID = nil
        selectedTool = nil
    }

    /// Overlay to focus when expanding collapsed overlay tracks: keep the current selection
    /// if it still exists, otherwise the topmost overlay under the playhead, otherwise the
    /// closest overlay on the timeline.
    func preferredOverlayClipID() -> UUID? {
        preferredTimelineItemID(
            selectedID: selectedOverlayClipID,
            items: overlayClips.map { ($0.id, $0.timelineStart, $0.timelineEnd, $0.zIndex) }
        )
    }

    func selectPreferredOverlayClip() {
        guard let id = preferredOverlayClipID(), selectedOverlayClipID != id else { return }
        selectOverlayClip(id)
    }

    /// Audio clip to focus when expanding collapsed audio tracks. Same playhead-first
    /// preference as overlays, using `laneIndex` as the tie-breaker (lower lane on top).
    func preferredAudioClipID() -> UUID? {
        preferredTimelineItemID(
            selectedID: selectedAudioClipID,
            items: audioClips.map { ($0.id, $0.timelineStart, $0.timelineEnd, -$0.laneIndex) }
        )
    }

    func selectPreferredAudioClip() {
        guard let id = preferredAudioClipID(), selectedAudioClipID != id else { return }
        selectAudioClip(id)
    }

    private func preferredTimelineItemID(
        selectedID: UUID?,
        items: [(id: UUID, start: TimeInterval, end: TimeInterval, rank: Int)]
    ) -> UUID? {
        if let selectedID, items.contains(where: { $0.id == selectedID }) {
            return selectedID
        }
        let time = timelinePosition
        let covering = items.filter { time >= $0.start && time < $0.end }
        if let top = covering.max(by: { $0.rank < $1.rank }) {
            return top.id
        }
        return items.min { lhs, rhs in
            let lhsDistance = distanceFromPlayhead(start: lhs.start, end: lhs.end, time: time)
            let rhsDistance = distanceFromPlayhead(start: rhs.start, end: rhs.end, time: time)
            if lhsDistance == rhsDistance { return lhs.rank > rhs.rank }
            return lhsDistance < rhsDistance
        }?.id
    }

    private func distanceFromPlayhead(
        start: TimeInterval,
        end: TimeInterval,
        time: TimeInterval
    ) -> TimeInterval {
        if time < start { return start - time }
        if time >= end { return time - end }
        return 0
    }

    func deselectClip() {
        if selectedTool == .speed {
            finalizeSpeedEditUndo()
        }
        if selectedTool == .duration {
            finalizePhotoDurationEditUndo()
        }
        if selectedTool == .crop {
            finalizeReframeEditUndo()
        }
        if selectedTool == .filter {
            finalizeColorAdjustmentUndo()
        }
        if selectedTool == .compositing {
            finalizeOverlayCompositingUndo()
        }
        if selectedTool == .track || selectedTool == .stabilize {
            finalizeMotionTrackingUndo()
        }
        cancelMotionTracking()
        selectedMotionTrackID = nil
        selectedTool = nil
        selectedClipID = nil
    }

    func performAudioAction(_ action: EditorAudioAction) {
        switch action {
        case .add:
            // Handled by EditorAudioActionBar's onAddAudio closure before this is ever called —
            // adding a clip needs to present a picker sheet, which the view owns, not the vm.
            break
        case .delete:
            deleteSelectedAudioClip()
        case .split:
            splitSelectedAudioAtPlayhead()
            selectedTool = .split
        case .volume:
            performToolAction(.volume)
        case .keyframe:
            performToolAction(.keyframe)
        case .duplicate:
            duplicateSelectedAudioClip()
        case .punchIn:
            togglePunchInMark()
        case .effects:
            performToolAction(.audioEffect)
        }
    }

    func performClipAction(_ action: EditorClipAction) {
        switch action {
        case .delete:
            deleteSelectedClip()
        case .split:
            splitAtPlayhead()
            selectedTool = .split
        case .precision:
            performToolAction(.precision)
        case .reverse:
            if selectedClip?.playback.isReverse == true {
                toggleReverseSelectedClip()
            } else {
                performToolAction(.reverse)
            }
        case .freeze:
            performToolAction(.freeze)
        case .speed:
            performToolAction(.speed)
        case .duration:
            performToolAction(.duration)
        case .crop:
            performToolAction(.crop)
        case .volume:
            performToolAction(.volume)
        case .filter:
            selectedAdjustmentLayerID = nil
            performToolAction(.filter)
        case .effects:
            performToolAction(.effects)
        case .compositing:
            performToolAction(.compositing)
        case .text:
            performToolAction(.text)
        case .keyframe:
            performToolAction(.keyframe)
        case .stabilize:
            performToolAction(.stabilize)
        case .track:
            performToolAction(.track)
        case .duplicate:
            duplicateSelectedClip()
        case .replace:
            break
        }
    }

    func jumpToClipStart(_ id: UUID) {
        guard let idx = clips.firstIndex(where: { $0.id == id }) else { return }
        timelinePosition = timelineOffsetForClipIndex(idx)
        Task {
            await alignPlaybackToTimeline()
            if isPlaying { resumePlaybackAfterAlign() }
        }
    }

    func selectTool(_ tool: EditorTool) {
        if selectedTool == .speed, tool != .speed {
            finalizeSpeedEditUndo()
        }
        if selectedTool == .duration, tool != .duration {
            finalizePhotoDurationEditUndo()
        }
        if selectedTool == .crop, tool != .crop {
            finalizeReframeEditUndo()
        }
        if selectedTool == .volume, tool != .volume {
            finalizeVolumeEditUndo()
            finalizeAudioVolumeEditUndo()
        }
        if selectedTool == .filter, tool != .filter {
            finalizeColorAdjustmentUndo()
            selectedColorMaskID = nil
            isColorMaskEditing = false
        }
        if selectedTool == .compositing, tool != .compositing {
            finalizeOverlayCompositingUndo()
        }
        if selectedTool == .track || selectedTool == .stabilize,
           tool != .track, tool != .stabilize {
            finalizeMotionTrackingUndo()
        }

        if selectedTool == tool {
            if tool == .speed { finalizeSpeedEditUndo() }
            if tool == .duration { finalizePhotoDurationEditUndo() }
            if tool == .crop { finalizeReframeEditUndo() }
            if tool == .filter { finalizeColorAdjustmentUndo() }
            if tool == .compositing { finalizeOverlayCompositingUndo() }
            if tool == .track || tool == .stabilize { finalizeMotionTrackingUndo() }
            if tool == .filter {
                selectedColorMaskID = nil
                isColorMaskEditing = false
            }
            selectedTool = nil
            if tool == .crop { showsReframeSafeAreaGuides = false }
            return
        }

        selectedTool = tool
        if tool == .speed {
            speedUndoSnapshot = currentSnapshot()
        }
        if tool == .duration {
            photoDurationUndoSnapshot = currentSnapshot()
        }
        if tool == .crop {
            reframeUndoSnapshot = currentSnapshot()
            showsReframeSafeAreaGuides = true
            pausePlaybackForEdit()
            if let id = selectedClipID,
               let index = clips.firstIndex(where: { $0.id == id }),
               playbackInfo?.clip.id != id {
                timelinePosition = timelineOffsetForClipIndex(index)
            }
            Task { await alignPlaybackToTimeline() }
        }
        if tool == .filter {
            colorUndoSnapshot = currentSnapshot()
            pausePlaybackForEdit()
        }
        if tool == .compositing {
            overlayCompositingUndoSnapshot = currentSnapshot()
            pausePlaybackForEdit()
        }
        if tool == .track {
            motionTrackingUndoSnapshot = currentSnapshot()
            pausePlaybackForEdit()
            prepareSubjectTrackingIfNeeded()
        }
        if tool == .stabilize {
            motionTrackingUndoSnapshot = currentSnapshot()
            pausePlaybackForEdit()
        }
    }

    func performToolAction(_ tool: EditorTool) {
        switch tool {
        case .split:
            splitAtPlayhead()
            selectedTool = .split
        case .text:
            if selectedTextOverlayID != nil {
                isTextEditorPresented = true
            } else {
                addTextOverlay()
            }
        case .graphics:
            selectTool(.graphics)
        case .captions:
            selectTool(.captions)
        case .sequence:
            beginMultiSelection()
        case .canvas:
            selectTool(.canvas)
        case .background:
            selectTool(.background)
        default:
            selectTool(tool)
        }
    }

    // MARK: Crop and reframe
}
