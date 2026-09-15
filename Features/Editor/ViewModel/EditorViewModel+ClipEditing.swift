//
//  EditorViewModel+ClipEditing.swift
//  Mixtape
//

import SwiftUI
import UIKit
import AVFoundation
import Photos

extension EditorViewModel {
    // MARK: Clips

    var precisionEditMessage: String? {
        guard let selectedClip, selectedClip.isVideo else {
            return "Select a video clip to use precision editing."
        }
        if selectedClip.speedRamp != nil {
            return "Commit or remove the speed curve before source-precision edits."
        }
        if selectedClip.playback != .forward {
            return "Return generated reverse/freeze media to a forward source clip before precision edits."
        }
        return nil
    }

    var canRollSelectedCut: Bool {
        guard precisionEditMessage == nil,
              let id = selectedClipID,
              let index = clips.firstIndex(where: { $0.id == id }),
              index + 1 < clips.count else { return false }
        return clips[index + 1].isVideo && clips[index + 1].speedRamp == nil
            && clips[index + 1].playback == .forward
    }

    var canSlideSelectedClip: Bool {
        guard precisionEditMessage == nil,
              let id = selectedClipID,
              let index = clips.firstIndex(where: { $0.id == id }),
              index > 0, index + 1 < clips.count else { return false }
        return clips[index - 1].isVideo && clips[index + 1].isVideo
            && clips[index - 1].speedRamp == nil && clips[index + 1].speedRamp == nil
            && clips[index - 1].playback == .forward && clips[index + 1].playback == .forward
    }

    func slipSelectedClip(by timelineDelta: TimeInterval) {
        guard precisionEditMessage == nil,
              let id = selectedClipID,
              let index = clips.firstIndex(where: { $0.id == id }) else { return }
        let clip = clips[index]
        let sourceDelta = timelineDelta * TimeInterval(max(clip.averageSpeed, 0.001))
        let minimumDelta = -clip.trimStart
        let maximumDelta = clip.originalDuration - clip.trimEnd
        let applied = min(max(sourceDelta, minimumDelta), maximumDelta)
        guard abs(applied) > 0.000_001 else { return }
        registerUndoIfNeeded()
        clips[index].trimStart += applied
        clips[index].trimEnd += applied
        if !clips[index].isAudioLinked {
            clips[index].audioTrimStart = (clips[index].audioTrimStart ?? clip.trimStart) + applied
            clips[index].audioTrimEnd = (clips[index].audioTrimEnd ?? clip.trimEnd) + applied
        }
        finishPrecisionEdit()
    }

    func rollSelectedCut(by timelineDelta: TimeInterval) {
        guard canRollSelectedCut,
              let id = selectedClipID,
              let index = clips.firstIndex(where: { $0.id == id }) else { return }
        let left = clips[index]
        let right = clips[index + 1]
        let leftRate = TimeInterval(max(left.averageSpeed, 0.001))
        let rightRate = TimeInterval(max(right.averageSpeed, 0.001))
        let leftMinimum = EditorClip.minimumSourceSpan(speed: left.averageSpeed)
        let rightMinimum = EditorClip.minimumSourceSpan(speed: right.averageSpeed)
        let minimumDelta = max(
            (left.trimStart + leftMinimum - left.trimEnd) / leftRate,
            -right.trimStart / rightRate
        )
        let maximumDelta = min(
            (left.originalDuration - left.trimEnd) / leftRate,
            (right.trimEnd - rightMinimum - right.trimStart) / rightRate
        )
        let applied = min(max(timelineDelta, minimumDelta), maximumDelta)
        guard abs(applied) > 0.000_001 else { return }
        registerUndoIfNeeded()
        clips[index].trimEnd += applied * leftRate
        clips[index + 1].trimStart += applied * rightRate
        clips[index].keyframes.trim(to: clips[index].duration)
        clips[index + 1].keyframes.trim(to: clips[index + 1].duration)
        clips[index].transitionDuration = min(
            clips[index].transitionDuration,
            min(clips[index].duration, clips[index + 1].duration)
        )
        finishPrecisionEdit()
    }

