//
//  EditorViewModel.swift
//  Mixtape
//
//  Created by Favour Baruch on 14/05/2026.
//

import SwiftUI
import UIKit
import AVFoundation
import Photos

@MainActor
@Observable
final class EditorViewModel {

    // MARK: Timeline state

    private(set) var clips: [EditorClip]
    var selectedClipID: UUID?
    var textOverlays: [EditorTextOverlay]
    var audioTrack: EditorAudioTrack?

    /// Global playhead: 0 … totalDuration across every clip in order.
    var timelinePosition: TimeInterval = 0

    var isPlaying: Bool = false
    var selectedTool: EditorTool?

    // MARK: Text overlay editing

    var selectedTextOverlayID: UUID?
    var isTextEditorPresented: Bool = false

    // MARK: Project persistence

    private(set) var projectID: UUID
    private let projectCreatedAt: Date
    var projectTitle: String

    // MARK: Export

    var isExporting: Bool = false
    var exportProgress: Double = 0
    var exportMessage: String?
    private(set) var exportedFileURL: URL?

    @ObservationIgnored
    private var exportTask: Task<Void, Never>?

    // MARK: Undo

    private(set) var canUndo: Bool = false
    private(set) var canRedo: Bool = false

    // MARK: Player

    private(set) var player: AVPlayer?

    @ObservationIgnored
    private var endObserver: NSObjectProtocol?
    @ObservationIgnored
    private var tickTimer: Timer?
    @ObservationIgnored
    private var compositionFingerprint: String?
    @ObservationIgnored
    private let undoManager = EditorUndoManager()
    @ObservationIgnored
    private var trimUndoSnapshot: EditorTimelineSnapshot?
    @ObservationIgnored
    private var speedUndoSnapshot: EditorTimelineSnapshot?
    @ObservationIgnored
    private var textEditUndoSnapshot: EditorTimelineSnapshot?
    @ObservationIgnored
    private var textEditDragOrigin: (x: CGFloat, y: CGFloat)?
    @ObservationIgnored
    private var textTimeRangeUndoSnapshot: EditorTimelineSnapshot?
    @ObservationIgnored
    private var saveTask: Task<Void, Never>?

    // MARK: Init

    init(project: EditorProject) {
        self.projectID = project.id
        self.projectCreatedAt = project.createdAt
        self.projectTitle = project.title
        let clips = EditorProjectResolver.clips(from: project.clips)
        self.clips = clips
        self.selectedClipID = project.selectedClipID ?? clips.first?.id
        self.timelinePosition = project.timelinePosition
        self.textOverlays = project.textOverlays.map { $0.toOverlay() }
        self.audioTrack = nil
    }

    // MARK: Derived

    var totalDuration: TimeInterval {
        clips.reduce(0) { $0 + $1.duration }
    }

    var selectedClip: EditorClip? {
        guard let id = selectedClipID else { return nil }
        return clips.first { $0.id == id }
    }

    var canDeleteSelectedClip: Bool {
        selectedClipID != nil && clips.count > 1
    }

    var selectedTextOverlay: EditorTextOverlay? {
        guard let id = selectedTextOverlayID else { return nil }
        return textOverlays.first { $0.id == id }
    }

    /// Clip currently under the global playhead (what the preview should show).
    var playbackInfo: (clip: EditorClip, index: Int, localTime: TimeInterval)? {
        clipAndLocalTime(at: timelinePosition)
    }

    var playbackClipID: UUID? { playbackInfo?.clip.id }

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
        let clamped = min(max(0, timelineT), totalDuration)
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

    // MARK: Selection

    func selectClipForEditing(_ id: UUID) {
        selectedClipID = id
        selectedTextOverlayID = nil
        isTextEditorPresented = false
    }

    func deselectClip() {
        if selectedTool == .speed {
            finalizeSpeedEditUndo()
        }
        selectedTool = nil
        selectedClipID = nil
    }

