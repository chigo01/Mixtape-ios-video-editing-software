//
//  EditorViewModel+MotionTracking.swift
//  Mixtape
//

import SwiftUI
import UIKit
import AVFoundation
import Photos

extension EditorViewModel {
    // MARK: Motion tracking and stabilization

    var isGraphicFollowTracking: Bool {
        selectedTextOverlayID != nil || selectedOverlayClipID != nil
    }

    /// The single CapCut-style tracking box for whichever text or graphic
    /// overlay is currently selected — the box being placed, or (once tracked)
    /// the box already attached to that element.
    var currentTrackingBox: EditorMotionTrack? {
        guard let hostClip = subjectTrackingHostClip else { return nil }
        if let id = selectedMotionTrackID {
            return hostClip.motionTracks.first { $0.id == id }
        }
        if let trackID = selectedTextOverlay?.attachedTrackID
            ?? selectedOverlayClip?.attachedTrackID {
            return hostClip.motionTracks.first { $0.id == trackID }
        }
        return nil
    }

    var selectedStabilization: EditorStabilizationSettings {
        if let clip = selectedClip { return clip.stabilization }
        if let overlay = selectedOverlayClip { return overlay.stabilization }
        return subjectTrackingHostClip?.stabilization ?? .disabled
    }

    var canStabilizeSelectedClip: Bool {
        if let clip = selectedClip { return clip.isVideo }
        if let overlay = selectedOverlayClip { return overlay.isVideo }
        return subjectTrackingHostClip?.isVideo == true
    }

    var isMotionTracking: Bool { isTrackingSubject || stabilizationAnalysisProgress != nil }

    func currentClipProgressForTracking() -> Double {
        if isGraphicFollowTracking, let host = subjectTrackingHost {
            let duration = max(host.clip.duration, 0.001)
            return min(max((timelinePosition - host.start) / duration, 0), 1)
        }
        if let overlay = selectedOverlayClip {
            let duration = max(overlay.duration, 0.001)
            return min(max((timelinePosition - overlay.timelineStart) / duration, 0), 1)
        }
        if let info = playbackInfo,
           selectedClipID == nil || info.clip.id == selectedClipID {
            return min(max(info.localTime / max(info.clip.duration, 0.001), 0), 1)
        }
        return 0
    }

    func updateSelectedMotionTrack(_ update: (inout EditorMotionTrack) -> Void) {
        guard let id = selectedMotionTrackID else { return }
        beginMotionTrackingEditIfNeeded()
        mutateSelectedMotionTracks { tracks in
            guard let index = tracks.firstIndex(where: { $0.id == id }) else { return }
            update(&tracks[index])
        }
        scheduleMotionPreviewRefresh()
    }

    func deleteSelectedMotionTrack() {
        guard let id = selectedMotionTrackID else { return }
        beginMotionTrackingEditIfNeeded()
        mutateSelectedMotionTracks { tracks in
            tracks.removeAll { $0.id == id }
        }
        detachMotionTrack(id)
        selectedMotionTrackID = nil
        commitMotionTrackingEdit()
    }

