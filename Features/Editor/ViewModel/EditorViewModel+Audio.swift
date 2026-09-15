//
//  EditorViewModel+Audio.swift
//  Mixtape
//

import SwiftUI
import UIKit
import AVFoundation
import Photos

extension EditorViewModel {
    // MARK: Audio Clips

    enum AudioInsertion {
        /// Adds a brand-new audio track (lane) positioned at the current playhead, so it can
        /// sit alongside — and overlap — whatever is already on the timeline. This is how you
        /// add a second piece of audio "at that particular playhead."
        case newTrackAtPlayhead
        /// Appends immediately after an existing clip, on that clip's own lane (CapCut-style
        /// "extend this track" via the insert button between two clips in the same lane).
        case afterClip(UUID)
    }

    /// Resolves where a newly-added audio clip should sit: which lane, and at what timeline
    /// second. Shared by user-imported files (`loadAudioClip`) and library items
    /// (`insertAudioLibraryItem`) so both sources place clips identically.
    private func resolveAudioInsertion(_ insertion: AudioInsertion) -> (timelineStart: TimeInterval, laneIndex: Int) {
        switch insertion {
        case .newTrackAtPlayhead:
            return (timelinePosition, (audioClips.map(\.laneIndex).max() ?? -1) + 1)
        case .afterClip(let clipID):
            if let source = audioClips.first(where: { $0.id == clipID }) {
                return (source.timelineEnd, source.laneIndex)
            }
            return (timelinePosition, (audioClips.map(\.laneIndex).max() ?? -1) + 1)
        }
    }

    func loadAudioClip(from sourceURL: URL, insertion: AudioInsertion = .newTrackAtPlayhead) {
        // Some document providers return an already-readable local URL and correctly
        // report `false` here because no new security scope was needed. Treating that
        // result as a failure made otherwise valid imports disappear silently.
        let didStartSecurityScope = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didStartSecurityScope { sourceURL.stopAccessingSecurityScopedResource() }
        }

        let fm = FileManager.default
        let audioDir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("MixtapeAudio", isDirectory: true)
        try? fm.createDirectory(at: audioDir, withIntermediateDirectories: true)
        let dest = audioDir.appendingPathComponent("\(UUID().uuidString)-\(sourceURL.lastPathComponent)")
        try? fm.removeItem(at: dest)
        do {
            try fm.copyItem(at: sourceURL, to: dest)
        } catch {
            return
        }

