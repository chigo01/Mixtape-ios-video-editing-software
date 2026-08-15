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
    private(set) var openingTransitionKind: EditorTransitionKind
    private(set) var openingTransitionDuration: TimeInterval
    private(set) var closingTransitionKind: EditorTransitionKind
    private(set) var closingTransitionDuration: TimeInterval
    var selectedClipID: UUID?
    var textOverlays: [EditorTextOverlay]
    var audioClips: [EditorAudioClip]
    var overlayClips: [EditorOverlayClip]

    /// Global playhead: 0 … totalDuration across every clip in order.
    var timelinePosition: TimeInterval = 0

    var isPlaying: Bool = false
    var selectedTool: EditorTool?
    var showsReframeSafeAreaGuides: Bool = true

    // MARK: Text overlay editing

    var selectedTextOverlayID: UUID?
    var isTextEditorPresented: Bool = false

    // MARK: Audio editing

    var selectedAudioClipID: UUID?

    // MARK: Video overlay editing

    var selectedOverlayClipID: UUID?

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
    private var photoDurationUndoSnapshot: EditorTimelineSnapshot?
    @ObservationIgnored
    private var reframeUndoSnapshot: EditorTimelineSnapshot?
    @ObservationIgnored
    private var colorUndoSnapshot: EditorTimelineSnapshot?
    private var copiedColorAdjustment: EditorColorAdjustment?
    @ObservationIgnored
    private var colorPreviewTask: Task<Void, Never>?
    @ObservationIgnored
    private var reframePositionDragOrigin: (x: CGFloat, y: CGFloat)?
    @ObservationIgnored
    private var textEditUndoSnapshot: EditorTimelineSnapshot?
    @ObservationIgnored
    private var textEditDragOrigin: (x: CGFloat, y: CGFloat)?
    @ObservationIgnored
    private var textTimeRangeUndoSnapshot: EditorTimelineSnapshot?
    @ObservationIgnored
    private var textMoveUndoSnapshot: EditorTimelineSnapshot?
    @ObservationIgnored
    private var volumeUndoSnapshot: EditorTimelineSnapshot?
    @ObservationIgnored
    private var audioTrimUndoSnapshot: EditorTimelineSnapshot?
    @ObservationIgnored
    private var audioMoveUndoSnapshot: EditorTimelineSnapshot?
    @ObservationIgnored
    private var audioVolumeUndoSnapshot: EditorTimelineSnapshot?
    @ObservationIgnored
    private var overlayTrimUndoSnapshot: EditorTimelineSnapshot?
    @ObservationIgnored
    private var overlayMoveUndoSnapshot: EditorTimelineSnapshot?
    @ObservationIgnored
    private var overlayTransformUndoSnapshot: EditorTimelineSnapshot?
    @ObservationIgnored
    private var overlayPositionDragOrigin: (x: CGFloat, y: CGFloat)?
    @ObservationIgnored
    private var transitionUndoSnapshot: EditorTimelineSnapshot?
    @ObservationIgnored
    private var saveTask: Task<Void, Never>?

    // MARK: Init

    init(project: EditorProject) {
        self.projectID = project.id
        self.projectCreatedAt = project.createdAt
        self.projectTitle = project.title
        let clips = EditorProjectResolver.clips(from: project.clips)
        self.clips = clips
        self.openingTransitionKind = project.openingTransitionKind
        self.openingTransitionDuration = project.openingTransitionDuration
        self.closingTransitionKind = project.closingTransitionKind
        self.closingTransitionDuration = project.closingTransitionDuration
        self.selectedClipID = project.selectedClipID ?? clips.first?.id
        self.timelinePosition = project.timelinePosition
        self.textOverlays = project.textOverlays.map { $0.toOverlay() }
        self.audioClips = project.audioClips.compactMap { $0.toAudioClip() }
        self.selectedAudioClipID = project.selectedAudioClipID
        var resolvedOverlays = EditorProjectResolver.overlayClips(from: project.overlayClips)
        var nextLegacyLane = (resolvedOverlays.map(\.laneIndex).filter { $0 >= 0 }.max() ?? -1) + 1
        for index in resolvedOverlays.indices where resolvedOverlays[index].laneIndex < 0 {
            resolvedOverlays[index].laneIndex = nextLegacyLane
            nextLegacyLane += 1
        }
        self.overlayClips = resolvedOverlays
        self.selectedOverlayClipID = project.selectedOverlayClipID
    }

    // MARK: Derived

    var totalDuration: TimeInterval {
        let video = clips.reduce(0) { $0 + $1.duration }
        let audioEnd = audioClips.map(\.timelineEnd).max() ?? 0
        let textEnd = textOverlays.map(\.endTime).max() ?? 0
        let overlayEnd = overlayClips.map(\.timelineEnd).max() ?? 0
        return max(video, audioEnd, textEnd, overlayEnd)
    }

    var videoDuration: TimeInterval {
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

    var sortedOverlayClips: [EditorOverlayClip] {
        overlayClips.sorted { $0.timelineStart < $1.timelineStart }
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

    // MARK: Selection

    func selectClipForEditing(_ id: UUID) {
        if selectedTool == .duration {
            finalizePhotoDurationEditUndo()
        }
        if selectedTool == .crop {
            finalizeReframeEditUndo()
        }
        if selectedTool == .filter {
            finalizeColorAdjustmentUndo()
        }
        selectedClipID = id
        selectedTextOverlayID = nil
        selectedAudioClipID = nil
        selectedOverlayClipID = nil
        isTextEditorPresented = false
        selectedTool = nil
    }

    func selectAudioClip(_ id: UUID) {
        if selectedTool == .duration {
            finalizePhotoDurationEditUndo()
        }
        if selectedTool == .crop {
            finalizeReframeEditUndo()
        }
        if selectedTool == .filter {
            finalizeColorAdjustmentUndo()
        }
        selectedAudioClipID = id
        selectedClipID = nil
        selectedTextOverlayID = nil
        selectedOverlayClipID = nil
        isTextEditorPresented = false
        selectedTool = nil
    }

    func deselectAudioClip() {
        finalizeAudioVolumeEditUndo()
        selectedTool = nil
        selectedAudioClipID = nil
    }

    func selectOverlayClip(_ id: UUID) {
        if selectedTool == .speed {
            finalizeSpeedEditUndo()
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
        finalizeOverlayTransform()
        selectedOverlayClipID = id
        selectedClipID = nil
        selectedTextOverlayID = nil
        selectedAudioClipID = nil
        isTextEditorPresented = false
        selectedTool = nil
    }

    func deselectOverlayClip() {
        if selectedTool == .speed {
            finalizeSpeedEditUndo()
        }
        if selectedTool == .volume {
            finalizeVolumeEditUndo()
        }
        finalizeOverlayTransform()
        selectedOverlayClipID = nil
        selectedTool = nil
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
        selectedTool = nil
        selectedClipID = nil
    }

    func performAudioAction(_ action: EditorAudioAction) {
        switch action {
        case .delete:
            deleteSelectedAudioClip()
        case .split:
            splitSelectedAudioAtPlayhead()
            selectedTool = .split
        case .volume:
            performToolAction(.volume)
        }
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
        case .duration:
            performToolAction(.duration)
        case .crop:
            performToolAction(.crop)
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
        }

        if selectedTool == tool {
            if tool == .speed { finalizeSpeedEditUndo() }
            if tool == .duration { finalizePhotoDurationEditUndo() }
            if tool == .crop { finalizeReframeEditUndo() }
            if tool == .filter { finalizeColorAdjustmentUndo() }
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

    // MARK: Crop and reframe

    // MARK: Color and filters

    var canPasteColorAdjustment: Bool { copiedColorAdjustment != nil }

    func setSelectedClipFilter(_ preset: EditorFilterPreset) {
        updateSelectedClipColor { $0.preset = preset }
    }

    func setSelectedClipFilterIntensity(_ intensity: Double) {
        updateSelectedClipColor { $0.presetIntensity = min(max(intensity, 0), 1) }
    }

    func setSelectedClipColorValue(
        _ keyPath: WritableKeyPath<EditorColorAdjustment, Double>,
        value: Double
    ) {
        updateSelectedClipColor {
            $0[keyPath: keyPath] = min(max(value, -1), 1)
        }
    }

    func setSelectedClipHSLValue(
        color: EditorHSLColor,
        keyPath: WritableKeyPath<EditorHSLBandAdjustment, Double>,
        value: Double
    ) {
        updateSelectedClipColor { adjustment in
            var band = adjustment.hsl[color]
            band[keyPath: keyPath] = min(max(value, -1), 1)
            adjustment.hsl[color] = band
        }
    }

    func setSelectedClipToneCurve(
        channel: EditorCurveChannel,
        points: [EditorCurvePoint]
    ) {
        updateSelectedClipColor { adjustment in
            adjustment.curves[channel] = points
                .sorted { $0.x < $1.x }
                .map {
                    EditorCurvePoint(
                        x: min(max($0.x, 0), 1),
                        y: min(max($0.y, 0), 1)
                    )
                }
        }
    }

    func setSelectedClipColorWheel(
        range: EditorColorWheelRange,
        value: EditorColorWheelValue
    ) {
        updateSelectedClipColor { adjustment in
            adjustment.wheels[range] = EditorColorWheelValue(
                x: min(max(value.x, -1), 1),
                y: min(max(value.y, -1), 1),
                luminance: min(max(value.luminance, -1), 1)
            )
        }
    }

    func resetSelectedClipColor() {
        updateSelectedClipColor { $0 = .neutral }
        commitColorAdjustmentEdit()
    }

    func copySelectedClipColor() {
        copiedColorAdjustment = selectedClip?.colorAdjustment
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    func pasteColorToSelectedClip() {
        guard let copiedColorAdjustment else { return }
        updateSelectedClipColor { $0 = copiedColorAdjustment }
        commitColorAdjustmentEdit()
    }

    func applySelectedColorToAllClips() {
        guard let adjustment = selectedClip?.colorAdjustment else { return }
        beginColorAdjustmentEditIfNeeded()
        for index in clips.indices {
            clips[index].colorAdjustment = adjustment
        }
        invalidateComposition()
        commitColorAdjustmentEdit()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func commitColorAdjustmentEdit() {
        colorPreviewTask?.cancel()
        colorPreviewTask = nil
        finalizeColorAdjustmentUndo()
        Task { await alignPlaybackToTimeline() }
    }

    private func updateSelectedClipColor(_ update: (inout EditorColorAdjustment) -> Void) {
        beginColorAdjustmentEditIfNeeded()
        guard let id = selectedClipID,
              let index = clips.firstIndex(where: { $0.id == id }) else { return }
        update(&clips[index].colorAdjustment)
        invalidateComposition()
        scheduleColorPreviewRefresh()
    }

    private func beginColorAdjustmentEditIfNeeded() {
        if colorUndoSnapshot == nil {
            colorUndoSnapshot = currentSnapshot()
        }
    }

    private func finalizeColorAdjustmentUndo() {
        colorPreviewTask?.cancel()
        colorPreviewTask = nil
        guard let before = colorUndoSnapshot else { return }
        colorUndoSnapshot = nil
        if before != currentSnapshot() {
            undoManager.pushUndoState(before)
            refreshUndoState()
            scheduleSave()
        }
    }

    private func scheduleColorPreviewRefresh() {
        colorPreviewTask?.cancel()
        colorPreviewTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(90))
            guard !Task.isCancelled, let self else { return }
            await self.alignPlaybackToTimeline()
        }
    }

    // MARK: Crop and reframe

    func setSelectedClipCropAspect(_ aspect: EditorCropAspect) {
        updateSelectedClipReframe { $0.cropAspect = aspect }
    }

    func setSelectedClipReframeMode(_ mode: EditorReframeMode) {
        updateSelectedClipReframe { $0.reframeMode = mode }
    }

    func rotateSelectedClipClockwise() {
        updateSelectedClipReframe {
            $0.rotationQuarterTurns = ($0.rotationQuarterTurns + 1) % 4
        }
    }

    func toggleSelectedClipHorizontalFlip() {
        updateSelectedClipReframe { $0.isFlippedHorizontally.toggle() }
    }

    func toggleSelectedClipVerticalFlip() {
        updateSelectedClipReframe { $0.isFlippedVertically.toggle() }
    }

    func setSelectedClipStraighten(_ degrees: Double) {
        updateSelectedClipReframe { $0.straightenDegrees = min(max(degrees, -45), 45) }
    }

    func setSelectedClipReframeScale(_ scale: CGFloat) {
        updateSelectedClipReframe { $0.reframeScale = min(max(scale, 0.5), 4) }
    }

    func centerSelectedClipReframe() {
        updateSelectedClipReframe {
            $0.straightenDegrees = 0
            $0.reframeScale = 1
            $0.reframeXOffset = 0
            $0.reframeYOffset = 0
        }
    }

    func beginSelectedClipReframeDrag() {
        beginReframeEditIfNeeded()
        guard reframePositionDragOrigin == nil, let clip = selectedClip else { return }
        reframePositionDragOrigin = (clip.reframeXOffset, clip.reframeYOffset)
    }

    func updateSelectedClipReframeDrag(translation: CGSize, canvasSize: CGSize) {
        guard let id = selectedClipID,
              let origin = reframePositionDragOrigin,
              canvasSize.width > 0,
              canvasSize.height > 0,
              let index = clips.firstIndex(where: { $0.id == id }) else { return }
        clips[index].reframeXOffset = min(max(origin.x + translation.width / canvasSize.width, -1), 1)
        clips[index].reframeYOffset = min(max(origin.y + translation.height / canvasSize.height, -1), 1)
        invalidateComposition()
    }

    func resetSelectedClipReframe() {
        updateSelectedClipReframe {
            $0.cropAspect = .original
            $0.reframeMode = .fit
            $0.rotationQuarterTurns = 0
            $0.straightenDegrees = 0
            $0.isFlippedHorizontally = false
            $0.isFlippedVertically = false
            $0.reframeScale = 1
            $0.reframeXOffset = 0
            $0.reframeYOffset = 0
        }
    }

    func commitSelectedClipReframe() {
        reframePositionDragOrigin = nil
        finalizeReframeEditUndo()
        Task { await alignPlaybackToTimeline() }
    }

    private func updateSelectedClipReframe(_ update: (inout EditorClip) -> Void) {
        beginReframeEditIfNeeded()
        guard let id = selectedClipID,
              let index = clips.firstIndex(where: { $0.id == id }) else { return }
        update(&clips[index])
        invalidateComposition()
    }

    private func beginReframeEditIfNeeded() {
        if reframeUndoSnapshot == nil {
            reframeUndoSnapshot = currentSnapshot()
        }
    }

    private func finalizeReframeEditUndo() {
        guard let before = reframeUndoSnapshot else { return }
        reframeUndoSnapshot = nil
        reframePositionDragOrigin = nil
        if before != currentSnapshot() {
            undoManager.pushUndoState(before)
            refreshUndoState()
            scheduleSave()
        }
    }

    // MARK: Video overlays

    func addOverlayClips(from media: [MediaItem]) {
        let videos = media.filter { $0.asset.mediaType == .video }
        guard !videos.isEmpty else { return }

        registerUndoIfNeeded()
        var insertionTime = timelinePosition
        var added: [EditorOverlayClip] = []
        var nextLane = (overlayClips.map(\.laneIndex).max() ?? -1) + 1
        for item in videos {
            let clip = EditorOverlayClip(
                asset: item.asset,
                timelineStart: insertionTime,
                laneIndex: nextLane
            )
            overlayClips.append(clip)
            added.append(clip)
            insertionTime += clip.duration
            nextLane += 1
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

    func deleteSelectedOverlayClip() {
        guard let id = selectedOverlayClipID else { return }
        registerUndoIfNeeded()
        overlayClips.removeAll { $0.id == id }
        selectedOverlayClipID = overlayClips.first?.id
        invalidateComposition()
        scheduleSave()
        Task { await alignPlaybackToTimeline() }
    }

    func splitSelectedOverlayAtPlayhead() {
        guard let id = selectedOverlayClipID,
              let index = overlayClips.firstIndex(where: { $0.id == id }) else { return }
        let clip = overlayClips[index]
        let minimumTimelineSpan = EditorOverlayClip.minimumSpan / TimeInterval(max(clip.speed, 0.001))
        guard timelinePosition > clip.timelineStart + minimumTimelineSpan,
              timelinePosition < clip.timelineEnd - minimumTimelineSpan else { return }

        let sourceTime = clip.sourceTime(forTimelineLocal: timelinePosition - clip.timelineStart)
        guard let parts = clip.split(atSourceTime: sourceTime) else { return }
        registerUndoIfNeeded()
        overlayClips[index] = parts.left
        overlayClips.insert(parts.right, at: index + 1)
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
        let minimumSpan = EditorClip.minimumSourceSpan(speed: overlayClips[index].speed)
        let start = min(max(0, trimStart), overlayClips[index].originalDuration - minimumSpan)
        let end = max(
            min(overlayClips[index].originalDuration, trimEnd),
            start + minimumSpan
        )
        overlayClips[index].trimStart = start
        overlayClips[index].trimEnd = end
        invalidateComposition()
    }

    func commitOverlayTrim(clipID: UUID) {
        if let before = overlayTrimUndoSnapshot,
           let index = overlayClips.firstIndex(where: { $0.id == clipID }),
           let baseline = before.overlayClips.first(where: { $0.id == clipID }) {
            overlayClips[index].timelineStart = max(
                0,
                baseline.timelineStart
                    + (overlayClips[index].trimStart - baseline.trimStart)
                    / TimeInterval(max(overlayClips[index].speed, 0.001))
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
        overlayClips[index].timelineStart = max(0, timelineStart)
        invalidateComposition()
    }

    func commitOverlayMove() {
        let before = overlayMoveUndoSnapshot
        overlayMoveUndoSnapshot = nil
        commitOverlayUndoSnapshot(before)
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

    private func finalizeOverlayTransform() {
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

    // MARK: Photo duration

    func setPhotoDuration(clipID: UUID, duration: TimeInterval) {
        guard let idx = clips.firstIndex(where: { $0.id == clipID }),
              clips[idx].isPhoto else { return }
        if photoDurationUndoSnapshot == nil {
            photoDurationUndoSnapshot = currentSnapshot()
        }

        let clampedDuration = min(
            max(duration, EditorClip.photoMinimumDuration),
            EditorClip.photoMaximumDuration
        )
        var clip = clips[idx]
        let sourceSpan = clampedDuration * TimeInterval(max(clip.speed, 0.001))
        clip.originalDuration = sourceSpan
        clip.trimStart = 0
        clip.trimEnd = sourceSpan
        clips[idx] = clip

        timelinePosition = min(timelinePosition, totalDuration)
        invalidateComposition()
    }

    func commitPhotoDuration(clipID: UUID, duration: TimeInterval) {
        setPhotoDuration(clipID: clipID, duration: duration)
        finalizePhotoDurationEditUndo()
        photoDurationUndoSnapshot = currentSnapshot()
        Task { await alignPlaybackToTimeline() }
    }

    private func finalizePhotoDurationEditUndo() {
        guard let before = photoDurationUndoSnapshot else { return }
        if before != currentSnapshot() {
            undoManager.pushUndoState(before)
            refreshUndoState()
            scheduleSave()
        }
        photoDurationUndoSnapshot = nil
    }

    // MARK: Volume

    func setVolume(clipID: UUID, volume: Float) {
        guard let idx = clips.firstIndex(where: { $0.id == clipID }) else { return }
        if volumeUndoSnapshot == nil {
            volumeUndoSnapshot = currentSnapshot()
        }
        var clip = clips[idx]
        clip.volume = min(max(volume, 0), 1.0)
        clips[idx] = clip
        invalidateComposition()
    }

    func commitVolume(clipID: UUID, volume: Float) {
        setVolume(clipID: clipID, volume: volume)
        finalizeVolumeEditUndo()
        volumeUndoSnapshot = currentSnapshot()
        Task { await alignPlaybackToTimeline() }
    }

    private func finalizeVolumeEditUndo() {
        guard let before = volumeUndoSnapshot else { return }
        if before != currentSnapshot() {
            undoManager.pushUndoState(before)
            refreshUndoState()
            scheduleSave()
        }
        volumeUndoSnapshot = nil
    }

    // MARK: Transitions

    func transition(for target: EditorTransitionTarget) -> (
        kind: EditorTransitionKind,
        duration: TimeInterval
    )? {
        switch target {
        case .opening:
            guard !clips.isEmpty else { return nil }
            return (openingTransitionKind, openingTransitionDuration)
        case .closing:
            guard !clips.isEmpty else { return nil }
            return (closingTransitionKind, closingTransitionDuration)
        case .cut(let index):
            return transition(afterClipAt: index)
        }
    }

    func transition(afterClipAt index: Int) -> (kind: EditorTransitionKind, duration: TimeInterval)? {
        guard index >= 0, index < clips.count - 1 else { return nil }
        return (clips[index].transitionKind, clips[index].transitionDuration)
    }

    func maximumTransitionDuration(for target: EditorTransitionTarget) -> TimeInterval {
        switch target {
        case .opening:
            return min(2, clips.first?.duration ?? 0)
        case .closing:
            return min(2, clips.last?.duration ?? 0)
        case .cut(let index):
            return maximumTransitionDuration(afterClipAt: index)
        }
    }

    func maximumTransitionDuration(afterClipAt index: Int) -> TimeInterval {
        guard index >= 0, index < clips.count - 1 else { return 0 }
        return min(2, min(clips[index].duration, clips[index + 1].duration))
    }

    func beginTransitionEditing() {
        pausePlaybackForEdit()
        transitionUndoSnapshot = currentSnapshot()
    }

    func previewTransition(
        kind: EditorTransitionKind,
        duration: TimeInterval,
        target: EditorTransitionTarget,
        applyToAll: Bool
    ) {
        // Every preview starts from the sheet's opening state. This makes
        // "Apply to all" reversible while the sheet is still open.
        if let baseline = transitionUndoSnapshot {
            clips = baseline.clips
            openingTransitionKind = baseline.openingTransitionKind
            openingTransitionDuration = baseline.openingTransitionDuration
            closingTransitionKind = baseline.closingTransitionKind
            closingTransitionDuration = baseline.closingTransitionDuration
        }

        switch target {
        case .opening:
            guard !clips.isEmpty else { return }
            openingTransitionKind = kind
            openingTransitionDuration = kind == .none
                ? 0
                : min(max(0.1, duration), maximumTransitionDuration(for: .opening))
        case .closing:
            guard !clips.isEmpty else { return }
            closingTransitionKind = kind
            closingTransitionDuration = kind == .none
                ? 0
                : min(max(0.1, duration), maximumTransitionDuration(for: .closing))
        case .cut(let index):
            guard index >= 0, index < clips.count - 1 else { return }
            let indices = applyToAll ? Array(0..<(clips.count - 1)) : [index]
            for boundaryIndex in indices {
                let maxDuration = maximumTransitionDuration(afterClipAt: boundaryIndex)
                clips[boundaryIndex].transitionKind = kind
                clips[boundaryIndex].transitionDuration = kind == .none
                    ? 0
                    : min(max(0.1, duration), maxDuration)
            }
        }

        invalidateComposition()
        playTransitionPreview(target: target)
    }

    func commitTransitionEditing() {
        guard let before = transitionUndoSnapshot else { return }
        if before.clips != clips
            || before.openingTransitionKind != openingTransitionKind
            || before.openingTransitionDuration != openingTransitionDuration
            || before.closingTransitionKind != closingTransitionKind
            || before.closingTransitionDuration != closingTransitionDuration {
            undoManager.pushUndoState(before)
            refreshUndoState()
            scheduleSave()
        }
        transitionUndoSnapshot = nil
    }

    func cancelTransitionEditing() {
        guard let before = transitionUndoSnapshot else { return }
        clips = before.clips
        openingTransitionKind = before.openingTransitionKind
        openingTransitionDuration = before.openingTransitionDuration
        closingTransitionKind = before.closingTransitionKind
        closingTransitionDuration = before.closingTransitionDuration
        transitionUndoSnapshot = nil
        invalidateComposition()
        Task { await alignPlaybackToTimeline() }
    }

    private func playTransitionPreview(target: EditorTransitionTarget) {
        switch target {
        case .opening:
            timelinePosition = 0
        case .closing:
            timelinePosition = max(
                0,
                videoDuration - max(0.35, closingTransitionDuration)
            )
        case .cut(let index):
            let cutTime = timelineOffsetForClipIndex(index + 1)
            let duration = max(0.35, clips[index].transitionDuration)
            timelinePosition = max(0, cutTime - duration)
        }
        Task {
            await ensureCompositionPlayer(resumePlaying: true)
            isPlaying = true
            startPlaybackTicking()
        }
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
            selectedAudioClipID = nil
            selectedOverlayClipID = nil
            isTextEditorPresented = false
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

    func moveTextOverlayOnTimeline(id: UUID, startTime: TimeInterval) {
        if textMoveUndoSnapshot == nil {
            textMoveUndoSnapshot = currentSnapshot()
        }
        guard let idx = textOverlays.firstIndex(where: { $0.id == id }) else { return }
        let duration = textOverlays[idx].duration
        let clampedStart = max(0, startTime)
        textOverlays[idx].startTime = clampedStart
        textOverlays[idx].endTime = clampedStart + duration
    }

    func commitTextOverlayMove() {
        if let before = textMoveUndoSnapshot {
            if before != currentSnapshot() {
                undoManager.pushUndoState(before)
                refreshUndoState()
                scheduleSave()
            }
            textMoveUndoSnapshot = nil
        }
    }

    private func clearTextOverlayEditUndo() {
        textEditUndoSnapshot = nil
        textEditDragOrigin = nil
        textTimeRangeUndoSnapshot = nil
        textMoveUndoSnapshot = nil
    }

    // MARK: Clips

    func setTrim(clipID: UUID, trimStart: TimeInterval, trimEnd: TimeInterval) {
        if trimUndoSnapshot == nil {
            trimUndoSnapshot = currentSnapshot()
        }

        guard let idx = clips.firstIndex(where: { $0.id == clipID }) else { return }
        var clip = clips[idx]
        let minSpan = EditorClip.minimumSourceSpan(speed: clip.speed)

        let start: TimeInterval
        let end: TimeInterval
        if clip.isPhoto {
            start = max(0, min(trimStart, trimEnd - minSpan))
            end = max(trimEnd, start + minSpan)
            clip.originalDuration = end
        } else {
            start = min(max(0, trimStart), clip.originalDuration - minSpan)
            end = max(min(clip.originalDuration, trimEnd), start + minSpan)
        }

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

    // MARK: Audio Clips

    func loadAudioClip(from sourceURL: URL, insertAfterIndex: Int? = nil) {
        guard sourceURL.startAccessingSecurityScopedResource() else { return }
        defer { sourceURL.stopAccessingSecurityScopedResource() }

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
            let originalDuration: TimeInterval
            if let cmDuration = try? await avAsset.load(.duration) {
                originalDuration = cmDuration.seconds
            } else {
                originalDuration = totalDuration
            }

            await MainActor.run {
                registerUndoIfNeeded()
                let title = sourceURL.deletingPathExtension().lastPathComponent
                let sorted = sortedAudioClips
                let timelineStart: TimeInterval
                let insertAt: Int

                if let idx = insertAfterIndex, idx >= 0, idx < sorted.count {
                    timelineStart = sorted[idx].timelineEnd
                    insertAt = idx + 1
                } else if let last = sorted.last {
                    timelineStart = last.timelineEnd
                    insertAt = audioClips.count
                } else {
                    timelineStart = 0
                    insertAt = audioClips.count
                }

                let clip = EditorAudioClip(
                    title: title,
                    fileURL: dest,
                    originalDuration: originalDuration,
                    timelineStart: timelineStart
                )

                if insertAt >= audioClips.count {
                    audioClips.append(clip)
                } else {
                    let targetID = sorted[insertAt].id
                    if let rawIndex = audioClips.firstIndex(where: { $0.id == targetID }) {
                        audioClips.insert(clip, at: rawIndex)
                    } else {
                        audioClips.append(clip)
                    }
                }

                selectAudioClip(clip.id)
                invalidateComposition()
                scheduleSave()
                Task { await alignPlaybackToTimeline() }
            }
        }
    }

    func deleteSelectedAudioClip() {
        guard let id = selectedAudioClipID,
              let index = audioClips.firstIndex(where: { $0.id == id }) else { return }
        registerUndoIfNeeded()
        let removed = audioClips.remove(at: index)
        releaseAudioFileIfUnused(removed.fileURL)
        selectedAudioClipID = audioClips.first?.id
        if selectedAudioClipID == nil { selectedTool = nil }
        invalidateComposition()
        scheduleSave()
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
        audioClips[idx].timelineStart = max(0, timelineStart)
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

    private func finalizeAudioVolumeEditUndo() {
        guard let before = audioVolumeUndoSnapshot else { return }
        if before != currentSnapshot() {
            undoManager.pushUndoState(before)
            refreshUndoState()
            scheduleSave()
        }
        audioVolumeUndoSnapshot = nil
    }

    private func releaseAudioFileIfUnused(_ url: URL) {
        let stillUsed = audioClips.contains { $0.fileURL == url }
        guard !stillUsed else { return }
        try? FileManager.default.removeItem(at: url)
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
        commitProjectTitle()
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
                let audioClipsSnapshot = audioClips
                let overlayClipsSnapshot = overlayClips
                let openingKindSnapshot = openingTransitionKind
                let openingDurationSnapshot = openingTransitionDuration
                let closingKindSnapshot = closingTransitionKind
                let closingDurationSnapshot = closingTransitionDuration
                let projectTitleSnapshot = projectTitle
                let url = try await EditorExportService.export(
                    clips: clipsSnapshot,
                    textOverlays: textOverlaysSnapshot,
                    audioClips: audioClipsSnapshot,
                    overlayClips: overlayClipsSnapshot,
                    openingTransitionKind: openingKindSnapshot,
                    openingTransitionDuration: openingDurationSnapshot,
                    closingTransitionKind: closingKindSnapshot,
                    closingTransitionDuration: closingDurationSnapshot,
                    settings: settings,
                    projectTitle: projectTitleSnapshot
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

    func commitProjectTitle() {
        let trimmed = projectTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            projectTitle = "Untitled Project"
        } else {
            projectTitle = trimmed
        }
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
            openingTransitionKind: openingTransitionKind,
            openingTransitionDuration: openingTransitionDuration,
            closingTransitionKind: closingTransitionKind,
            closingTransitionDuration: closingTransitionDuration,
            timelinePosition: timelinePosition,
            selectedClipID: selectedClipID,
            selectedAudioClipID: selectedAudioClipID,
            selectedOverlayClipID: selectedOverlayClipID,
            textOverlays: textOverlays,
            audioClips: audioClips,
            overlayClips: overlayClips
        )
    }

    private func applySnapshot(_ snapshot: EditorTimelineSnapshot) {
        clips = snapshot.clips
        openingTransitionKind = snapshot.openingTransitionKind
        openingTransitionDuration = snapshot.openingTransitionDuration
        closingTransitionKind = snapshot.closingTransitionKind
        closingTransitionDuration = snapshot.closingTransitionDuration
        timelinePosition = min(snapshot.timelinePosition, totalDuration)
        selectedClipID = snapshot.selectedClipID
        selectedAudioClipID = snapshot.selectedAudioClipID
        selectedOverlayClipID = snapshot.selectedOverlayClipID
        textOverlays = snapshot.textOverlays
        audioClips = snapshot.audioClips
        overlayClips = snapshot.overlayClips
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
            audioClips: audioClips.map { SavedAudioClip(from: $0) },
            overlayClips: overlayClips.map { SavedOverlayClip(from: $0) },
            openingTransitionKind: openingTransitionKind,
            openingTransitionDuration: openingTransitionDuration,
            closingTransitionKind: closingTransitionKind,
            closingTransitionDuration: closingTransitionDuration,
            timelinePosition: timelinePosition,
            selectedClipID: selectedClipID,
            selectedAudioClipID: selectedAudioClipID,
            selectedOverlayClipID: selectedOverlayClipID
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
        let clipsHash = clips.map { clip in
            "\(clip.id.uuidString)|\(clip.trimStart)|\(clip.trimEnd)|\(clip.speed)|\(clip.volume)|\(clip.cropAspect.rawValue)|\(clip.reframeMode.rawValue)|\(clip.rotationQuarterTurns)|\(clip.straightenDegrees)|\(clip.isFlippedHorizontally)|\(clip.isFlippedVertically)|\(clip.reframeScale)|\(clip.reframeXOffset)|\(clip.reframeYOffset)|\(clip.colorAdjustment)|\(clip.transitionKind.rawValue)|\(clip.transitionDuration)|\(clip.duration)|\(clip.asset.localIdentifier)"
        }.joined(separator: ";")
        let audioHash = audioClips.map {
            "\($0.id.uuidString)|\($0.trimStart)|\($0.trimEnd)|\($0.timelineStart)|\($0.volume)|\($0.fadeInDuration)|\($0.fadeOutDuration)|\($0.fileURL.path)"
        }.joined(separator: ";")
        let overlayHash = overlayClips.map {
            "\($0.id.uuidString)|\($0.trimStart)|\($0.trimEnd)|\($0.timelineStart)|\($0.laneIndex)|\($0.speed)|\($0.scale)|\($0.xOffset)|\($0.yOffset)|\($0.opacity)|\($0.volume)|\($0.asset.localIdentifier)"
        }.joined(separator: ";")
        let openingHash = "\(openingTransitionKind.rawValue)|\(openingTransitionDuration)"
        let closingHash = "\(closingTransitionKind.rawValue)|\(closingTransitionDuration)"
        return clipsHash + "|||" + audioHash + "|||" + overlayHash + "|||" + openingHash + "|||" + closingHash
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
        let audioClipsSnapshot = audioClips
        let overlayClipsSnapshot = overlayClips
        let openingKindSnapshot = openingTransitionKind
        let openingDurationSnapshot = openingTransitionDuration
        let closingKindSnapshot = closingTransitionKind
        let closingDurationSnapshot = closingTransitionDuration

        let item: AVPlayerItem?
        if audioClipsSnapshot.isEmpty,
           overlayClipsSnapshot.isEmpty,
           openingKindSnapshot == .none,
           closingKindSnapshot == .none,
           let warmed = EditorCompositionBuilder.consumeWarmedPlayerItem(matching: clipsSnapshot) {
            item = warmed
        } else {
            item = await Task.detached(priority: .userInitiated) {
                await EditorCompositionBuilder.makePlayerItem(
                    from: clipsSnapshot,
                    audioClips: audioClipsSnapshot,
                    overlayClips: overlayClipsSnapshot,
                    openingTransitionKind: openingKindSnapshot,
                    openingTransitionDuration: openingDurationSnapshot,
                    closingTransitionKind: closingKindSnapshot,
                    closingTransitionDuration: closingDurationSnapshot
                )
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