    /// CapCut-style: place the box, tap Start, track the graphic's range, attach it.
    func startSubjectTracking() {
        guard motionTrackingTask == nil else { return }
        prepareSubjectTrackingIfNeeded()
        guard let host = subjectTrackingHost,
              let track = currentTrackingBox else {
            motionTrackingMessage = EditorMotionTrackingError.notVideo.localizedDescription
            return
        }

        let range = subjectTrackingRange(for: host)
        let seedProgress = min(max(range.seed, range.start), range.end)
        let trackID = track.id
        let clipID = host.clip.id
        let sessionID = UUID()
        motionTrackingSessionID = sessionID
        isTrackingSubject = true
        stabilizationAnalysisProgress = 0
        motionTrackingMessage = "Tracking subject…"
        pausePlaybackForEdit()

        var seed = track
        seed.seedProgress = seedProgress
        let correction = track.resolved(at: seedProgress)
        seed.seedX = correction.x
        seed.seedY = correction.y
        seed.seedRotation = correction.rotation
        seed.seedWidth = min(max(track.seedWidth * correction.scale, 0.02), 0.9)
        seed.seedHeight = min(max(track.seedHeight * correction.scale, 0.02), 0.9)
        let sourceAsset = host.clip.asset
        let clipDuration = host.clip.duration
        let sourceTime = host.sourceTime
        let canvasAspect = canvasSettings.aspectRatio
        let fillCanvas = host.clip.reframeMode == .fill
        let attachText = selectedTextOverlayID != nil
        let attachOverlay = selectedOverlayClipID != nil
        motionTrackingTask = Task { [weak self] in
            guard let self else { return }
            do {
                guard let asset = await EditorMotionTracker.loadSourceAsset(for: sourceAsset) else {
                    throw EditorMotionTrackingError.unavailableFrame
                }
                var combined: [EditorMotionTrackSample] = []
                let backwardSpan = max(seedProgress - range.start, 0)
                let forwardSpan = max(range.end - seedProgress, 0)
                let totalSpan = max(backwardSpan + forwardSpan, 0.000_001)

                if backwardSpan > 0.0001 {
                    let backward = try await EditorMotionTracker.track(
                        seed,
                        asset: asset,
                        sourceTime: sourceTime,
                        startProgress: seedProgress,
                        boundProgress: range.start,
                        clipDuration: clipDuration,
                        canvasAspect: canvasAspect,
                        fillCanvas: fillCanvas,
                        referenceScale: correction.scale,
                        progressHandler: { progress in
                            Task { @MainActor in
                                if self.motionTrackingSessionID == sessionID {
                                    self.stabilizationAnalysisProgress = progress * (backwardSpan / totalSpan)
                                }
                            }
                        }
                    )
                    combined.append(contentsOf: backward)
                }
                try Task.checkCancellation()
                if forwardSpan > 0.0001 {
                    let forward = try await EditorMotionTracker.track(
                        seed,
                        asset: asset,
                        sourceTime: sourceTime,
                        startProgress: seedProgress,
                        boundProgress: range.end,
                        clipDuration: clipDuration,
                        canvasAspect: canvasAspect,
                        fillCanvas: fillCanvas,
                        referenceScale: correction.scale,
                        progressHandler: { progress in
                            Task { @MainActor in
                                if self.motionTrackingSessionID == sessionID {
                                    self.stabilizationAnalysisProgress = (backwardSpan / totalSpan)
                                        + progress * (forwardSpan / totalSpan)
                                }
                            }
                        }
                    )
                    combined.append(contentsOf: forward)
                }
                try Task.checkCancellation()
                guard self.motionTrackingSessionID == sessionID else { return }
                self.beginMotionTrackingEditIfNeeded()
                self.mutateMotionTracks(onClipID: clipID) { tracks in
                    guard let index = tracks.firstIndex(where: { $0.id == trackID }) else { return }
                    var updated = tracks[index]
                    updated.seedProgress = seedProgress
                    updated.replaceSamples(combined)
                    tracks[index] = updated
                }
                // Tracking is an explicit "pin this graphic to that object"
                // action. Put the graphic's anchor on the selected subject at
                // the seed frame, then let the recorded path drive it from
                // there. Without this, a valid palm track can move correctly
                // while the sticker remains visibly beside the palm because
                // it keeps its old placement offset.
                self.snapAttachedElementToTrackSeed(seedX: seed.seedX, seedY: seed.seedY)
                if attachText {
                    self.attachSelectedTextToTrack(clipID: clipID, trackID: trackID)
                } else if attachOverlay {
                    self.attachSelectedOverlayToTrack(clipID: clipID, trackID: trackID)
                } else {
                    self.commitMotionTrackingEdit()
                }
                self.motionTrackingMessage = "Tracking complete · the graphic will follow this subject"
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch is CancellationError {
                if self.motionTrackingSessionID == sessionID {
                    self.motionTrackingMessage = "Tracking cancelled"
                }
            } catch {
                if self.motionTrackingSessionID == sessionID {
                    self.motionTrackingMessage = error.localizedDescription
                }
            }
            guard self.motionTrackingSessionID == sessionID else { return }
            self.motionTrackingSessionID = nil
            self.isTrackingSubject = false
            self.stabilizationAnalysisProgress = nil
            self.motionTrackingTask = nil
        }
    }

    func prepareSubjectTrackingIfNeeded() {
        guard isGraphicFollowTracking else { return }
        if let text = selectedTextOverlay, !text.isVisible(at: timelinePosition) {
            timelinePosition = text.startTime
            Task { await alignPlaybackToTimeline() }
        } else if let overlay = selectedOverlayClip,
                  timelinePosition < overlay.timelineStart
                    || timelinePosition > overlay.timelineEnd {
            timelinePosition = overlay.timelineStart
            Task { await alignPlaybackToTimeline() }
        }
        if let existing = currentTrackingBox {
            selectedMotionTrackID = existing.id
        } else {
            addSubjectFollowTrack()
        }
    }

    func clearSubjectTracking() {
        detachSelectedAttachment()
        if let trackID = selectedMotionTrackID {
            deleteSelectedMotionTrack()
            _ = trackID
        }
        motionTrackingMessage = "Tracking cleared"
    }

    func analyzeSelectedStabilization() {
        guard motionTrackingTask == nil else { return }
        let host: (id: UUID, asset: PHAsset, duration: TimeInterval, sourceTime: (Double) -> TimeInterval)
        if let clip = selectedClip, clip.isVideo {
            let duration = max(clip.duration, 0.001)
            host = (
                clip.id,
                clip.asset,
                duration,
                { progress in
                    clip.sourceTime(forExportedLocal: progress * duration)
                }
            )
        } else if let overlay = selectedOverlayClip, overlay.isVideo {
            let duration = max(overlay.duration, 0.001)
            host = (
                overlay.id,
                overlay.asset,
                duration,
                { progress in
                    overlay.sourceTime(forTimelineLocal: progress * duration)
                }
            )
        } else if let clip = subjectTrackingHostClip, clip.isVideo {
            let duration = max(clip.duration, 0.001)
            host = (
                clip.id,
                clip.asset,
                duration,
                { progress in
                    clip.sourceTime(forExportedLocal: progress * duration)
                }
            )
        } else {
            motionTrackingMessage = EditorMotionTrackingError.notVideo.localizedDescription
            return
        }

        let sessionID = UUID()
        motionTrackingSessionID = sessionID
        stabilizationAnalysisProgress = 0
        motionTrackingMessage = "Analyzing camera motion…"
        pausePlaybackForEdit()

        let sourceAsset = host.asset
        let clipDuration = host.duration
        let sourceTime = host.sourceTime
        let clipID = host.id
        motionTrackingTask = Task { [weak self] in
            guard let self else { return }
            do {
                guard let asset = await EditorMotionTracker.loadSourceAsset(for: sourceAsset) else {
                    throw EditorMotionTrackingError.unavailableFrame
                }
                let samples = try await EditorMotionTracker.analyzeStabilization(
                    asset: asset,
                    sourceTime: sourceTime,
                    clipDuration: clipDuration,
                    progressHandler: { progress in
                        Task { @MainActor in
                            if self.motionTrackingSessionID == sessionID {
                                self.stabilizationAnalysisProgress = progress
                            }
                        }
                    }
                )
                try Task.checkCancellation()
                guard self.motionTrackingSessionID == sessionID else { return }
                self.beginMotionTrackingEditIfNeeded()
                self.mutateStabilization(onClipID: clipID) { settings in
                    settings.samples = samples
                    settings.isEnabled = true
                    settings.autoCrop = true
                    settings.crop = 0
                    settings.refreshFittedCrop()
                }
                self.commitMotionTrackingEdit()
                let cropPercent = Int((self.selectedStabilization.effectiveCrop * 100).rounded())
                let modeLabel = self.selectedStabilization.mode == .lock ? "Lock" : "Smooth"
                self.motionTrackingMessage = "\(modeLabel) ready · \(samples.count) samples · crop \(cropPercent)%"
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch is CancellationError {
                if self.motionTrackingSessionID == sessionID {
                    self.motionTrackingMessage = "Analysis cancelled"
                }
            } catch {
                if self.motionTrackingSessionID == sessionID {
                    self.motionTrackingMessage = error.localizedDescription
                }
            }
            guard self.motionTrackingSessionID == sessionID else { return }
            self.motionTrackingSessionID = nil
            self.stabilizationAnalysisProgress = nil
            self.motionTrackingTask = nil
        }
    }

    func cancelMotionTracking() {
        guard motionTrackingTask != nil else { return }
        motionTrackingTask?.cancel()
        motionTrackingTask = nil
        motionTrackingSessionID = nil
        isTrackingSubject = false
        stabilizationAnalysisProgress = nil
        motionTrackingMessage = "Tracking cancelled"
    }

    func updateSelectedStabilization(_ update: (inout EditorStabilizationSettings) -> Void) {
        beginMotionTrackingEditIfNeeded()
        if let id = selectedClipID ?? selectedOverlayClipID ?? subjectTrackingHostClip?.id {
            mutateStabilization(onClipID: id) { settings in
                update(&settings)
                settings.refreshFittedCrop()
            }
        }
        scheduleMotionPreviewRefresh()
        scheduleSave()
    }

    func clearSelectedStabilization() {
        beginMotionTrackingEditIfNeeded()
        updateSelectedStabilization { $0 = .disabled }
        commitMotionTrackingEdit()
        motionTrackingMessage = "Stabilization cleared"
    }

    func attachSelectedTextToTrack(clipID: UUID, trackID: UUID) {
        guard let id = selectedTextOverlayID,
              let index = textOverlays.firstIndex(where: { $0.id == id }) else { return }
        beginMotionTrackingEditIfNeeded()
        textOverlays[index].attachedClipID = clipID
        textOverlays[index].attachedTrackID = trackID
        commitMotionTrackingEdit()
    }

    func attachSelectedOverlayToTrack(clipID: UUID, trackID: UUID) {
        guard let id = selectedOverlayClipID,
              let index = overlayClips.firstIndex(where: { $0.id == id }) else { return }
        beginMotionTrackingEditIfNeeded()
        overlayClips[index].attachedClipID = clipID
        overlayClips[index].attachedTrackID = trackID
        commitMotionTrackingEdit()
    }

    private func snapAttachedElementToTrackSeed(seedX: Double, seedY: Double) {
        if let id = selectedOverlayClipID,
           let index = overlayClips.firstIndex(where: { $0.id == id }) {
            overlayClips[index].xOffset = min(max(seedX - 0.5, -0.75), 0.75)
            overlayClips[index].yOffset = min(max(seedY - 0.5, -0.75), 0.75)
        } else if let id = selectedTextOverlayID,
                  let index = textOverlays.firstIndex(where: { $0.id == id }) {
            let canvas = EditorTextOverlayLayout.referenceCanvasSize(
                aspectRatio: canvasSettings.aspectRatio
            )
            textOverlays[index].xOffset = CGFloat(seedX - 0.5) * canvas.width
            textOverlays[index].yOffset = CGFloat(seedY - 0.5) * canvas.height
        }
    }

    func detachSelectedAttachment() {
        beginMotionTrackingEditIfNeeded()
        if let id = selectedTextOverlayID,
           let index = textOverlays.firstIndex(where: { $0.id == id }) {
            textOverlays[index].attachedClipID = nil
            textOverlays[index].attachedTrackID = nil
        }
        if let id = selectedOverlayClipID,
           let index = overlayClips.firstIndex(where: { $0.id == id }) {
            overlayClips[index].attachedClipID = nil
            overlayClips[index].attachedTrackID = nil
        }
        commitMotionTrackingEdit()
    }

    func setSelectedAttachmentFollowsRotation(_ follows: Bool) {
        beginMotionTrackingEditIfNeeded()
        if let id = selectedTextOverlayID,
           let index = textOverlays.firstIndex(where: { $0.id == id }) {
            textOverlays[index].attachRotation = follows
        }
        if let id = selectedOverlayClipID,
           let index = overlayClips.firstIndex(where: { $0.id == id }) {
            overlayClips[index].attachRotation = follows
        }
        scheduleMotionPreviewRefresh()
        scheduleSave()
    }

    func setSelectedAttachmentFollowsScale(_ follows: Bool) {
        beginMotionTrackingEditIfNeeded()
        if let id = selectedTextOverlayID,
           let index = textOverlays.firstIndex(where: { $0.id == id }) {
            textOverlays[index].attachScale = follows
        }
        if let id = selectedOverlayClipID,
           let index = overlayClips.firstIndex(where: { $0.id == id }) {
            overlayClips[index].attachScale = follows
        }
        scheduleMotionPreviewRefresh()
        scheduleSave()
    }

    func resolvedTextOverlay(
        _ overlay: EditorTextOverlay,
        at time: TimeInterval,
        canvasSize: CGSize
    ) -> EditorTextOverlay {
        var resolved = overlay.resolved(at: time)
        if let sample = motionSample(
            clipID: overlay.attachedClipID,
            trackID: overlay.attachedTrackID,
            at: time
        ) {
            resolved = resolved.applyingTrack(sample.sample, seed: sample.seed, canvasSize: canvasSize)
        }
        return resolved
    }

    func resolvedOverlayClip(
        _ clip: EditorOverlayClip,
        at time: TimeInterval
    ) -> EditorOverlayClip {
        var resolved = clip.resolved(at: time)
        if let sample = motionSample(
            clipID: clip.attachedClipID,
            trackID: clip.attachedTrackID,
            at: time
        ) {
            resolved = resolved.applyingTrack(sample.sample, seed: sample.seed)
        }
        return resolved
    }

    func motionSample(
        clipID: UUID?,
        trackID: UUID?,
        at time: TimeInterval
    ) -> (sample: EditorMotionTrackSample, seed: EditorMotionTrackSample)? {
        guard let clipID, let trackID,
              let resolved = resolvedMotionTrack(clipID: clipID, trackID: trackID) else {
            return nil
        }
        let progress: Double
        if let index = clips.firstIndex(where: { $0.id == clipID }) {
            let start = timelineOffsetForClipIndex(index)
            let duration = max(clips[index].duration, 0.001)
            progress = min(max((time - start) / duration, 0), 1)
        } else if let overlay = overlayClips.first(where: { $0.id == clipID }) {
            progress = min(
                max((time - overlay.timelineStart) / max(overlay.duration, 0.001), 0),
                1
            )
        } else {
            return nil
        }
        return (resolved.resolved(at: progress), resolved.seedSample)
    }

    func resolvedMotionTrack(clipID: UUID, trackID: UUID) -> EditorMotionTrack? {
        if let clip = clips.first(where: { $0.id == clipID }) {
            return clip.motionTracks.first { $0.id == trackID }
        }
        return overlayClips.first(where: { $0.id == clipID })?
            .motionTracks.first { $0.id == trackID }
    }

    func commitMotionTrackingEdit() {
        motionPreviewTask?.cancel()
        motionPreviewTask = nil
        finalizeMotionTrackingUndo()
        invalidateComposition()
        scheduleSave()
        Task { await alignPlaybackToTimeline() }
    }

    private func beginMotionTrackingEditIfNeeded() {
        if motionTrackingUndoSnapshot == nil {
            motionTrackingUndoSnapshot = currentSnapshot()
        }
    }

    func finalizeMotionTrackingUndo() {
        motionPreviewTask?.cancel()
        motionPreviewTask = nil
        let before = motionTrackingUndoSnapshot
        motionTrackingUndoSnapshot = nil
        if let before, before != currentSnapshot() {
            undoManager.pushUndoState(before)
            refreshUndoState()
            scheduleSave()
        }
    }

    private func scheduleMotionPreviewRefresh() {
        invalidateComposition()
        motionPreviewTask?.cancel()
        motionPreviewTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(90))
            guard !Task.isCancelled, let self else { return }
            await self.alignPlaybackToTimeline()
        }
    }