    func slideSelectedClip(by timelineDelta: TimeInterval) {
        guard canSlideSelectedClip,
              let id = selectedClipID,
              let index = clips.firstIndex(where: { $0.id == id }) else { return }
        let previous = clips[index - 1]
        let next = clips[index + 1]
        let previousRate = TimeInterval(max(previous.averageSpeed, 0.001))
        let nextRate = TimeInterval(max(next.averageSpeed, 0.001))
        let previousMinimum = EditorClip.minimumSourceSpan(speed: previous.averageSpeed)
        let nextMinimum = EditorClip.minimumSourceSpan(speed: next.averageSpeed)
        let minimumDelta = max(
            (previous.trimStart + previousMinimum - previous.trimEnd) / previousRate,
            -next.trimStart / nextRate
        )
        let maximumDelta = min(
            (previous.originalDuration - previous.trimEnd) / previousRate,
            (next.trimEnd - nextMinimum - next.trimStart) / nextRate
        )
        let applied = min(max(timelineDelta, minimumDelta), maximumDelta)
        guard abs(applied) > 0.000_001 else { return }
        registerUndoIfNeeded()
        clips[index - 1].trimEnd += applied * previousRate
        clips[index + 1].trimStart += applied * nextRate
        clips[index - 1].keyframes.trim(to: clips[index - 1].duration)
        clips[index + 1].keyframes.trim(to: clips[index + 1].duration)
        clips[index - 1].transitionDuration = min(
            clips[index - 1].transitionDuration,
            min(clips[index - 1].duration, clips[index].duration)
        )
        clips[index].transitionDuration = min(
            clips[index].transitionDuration,
            min(clips[index].duration, clips[index + 1].duration)
        )
        timelinePosition = min(max(0, timelinePosition + applied), totalDuration)
        finishPrecisionEdit()
    }

    func rippleTrimSelectedClipOut(by timelineDelta: TimeInterval) {
        guard precisionEditMessage == nil,
              let id = selectedClipID,
              let index = clips.firstIndex(where: { $0.id == id }) else { return }
        let oldDuration = clips[index].duration
        let oldEnd = timelineOffsetForClipIndex(index) + oldDuration
        let rate = TimeInterval(max(clips[index].averageSpeed, 0.001))
        let minimum = clips[index].trimStart + EditorClip.minimumSourceSpan(speed: clips[index].averageSpeed)
        let proposedEnd = clips[index].trimEnd + timelineDelta * rate
        let newEnd = min(max(proposedEnd, minimum), clips[index].originalDuration)
        guard abs(newEnd - clips[index].trimEnd) > 0.000_001 else { return }
        registerUndoIfNeeded()
        clips[index].trimEnd = newEnd
        clips[index].keyframes.trim(to: clips[index].duration)
        if index + 1 < clips.count {
            clips[index].transitionDuration = min(
                clips[index].transitionDuration,
                min(clips[index].duration, clips[index + 1].duration)
            )
        }
        let durationDelta = clips[index].duration - oldDuration
        if durationDelta < 0 {
            rippleDeleteTimedItems(from: oldEnd + durationDelta, to: oldEnd)
        } else {
            rippleInsertTimedItems(at: oldEnd, duration: durationDelta)
        }
        finishPrecisionEdit()
    }

    func toggleSelectedClipAudioLink() {
        guard let id = selectedClipID,
              let index = clips.firstIndex(where: { $0.id == id }),
              clips[index].isVideo, clips[index].speedRamp == nil else { return }
        registerUndoIfNeeded()
        if clips[index].isAudioLinked {
            clips[index].audioTrimStart = clips[index].trimStart
            clips[index].audioTrimEnd = clips[index].trimEnd
            clips[index].isAudioLinked = false
        } else {
            clips[index].audioTrimStart = nil
            clips[index].audioTrimEnd = nil
            clips[index].isAudioLinked = true
        }
        finishPrecisionEdit()
    }

    func adjustSelectedClipAudioStart(by timelineDelta: TimeInterval) {
        adjustSelectedEmbeddedAudioBoundary(isStart: true, by: timelineDelta)
    }

    func adjustSelectedClipAudioEnd(by timelineDelta: TimeInterval) {
        adjustSelectedEmbeddedAudioBoundary(isStart: false, by: timelineDelta)
    }

