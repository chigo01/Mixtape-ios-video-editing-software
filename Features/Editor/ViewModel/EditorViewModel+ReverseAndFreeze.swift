//
//  EditorViewModel+ReverseAndFreeze.swift
//  Mixtape
//

import SwiftUI
import UIKit
import AVFoundation
import Photos

extension EditorViewModel {
    var canReverseSelectedClip: Bool {
        let selectedVideo = selectedOverlayClip?.isVideo == true || selectedClip?.isVideo == true
        return selectedVideo && reverseGenerationProgress == nil
            && selectedVideoPlayback?.isFreezeFrame != true
    }

    var canFreezeSelectedClipAtPlayhead: Bool {
        if let overlay = selectedOverlayClip {
            return overlay.isVideo
                && !overlay.playback.isFreezeFrame
                && timelinePosition >= overlay.timelineStart - 0.000_001
                && timelinePosition <= overlay.timelineEnd + 0.000_001
        }
        guard let id = selectedClipID,
              let index = clips.firstIndex(where: { $0.id == id }),
              clips[index].isVideo,
              !clips[index].playback.isFreezeFrame else { return false }
        let start = timelineOffsetForClipIndex(index)
        return timelinePosition >= start - 0.000_001
            && timelinePosition <= start + clips[index].duration + 0.000_001
    }

    func toggleReverseSelectedClip(audioPolicy: EditorReverseAudioPolicy = .reverse) {
        if selectedOverlayClipID != nil {
            toggleReverseSelectedOverlay(audioPolicy: audioPolicy)
            return
        }
        guard let id = selectedClipID,
              let index = clips.firstIndex(where: { $0.id == id }),
              clips[index].isVideo, !clips[index].playback.isFreezeFrame else { return }

        if clips[index].playback.isReverse {
            registerUndoIfNeeded()
            clips[index].playback = .forward
            invalidateComposition()
            scheduleSave()
            Task { await alignPlaybackToTimeline() }
            return
        }
        if audioPolicy == .reverse && !clips[index].isAudioLinked {
            reverseGenerationErrorMessage = "Relink the clip audio before reversing it, or choose Mute Audio. Existing J/L handles cannot be reversed as one embedded range."
            return
        }

        cancelReverseGeneration()
        pausePlaybackForEdit()
        let source = clips[index]
        reverseGenerationClipID = source.id
        reverseGenerationProgress = 0
        reverseGenerationErrorMessage = nil
        reverseGenerationTask = Task { [weak self] in
            do {
                _ = try await EditorReverseMediaService.cachedURL(
                    for: source.asset,
                    sourceStart: source.trimStart,
                    sourceEnd: source.trimEnd,
                    audioPolicy: audioPolicy
                ) { progress in
                    Task { @MainActor [weak self] in
                        guard self?.reverseGenerationClipID == source.id else { return }
                        self?.reverseGenerationProgress = min(max(progress, 0), 1)
                    }
                }
                try Task.checkCancellation()
                guard let self else { return }
                guard let liveIndex = self.clips.firstIndex(where: { $0.id == source.id }),
                      self.clips[liveIndex].trimStart == source.trimStart,
                      self.clips[liveIndex].trimEnd == source.trimEnd else {
                    self.reverseGenerationProgress = nil
                    self.reverseGenerationClipID = nil
                    self.reverseGenerationTask = nil
                    return
                }
                self.registerUndoIfNeeded()
                self.clips[liveIndex].playback = .reverse(audio: audioPolicy)
                self.reverseGenerationProgress = nil
                self.reverseGenerationClipID = nil
                self.reverseGenerationTask = nil
                self.invalidateComposition()
                self.scheduleSave()
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                await self.alignPlaybackToTimeline()
            } catch is CancellationError {
                self?.reverseGenerationProgress = nil
                self?.reverseGenerationClipID = nil
                self?.reverseGenerationTask = nil
            } catch {
                self?.reverseGenerationErrorMessage = error.localizedDescription
                self?.reverseGenerationProgress = nil
                self?.reverseGenerationClipID = nil
                self?.reverseGenerationTask = nil
            }
        }
    }