    var subjectTrackingHostClip: EditorClip? {
        subjectTrackingHost?.clip
    }

    private var subjectTrackingHost: (
        clip: EditorClip,
        start: TimeInterval,
        sourceTime: (Double) -> TimeInterval
    )? {
        let graphicStart: TimeInterval
        let graphicEnd: TimeInterval
        if let text = selectedTextOverlay {
            graphicStart = text.startTime
            graphicEnd = text.endTime
        } else if let overlay = selectedOverlayClip {
            graphicStart = overlay.timelineStart
            graphicEnd = overlay.timelineEnd
        } else {
            return nil
        }

        if let info = playbackInfo, info.clip.isVideo {
            let start = timelineOffsetForClipIndex(info.index)
            let end = start + info.clip.duration
            if graphicStart < end && graphicEnd > start {
                return hostDescriptor(for: info.clip, clipStart: start)
            }
        }
        var cursor: TimeInterval = 0
        for clip in clips {
            let end = cursor + clip.duration
            if clip.isVideo, graphicStart < end, graphicEnd > cursor {
                return hostDescriptor(for: clip, clipStart: cursor)
            }
            cursor = end
        }
        if let index = clips.firstIndex(where: \.isVideo) {
            return hostDescriptor(
                for: clips[index],
                clipStart: timelineOffsetForClipIndex(index)
            )
        }
        return nil
    }