    private func adjustSelectedEmbeddedAudioBoundary(isStart: Bool, by timelineDelta: TimeInterval) {
        guard let id = selectedClipID,
              let index = clips.firstIndex(where: { $0.id == id }),
              clips[index].isVideo, clips[index].speedRamp == nil else { return }
        let original = clips[index]
        let rate = TimeInterval(max(original.averageSpeed, 0.001))
        var start = original.effectiveAudioTrimStart
        var end = original.effectiveAudioTrimEnd
        if isStart {
            start = min(max(0, start + timelineDelta * rate), end - 0.03)
        } else {
            end = max(min(original.originalDuration, end + timelineDelta * rate), start + 0.03)
        }
        guard abs(start - original.effectiveAudioTrimStart) > 0.000_001
                || abs(end - original.effectiveAudioTrimEnd) > 0.000_001 else { return }
        registerUndoIfNeeded()
        clips[index].isAudioLinked = false
        clips[index].audioTrimStart = start
        clips[index].audioTrimEnd = end
        finishPrecisionEdit()
    }

    func rippleInsertTimedItems(at boundary: TimeInterval, duration: TimeInterval) {
        guard duration > 0.000_001 else { return }
        for index in markers.indices where markers[index].time >= boundary - 0.000_001 {
            markers[index].time += duration
        }
        if let exportInPoint, exportInPoint >= boundary { self.exportInPoint = exportInPoint + duration }
        if let exportOutPoint, exportOutPoint >= boundary { self.exportOutPoint = exportOutPoint + duration }
        for index in textOverlays.indices {
            if textOverlays[index].startTime >= boundary - 0.000_001 {
                textOverlays[index].startTime += duration
                textOverlays[index].endTime += duration
                for wordIndex in textOverlays[index].captionWords.indices {
                    textOverlays[index].captionWords[wordIndex].startTime += duration
                    textOverlays[index].captionWords[wordIndex].endTime += duration
                }
            } else if textOverlays[index].endTime > boundary {
                textOverlays[index].endTime += duration
                for wordIndex in textOverlays[index].captionWords.indices {
                    if textOverlays[index].captionWords[wordIndex].startTime >= boundary {
                        textOverlays[index].captionWords[wordIndex].startTime += duration
                        textOverlays[index].captionWords[wordIndex].endTime += duration
                    } else if textOverlays[index].captionWords[wordIndex].endTime > boundary {
                        textOverlays[index].captionWords[wordIndex].endTime += duration
                    }
                }
            }
        }

        var insertedAudio: [EditorAudioClip] = []
        for var clip in audioClips {
            if clip.timelineStart >= boundary - 0.000_001 {
                clip.timelineStart += duration
                insertedAudio.append(clip)
            } else if clip.timelineEnd > boundary {
                let sourceTime = clip.trimStart + (boundary - clip.timelineStart)
                if let parts = clip.split(atSourceTime: sourceTime) {
                    insertedAudio.append(parts.left)
                    var tail = parts.right
                    tail.timelineStart += duration
                    insertedAudio.append(tail)
                    remapSequenceMembershipAfterSplit(
                        original: .audio(parts.left.id),
                        right: .audio(tail.id)
                    )
                } else {
                    insertedAudio.append(clip)
                }
            } else {
                insertedAudio.append(clip)
            }
        }
        audioClips = insertedAudio

        var insertedOverlays: [EditorOverlayClip] = []
        for var clip in overlayClips {
            if clip.timelineStart >= boundary - 0.000_001 {
                clip.timelineStart += duration
                insertedOverlays.append(clip)
            } else if clip.timelineEnd > boundary {
                let sourceTime = clip.sourceTime(forTimelineLocal: boundary - clip.timelineStart)
                if let parts = clip.split(atSourceTime: sourceTime) {
                    insertedOverlays.append(parts.left)
                    var tail = parts.right
                    tail.timelineStart += duration
                    insertedOverlays.append(tail)
                    remapSequenceMembershipAfterSplit(
                        original: .overlay(parts.left.id),
                        right: .overlay(tail.id)
                    )
                } else {
                    insertedOverlays.append(clip)
                }
            } else {
                insertedOverlays.append(clip)
            }
        }
        overlayClips = insertedOverlays

        for index in adjustmentLayers.indices {
            if adjustmentLayers[index].startTime >= boundary - 0.000_001 {
                adjustmentLayers[index].startTime += duration
                adjustmentLayers[index].endTime += duration
            } else if adjustmentLayers[index].endTime > boundary {
                adjustmentLayers[index].endTime += duration
            }
        }
    }

