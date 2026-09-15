//
//  EditorViewModel+Copilot.swift
//  Mixtape
//

import SwiftUI
import UIKit
import AVFoundation
import Photos

extension EditorViewModel {
    // MARK: Copilot transactions

    var copilotRestriction: String? {
        guard !clips.isEmpty else {
            return "Add a clip before using MixPilot."
        }
        guard !isTranscribingCaptions, reverseGenerationProgress == nil, !isExporting,
              !isTrackingSubject, colorMaskTrackingDirection == nil,
              stabilizationAnalysisProgress == nil else {
            return "Wait for the current editor operation to finish before using MixPilot."
        }
        return nil
    }

    var copilotHighlightRestriction: String? {
        if let reason = copilotRestriction { return reason }
        guard clips.allSatisfy({ $0.isVideo }) else {
            return "Highlight reels need a spoken-video timeline. Photo montages can still use MixPilot for effects, keyframes, and text."
        }
        guard audioClips.isEmpty, overlayClips.isEmpty, graphicOverlays.isEmpty,
              adjustmentLayers.isEmpty, sequences.isEmpty, markers.isEmpty,
              textOverlays.allSatisfy({ $0.isCaption }) else {
            return "Highlight reels currently work on primary video clips and captions. Apply them before adding music, overlays, graphics, adjustment layers, sequences, or markers — or ask MixPilot for a timeline edit instead."
        }
        guard openingTransitionKind == .none, closingTransitionKind == .none,
              clips.allSatisfy({ $0.transitionKind == .none && $0.speedRamp == nil
                && !$0.playback.isReverse && $0.isAudioLinked }) else {
            return "Highlight reels currently need a simple spoken-video timeline. Use MixPilot for effects and keyframes on this project, or extract highlights before adding transitions, speed ramps, reverse playback, or unlinked dialogue."
        }
        return nil
    }

    var hasCopilotDraft: Bool { copilotPlan != nil || copilotEditPlan != nil }

    func revealPlayheadInTimeline() {
        timelineRevealNonce += 1
    }

    /// Ignore selection and playhead changes when checking whether a draft is stale.
    private func copilotComparableSnapshot() -> EditorTimelineSnapshot {
        var snapshot = currentSnapshot()
        snapshot.timelinePosition = 0
        snapshot.selectedClipID = nil
        snapshot.selectedTextOverlayID = nil
        snapshot.selectedGraphicOverlayID = nil
        snapshot.selectedAudioClipID = nil
        snapshot.selectedOverlayClipID = nil
        snapshot.selectedTimelineItems = []
        snapshot.selectedSequenceID = nil
        snapshot.activeSequenceID = nil
        return snapshot
    }