    private func hostDescriptor(
        for clip: EditorClip,
        clipStart: TimeInterval
    ) -> (clip: EditorClip, start: TimeInterval, sourceTime: (Double) -> TimeInterval) {
        let duration = max(clip.duration, 0.001)
        return (
            clip,
            clipStart,
            { progress in
                clip.sourceTime(forExportedLocal: progress * duration)
            }
        )
    }

    private func subjectTrackingRange(
        for host: (clip: EditorClip, start: TimeInterval, sourceTime: (Double) -> TimeInterval)
    ) -> (start: Double, end: Double, seed: Double) {
        let duration = max(host.clip.duration, 0.001)
        let clipEnd = host.start + host.clip.duration
        let graphicStart: TimeInterval
        let graphicEnd: TimeInterval
        if let text = selectedTextOverlay {
            graphicStart = text.startTime
            graphicEnd = text.endTime
        } else if let overlay = selectedOverlayClip {
            graphicStart = overlay.timelineStart
            graphicEnd = overlay.timelineEnd
        } else {
            graphicStart = host.start
            graphicEnd = clipEnd
        }
        let start = min(max((max(graphicStart, host.start) - host.start) / duration, 0), 1)
        let end = min(max((min(graphicEnd, clipEnd) - host.start) / duration, 0), 1)
        let seed = min(max((timelinePosition - host.start) / duration, start), end)
        return (min(start, end), max(start, end), seed)
    }