    func rippleDeleteTimedItems(from start: TimeInterval, to end: TimeInterval) {
        let lower = max(0, min(start, end))
        let upper = max(lower, max(start, end))
        let removedDuration = upper - lower
        guard removedDuration > 0.000_001 else { return }

        for index in markers.indices {
            if markers[index].time >= upper {
                markers[index].time -= removedDuration
            } else if markers[index].time > lower {
                markers[index].time = lower
            }
        }
        markers.sort { $0.time < $1.time }
        func remappedRangePoint(_ point: TimeInterval?) -> TimeInterval? {
            guard let point else { return nil }
            if point >= upper { return point - removedDuration }
            if point > lower { return lower }
            return point
        }
        exportInPoint = remappedRangePoint(exportInPoint)
        exportOutPoint = remappedRangePoint(exportOutPoint)

        var remappedText: [EditorTextOverlay] = []
        for var overlay in textOverlays {
            if overlay.endTime <= lower {
                remappedText.append(overlay)
            } else if overlay.startTime >= upper {
                overlay.startTime -= removedDuration
                overlay.endTime -= removedDuration
                for index in overlay.captionWords.indices {
                    overlay.captionWords[index].startTime -= removedDuration
                    overlay.captionWords[index].endTime -= removedDuration
                }
                remappedText.append(overlay)
            } else if overlay.isCaption {
                var words = overlay.captionWords.filter {
                    let midpoint = ($0.startTime + $0.endTime) / 2
                    return midpoint < lower || midpoint >= upper
                }
                for index in words.indices where words[index].startTime >= upper {
                    words[index].startTime -= removedDuration
                    words[index].endTime -= removedDuration
                }
                guard let first = words.first, let last = words.last else { continue }
                overlay.captionWords = words
                overlay.text = words.map(\.text).joined(separator: " ")
                overlay.startTime = first.startTime
                overlay.endTime = last.endTime
                remappedText.append(overlay)
            } else if overlay.startTime < lower, overlay.endTime > upper {
                overlay.endTime -= removedDuration
                remappedText.append(overlay)
            } else if overlay.startTime < lower {
                overlay.endTime = lower
                if overlay.duration > 0.03 { remappedText.append(overlay) }
            } else if overlay.endTime > upper {
                overlay.startTime = lower
                overlay.endTime -= removedDuration
                if overlay.duration > 0.03 { remappedText.append(overlay) }
            }
        }
        textOverlays = remappedText

        var remappedAudio: [EditorAudioClip] = []
        for var clip in audioClips {
            if clip.timelineEnd <= lower {
                remappedAudio.append(clip)
            } else if clip.timelineStart >= upper {
                clip.timelineStart -= removedDuration
                remappedAudio.append(clip)
            } else if clip.timelineStart < lower, clip.timelineEnd > upper {
                let sourceStart = clip.sourceTime(forTimelineLocal: lower - clip.timelineStart)
                let sourceEnd = clip.sourceTime(forTimelineLocal: upper - clip.timelineStart)
                if let splitAtStart = clip.split(atSourceTime: sourceStart),
                   let splitAtEnd = splitAtStart.right.split(atSourceTime: sourceEnd) {
                    remappedAudio.append(splitAtStart.left)
                    var tail = splitAtEnd.right
                    tail.timelineStart = lower
                    remappedAudio.append(tail)
                    remapSequenceMembershipAfterSplit(
                        original: .audio(splitAtStart.left.id),
                        right: .audio(tail.id)
                    )
                } else {
                    remappedAudio.append(clip)
                }
            } else if clip.timelineStart < lower {
                clip.trimEnd = clip.sourceTime(forTimelineLocal: lower - clip.timelineStart)
                if clip.duration >= EditorAudioClip.minimumSpan { remappedAudio.append(clip) }
            } else if clip.timelineEnd > upper {
                clip.trimStart = clip.sourceTime(forTimelineLocal: upper - clip.timelineStart)
                clip.timelineStart = lower
                if clip.duration >= EditorAudioClip.minimumSpan { remappedAudio.append(clip) }
            }
        }
        audioClips = remappedAudio

        var remappedOverlays: [EditorOverlayClip] = []
        for var clip in overlayClips {
            if clip.timelineEnd <= lower {
                remappedOverlays.append(clip)
            } else if clip.timelineStart >= upper {
                clip.timelineStart -= removedDuration
                remappedOverlays.append(clip)
            } else if clip.timelineStart < lower, clip.timelineEnd > upper {
                let sourceStart = clip.sourceTime(forTimelineLocal: lower - clip.timelineStart)
                let sourceEnd = clip.sourceTime(forTimelineLocal: upper - clip.timelineStart)
                if let splitAtStart = clip.split(atSourceTime: sourceStart),
                   let splitAtEnd = splitAtStart.right.split(atSourceTime: sourceEnd) {
                    remappedOverlays.append(splitAtStart.left)
                    var tail = splitAtEnd.right
                    tail.timelineStart = lower
                    remappedOverlays.append(tail)
                    remapSequenceMembershipAfterSplit(
                        original: .overlay(splitAtStart.left.id),
                        right: .overlay(tail.id)
                    )
                } else {
                    remappedOverlays.append(clip)
                }
            } else if clip.timelineStart < lower {
                clip.trimEnd = clip.sourceTime(forTimelineLocal: lower - clip.timelineStart)
                if clip.duration > 0.03 { remappedOverlays.append(clip) }
            } else if clip.timelineEnd > upper {
                clip.trimStart = clip.sourceTime(forTimelineLocal: upper - clip.timelineStart)
                clip.timelineStart = lower
                if clip.duration > 0.03 { remappedOverlays.append(clip) }
            }
        }
        overlayClips = remappedOverlays

        adjustmentLayers = adjustmentLayers.compactMap { original in
            var layer = original
            if layer.endTime <= lower { return layer }
            if layer.startTime >= upper {
                layer.startTime -= removedDuration
                layer.endTime -= removedDuration
            } else if layer.startTime < lower, layer.endTime > upper {
                layer.endTime -= removedDuration
            } else if layer.startTime < lower {
                layer.endTime = lower
            } else if layer.endTime > upper {
                layer.startTime = lower
                layer.endTime -= removedDuration
            } else {
                return nil
            }
            return layer.duration >= 0.1 ? layer : nil
        }
        pruneSequenceStructure()
    }