    func performClipAction(_ action: EditorClipAction) {
        switch action {
        case .delete:
            deleteSelectedClip()
        case .split:
            splitAtPlayhead()
            selectedTool = .split
        case .speed:
            performToolAction(.speed)
        case .volume:
            performToolAction(.volume)
        case .filter:
            performToolAction(.filter)
        case .text:
            performToolAction(.text)
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

        if selectedTool == tool {
            if tool == .speed { finalizeSpeedEditUndo() }
            selectedTool = nil
            return
        }

        selectedTool = tool
        if tool == .speed {
            speedUndoSnapshot = currentSnapshot()
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
        default:
            selectTool(tool)
        }
    }

    private func finalizeSpeedEditUndo() {
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
        var clip = clips[idx]
        clip.speed = min(max(speed, 0.25), 3.0)
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

    // MARK: Text Overlays

    func addTextOverlay() {
        registerUndoIfNeeded()

        let defaultDuration: TimeInterval = 3.0
        let start = timelinePosition
        let end = min(start + defaultDuration, totalDuration)

        guard end > start + 0.1 else { return } // not enough room

        let overlay = EditorTextOverlay(
            text: "Text",
            startTime: start,
            endTime: end
        )
        textOverlays.append(overlay)
        selectedTextOverlayID = overlay.id
        isTextEditorPresented = true
        scheduleSave()

        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func updateTextOverlay(_ overlay: EditorTextOverlay) {
        guard let idx = textOverlays.firstIndex(where: { $0.id == overlay.id }) else { return }
        textOverlays[idx] = overlay
        scheduleSave()
    }

    func beginTextOverlayEdit() {
        if textEditUndoSnapshot == nil {
            textEditUndoSnapshot = currentSnapshot()
        }
    }

    func finalizeTextOverlayEdit() {
        guard let before = textEditUndoSnapshot else { return }
        textEditUndoSnapshot = nil
        textEditDragOrigin = nil
        if before != currentSnapshot() {
            undoManager.pushUndoState(before)
            refreshUndoState()
            scheduleSave()
        }
    }

    func beginTextOverlayPositionDrag(id: UUID) {
        beginTextOverlayEdit()
        guard textEditDragOrigin == nil,
              let overlay = textOverlays.first(where: { $0.id == id }) else { return }
        textEditDragOrigin = (overlay.xOffset, overlay.yOffset)
    }

    func updateTextOverlayPositionDrag(id: UUID, translation: CGSize) {
        guard let origin = textEditDragOrigin,
              let idx = textOverlays.firstIndex(where: { $0.id == id }) else { return }
        textOverlays[idx].xOffset = origin.x + translation.width
        textOverlays[idx].yOffset = origin.y + translation.height
    }

    func commitTextOverlayPositionDrag() {
        textEditDragOrigin = nil
        finalizeTextOverlayEdit()
    }

    func deleteTextOverlay(id: UUID) {
        clearTextOverlayEditUndo()
        registerUndoIfNeeded()
        textOverlays.removeAll { $0.id == id }
        if selectedTextOverlayID == id {
            selectedTextOverlayID = nil
            isTextEditorPresented = false
        }
        scheduleSave()
    }

    func selectTextOverlay(_ id: UUID) {
        if selectedTextOverlayID == id {
            selectedTextOverlayID = nil
        } else {
            selectedTextOverlayID = id
            selectedClipID = nil
            selectedTool = nil
        }
    }

    func dismissTextEditor() {
        finalizeTextOverlayEdit()

        // If the text is empty, delete the overlay.
        if let id = selectedTextOverlayID,
           let overlay = textOverlays.first(where: { $0.id == id }),
           overlay.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            deleteTextOverlay(id: id)
        }
        // Notice we do NOT clear selectedTextOverlayID here, so it remains selected on the timeline
        isTextEditorPresented = false
    }

    func updateTextOverlayTimeRange(id: UUID, start: TimeInterval, end: TimeInterval) {
        if textTimeRangeUndoSnapshot == nil {
            textTimeRangeUndoSnapshot = currentSnapshot()
        }

        guard let idx = textOverlays.firstIndex(where: { $0.id == id }) else { return }
        textOverlays[idx].startTime = start
        textOverlays[idx].endTime = end
    }

    func commitTextOverlayTimeRange() {
        if let before = textTimeRangeUndoSnapshot {
            if before != currentSnapshot() {
                undoManager.pushUndoState(before)
                refreshUndoState()
            }
            textTimeRangeUndoSnapshot = nil
        }
        scheduleSave()
    }

    private func clearTextOverlayEditUndo() {
        textEditUndoSnapshot = nil
        textEditDragOrigin = nil
        textTimeRangeUndoSnapshot = nil
    }

    // MARK: Clips

    func setTrim(clipID: UUID, trimStart: TimeInterval, trimEnd: TimeInterval) {
        if trimUndoSnapshot == nil {
            trimUndoSnapshot = currentSnapshot()
        }

        guard let idx = clips.firstIndex(where: { $0.id == clipID }) else { return }
        var clip = clips[idx]
        let minSpan = EditorClip.minimumSourceSpan(speed: clip.speed)

        let start = min(max(0, trimStart), clip.originalDuration - minSpan)
        let end = max(min(clip.originalDuration, trimEnd), start + minSpan)

        clip.trimStart = start
        clip.trimEnd = end
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
        invalidateComposition()
        Task { await alignPlaybackToTimeline() }
    }

    func splitAtPlayhead() {
        guard let info = clipAndLocalTime(at: timelinePosition) else { return }

        let splitSource = info.clip.sourceTime(forExportedLocal: info.localTime)
        guard let parts = info.clip.split(atSourceTime: splitSource) else { return }

        registerUndoIfNeeded()

        pausePlaybackForEdit()

        let index = info.index
        clips.remove(at: index)
        clips.insert(contentsOf: [parts.left, parts.right], at: index)

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

    // MARK: Undo / Redo

    func undo() {
        guard let restored = undoManager.undo(replacing: currentSnapshot()) else { return }
        applySnapshot(restored)
        refreshUndoState()
        scheduleSave()
        Task { await alignPlaybackToTimeline() }
    }

    func redo() {
        guard let restored = undoManager.redo(replacing: currentSnapshot()) else { return }
        applySnapshot(restored)
        refreshUndoState()
        scheduleSave()
        Task { await alignPlaybackToTimeline() }
    }

    // MARK: Export

    func formatDuration(_ duration: TimeInterval) -> String {
        let total = Int(duration.rounded())
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    func startExport(settings: EditorExportSettings) {
        guard !clips.isEmpty, !isExporting else { return }
        exportTask?.cancel()
        exportedFileURL = nil
        exportMessage = nil

        exportTask = Task {
            isExporting = true
            exportProgress = 0
            exportMessage = "Rendering clips…"

            do {
                let clipsSnapshot = clips
                let textOverlaysSnapshot = textOverlays
                let url = try await EditorExportService.export(
                    clips: clipsSnapshot,
                    textOverlays: textOverlaysSnapshot,
                    settings: settings
                ) { progress in
                    Task { @MainActor in
                        self.exportProgress = progress
                    }
                }

                guard !Task.isCancelled else { return }

                exportMessage = "Saving to Photos…"
                try await EditorExportService.saveVideoToPhotoLibrary(url: url)
                exportedFileURL = url
                exportMessage = "Saved to Photos"
                exportProgress = 1
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch is CancellationError {
                exportMessage = nil
            } catch EditorExportError.exportCancelled {
                exportMessage = nil
            } catch {
                exportMessage = error.localizedDescription
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }

            isExporting = false
        }
    }

    func cancelExport() {
        exportTask?.cancel()
        EditorExportService.cancelCurrentExport()
        isExporting = false
        exportProgress = 0
        exportMessage = nil
    }

    func clearExportState() {
        if let url = exportedFileURL {
            try? FileManager.default.removeItem(at: url)
        }
        exportedFileURL = nil
        exportMessage = nil
        exportProgress = 0
    }

    // MARK: Playback

    func togglePlay() {
        guard totalDuration > 0 else { return }
        if isPlaying {
            stopPlaybackTicking()
            player?.pause()
            isPlaying = false
        } else {
            if timelinePosition >= totalDuration - 0.05 {
                timelinePosition = 0
            }
            isPlaying = true
            Task {
                await ensureCompositionPlayer(resumePlaying: true)
                startPlaybackTicking()
            }
        }
    }

    func seekTimeline(to time: TimeInterval) {
        setTimelinePositionForScrub(time)
        commitTimelineAfterScrub()
    }

    func setTimelinePositionForScrub(_ time: TimeInterval) {
        if isPlaying {
            stopPlaybackTicking()
            player?.pause()
            isPlaying = false
        }
        timelinePosition = min(max(0, time), totalDuration)
    }

    func commitTimelineAfterScrub() {
        Task { await alignPlaybackToTimeline() }
        scheduleSave()
    }

    // MARK: Lifecycle

    func setupPlayer() async {
        await alignPlaybackToTimeline()
    }

    func teardownPlayer() {
        stopPlaybackTicking()
        removeEndObserver()
        player?.pause()
        player = nil
        compositionFingerprint = nil
        saveTask?.cancel()
        exportTask?.cancel()
        EditorExportService.cancelCurrentExport()
        EditorCompositionBuilder.clearCaches()
        isPlaying = false
    }

    func saveNow() {
        saveTask?.cancel()
        try? ProjectStore.shared.save(makeProject())
    }

    // MARK: - Private helpers

    private func currentSnapshot() -> EditorTimelineSnapshot {
        EditorTimelineSnapshot(
            clips: clips,
            timelinePosition: timelinePosition,
            selectedClipID: selectedClipID,
            textOverlays: textOverlays
        )
    }

    private func applySnapshot(_ snapshot: EditorTimelineSnapshot) {
        clips = snapshot.clips
        timelinePosition = min(snapshot.timelinePosition, totalDuration)
        selectedClipID = snapshot.selectedClipID
        textOverlays = snapshot.textOverlays
        invalidateComposition()
    }

    private func registerUndoIfNeeded() {
        undoManager.pushUndoState(currentSnapshot())
        refreshUndoState()
    }

    private func refreshUndoState() {
        canUndo = undoManager.canUndo
        canRedo = undoManager.canRedo
    }

    private func makeProject() -> EditorProject {
        EditorProject(
            id: projectID,
            title: projectTitle,
            createdAt: projectCreatedAt,
            modifiedAt: Date(),
            clips: clips.map { SavedEditorClip(from: $0) },
            textOverlays: textOverlays.map { SavedTextOverlay(from: $0) },
            audioTrack: audioTrack.map { SavedAudioTrack(from: $0) },
            timelinePosition: timelinePosition,
            selectedClipID: selectedClipID
        )
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            try? ProjectStore.shared.save(makeProject())
        }
    }

    private func clipsFingerprint() -> String {
        clips.map { clip in
            "\(clip.id.uuidString)|\(clip.trimStart)|\(clip.trimEnd)|\(clip.speed)|\(clip.duration)|\(clip.asset.localIdentifier)"
        }.joined(separator: ";")
    }

    private func invalidateComposition() {
        compositionFingerprint = nil
    }

    private func pausePlaybackForEdit() {
        if isPlaying {
            stopPlaybackTicking()
            player?.pause()
            isPlaying = false
        }
    }

    private func ensureCompositionPlayer(resumePlaying: Bool = false) async {
        let fingerprint = clipsFingerprint()
        let needsRebuild = fingerprint != compositionFingerprint || player?.currentItem == nil

        if !needsRebuild {
            await seekPlayerToTimeline(exact: !isPlaying)
            if resumePlaying || isPlaying { player?.play() }
            return
        }

        let savedTime = timelinePosition
        let wasPlaying = isPlaying
        let clipsSnapshot = clips

        let item: AVPlayerItem?
        if let warmed = EditorCompositionBuilder.consumeWarmedPlayerItem(matching: clipsSnapshot) {
            item = warmed
        } else {
            item = await Task.detached(priority: .userInitiated) {
                await EditorCompositionBuilder.makePlayerItem(from: clipsSnapshot)
            }.value
        }

        guard let item else { return }

        if player == nil {
            AudioSessionConfigurator.configureForVideoPlayback()
            let newPlayer = AVPlayer(playerItem: item)
            newPlayer.actionAtItemEnd = .pause
            newPlayer.automaticallyWaitsToMinimizeStalling = true
            player = newPlayer
        } else {
            player?.replaceCurrentItem(with: item)
        }

        attachCompositionEndObserver(for: item)
        compositionFingerprint = fingerprint
        timelinePosition = min(savedTime, totalDuration)
        await seekPlayerToTimeline(exact: true)

        if wasPlaying || resumePlaying {
            player?.play()
        }
    }

    private func seekPlayerToTimeline(exact: Bool) async {
        let target = CMTime(seconds: timelinePosition, preferredTimescale: 600)
        if exact {
            await player?.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
        } else {
            await player?.seek(
                to: target,
                toleranceBefore: CMTime(seconds: 0.03, preferredTimescale: 600),
                toleranceAfter: CMTime(seconds: 0.03, preferredTimescale: 600)
            )
        }
    }

    private func startPlaybackTicking() {
        stopPlaybackTicking()
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.playbackTick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
    }

    private func stopPlaybackTicking() {
        tickTimer?.invalidate()
        tickTimer = nil
    }

    private func playbackTick() {
        guard isPlaying, totalDuration > 0, let player else { return }

        let current = player.currentTime().seconds
        if current.isFinite, current >= 0 {
            timelinePosition = min(current, totalDuration)
        }

        if timelinePosition >= totalDuration - 0.02 {
            timelinePosition = totalDuration
            player.pause()
            stopPlaybackTicking()
            isPlaying = false
        }
    }

    private func resumePlaybackAfterAlign() {
        guard isPlaying else { return }
        player?.play()
    }

    private func alignPlaybackToTimeline() async {
        guard !clips.isEmpty else { return }
        await ensureCompositionPlayer()
        await seekPlayerToTimeline(exact: !isPlaying)
    }

    private func attachCompositionEndObserver(for item: AVPlayerItem) {
        removeEndObserver()
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handlePlaybackEnded() }
        }
    }

    private func removeEndObserver() {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
    }

    private func handlePlaybackEnded() {
        timelinePosition = totalDuration
        player?.pause()
        stopPlaybackTicking()
        isPlaying = false
    }
}