    private func addSubjectFollowTrack() {
        beginMotionTrackingEditIfNeeded()
        let label: String
        if let text = selectedTextOverlay {
            let snippet = text.text.trimmingCharacters(in: .whitespacesAndNewlines)
            label = snippet.isEmpty ? "Subject" : String(snippet.prefix(18))
        } else {
            label = "Subject"
        }
        var seedX = 0.5
        var seedY = 0.5
        var seedWidth = 0.22
        var seedHeight = 0.16
        if let overlay = selectedOverlayClip {
            seedX = min(max(0.5 + overlay.xOffset, 0.08), 0.92)
            seedY = min(max(0.5 + overlay.yOffset, 0.08), 0.92)
            seedWidth = min(max(overlay.scale * 0.28, 0.10), 0.45)
            seedHeight = min(max(overlay.scale * 0.36, 0.10), 0.50)
        } else if let text = selectedTextOverlay {
            let canvas = EditorTextOverlayLayout.referenceCanvasSize(
                aspectRatio: canvasSettings.aspectRatio
            )
            seedX = min(max(0.5 + Double(text.xOffset / max(canvas.width, 1)), 0.08), 0.92)
            seedY = min(max(0.5 + Double(text.yOffset / max(canvas.height, 1)), 0.08), 0.92)
        }
        let track = EditorMotionTrack(
            name: label,
            seedX: seedX,
            seedY: seedY,
            seedWidth: seedWidth,
            seedHeight: seedHeight,
            seedProgress: currentClipProgressForTracking()
        )
        mutateSelectedMotionTracks { tracks in
            tracks.append(track)
        }
        selectedMotionTrackID = track.id
        motionTrackingMessage = "Place the box on the subject, then tap Start."
    }