    private func finishPrecisionEdit() {
        pausePlaybackForEdit()
        timelinePosition = min(max(0, timelinePosition), totalDuration)
        normalizeExportRange()
        invalidateComposition()
        scheduleSave()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Task { await alignPlaybackToTimeline() }
    }

    func setTrim(clipID: UUID, trimStart: TimeInterval, trimEnd: TimeInterval) {
        if trimUndoSnapshot == nil {
            trimUndoSnapshot = currentSnapshot()
        }

        guard let idx = clips.firstIndex(where: { $0.id == clipID }) else { return }
        var clip = clips[idx]
        let minSpan = EditorClip.minimumSourceSpan(speed: clip.averageSpeed)
        let requestedStart = clip.playback.isReverse
            ? clip.originalDuration - trimEnd
            : trimStart
        let requestedEnd = clip.playback.isReverse
            ? clip.originalDuration - trimStart
            : trimEnd

        let start: TimeInterval
        let end: TimeInterval
        if clip.isPhoto {
            start = max(0, min(requestedStart, requestedEnd - minSpan))
            end = max(requestedEnd, start + minSpan)
            clip.originalDuration = end
        } else {
            start = min(max(0, requestedStart), clip.originalDuration - minSpan)
            end = max(min(clip.originalDuration, requestedEnd), start + minSpan)
        }

        var resolvedStart = start
        var resolvedEnd = end
        if let baseline = trimUndoSnapshot?.clips.first(where: { $0.id == clipID }) {
            let clipStart = timelineOffsetForClipIndex(idx)
            let speed = TimeInterval(max(clip.averageSpeed, 0.001))
            let snappedEnd = snappedTime(clipStart + (end - start) / speed, excluding: clipID)
            let snappedSpan = max(minSpan, (snappedEnd - clipStart) * speed)
            if abs(start - baseline.trimStart) > abs(end - baseline.trimEnd) {
                resolvedStart = max(0, end - snappedSpan)
            } else {
                resolvedEnd = min(clip.originalDuration, start + snappedSpan)
            }
        }
        clip.trimStart = resolvedStart
        clip.trimEnd = resolvedEnd
        clips[idx] = clip

        timelinePosition = min(timelinePosition, totalDuration)
        invalidateComposition()
    }