    private func toggleReverseSelectedOverlay(audioPolicy: EditorReverseAudioPolicy) {
        guard let id = selectedOverlayClipID,
              let index = overlayClips.firstIndex(where: { $0.id == id }),
              overlayClips[index].isVideo,
              !overlayClips[index].playback.isFreezeFrame else { return }

        if overlayClips[index].playback.isReverse {
            registerUndoIfNeeded()
            overlayClips[index].playback = .forward
            invalidateComposition()
            scheduleSave()
            Task { await alignPlaybackToTimeline() }
            return
        }

        cancelReverseGeneration()
        pausePlaybackForEdit()
        let source = overlayClips[index]
        reverseGenerationClipID = source.id
        reverseGenerationProgress = 0
        reverseGenerationErrorMessage = nil
        reverseGenerationTask = Task { [weak self] in
            do {
                _ = try await EditorReverseMediaService.cachedURL(
                    for: source.asset,
                    sourceStart: source.trimStart,
                    sourceEnd: source.trimEnd,
                    audioPolicy: audioPolicy
                ) { progress in
                    Task { @MainActor [weak self] in
                        guard self?.reverseGenerationClipID == source.id else { return }
                        self?.reverseGenerationProgress = min(max(progress, 0), 1)
                    }
                }
                try Task.checkCancellation()
                guard let self else { return }
                guard let liveIndex = self.overlayClips.firstIndex(where: { $0.id == source.id }),
                      self.overlayClips[liveIndex].trimStart == source.trimStart,
                      self.overlayClips[liveIndex].trimEnd == source.trimEnd else {
                    self.reverseGenerationProgress = nil
                    self.reverseGenerationClipID = nil
                    self.reverseGenerationTask = nil
                    return
                }
                self.registerUndoIfNeeded()
                self.overlayClips[liveIndex].playback = .reverse(audio: audioPolicy)
                self.reverseGenerationProgress = nil
                self.reverseGenerationClipID = nil
                self.reverseGenerationTask = nil
                self.invalidateComposition()
                self.scheduleSave()
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                await self.alignPlaybackToTimeline()
            } catch is CancellationError {
                self?.reverseGenerationProgress = nil
                self?.reverseGenerationClipID = nil
                self?.reverseGenerationTask = nil
            } catch {
                self?.reverseGenerationErrorMessage = error.localizedDescription
                self?.reverseGenerationProgress = nil
                self?.reverseGenerationClipID = nil
                self?.reverseGenerationTask = nil
            }
        }
    }

    func cancelReverseGeneration() {
        guard let id = reverseGenerationClipID else { return }
        reverseGenerationTask?.cancel()
        reverseGenerationTask = nil
        reverseGenerationProgress = nil
        reverseGenerationClipID = nil
        let assetIdentifier = clips.first(where: { $0.id == id })?.asset.localIdentifier
            ?? overlayClips.first(where: { $0.id == id })?.asset.localIdentifier
            ?? ""
        Task { await EditorReverseMediaService.cancel(for: assetIdentifier) }
    }

    func insertFreezeFrame(
        duration requestedDuration: TimeInterval,
        audioPolicy: EditorFreezeAudioPolicy
    ) {
        if selectedOverlayClipID != nil {
            insertOverlayFreezeFrame(duration: requestedDuration, audioPolicy: audioPolicy)
            return
        }
        guard let id = selectedClipID,
              let index = clips.firstIndex(where: { $0.id == id }),
              clips[index].isVideo,
              !clips[index].playback.isFreezeFrame else { return }
        let source = clips[index]
        let clipStart = timelineOffsetForClipIndex(index)
        let localTime = min(max(0, timelinePosition - clipStart), source.duration)
        let duration = min(max(requestedDuration, 0.1), 10)
        let sourceTime = source.displayedSourceTime(atTimelineTime: localTime)
        let heldKeyframes = source.keyframes.held(at: localTime)
        let resolvedAudioPolicy: EditorFreezeAudioPolicy = source.playback.isReverse
            ? .mute
            : audioPolicy
        let freeze = EditorClip(
            asset: source.asset,
            originalDuration: max(source.originalDuration, duration),
            trimStart: 0,
            trimEnd: duration,
            playback: .freeze(sourceTime: sourceTime, audio: resolvedAudioPolicy),
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
            effects: source.effects.map { $0.held(at: localTime) },
            compositing: source.compositing,
            keyframes: heldKeyframes,
            motionTracks: [],
            stabilization: .disabled
        )

        registerUndoIfNeeded()
        pausePlaybackForEdit()
        rippleInsertTimedItems(at: timelinePosition, duration: duration)

        if let parts = source.split(atTimelineTime: localTime) {
            clips.remove(at: index)
            clips.insert(contentsOf: [parts.left, freeze, parts.right], at: index)
            remapSequenceMembershipForFreeze(
                originalID: source.id,
                displayedIDs: [parts.left.id, freeze.id, parts.right.id]
            )
            remapMotionAttachmentsAfterSplit(
                left: parts.left,
                right: parts.right,
                splitTime: timelinePosition + duration
            )
        } else if localTime <= source.duration / 2 {
            clips.insert(freeze, at: index)
            remapSequenceMembershipForFreeze(
                originalID: source.id,
                displayedIDs: [freeze.id, source.id]
            )
        } else {
            clips[index].transitionKind = .none
            clips[index].transitionDuration = 0
            var outgoingFreeze = freeze
            outgoingFreeze.transitionKind = source.transitionKind
            outgoingFreeze.transitionDuration = source.transitionDuration
            clips.insert(outgoingFreeze, at: index + 1)
            remapSequenceMembershipForFreeze(
                originalID: source.id,
                displayedIDs: [source.id, outgoingFreeze.id]
            )
        }

        selectedClipID = freeze.id
        timelinePosition = min(clipStart + localTime, totalDuration)
        normalizeExportRange()
        invalidateComposition()
        scheduleSave()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task { await alignPlaybackToTimeline() }
    }