    private func mutateSelectedMotionTracks(_ body: (inout [EditorMotionTrack]) -> Void) {
        guard let id = subjectTrackingHostClip?.id,
              let index = clips.firstIndex(where: { $0.id == id }) else { return }
        body(&clips[index].motionTracks)
        invalidateComposition()
    }

    private func mutateMotionTracks(
        onClipID clipID: UUID,
        _ body: (inout [EditorMotionTrack]) -> Void
    ) {
        if let index = clips.firstIndex(where: { $0.id == clipID }) {
            body(&clips[index].motionTracks)
        } else if let index = overlayClips.firstIndex(where: { $0.id == clipID }) {
            body(&overlayClips[index].motionTracks)
        }
        invalidateComposition()
    }

    private func mutateStabilization(
        onClipID clipID: UUID,
        _ body: (inout EditorStabilizationSettings) -> Void
    ) {
        if let index = clips.firstIndex(where: { $0.id == clipID }) {
            body(&clips[index].stabilization)
        } else if let index = overlayClips.firstIndex(where: { $0.id == clipID }) {
            body(&overlayClips[index].stabilization)
        }
        invalidateComposition()
    }

    private func detachMotionTrack(_ trackID: UUID) {
        for index in textOverlays.indices where textOverlays[index].attachedTrackID == trackID {
            textOverlays[index].attachedClipID = nil
            textOverlays[index].attachedTrackID = nil
        }
        for index in overlayClips.indices where overlayClips[index].attachedTrackID == trackID {
            overlayClips[index].attachedClipID = nil
            overlayClips[index].attachedTrackID = nil
        }
    }