    func commitTrimEdit() {
        if let before = trimUndoSnapshot {
            undoManager.pushUndoState(before)
            trimUndoSnapshot = nil
            refreshUndoState()
            scheduleSave()
        }
        clearSnapGuide()
        invalidateComposition()
        Task { await alignPlaybackToTimeline() }
    }

    func splitAtPlayhead() {
        guard let info = clipAndLocalTime(at: timelinePosition) else { return }

        guard let parts = info.clip.split(atTimelineTime: info.localTime) else { return }

        registerUndoIfNeeded()

        pausePlaybackForEdit()

        let index = info.index
        clips.remove(at: index)
        clips.insert(contentsOf: [parts.left, parts.right], at: index)
        remapSequenceMembershipAfterSplit(
            original: .primary(info.clip.id),
            right: .primary(parts.left.id == info.clip.id ? parts.right.id : parts.left.id)
        )
        remapMotionAttachmentsAfterSplit(
            left: parts.left,
            right: parts.right,
            splitTime: timelinePosition
        )

        selectedClipID = parts.right.id
        timelinePosition = timelineOffsetForClipIndex(index) + parts.left.duration
        invalidateComposition()
        scheduleSave()

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task { await alignPlaybackToTimeline() }
    }

    func deleteSelectedClip() {
        guard let id = selectedClipID,
              let index = clips.firstIndex(where: { $0.id == id }),
              clips.count > 1 else { return }

        registerUndoIfNeeded()
        pausePlaybackForEdit()

        let clipStart = timelineOffsetForClipIndex(index)
        let removedDuration = clips[index].duration
        let clipEnd = clipStart + removedDuration

        clips.remove(at: index)
        selectedTimelineItems.remove(.primary(id))
        rippleDeleteTimedItems(from: clipStart, to: clipEnd)
        normalizeExportRange()
        for overlayIndex in textOverlays.indices
        where textOverlays[overlayIndex].attachedClipID == id {
            textOverlays[overlayIndex].attachedClipID = nil
            textOverlays[overlayIndex].attachedTrackID = nil
        }
        for overlayIndex in overlayClips.indices
        where overlayClips[overlayIndex].attachedClipID == id {
            overlayClips[overlayIndex].attachedClipID = nil
            overlayClips[overlayIndex].attachedTrackID = nil
        }
        pruneSequenceStructure()

        if timelinePosition >= clipEnd {
            timelinePosition -= removedDuration
        } else if timelinePosition > clipStart {
            timelinePosition = clipStart
        }
        timelinePosition = min(max(0, timelinePosition), totalDuration)

        if index < clips.count {
            selectedClipID = clips[index].id
        } else {
            selectedClipID = clips.last?.id
        }

        invalidateComposition()
        scheduleSave()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task { await alignPlaybackToTimeline() }
    }