    func generateCopilot(prompt: String, target: Int, captions: Bool, locale: String?) {
        cancelCopilot()
        copilotError = nil
        guard copilotRestriction == nil else { copilotError = copilotRestriction; return }
        copilotRestoreTime = min(max(0, timelinePosition), max(totalDuration, 0))
        let source = copilotComparableSnapshot()
        let context = copilotTimelineContext(from: source)
        pausePlaybackForEdit()
        let jobID = UUID()
        copilotJobID = jobID
        isCopilotWorking = true
        copilotStatus = "Preparing on-device analysis…"
        copilotTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.copilotJobID == jobID {
                    self.isCopilotWorking = false
                    self.copilotTask = nil
                }
            }
            do {
                let kind = try await EditorCopilotService.interpret(
                    prompt: prompt, target: target, captions: captions, context: context,
                    progress: { [weak self] message in
                        guard self?.copilotJobID == jobID else { return }
                        self?.copilotStatus = message
                    })
                try Task.checkCancellation()
                guard self.copilotJobID == jobID else { return }
                switch kind {
                case .highlights(let duration, let wantsCaptions):
                    if let reason = self.copilotHighlightRestriction {
                        throw EditorCopilotError.message(reason)
                    }
                    let duration = try EditorCopilotPlan.resolvedDuration(
                        duration, sourceDuration: context.duration
                    )
                    let transcript = try await self.copilotTranscript(
                        source: source, locale: locale, jobID: jobID,
                        highlightSampleTarget: Double(duration),
                        allowsAudioOnlyFallback: true
                    )
                    let plan = try await EditorCopilotService.plan(
                        prompt: prompt, target: duration, captions: wantsCaptions,
                        transcript: transcript, duration: context.duration,
                        progress: { [weak self] message in
                            guard self?.copilotJobID == jobID else { return }
                            self?.copilotStatus = message
                        },
                        skipIntent: true
                    )
                    try Task.checkCancellation()
                    guard self.copilotJobID == jobID else { return }
                    guard self.copilotComparableSnapshot() == source else {
                        throw EditorCopilotError.message("The timeline changed during analysis. Generate a new draft.")
                    }
                    let draft = try self.makeCopilotDraft(source: source, plan: plan, transcript: transcript)
                    try await self.publishCopilotDraft(
                        source: source, draft: draft, plan: plan, editPlan: nil,
                        seekTo: 0, jobID: jobID,
                        readyMessage: transcript.isAudioOnly
                            ? "Draft ready from audio activity. Review the cuts before applying; captions need supported on-device speech recognition."
                            : "Draft ready. Review the cuts before applying."
                    )
                case .excerpt(let start, let end, let wantsCaptions):
                    if let reason = self.copilotHighlightRestriction {
                        throw EditorCopilotError.message(reason)
                    }
                    let plan = try EditorCopilotPlan.contiguousExcerpt(
                        start: start, end: end, sourceDuration: context.duration,
                        addsCaptions: wantsCaptions
                    )
                    var transcript = EditorCaptionTranscriptResult(words: [], localeIdentifier: locale ?? "")
                    if wantsCaptions {
                        transcript = try await self.copilotTranscript(
                            source: source, locale: locale, jobID: jobID,
                            timeRange: start...end
                        )
                    }
                    let draft = try self.makeCopilotDraft(source: source, plan: plan, transcript: transcript)
                    try await self.publishCopilotDraft(
                        source: source, draft: draft, plan: plan, editPlan: nil,
                        seekTo: 0, jobID: jobID,
                        readyMessage: "Draft ready. Review the excerpt before applying."
                    )
                case .edits:
                    let editPlan = try await EditorCopilotService.planEdits(
                        prompt: prompt, context: context,
                        progress: { [weak self] message in
                            guard self?.copilotJobID == jobID else { return }
                            self?.copilotStatus = message
                        })
                    try Task.checkCancellation()
                    guard self.copilotJobID == jobID else { return }
                    guard self.copilotComparableSnapshot() == source else {
                        throw EditorCopilotError.message("The timeline changed during analysis. Generate a new draft.")
                    }
                    var transcript: EditorCaptionTranscriptResult?
                    if editPlan.needsTranscript {
                        transcript = try await self.copilotTranscript(
                            source: source, locale: locale, jobID: jobID
                        )
                    }
                    let draft = try self.makeCopilotEditDraft(
                        source: source, plan: editPlan, transcript: transcript
                    )
                    try await self.publishCopilotDraft(
                        source: source, draft: draft, plan: nil, editPlan: editPlan,
                        seekTo: self.copilotRestoreTime,
                        jobID: jobID,
                        readyMessage: "Draft ready. Review the changes before applying."
                    )
                case .unsupported(let message):
                    throw EditorCopilotError.message(message)
                }
            } catch is CancellationError {
                if self.copilotJobID == jobID { self.discardCopilotDraft() }
            } catch {
                guard self.copilotJobID == jobID else { return }
                self.discardCopilotDraft()
                self.copilotStatus = nil
                self.copilotError = error.localizedDescription
            }
        }
    }

    private func copilotTimelineContext(from source: EditorTimelineSnapshot) -> EditorCopilotTimelineContext {
        let duration = max(source.clips.reduce(0) { $0 + $1.duration }, 0.001)
        var offset = 0.0
        var lines: [String] = []
        for (index, clip) in source.clips.enumerated() {
            let end = offset + clip.duration
            lines.append(
                "Clip \(index + 1): \(String(format: "%.2f", offset))–\(String(format: "%.2f", end))s \(clip.isVideo ? "video" : "photo")"
            )
            offset = end
        }
        let selected: String
        var selectedPrimaryStart: Double?
        if let id = source.selectedClipID, let index = source.clips.firstIndex(where: { $0.id == id }) {
            let start = source.clips.prefix(index).reduce(0) { $0 + $1.duration }
            selectedPrimaryStart = start
            selected = "primary clip \(index + 1) \(String(format: "%.2f", start))–\(String(format: "%.2f", start + source.clips[index].duration))s"
        } else if source.selectedAudioClipID != nil {
            selected = "separate audio track (primary-clip operations cannot edit this target)"
        } else if source.selectedOverlayClipID != nil {
            selected = "media overlay (primary-clip operations cannot edit this target)"
        } else if source.selectedTextOverlayID != nil || source.selectedGraphicOverlayID != nil {
            selected = "existing text or graphic overlay (addText would create new text, not edit this target)"
        } else {
            selected = "none"
        }
        return EditorCopilotTimelineContext(
            duration: duration,
            playhead: min(max(0, timelinePosition), duration),
            clipSummary: lines.joined(separator: "\n"),
            selectedRange: selected,
            selectedPrimaryStart: selectedPrimaryStart,
            hasMusic: !source.audioClips.isEmpty,
            hasCaptions: source.textOverlays.contains(where: \.isCaption)
        )
    }

    func copilotTranscript(
        source: EditorTimelineSnapshot, locale: String?, jobID: UUID,
        timeRange: ClosedRange<TimeInterval>? = nil,
        highlightSampleTarget: TimeInterval? = nil,
        allowsAudioOnlyFallback: Bool = false
    ) async throws -> EditorCaptionTranscriptResult {
        let canReuseFullTranscript = timeRange == nil
            && copilotTranscriptSource == source
            && copilotTranscriptLocale == locale
        if canReuseFullTranscript, let cached = copilotTranscript,
           allowsAudioOnlyFallback || !cached.isAudioOnly {
            return cached
        }
        do {
            let transcript = try await EditorCaptionService.transcribe(
                clips: source.clips, audioClips: [], overlayClips: [],
                audioTrackSettings: [:], masterVolume: 1,
                requestedLocaleIdentifier: locale, source: .video,
                requiresOnDeviceRecognition: true,
                allowsAudioOnlyFallback: allowsAudioOnlyFallback,
                timeRange: timeRange,
                highlightSampleTarget: highlightSampleTarget,
                onProgress: { [weak self] message in
                    guard self?.copilotJobID == jobID else { return }
                    self?.copilotStatus = message
                })
            try Task.checkCancellation()
            guard copilotJobID == jobID else {
                throw CancellationError()
            }
            if timeRange == nil, !transcript.isAudioOnly {
                copilotTranscript = transcript
                copilotTranscriptSource = source
                copilotTranscriptLocale = locale
            }
            return transcript
        } catch let error as EditorCaptionError {
            switch error {
            case .noSpeech:
                throw EditorCopilotError.message(
                    "No speech was recognized on this device. Choose the spoken language. For a long webinar, MixPilot samples spoken sections and does not upload audio."
                )
            case .silentAudio, .noAudioTrack:
                throw EditorCopilotError.message(
                    "No usable speech audio was found on the video track. Check that the webinar has embedded dialogue."
                )
            default:
                throw EditorCopilotError.message(error.localizedDescription)
            }
        }
    }

    private func publishCopilotDraft(
        source: EditorTimelineSnapshot,
        draft: EditorTimelineSnapshot,
        plan: EditorCopilotPlan?,
        editPlan: EditorCopilotEditPlan?,
        seekTo: TimeInterval,
        jobID: UUID,
        readyMessage: String
    ) async throws {
        let preview = EditorViewModel(project: makeProject())
        preview.isCopilotPreview = true
        preview.applySnapshot(draft)
        preview.timelinePosition = min(max(0, seekTo), preview.totalDuration)
        copilotPreview = preview
        copilotSource = source
        copilotDraft = draft
        copilotPlan = plan
        copilotEditPlan = editPlan
        copilotStatus = "Preparing preview…"
        await preview.alignPlaybackToTimeline()
        try Task.checkCancellation()
        guard copilotJobID == jobID else { throw CancellationError() }
        guard preview.player?.currentItem != nil else {
            throw EditorCopilotError.message("The preview could not load. Check that the source videos are available and try again.")
        }
        copilotStatus = readyMessage
    }

    private func makeCopilotDraft(source: EditorTimelineSnapshot, plan: EditorCopilotPlan,
                                  transcript: EditorCaptionTranscriptResult) throws -> EditorTimelineSnapshot {
        var draft = source
        var assembled: [EditorClip] = []
        var words: [EditorCaptionWord] = []
        for slice in try plan.clipSlices(durations: source.clips.map(\.duration)) {
            var piece = source.clips[slice.clipIndex]
            if slice.end < piece.duration - 0.000_001 {
                guard let split = piece.split(atTimelineTime: slice.end) else {
                    throw EditorCopilotError.message("A cut is too close to a clip boundary. Try another selection.")
                }
                piece = split.left
            }
            if slice.start > 0.000_001 {
                guard let split = piece.split(atTimelineTime: slice.start) else {
                    throw EditorCopilotError.message("A selected section is too short to cut safely. Try another selection.")
                }
                piece = split.right
            }
            assembled.append(piece)
        }
        for word in transcript.words {
            guard let range = plan.mappedWordRange(start: word.startTime, end: word.endTime) else { continue }
            words.append(EditorCaptionWord(text: word.text, startTime: range.lowerBound,
                endTime: range.upperBound, confidence: word.confidence))
        }
        guard !assembled.isEmpty, Set(assembled.map(\.id)).count == assembled.count,
              abs(assembled.reduce(0) { $0 + $1.duration } - plan.duration) < 0.05 else {
            throw EditorCopilotError.message("The selected ranges could not be assembled accurately. The timeline was not changed.")
        }
        draft.clips = assembled
        draft.textOverlays = plan.addsCaptions ? EditorCaptionService.makeCaptionOverlays(
            from: .init(words: words, localeIdentifier: transcript.localeIdentifier)) : []
        draft.exportInPoint = nil
        draft.exportOutPoint = nil
        return draft
    }

    private func makeCopilotEditDraft(
        source: EditorTimelineSnapshot,
        plan: EditorCopilotEditPlan,
        transcript: EditorCaptionTranscriptResult?
    ) throws -> EditorTimelineSnapshot {
        var draft = source
        for operation in plan.operations {
            try applyCopilotEdit(operation, to: &draft, transcript: transcript)
        }
        let restore = copilotRestoreTime
        let timeline = draft.clips.reduce(0) { $0 + $1.duration }
        draft.timelinePosition = min(max(0, restore), max(timeline, 0))
        return draft
    }

    private func applyCopilotEdit(
        _ operation: EditorCopilotEditOperation,
        to draft: inout EditorTimelineSnapshot,
        transcript: EditorCaptionTranscriptResult?
    ) throws {
        switch operation.kind {
        case .addEffect:
            guard let name = operation.effect,
                  let kind = EditorVisualEffectKind(rawValue: name) else {
                throw EditorCopilotError.message("That effect is not available. No changes were applied.")
            }
            var effect = EditorVisualEffect(kind: kind, amount: operation.amount)
            effect.amountKeyframes = copilotAmountTrack(
                duration: operation.duration,
                amount: operation.amount,
                fadeIn: operation.fadeIn,
                fadeOut: operation.fadeOut
            )
            let layer = EditorAdjustmentLayer(
                title: kind.title,
                startTime: operation.start,
                endTime: operation.end,
                zIndex: (draft.adjustmentLayers.map(\.zIndex).max() ?? -1) + 1,
                effects: [effect]
            )
            draft.adjustmentLayers.append(layer)
        case .addKeyframe:
            guard let name = operation.property,
                  let property = EditorKeyframeProperty(rawValue: name) else {
                throw EditorCopilotError.message("That keyframe property is not available. No changes were applied.")
            }
            try upsertCopilotClipKeyframes(
                property: property,
                start: operation.start,
                end: operation.end,
                amount: operation.amount,
                fadeIn: operation.fadeIn,
                fadeOut: operation.fadeOut,
                in: &draft.clips
            )
        case .setVolume:
            if operation.fadeIn || operation.fadeOut {
                try upsertCopilotClipKeyframes(
                    property: .volume,
                    start: operation.start,
                    end: max(operation.end, operation.start + 1),
                    amount: operation.amount,
                    fadeIn: operation.fadeIn,
                    fadeOut: operation.fadeOut,
                    in: &draft.clips
                )
            } else if let index = copilotClipIndex(at: operation.start, clips: draft.clips)?.index {
                draft.clips[index].volume = Float(min(max(operation.amount, 0), 1))
            } else {
                throw EditorCopilotError.message("No clip is available at that time to change volume.")
            }
        case .addText:
            let overlay = EditorTextOverlay(
                text: operation.text ?? "Text",
                startTime: operation.start,
                endTime: operation.end,
                opacity: operation.amount
            )
            draft.textOverlays.append(overlay)
        case .addMarker:
            let name = operation.text?.trimmingCharacters(in: .whitespacesAndNewlines)
            var number = 1
            let existing = Set(draft.markers.map(\.name))
            var resolved = (name?.isEmpty == false) ? name! : "MixPilot"
            if existing.contains(resolved) {
                while existing.contains("\(resolved) \(number)") { number += 1 }
                resolved = "\(resolved) \(number)"
            }
            draft.markers.append(EditorTimelineMarker(name: resolved, time: operation.start))
            draft.markers.sort { $0.time < $1.time }
        case .addCaptions:
            guard let transcript else {
                throw EditorCopilotError.message("Captions need an on-device transcript. Choose a spoken language and try again.")
            }
            let captions = EditorCaptionService.makeCaptionOverlays(from: transcript)
            draft.textOverlays = draft.textOverlays.filter { !$0.isCaption } + captions
        case .addTransition:
            try applyCopilotTransition(
                at: operation.start,
                kindName: operation.effect ?? "fade",
                duration: operation.amount,
                to: &draft
            )
        case .split:
            try applyCopilotSplit(at: operation.start, to: &draft)
        case .setSpeed:
            try mutateCopilotClip(at: operation.start, in: &draft) { clip in
                clip.speed = Float(min(max(operation.amount, 0.25), 3))
                clip.speedRamp = nil
            }
        case .crop:
            let aspect = EditorCropAspect(rawValue: operation.effect ?? "vertical") ?? .vertical
            try mutateCopilotClip(at: operation.start, in: &draft) { clip in
                clip.cropAspect = aspect
            }
        case .rotate:
            let turns = Int(operation.amount)
            try mutateCopilotClip(at: operation.start, in: &draft) { clip in
                clip.rotationQuarterTurns = (clip.rotationQuarterTurns + turns) % 4
            }
        case .flip:
            let vertical = operation.text == "vertical"
            try mutateCopilotClip(at: operation.start, in: &draft) { clip in
                if vertical { clip.isFlippedVertically.toggle() }
                else { clip.isFlippedHorizontally.toggle() }
            }
        case .setFilter:
            let preset = EditorFilterPreset(rawValue: operation.effect ?? "cinematic") ?? .cinematic
            try mutateCopilotClip(at: operation.start, in: &draft) { clip in
                clip.colorAdjustment.preset = preset
                clip.colorAdjustment.presetIntensity = min(max(operation.amount, 0.1), 1)
            }
        }
    }

    private func mutateCopilotClip(
        at time: Double,
        in draft: inout EditorTimelineSnapshot,
        _ body: (inout EditorClip) -> Void
    ) throws {
        guard let hit = copilotClipIndex(at: time, clips: draft.clips) else {
            throw EditorCopilotError.message("No clip is available at the playhead for that edit.")
        }
        body(&draft.clips[hit.index])
    }

    private func applyCopilotSplit(at time: Double, to draft: inout EditorTimelineSnapshot) throws {
        guard let hit = copilotClipIndex(at: time, clips: draft.clips) else {
            throw EditorCopilotError.message("No clip is available at the playhead to split.")
        }
        let atStart = hit.local <= 0.12
        let atEnd = hit.duration - hit.local <= 0.12
        if atStart || atEnd {
            let alreadyCut = (atStart && hit.index > 0)
                || (atEnd && hit.index < draft.clips.count - 1)
            if alreadyCut { return }
            throw EditorCopilotError.message("The playhead is too close to a clip edge to split. Nudge it and try again.")
        }
        guard let parts = draft.clips[hit.index].split(atTimelineTime: hit.local) else {
            throw EditorCopilotError.message("That cut is too close to a clip boundary to split safely.")
        }
        draft.clips.replaceSubrange(hit.index...hit.index, with: [parts.left, parts.right])
    }

    private func applyCopilotTransition(
        at time: Double,
        kindName: String,
        duration: Double,
        to draft: inout EditorTimelineSnapshot
    ) throws {
        let kind = EditorTransitionKind(rawValue: kindName) ?? .fade
        let fade = min(max(duration, 0.1), 2)
        let timeline = draft.clips.reduce(0) { $0 + $1.duration }
        if time <= 0.12 || draft.clips.count == 1 && time < 0.25 {
            guard let first = draft.clips.first, first.duration > 0.3 else {
                throw EditorCopilotError.message("There is not enough footage for an opening fade.")
            }
            draft.openingTransitionKind = kind
            draft.openingTransitionDuration = min(fade, min(2, first.duration))
            return
        }
        if time >= timeline - 0.12 {
            guard let last = draft.clips.last, last.duration > 0.3 else {
                throw EditorCopilotError.message("There is not enough footage for a closing fade.")
            }
            draft.closingTransitionKind = kind
            draft.closingTransitionDuration = min(fade, min(2, last.duration))
            return
        }
        guard let hit = copilotClipIndex(at: time, clips: draft.clips) else {
            throw EditorCopilotError.message("No clip is available at the playhead for a transition.")
        }
        let boundaryIndex: Int
        if hit.local <= 0.12, hit.index > 0 {
            boundaryIndex = hit.index - 1
        } else if hit.duration - hit.local <= 0.12, hit.index < draft.clips.count - 1 {
            boundaryIndex = hit.index
        } else {
            guard let parts = draft.clips[hit.index].split(atTimelineTime: hit.local) else {
                throw EditorCopilotError.message("The playhead is too close to a clip edge to add a fade. Nudge it and try again.")
            }
            var left = parts.left
            let right = parts.right
            let maxDuration = min(2, min(left.duration, right.duration))
            guard maxDuration >= 0.1 else {
                throw EditorCopilotError.message("There is not enough clip on both sides of the playhead for a fade.")
            }
            left.transitionKind = kind
            left.transitionDuration = min(fade, maxDuration)
            draft.clips.replaceSubrange(hit.index...hit.index, with: [left, right])
            return
        }
        let maxDuration = min(
            2,
            min(draft.clips[boundaryIndex].duration, draft.clips[boundaryIndex + 1].duration)
        )
        guard maxDuration >= 0.1 else {
            throw EditorCopilotError.message("There is not enough clip on both sides of that cut for a fade.")
        }
        draft.clips[boundaryIndex].transitionKind = kind
        draft.clips[boundaryIndex].transitionDuration = min(fade, maxDuration)
    }

    private func upsertCopilotClipKeyframes(
        property: EditorKeyframeProperty,
        start: Double,
        end: Double,
        amount: Double,
        fadeIn: Bool,
        fadeOut: Bool,
        in clips: inout [EditorClip]
    ) throws {
        guard let hit = copilotClipIndex(at: start, clips: clips) else {
            throw EditorCopilotError.message("No clip is available at that time to keyframe.")
        }
        var tracks = clips[hit.index].keyframes
        var track = tracks.track(for: property)
        let localStart = hit.local
        let localEnd = min(hit.duration, localStart + max(0, end - start))
        track.applyCopilotAnimation(
            start: localStart, end: localEnd, amount: amount,
            fadeIn: fadeIn, fadeOut: fadeOut,
            defaultValue: property == .volume ? Double(clips[hit.index].volume) : property.neutralValue
        )
        tracks.replace(track)
        clips[hit.index].keyframes = tracks
    }

    private func copilotAmountTrack(
        duration: Double, amount: Double, fadeIn: Bool, fadeOut: Bool
    ) -> EditorKeyframeTrack {
        var track = EditorKeyframeTrack(property: .effectAmount)
        let duration = max(duration, 0.45)
        let window = min(0.4, max(0.12, duration / 3))
        if fadeIn {
            _ = track.upsert(at: 0, value: 0, curve: .init(preset: .easeInOut))
            _ = track.upsert(at: window, value: amount, curve: .init(preset: .easeInOut))
        } else {
            _ = track.upsert(at: 0, value: amount, curve: .init(preset: .easeInOut))
        }
        if fadeOut {
            _ = track.upsert(at: max(duration - window, 0), value: amount, curve: .init(preset: .easeInOut))
            _ = track.upsert(at: duration, value: 0, curve: .init(preset: .easeInOut))
        } else {
            _ = track.upsert(at: duration, value: amount, curve: .init(preset: .easeInOut))
        }
        return track
    }

    private func copilotClipIndex(
        at time: Double, clips: [EditorClip]
    ) -> (index: Int, local: Double, duration: Double)? {
        guard !clips.isEmpty else { return nil }
        var offset = 0.0
        let clamped = max(0, time)
        for (index, clip) in clips.enumerated() {
            let duration = clip.duration
            if duration <= 0 { continue }
            if clamped < offset + duration - 0.000_001 || index == clips.count - 1 {
                return (index, min(max(0, clamped - offset), duration), duration)
            }
            offset += duration
        }
        return nil
    }

    @discardableResult
    func applyCopilotDraft() -> Bool {
        guard !isCopilotWorking, let source = copilotSource, let draft = copilotDraft else { return false }
        let highlightApply = copilotPlan != nil
        guard copilotComparableSnapshot() == source, copilotRestriction == nil else {
            copilotError = "The timeline changed after this preview. Generate a new draft before applying."
            return false
        }
        if highlightApply, copilotHighlightRestriction != nil {
            copilotError = copilotHighlightRestriction
            return false
        }
        pausePlaybackForEdit()
        registerUndoIfNeeded()
        let restoreTime = highlightApply ? 0 : copilotRestoreTime
        applySnapshot(draft)
        timelinePosition = min(max(0, restoreTime), totalDuration)
        revealPlayheadInTimeline()
        selectedTool = nil
        isMultiSelectMode = false
        scheduleSave()
        Task { await alignPlaybackToTimeline() }
        let appliedEdits = copilotEditPlan != nil
        discardCopilotDraft()
        copilotStatus = appliedEdits
            ? "Edits applied. Undo restores the previous timeline."
            : "Highlights applied. Undo restores the complete previous timeline."
        return true
    }

    func cancelCopilot() {
        copilotJobID = nil
        copilotTask?.cancel()
        copilotTask = nil
        isCopilotWorking = false
        copilotStatus = nil
        discardCopilotDraft()
    }

    private func discardCopilotDraft() {
        if let preview = copilotPreview {
            preview.isCopilotPreviewDiscarded = true
            preview.stopPlaybackTicking()
            preview.removeEndObserver()
            preview.player?.pause()
            preview.player = nil
            preview.isPlaying = false
        }
        copilotPreview = nil
        copilotPlan = nil
        copilotEditPlan = nil
        copilotSource = nil
        copilotDraft = nil
    }
}