    func remapMotionAttachmentsAfterSplit(
        left: EditorClip,
        right: EditorClip,
        splitTime: TimeInterval
    ) {
        let originalID: UUID
        let leftTrackIDs: [UUID: UUID]
        let rightTrackIDs: [UUID: UUID]
        if left.motionTracks.contains(where: { leftTrack in
            right.motionTracks.contains(where: { $0.id == leftTrack.id })
        }) || left.id == selectedClipID {
            originalID = left.id
            leftTrackIDs = Dictionary(uniqueKeysWithValues: left.motionTracks.map { ($0.id, $0.id) })
            rightTrackIDs = Dictionary(uniqueKeysWithValues: zip(left.motionTracks, right.motionTracks).map {
                ($0.id, $1.id)
            })
        } else {
            originalID = right.id
            leftTrackIDs = Dictionary(uniqueKeysWithValues: zip(right.motionTracks, left.motionTracks).map {
                ($0.id, $1.id)
            })
            rightTrackIDs = Dictionary(uniqueKeysWithValues: right.motionTracks.map { ($0.id, $0.id) })
        }
        for index in textOverlays.indices {
            guard textOverlays[index].attachedClipID == originalID else { continue }
            let usesRight = textOverlays[index].startTime >= splitTime
            textOverlays[index].attachedClipID = usesRight ? right.id : left.id
            if let oldTrack = textOverlays[index].attachedTrackID {
                textOverlays[index].attachedTrackID = (usesRight ? rightTrackIDs : leftTrackIDs)[oldTrack]
                    ?? oldTrack
            }
        }
        for index in overlayClips.indices {
            guard overlayClips[index].attachedClipID == originalID else { continue }
            let usesRight = overlayClips[index].timelineStart >= splitTime
            overlayClips[index].attachedClipID = usesRight ? right.id : left.id
            if let oldTrack = overlayClips[index].attachedTrackID {
                overlayClips[index].attachedTrackID = (usesRight ? rightTrackIDs : leftTrackIDs)[oldTrack]
                    ?? oldTrack
            }
        }
    }
}