    func duplicateSelectedClip() {
        guard let id = selectedClipID, let index = clips.firstIndex(where: { $0.id == id }) else { return }
        registerUndoIfNeeded()
        let source = clips[index]
        let copy = EditorClip(
            asset: source.asset, originalDuration: source.originalDuration,
            trimStart: source.trimStart, trimEnd: source.trimEnd, speed: source.speed,
            speedRamp: source.speedRamp,
            playback: source.playback,
            volume: source.volume,
            audioTrimStart: source.audioTrimStart,
            audioTrimEnd: source.audioTrimEnd,
            isAudioLinked: source.isAudioLinked,
            cropAspect: source.cropAspect, reframeMode: source.reframeMode,
            rotationQuarterTurns: source.rotationQuarterTurns, straightenDegrees: source.straightenDegrees,
            isFlippedHorizontally: source.isFlippedHorizontally,
            isFlippedVertically: source.isFlippedVertically, reframeScale: source.reframeScale,
            reframeXOffset: source.reframeXOffset, reframeYOffset: source.reframeYOffset,
            colorAdjustment: source.colorAdjustment, effects: source.effects,
            compositing: source.compositing,
            keyframes: source.keyframes,
            motionTracks: source.motionTracks.map { track in
                var copy = track
                copy.id = UUID()
                return copy
            },
            stabilization: source.stabilization,
            transitionKind: source.transitionKind,
            transitionDuration: source.transitionDuration
        )
        clips.insert(copy, at: index + 1)
        selectedClipID = copy.id
        timelinePosition = timelineOffsetForClipIndex(index + 1)
        invalidateComposition(); scheduleSave()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task { await alignPlaybackToTimeline() }
    }

    /// Replaces media while retaining every compatible non-destructive edit.
    func replaceSelectedClip(with media: MediaItem) {
        guard let id = selectedClipID, let index = clips.firstIndex(where: { $0.id == id }) else { return }
        registerUndoIfNeeded()
        let old = clips[index]
        let rawDuration = media.asset.mediaType == .video ? media.asset.duration : EditorClip.photoDefaultDuration
        let sourceSpan = min(old.trimEnd - old.trimStart, rawDuration)
        let start = min(old.trimStart, max(0, rawDuration - EditorClip.minimumSourceSpan(speed: old.averageSpeed)))
        let end = min(rawDuration, max(start + EditorClip.minimumSourceSpan(speed: old.averageSpeed), start + sourceSpan))
        clips[index] = EditorClip(
            id: old.id, asset: media.asset, originalDuration: rawDuration,
            trimStart: start, trimEnd: end, speed: old.speed,
            speedRamp: media.asset.mediaType == .video ? old.speedRamp : nil,
            volume: old.volume,
            cropAspect: old.cropAspect, reframeMode: old.reframeMode,
            rotationQuarterTurns: old.rotationQuarterTurns, straightenDegrees: old.straightenDegrees,
            isFlippedHorizontally: old.isFlippedHorizontally,
            isFlippedVertically: old.isFlippedVertically, reframeScale: old.reframeScale,
            reframeXOffset: old.reframeXOffset, reframeYOffset: old.reframeYOffset,
            colorAdjustment: old.colorAdjustment, effects: old.effects,
            compositing: old.compositing,
            keyframes: old.keyframes,
            transitionKind: old.transitionKind,
            transitionDuration: min(old.transitionDuration, old.duration)
        )
        timelinePosition = timelineOffsetForClipIndex(index)
        invalidateComposition(); scheduleSave()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task { await alignPlaybackToTimeline() }
    }

    func moveClip(from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceIndex != destinationIndex,
              clips.indices.contains(sourceIndex),
              clips.indices.contains(destinationIndex) else { return }

        registerUndoIfNeeded()
        pausePlaybackForEdit()

        let moved = clips.remove(at: sourceIndex)
        clips.insert(moved, at: destinationIndex)
        selectedClipID = moved.id
        timelinePosition = min(timelinePosition, totalDuration)

        invalidateComposition()
        scheduleSave()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Task { await alignPlaybackToTimeline() }
    }

    func insertClips(from media: [MediaItem], afterIndex: Int) {
        guard !media.isEmpty else { return }
        registerUndoIfNeeded()

        pausePlaybackForEdit()

        let newClips = media.map { EditorClip(asset: $0.asset) }
        let insertAt = min(max(0, afterIndex + 1), clips.count)
        clips.insert(contentsOf: newClips, at: insertAt)

        if let first = newClips.first {
            selectedClipID = first.id
        }

        timelinePosition = timelineOffsetForClipIndex(insertAt)
        invalidateComposition()
        scheduleSave()

        Task { await alignPlaybackToTimeline() }
    }
}