    private func insertOverlayFreezeFrame(
        duration requestedDuration: TimeInterval,
        audioPolicy _: EditorFreezeAudioPolicy
    ) {
        guard let id = selectedOverlayClipID,
              let index = overlayClips.firstIndex(where: { $0.id == id }),
              overlayClips[index].isVideo,
              !overlayClips[index].playback.isFreezeFrame else { return }
        let source = overlayClips[index]
        let localTime = min(max(0, timelinePosition - source.timelineStart), source.duration)
        let insertionTime = source.timelineStart + localTime
        let duration = min(max(requestedDuration, 0.1), 10)
        let sourceTime = source.sourceTime(forTimelineLocal: localTime)
        let resolvedAudioPolicy = EditorFreezeAudioPolicy.mute
        let heldKeyframes = source.keyframes.held(at: localTime)
        let freeze = EditorOverlayClip(
            asset: source.asset,
            originalDuration: max(source.originalDuration, duration),
            trimStart: 0,
            trimEnd: duration,
            timelineStart: insertionTime,
            laneIndex: source.laneIndex,
            zIndex: source.zIndex,
            speed: 1,
            playback: .freeze(sourceTime: sourceTime, audio: resolvedAudioPolicy),
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
            effects: source.effects.map { $0.held(at: localTime) },
            compositing: source.compositing,
            keyframes: heldKeyframes,
            motionTracks: [],
            stabilization: .disabled,
            attachedClipID: source.attachedClipID,
            attachedTrackID: source.attachedTrackID,
            attachRotation: source.attachRotation,
            attachScale: source.attachScale
        )

        registerUndoIfNeeded()
        pausePlaybackForEdit()
        for otherIndex in overlayClips.indices
        where overlayClips[otherIndex].id != source.id
            && overlayClips[otherIndex].laneIndex == source.laneIndex
            && overlayClips[otherIndex].timelineStart >= insertionTime - 0.000_001 {
            overlayClips[otherIndex].timelineStart += duration
        }

        if let parts = source.split(atTimelineTime: localTime) {
            var right = parts.right
            right.timelineStart += duration
            overlayClips[index] = parts.left
            overlayClips.insert(contentsOf: [freeze, right], at: index + 1)
            remapSequenceMembershipForFreeze(
                original: .overlay(source.id),
                replacements: [.overlay(parts.left.id), .overlay(freeze.id), .overlay(right.id)]
            )
        } else if localTime <= source.duration / 2 {
            overlayClips[index].timelineStart += duration
            overlayClips.insert(freeze, at: index)
            remapSequenceMembershipForFreeze(
                original: .overlay(source.id),
                replacements: [.overlay(freeze.id), .overlay(source.id)]
            )
        } else {
            overlayClips.insert(freeze, at: index + 1)
            remapSequenceMembershipForFreeze(
                original: .overlay(source.id),
                replacements: [.overlay(source.id), .overlay(freeze.id)]
            )
        }

        selectedOverlayClipID = freeze.id
        timelinePosition = insertionTime
        normalizeExportRange()
        invalidateComposition()
        scheduleSave()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task { await alignPlaybackToTimeline() }
    }
}