        let avAsset = AVURLAsset(url: dest)
        Task {
            let assetDuration = (try? await avAsset.load(.duration))?.seconds
            let audioFileDuration: TimeInterval? = {
                guard let file = try? AVAudioFile(forReading: dest),
                      file.processingFormat.sampleRate > 0 else { return nil }
                return Double(file.length) / file.processingFormat.sampleRate
            }()
            guard let originalDuration = [assetDuration, audioFileDuration]
                .compactMap({ $0 })
                .first(where: { $0.isFinite && $0 >= EditorAudioClip.minimumSpan }) else {
                try? fm.removeItem(at: dest)
                return
            }

            await MainActor.run {
                registerUndoIfNeeded()
                let title = sourceURL.deletingPathExtension().lastPathComponent
                let (timelineStart, laneIndex) = resolveAudioInsertion(insertion)

                let clip = EditorAudioClip(
                    title: title,
                    fileURL: dest,
                    originalDuration: originalDuration,
                    timelineStart: timelineStart,
                    laneIndex: laneIndex
                )
                audioClips.append(clip)

                selectAudioClip(clip.id)
                invalidateComposition()
                scheduleSave()
                Task { await alignPlaybackToTimeline() }
            }
        }
    }

    /// Inserts a sound/music library item as a normal timeline clip. Remote downloads are copied
    /// from the bounded shared cache into durable project storage before the project references
    /// them, so cache eviction cannot silently remove audio from a saved edit.
    func insertAudioLibraryItem(
        title: String,
        fileURL: URL,
        duration: TimeInterval,
        attribution: String? = nil,
        insertion: AudioInsertion = .newTrackAtPlayhead
    ) throws {
        let storedURL = try durableAudioLibraryURL(for: fileURL)
        registerUndoIfNeeded()
        let (timelineStart, laneIndex) = resolveAudioInsertion(insertion)

        let clip = EditorAudioClip(
            title: title,
            fileURL: storedURL,
            originalDuration: duration,
            timelineStart: timelineStart,
            laneIndex: laneIndex,
            attribution: attribution
        )
        audioClips.append(clip)

        selectAudioClip(clip.id)
        invalidateComposition()
        scheduleSave()
        Task { await alignPlaybackToTimeline() }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func durableAudioLibraryURL(for sourceURL: URL) throws -> URL {
        guard !sourceURL.path.hasPrefix(Bundle.main.bundlePath) else { return sourceURL }
        let fm = FileManager.default
        guard let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw EditorAudioLibraryError.downloadFailed
        }
        let directory = base.appendingPathComponent("MixtapeAudio", isDirectory: true)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileExtension = sourceURL.pathExtension.isEmpty ? "audio" : sourceURL.pathExtension
        let destination = directory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(fileExtension)
        try fm.copyItem(at: sourceURL, to: destination)
        return destination
    }

    /// Inserts an M4A already exported into Mixtape's durable audio directory.
    func insertExtractedVideoAudio(
        fileURL: URL,
        duration: TimeInterval,
        insertion: AudioInsertion = .newTrackAtPlayhead
    ) {
        registerUndoIfNeeded()
        let (timelineStart, laneIndex) = resolveAudioInsertion(insertion)
        let existingCount = audioClips.filter { $0.title.hasPrefix("Extracted Audio") }.count
        let clip = EditorAudioClip(
            title: "Extracted Audio \(existingCount + 1)",
            fileURL: fileURL,
            originalDuration: duration,
            timelineStart: timelineStart,
            laneIndex: laneIndex
        )
        audioClips.append(clip)
        selectAudioClip(clip.id)
        invalidateComposition()
        scheduleSave()
        Task { await alignPlaybackToTimeline() }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    /// Inserts a finished `VoiceoverRecorderService` take (Priority 14) as a normal timeline
    /// clip. The file already lives in `MixtapeAudio/` (the recorder writes there directly), so
    /// unlike `loadAudioClip` this needs no security-scoped copy step. From here on the take is
    /// indistinguishable from an imported or library clip.
    func insertRecordedVoiceover(
        fileURL: URL,
        duration: TimeInterval,
        insertion: AudioInsertion = .newTrackAtPlayhead
    ) {
        registerUndoIfNeeded()
        let (timelineStart, laneIndex) = resolveAudioInsertion(insertion)
        let existingVoiceovers = audioClips.filter { $0.title.hasPrefix("Voiceover") }.count

        let clip = EditorAudioClip(
            title: "Voiceover \(existingVoiceovers + 1)",
            fileURL: fileURL,
            originalDuration: duration,
            timelineStart: timelineStart,
            laneIndex: laneIndex
        )
        audioClips.append(clip)

        selectAudioClip(clip.id)
        invalidateComposition()
        scheduleSave()
        Task { await alignPlaybackToTimeline() }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Splices a punch-in take (Priority 14 follow-up) into an existing audio clip in place.
    /// Reuses `EditorAudioClip.split(atSourceTime:)` twice — once at the in-point, once at the
    /// out-point of the resulting remainder — the same machinery `splitAtPlayhead()` uses for
    /// video, so fades, keyframes, and minimum-span rules all fall out for free rather than
    /// being re-derived here. Whatever the original clip had after the out-point is kept but
    /// reflowed to start right after the new recording — not time-stretched to fit — since
    /// nothing played back while recording to time it against (see the Priority 14 writeup for
    /// why punch-in ships without live monitoring).
    func punchInRecordedTake(clipID: UUID, start: TimeInterval, end: TimeInterval, fileURL: URL, duration: TimeInterval) {
        guard let idx = audioClips.firstIndex(where: { $0.id == clipID }) else { return }
        registerUndoIfNeeded()

        let original = audioClips[idx]
        let sourceStart = original.sourceTime(forTimelineLocal: start - original.timelineStart)
        let sourceEnd = original.sourceTime(forTimelineLocal: end - original.timelineStart)

        var newClips: [EditorAudioClip] = []
        var remainder = original
        if let (head, afterHead) = original.split(atSourceTime: sourceStart) {
            newClips.append(head)
            remainder = afterHead
        }

        let replacement = EditorAudioClip(
            title: original.title,
            fileURL: fileURL,
            originalDuration: duration,
            timelineStart: newClips.last?.timelineEnd ?? start,
            laneIndex: original.laneIndex
        )
        newClips.append(replacement)

        if let (_, tail) = remainder.split(atSourceTime: sourceEnd) {
            var repositionedTail = tail
            repositionedTail.timelineStart = replacement.timelineEnd
            newClips.append(repositionedTail)
        }

        audioClips.remove(at: idx)
        audioClips.insert(contentsOf: newClips, at: idx)
        selectAudioClip(replacement.id)
        invalidateComposition()
        scheduleSave()
        Task { await alignPlaybackToTimeline() }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Applies (or clears) a Priority 15 audio effect on an audio clip. Clearing is immediate —
    /// there's nothing to render. Applying awaits `EditorAudioEffectRenderer` and only commits
    /// `clip.effect` once the offline render has actually produced a file, so a clip is never
    /// left pointing at an effect with nothing behind it; a failed render leaves the clip
    /// unchanged and surfaces `audioEffectErrorMessage` instead.
    func setAudioClipEffect(clipID: UUID, effect: EditorAudioEffect) {
        guard let clip = audioClips.first(where: { $0.id == clipID }), clip.effect != effect else { return }

        guard effect != .none else {
            registerUndoIfNeeded()
            guard let idx = audioClips.firstIndex(where: { $0.id == clipID }) else { return }
            audioClips[idx].effect = .none
            invalidateComposition()
            scheduleSave()
            Task { await alignPlaybackToTimeline() }
            return
        }

        let sourceURL = clip.fileURL
        renderingAudioEffectClipID = clipID
        renderingAudioEffect = effect
        audioEffectErrorMessage = nil
        audioEffectRenderTask?.cancel()
        audioEffectRenderTask = Task { [weak self] in
            let rendered = await EditorAudioEffectRenderer.shared.render(sourceURL: sourceURL, effect: effect)
            guard let self, !Task.isCancelled, self.renderingAudioEffectClipID == clipID else { return }
            self.renderingAudioEffectClipID = nil
            self.renderingAudioEffect = nil
            guard rendered != nil, let idx = self.audioClips.firstIndex(where: { $0.id == clipID }) else {
                self.audioEffectErrorMessage = "Couldn't apply that effect. Try again."
                return
            }
            self.registerUndoIfNeeded()
            self.audioClips[idx].effect = effect
            self.invalidateComposition()
            self.scheduleSave()
            await self.alignPlaybackToTimeline()
        }
    }

    func deleteSelectedAudioClip() {
        guard let id = selectedAudioClipID,
              let index = audioClips.firstIndex(where: { $0.id == id }) else { return }
        registerUndoIfNeeded()
        cancelPunchInMark()
        let removed = audioClips.remove(at: index)
        selectedTimelineItems.remove(.audio(id))
        pruneSequenceStructure()
        releaseAudioFileIfUnused(removed.fileURL)
        selectedAudioClipID = audioClips.first?.id
        if selectedAudioClipID == nil { selectedTool = nil }
        invalidateComposition()
        scheduleSave()
        Task { await alignPlaybackToTimeline() }
    }

    func duplicateSelectedAudioClip() {
        guard let id = selectedAudioClipID, let index = audioClips.firstIndex(where: { $0.id == id }) else { return }
        registerUndoIfNeeded()
        let source = audioClips[index]
        let copy = EditorAudioClip(
            title: source.title + " Copy", fileURL: source.fileURL,
            originalDuration: source.originalDuration, trimStart: source.trimStart,
            trimEnd: source.trimEnd, timelineStart: source.timelineEnd,
            laneIndex: source.laneIndex,
            volume: source.volume, fadeInDuration: source.fadeInDuration,
            fadeOutDuration: source.fadeOutDuration, keyframes: source.keyframes,
            attribution: source.attribution, effect: source.effect
        )
        audioClips.insert(copy, at: index + 1)
        selectedAudioClipID = copy.id
        invalidateComposition(); scheduleSave()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task { await alignPlaybackToTimeline() }
    }

    func setAudioTrim(clipID: UUID, trimStart: TimeInterval, trimEnd: TimeInterval) {
        if audioTrimUndoSnapshot == nil {
            audioTrimUndoSnapshot = currentSnapshot()
        }
        guard let idx = audioClips.firstIndex(where: { $0.id == clipID }) else { return }
        var clip = audioClips[idx]
        let minSpan = EditorAudioClip.minimumSpan
        let start = min(max(0, trimStart), clip.originalDuration - minSpan)
        let end = max(min(clip.originalDuration, trimEnd), start + minSpan)
        clip.trimStart = start
        clip.trimEnd = end
        clip.fadeInDuration = min(clip.fadeInDuration, clip.duration)
        clip.fadeOutDuration = min(clip.fadeOutDuration, clip.duration)
        audioClips[idx] = clip
        invalidateComposition()
    }

    func commitAudioTrim(clipID: UUID) {
        if let before = audioTrimUndoSnapshot,
           let idx = audioClips.firstIndex(where: { $0.id == clipID }),
           let baseline = before.audioClips.first(where: { $0.id == clipID }) {
            audioClips[idx].timelineStart = max(
                0,
                baseline.timelineStart + (audioClips[idx].trimStart - baseline.trimStart)
            )
        }
        if let before = audioTrimUndoSnapshot {
            if before != currentSnapshot() {
                undoManager.pushUndoState(before)
                refreshUndoState()
                scheduleSave()
            }
            audioTrimUndoSnapshot = nil
        }
        invalidateComposition()
        Task { await alignPlaybackToTimeline() }
    }

    func setAudioTimelineStart(clipID: UUID, timelineStart: TimeInterval) {
        if audioMoveUndoSnapshot == nil {
            audioMoveUndoSnapshot = currentSnapshot()
        }
        guard let idx = audioClips.firstIndex(where: { $0.id == clipID }) else { return }
        audioClips[idx].timelineStart = snappedTime(timelineStart, excluding: clipID)
        invalidateComposition()
    }

    /// The decoded waveform knows the real file duration. Use it to repair stale
    /// saved metadata so the visible bar and composition cover the same audio.
    func reconcileAudioSourceDuration(clipID: UUID, duration: TimeInterval) {
        guard let index = audioClips.firstIndex(where: { $0.id == clipID }),
              audioClips[index].reconcileSourceDuration(duration) else { return }
        invalidateComposition()
        scheduleSave()
        // The bar has just changed length, so rebuild the player from the same
        // corrected duration immediately. This keeps the sound and its visible
        // timeline extent in sync without waiting for another edit or replay.
        Task { await alignPlaybackToTimeline() }
    }

    func setAudioLaneIndex(clipID: UUID, laneIndex: Int) {
        if audioMoveUndoSnapshot == nil {
            audioMoveUndoSnapshot = currentSnapshot()
        }
        guard let index = audioClips.firstIndex(where: { $0.id == clipID }) else { return }
        audioClips[index].laneIndex = max(0, laneIndex)
        invalidateComposition()
    }

    func commitAudioMove() {
        if let before = audioMoveUndoSnapshot {
            if before != currentSnapshot() {
                undoManager.pushUndoState(before)
                refreshUndoState()
                scheduleSave()
            }
            audioMoveUndoSnapshot = nil
        }
        clearSnapGuide()
        Task { await alignPlaybackToTimeline() }
    }

    func splitSelectedAudioAtPlayhead() {
        guard let id = selectedAudioClipID,
              let idx = audioClips.firstIndex(where: { $0.id == id }) else { return }
        let clip = audioClips[idx]
        let playhead = timelinePosition
        guard playhead > clip.timelineStart + EditorAudioClip.minimumSpan,
              playhead < clip.timelineEnd - EditorAudioClip.minimumSpan else { return }

        let local = playhead - clip.timelineStart
        let sourceTime = clip.sourceTime(forTimelineLocal: local)
        guard let parts = clip.split(atSourceTime: sourceTime) else { return }

        registerUndoIfNeeded()
        audioClips[idx] = parts.left
        audioClips.insert(parts.right, at: idx + 1)
        remapSequenceMembershipAfterSplit(
            original: .audio(parts.left.id),
            right: .audio(parts.right.id)
        )
        selectedAudioClipID = parts.right.id
        invalidateComposition()
        scheduleSave()
        Task { await alignPlaybackToTimeline() }
    }

    func setAudioVolume(clipID: UUID, volume: Float) {
        guard let idx = audioClips.firstIndex(where: { $0.id == clipID }) else { return }
        if audioVolumeUndoSnapshot == nil {
            audioVolumeUndoSnapshot = currentSnapshot()
        }
        audioClips[idx].volume = min(max(volume, 0), 1.0)
        invalidateComposition()
    }

    func commitAudioVolume(clipID: UUID, volume: Float) {
        setAudioVolume(clipID: clipID, volume: volume)
        finalizeAudioVolumeEditUndo()
        audioVolumeUndoSnapshot = currentSnapshot()
        Task { await alignPlaybackToTimeline() }
    }

    func setAudioFades(clipID: UUID, fadeIn: TimeInterval, fadeOut: TimeInterval) {
        guard let idx = audioClips.firstIndex(where: { $0.id == clipID }) else { return }
        if audioVolumeUndoSnapshot == nil {
            audioVolumeUndoSnapshot = currentSnapshot()
        }
        let duration = audioClips[idx].duration
        audioClips[idx].fadeInDuration = min(max(0, fadeIn), duration)
        audioClips[idx].fadeOutDuration = min(max(0, fadeOut), duration)
        invalidateComposition()
    }

    func commitAudioFades(clipID: UUID, fadeIn: TimeInterval, fadeOut: TimeInterval) {
        setAudioFades(clipID: clipID, fadeIn: fadeIn, fadeOut: fadeOut)
        finalizeAudioVolumeEditUndo()
        audioVolumeUndoSnapshot = currentSnapshot()
        Task { await alignPlaybackToTimeline() }
    }

    func finalizeAudioVolumeEditUndo() {
        guard let before = audioVolumeUndoSnapshot else { return }
        if before != currentSnapshot() {
            undoManager.pushUndoState(before)
            refreshUndoState()
            scheduleSave()
        }
        audioVolumeUndoSnapshot = nil
    }

    // MARK: Gain staging (Priority 13) — track + master gain on top of per-clip volume

    func audioTrackSettings(forLane laneIndex: Int) -> EditorAudioTrackSettings {
        audioTrackSettings[laneIndex] ?? EditorAudioTrackSettings()
    }

    /// All lanes that currently have at least one clip — the set a mixer UI should show rows
    /// for, in the same left-to-right order the timeline lanes are displayed.
    var audioLaneIndices: [Int] {
        Set(audioClips.map(\.laneIndex)).sorted()
    }

    func setAudioTrackGain(laneIndex: Int, gain: Float) {
        if mixUndoSnapshot == nil { mixUndoSnapshot = currentSnapshot() }
        var settings = audioTrackSettings(forLane: laneIndex)
        settings.gain = min(max(gain, 0), 1)
        audioTrackSettings[laneIndex] = settings
        invalidateComposition()
    }

    func toggleAudioTrackMute(laneIndex: Int) {
        registerUndoIfNeeded()
        var settings = audioTrackSettings(forLane: laneIndex)
        settings.isMuted.toggle()
        audioTrackSettings[laneIndex] = settings
        invalidateComposition()
        scheduleSave()
        Task { await alignPlaybackToTimeline() }
    }

    /// Priority 15 solo. Every lane's `effectiveGain(anySoloed:)` reacts to *any* lane being
    /// soloed, so toggling this one lane's flag is the entire implementation — no separate
    /// bookkeeping of "which lanes are silenced" needed.
    func toggleAudioTrackSolo(laneIndex: Int) {
        registerUndoIfNeeded()
        var settings = audioTrackSettings(forLane: laneIndex)
        settings.isSoloed.toggle()
        audioTrackSettings[laneIndex] = settings
        invalidateComposition()
        scheduleSave()
        Task { await alignPlaybackToTimeline() }
    }

    /// Priority 15 track header naming. Empty/whitespace-only names are stored as `nil` so the
    /// mixer falls back to its positional "Track N" label instead of showing a blank row.
    func setAudioTrackName(laneIndex: Int, name: String) {
        registerUndoIfNeeded()
        var settings = audioTrackSettings(forLane: laneIndex)
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.name = trimmed.isEmpty ? nil : trimmed
        audioTrackSettings[laneIndex] = settings
        scheduleSave()
    }

    func setMasterVolume(_ volume: Float) {
        if mixUndoSnapshot == nil { mixUndoSnapshot = currentSnapshot() }
        masterVolume = min(max(volume, 0), 1)
        invalidateComposition()
    }

    /// Call when a gain slider drag ends (mirrors `commitAudioVolume`) — folds the drag into one
    /// undo step and persists.
    func commitMixChange() {
        guard let before = mixUndoSnapshot else { return }
        if before != currentSnapshot() {
            undoManager.pushUndoState(before)
            refreshUndoState()
            scheduleSave()
        }
        mixUndoSnapshot = nil
        Task { await alignPlaybackToTimeline() }
    }

    func releaseAudioFileIfUnused(_ url: URL) {
        // Bundled library clips point at read-only files inside the app bundle — never ours to
        // delete. Freesound-sourced clips point at the shared AudioLibraryCache, which may be
        // referenced by other projects too; that cache manages its own eviction independently
        // (see AudioLibraryCache), so per-project deletion must never touch it directly.
        guard !url.path.hasPrefix(Bundle.main.bundlePath) else { return }
        guard !url.path.contains("/MixtapeAudioLibraryCache/") else { return }
        let stillUsed = audioClips.contains { $0.fileURL == url }
        guard !stillUsed else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
