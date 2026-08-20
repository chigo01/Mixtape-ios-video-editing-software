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
    var canvasSettings: EditorCanvasSettings
    var exportInPoint: TimeInterval?
    var exportOutPoint: TimeInterval?

    /// Global playhead: 0 … totalDuration across every clip in order.
    var timelinePosition: TimeInterval = 0
    private(set) var snapGuideTime: TimeInterval?

    var isPlaying: Bool = false
    var selectedTool: EditorTool?
    var showsReframeSafeAreaGuides: Bool = true
    var selectedColorMaskID: UUID?
    var isColorMaskEditing = false
    var showsColorMaskOverlay = true
    private(set) var colorMaskTrackingDirection: EditorColorMaskTrackingDirection?
    private(set) var colorMaskTrackingMessage: String?
    var selectedMotionTrackID: UUID?
    private(set) var isTrackingSubject = false
    private(set) var motionTrackingMessage: String?
    /// Live preview canvas size in points, kept fresh by
    /// `MotionTrackingSelectionLayer`'s `GeometryReader` while the tracking
    /// box is on screen. Text overlay offsets themselves are stored in
    /// `EditorTextOverlayLayout` reference points, not this size.
    @ObservationIgnored
    var activeTrackingCanvasSize: CGSize?
    private(set) var stabilizationAnalysisProgress: Double?

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
    private var overlayCompositingPreviewTask: Task<Void, Never>?
    @ObservationIgnored
    private var colorMaskTrackingTask: Task<Void, Never>?
    @ObservationIgnored
    private var colorMaskTrackingSessionID: UUID?
    @ObservationIgnored
    private var motionTrackingTask: Task<Void, Never>?
    @ObservationIgnored
    private var motionTrackingSessionID: UUID?
    @ObservationIgnored
    private var motionTrackingUndoSnapshot: EditorTimelineSnapshot?
    @ObservationIgnored
    private var motionPreviewTask: Task<Void, Never>?
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
    private var overlayCompositingUndoSnapshot: EditorTimelineSnapshot?
    @ObservationIgnored
    private var overlayPositionDragOrigin: (x: CGFloat, y: CGFloat)?
    @ObservationIgnored
    private var transitionUndoSnapshot: EditorTimelineSnapshot?
    @ObservationIgnored
    private var saveTask: Task<Void, Never>?
    @ObservationIgnored
    private var lastHapticSnapTime: TimeInterval?

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
        var savedOrderByLane: [Int: Int] = [:]
        for overlay in resolvedOverlays {
            let savedOrder = overlay.zIndex >= 0 ? overlay.zIndex : overlay.laneIndex
            savedOrderByLane[overlay.laneIndex] = min(
                savedOrderByLane[overlay.laneIndex] ?? savedOrder,
                savedOrder
            )
        }
        let orderedLayerLanes = savedOrderByLane.keys.sorted { lhs, rhs in
            let lhsOrder = savedOrderByLane[lhs] ?? lhs
            let rhsOrder = savedOrderByLane[rhs] ?? rhs
            return lhsOrder == rhsOrder ? lhs < rhs : lhsOrder < rhsOrder
        }
        var normalizedZIndex: [Int: Int] = [:]
        for (order, lane) in orderedLayerLanes.enumerated() {
            normalizedZIndex[lane] = order
        }
        for index in resolvedOverlays.indices {
            resolvedOverlays[index].zIndex = normalizedZIndex[resolvedOverlays[index].laneIndex] ?? 0
        }
        self.overlayClips = resolvedOverlays
        self.selectedOverlayClipID = project.selectedOverlayClipID
        self.canvasSettings = project.canvasSettings
        self.exportInPoint = project.exportInPoint
        self.exportOutPoint = project.exportOutPoint
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

    private func normalizeExportRange() {
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

    var selectedReframeClip: EditorClip? {
        selectedOverlayClip?.thumbnailClip ?? selectedClip
    }

    var selectedDurationClip: EditorClip? {
        selectedOverlayClip?.thumbnailClip ?? selectedClip
    }

    // MARK: Keyframes

    var availableKeyframeProperties: [EditorKeyframeProperty] {
        if selectedOverlayClip != nil {
            return [
                .positionX, .positionY, .scale, .rotation, .opacity, .volume,
                .cropX, .cropY, .cropScale, .filterIntensity, .effectAmount
            ]
        }
        if selectedAudioClip != nil { return [.volume] }
        if selectedTextOverlay != nil {
            return [.textPositionX, .textPositionY, .textScale, .textRotation, .opacity, .effectAmount]
        }
        if selectedClip != nil {
            return [
                .positionX, .positionY, .scale, .rotation, .opacity, .volume,
                .cropX, .cropY, .cropScale, .filterIntensity, .effectAmount
            ]
        }
        return []
    }

    var keyframeTargetTitle: String {
        if selectedOverlayClip != nil { return "Media Overlay" }
        if selectedAudioClip != nil { return "Audio" }
        if selectedTextOverlay != nil { return "Text" }
        return "Clip"
    }

    var keyframeTargetDuration: TimeInterval {
        if let overlay = selectedOverlayClip { return overlay.duration }
        if let audio = selectedAudioClip { return audio.duration }
        if let text = selectedTextOverlay { return text.duration }
        return selectedClip?.duration ?? 0
    }

    var keyframeLocalTime: TimeInterval {
        min(
            max(0, timelinePosition - selectedKeyframeTargetStartTime),
            keyframeTargetDuration
        )
    }

    func selectedKeyframeTrack(for property: EditorKeyframeProperty) -> EditorKeyframeTrack {
        selectedKeyframeTracks.track(for: property)
    }

    func selectedKeyframeValue(for property: EditorKeyframeProperty) -> Double {
        selectedKeyframeTracks.value(
            for: property,
            at: keyframeLocalTime,
            default: keyframeBaseValue(for: property)
        )
    }

    @discardableResult
    func upsertSelectedKeyframe(
        property: EditorKeyframeProperty,
        value: Double,
        curve: EditorKeyframeCurve = .linear
    ) -> UUID? {
        guard availableKeyframeProperties.contains(property) else { return nil }
        registerUndoIfNeeded()
        var tracks = selectedKeyframeTracks
        var track = tracks.track(for: property)
        let id = track.upsert(at: keyframeLocalTime, value: value, curve: curve)
        tracks.replace(track)
        setSelectedKeyframeTracks(tracks)
        finishKeyframeMutation()
        return id
    }

    func updateSelectedKeyframe(
        property: EditorKeyframeProperty,
        id: UUID,
        time: TimeInterval? = nil,
        value: Double? = nil
    ) {
        var tracks = selectedKeyframeTracks
        var track = tracks.track(for: property)
        guard track.keyframes.contains(where: { $0.id == id }) else { return }
        registerUndoIfNeeded()
        track.update(
            id: id,
            time: time.map { min(max(0, $0), keyframeTargetDuration) },
            value: value
        )
        tracks.replace(track)
        setSelectedKeyframeTracks(tracks)
        finishKeyframeMutation()
    }

    func updateSelectedKeyframeCurve(
        property: EditorKeyframeProperty,
        id: UUID,
        curve: EditorKeyframeCurve
    ) {
        var tracks = selectedKeyframeTracks
        var track = tracks.track(for: property)
        guard track.keyframes.contains(where: { $0.id == id }) else { return }
        registerUndoIfNeeded()
        track.updateCurve(id: id, curve: curve)
        tracks.replace(track)
        setSelectedKeyframeTracks(tracks)
        finishKeyframeMutation()
    }

    func deleteSelectedKeyframe(property: EditorKeyframeProperty, id: UUID) {
        var tracks = selectedKeyframeTracks
        var track = tracks.track(for: property)
        guard track.keyframes.contains(where: { $0.id == id }) else { return }
        registerUndoIfNeeded()
        track.remove(id: id)
        tracks.replace(track)
        setSelectedKeyframeTracks(tracks)
        finishKeyframeMutation()
    }

    func seekToSelectedKeyframe(localTime: TimeInterval) {
        seekTimeline(
            to: selectedKeyframeTargetStartTime
                + min(max(0, localTime), keyframeTargetDuration)
        )
    }

    func scrubSelectedKeyframePlayhead(to localTime: TimeInterval) {
        if isPlaying {
            stopPlaybackTicking()
            player?.pause()
            isPlaying = false
        }
        timelinePosition = min(
            max(
                0,
                selectedKeyframeTargetStartTime
                    + min(max(0, localTime), keyframeTargetDuration)
            ),
            totalDuration
        )
    }

    func commitSelectedKeyframePlayhead() {
        commitTimelineAfterScrub()
    }

    private var selectedKeyframeTracks: EditorKeyframeTracks {
        if let overlay = selectedOverlayClip { return overlay.keyframes }
        if let audio = selectedAudioClip { return audio.keyframes }
        if let text = selectedTextOverlay { return text.keyframes }
        return selectedClip?.keyframes ?? .empty
    }

    private var selectedKeyframeTargetStartTime: TimeInterval {
        if let overlay = selectedOverlayClip { return overlay.timelineStart }
        if let audio = selectedAudioClip { return audio.timelineStart }
        if let text = selectedTextOverlay { return text.startTime }
        if let id = selectedClipID,
           let index = clips.firstIndex(where: { $0.id == id }) {
            return timelineOffsetForClipIndex(index)
        }
        return 0
    }

    private func setSelectedKeyframeTracks(_ tracks: EditorKeyframeTracks) {
        if let id = selectedOverlayClipID,
           let index = overlayClips.firstIndex(where: { $0.id == id }) {
            overlayClips[index].keyframes = tracks
        } else if let id = selectedAudioClipID,
                  let index = audioClips.firstIndex(where: { $0.id == id }) {
            audioClips[index].keyframes = tracks
        } else if let id = selectedTextOverlayID,
                  let index = textOverlays.firstIndex(where: { $0.id == id }) {
            textOverlays[index].keyframes = tracks
        } else if let id = selectedClipID,
                  let index = clips.firstIndex(where: { $0.id == id }) {
            clips[index].keyframes = tracks
        }
    }

    private func keyframeBaseValue(for property: EditorKeyframeProperty) -> Double {
        if let overlay = selectedOverlayClip {
            switch property {
            case .positionX: return Double(overlay.xOffset)
            case .positionY: return Double(overlay.yOffset)
            case .scale: return Double(overlay.scale)
            case .rotation: return overlay.straightenDegrees
            case .opacity: return overlay.opacity
            case .volume: return Double(overlay.volume)
            case .cropX: return Double(overlay.reframeXOffset)
            case .cropY: return Double(overlay.reframeYOffset)
            case .cropScale: return Double(overlay.reframeScale)
            case .filterIntensity: return overlay.colorAdjustment.presetIntensity
            default: return property.neutralValue
            }
        }
        if let audio = selectedAudioClip {
            return property == .volume ? Double(audio.volume) : property.neutralValue
        }
        if let text = selectedTextOverlay {
            switch property {
            case .textPositionX: return Double(text.xOffset)
            case .textPositionY: return Double(text.yOffset)
            case .opacity: return text.opacity
            default: return property.neutralValue
            }
        }
        if let clip = selectedClip {
            switch property {
            case .positionX: return Double(clip.reframeXOffset)
            case .positionY: return Double(clip.reframeYOffset)
            case .scale: return Double(clip.reframeScale)
            case .rotation: return clip.straightenDegrees
            case .volume: return Double(clip.volume)
            case .cropX: return Double(clip.reframeXOffset)
            case .cropY: return Double(clip.reframeYOffset)
            case .cropScale: return Double(clip.reframeScale)
            case .filterIntensity: return clip.colorAdjustment.presetIntensity
            default: return property.neutralValue
            }
        }
        return property.neutralValue
    }

    private func finishKeyframeMutation() {
        invalidateComposition()
        scheduleSave()
        Task { await alignPlaybackToTimeline() }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    var sortedOverlayClips: [EditorOverlayClip] {
        overlayClips.sorted {
            if $0.timelineStart == $1.timelineStart { return $0.zIndex < $1.zIndex }
            return $0.timelineStart < $1.timelineStart
        }
    }

    private var orderedOverlayLanes: [(laneIndex: Int, zIndex: Int)] {
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
        selectedOverlayClip?.colorAdjustment ?? selectedClip?.colorAdjustment
    }

    var selectedColorAsset: PHAsset? {
        selectedOverlayClip?.asset ?? selectedClip?.asset
    }

    var selectedColorTargetID: UUID? {
        selectedOverlayClipID ?? selectedClipID
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

    // MARK: Selection

    func selectClipForEditing(_ id: UUID) {
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
        if selectedTool == .compositing {
            finalizeOverlayCompositingUndo()
        }
        if selectedTool == .track || selectedTool == .stabilize {
            finalizeMotionTrackingUndo()
        }
        cancelMotionTracking()
        selectedMotionTrackID = nil
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
        selectedClipID = nil
        selectedTextOverlayID = nil
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
        case .canvas:
            selectTool(.canvas)
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

    @discardableResult
    func addSelectedClipColorMask(_ mask: EditorColorMask) -> UUID? {
        guard (selectedColorAdjustment?.masks.count ?? 0) < 8 else { return nil }
        var sanitized = mask
        sanitizeColorMask(&sanitized)
        updateSelectedClipColor { $0.masks.append(sanitized) }
        selectedColorMaskID = sanitized.id
        return sanitized.id
    }

    func updateSelectedClipColorMask(_ mask: EditorColorMask) {
        var sanitized = mask
        sanitizeColorMask(&sanitized)
        let correctionProgress = selectedColorMaskProgress
        updateSelectedClipColor { adjustment in
            guard let index = adjustment.masks.firstIndex(where: { $0.id == sanitized.id }) else {
                return
            }
            let old = adjustment.masks[index]
            let geometryChanged = old.centerX != sanitized.centerX
                || old.centerY != sanitized.centerY
                || old.width != sanitized.width
                || old.height != sanitized.height
                || old.points != sanitized.points
            if geometryChanged,
               !old.trackingKeyframes.isEmpty,
               let correctionProgress {
                var samples = old.trackingKeyframes.filter {
                    abs($0.progress - correctionProgress) > 0.004
                }
                samples.append(
                    EditorColorMaskTrackingKeyframe(
                        progress: correctionProgress,
                        centerX: sanitized.centerX,
                        centerY: sanitized.centerY,
                        width: sanitized.width,
                        height: sanitized.height,
                        confidence: 1
                    )
                )
                sanitized.trackingKeyframes = deduplicatedTrackingSamples(samples)
            }
            adjustment.masks[index] = sanitized
        }
    }

    private var selectedColorMaskProgress: Double? {
        if let overlay = selectedOverlayClip {
            guard timelinePosition >= overlay.timelineStart,
                  timelinePosition <= overlay.timelineEnd else { return nil }
            return min(max(
                (timelinePosition - overlay.timelineStart) / max(overlay.duration, 0.001),
                0
            ), 1)
        }
        guard let id = selectedClipID,
              let index = clips.firstIndex(where: { $0.id == id }) else { return nil }
        let clip = clips[index]
        let local = timelinePosition - timelineOffsetForClipIndex(index)
        return min(max(local / max(clip.duration, 0.001), 0), 1)
    }

    func removeSelectedClipColorMask(id: UUID) {
        updateSelectedClipColor { adjustment in
            adjustment.masks.removeAll { $0.id == id }
        }
        if selectedColorMaskID == id {
            selectedColorMaskID = selectedColorAdjustment?.masks.first?.id
        }
        commitColorAdjustmentEdit()
    }

    func resetSelectedClipColorMask(id: UUID) {
        updateSelectedClipColor { adjustment in
            guard let index = adjustment.masks.firstIndex(where: { $0.id == id }) else { return }
            adjustment.masks[index].adjustment = .init()
        }
        commitColorAdjustmentEdit()
    }

    private func sanitizeColorMask(_ mask: inout EditorColorMask) {
        mask.centerX = min(max(mask.centerX, 0), 1)
        mask.centerY = min(max(mask.centerY, 0), 1)
        mask.width = min(max(mask.width, 0.04), 1.5)
        mask.height = min(max(mask.height, 0.04), 1.5)
        mask.rotation = min(max(mask.rotation, -1), 1)
        mask.feather = min(max(mask.feather, 0), 1)
        mask.opacity = min(max(mask.opacity, 0), 1)
        mask.points = Array(mask.points.prefix(12)).map { point in
            var point = point
            point.x = min(max(point.x, 0), 1)
            point.y = min(max(point.y, 0), 1)
            return point
        }
        mask.trackingKeyframes = Array(mask.trackingKeyframes.prefix(720))
            .map { keyframe in
                var keyframe = keyframe
                keyframe.progress = min(max(keyframe.progress, 0), 1)
                keyframe.centerX = min(max(keyframe.centerX, 0), 1)
                keyframe.centerY = min(max(keyframe.centerY, 0), 1)
                keyframe.width = min(max(keyframe.width, 0.02), 1.5)
                keyframe.height = min(max(keyframe.height, 0.02), 1.5)
                keyframe.confidence = min(max(keyframe.confidence, 0), 1)
                return keyframe
            }
            .sorted { $0.progress < $1.progress }
        mask.adjustment.exposure = min(max(mask.adjustment.exposure, -1), 1)
        mask.adjustment.brightness = min(max(mask.adjustment.brightness, -1), 1)
        mask.adjustment.contrast = min(max(mask.adjustment.contrast, -1), 1)
        mask.adjustment.saturation = min(max(mask.adjustment.saturation, -1), 1)
        mask.adjustment.vibrance = min(max(mask.adjustment.vibrance, -1), 1)
        mask.adjustment.temperature = min(max(mask.adjustment.temperature, -1), 1)
        mask.adjustment.tint = min(max(mask.adjustment.tint, -1), 1)
        mask.adjustment.hue = min(max(mask.adjustment.hue, -1), 1)
        mask.adjustment.smoothness = min(max(mask.adjustment.smoothness, 0), 1)
    }

    func resetSelectedClipColor() {
        updateSelectedClipColor { $0 = .neutral }
        selectedColorMaskID = nil
        commitColorAdjustmentEdit()
    }

    func currentProgramFrameForMaskDetection() async -> UIImage? {
        guard let item = player?.currentItem else { return nil }
        let generator = AVAssetImageGenerator(asset: item.asset)
        generator.videoComposition = item.videoComposition
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 720, height: 1280)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let time = player?.currentTime() ?? CMTime(seconds: timelinePosition, preferredTimescale: 600)
        guard let result = try? await generator.image(at: time) else { return nil }
        return UIImage(cgImage: result.image)
    }

    var isColorMaskTracking: Bool { colorMaskTrackingDirection != nil }

    func trackSelectedColorMask(_ direction: EditorColorMaskTrackingDirection) {
        guard colorMaskTrackingTask == nil,
              let mask = selectedColorMask,
              let item = player?.currentItem else { return }

        let target: (id: UUID, start: TimeInterval, duration: TimeInterval)
        if let overlay = selectedOverlayClip {
            guard timelinePosition >= overlay.timelineStart,
                  timelinePosition <= overlay.timelineEnd else { return }
            target = (overlay.id, overlay.timelineStart, max(overlay.duration, 0.001))
        } else if let info = playbackInfo, info.clip.id == selectedClipID {
            target = (
                info.clip.id,
                timelineOffsetForClipIndex(info.index),
                max(info.clip.duration, 0.001)
            )
        } else {
            return
        }

        let clipStart = target.start
        let clipDuration = target.duration
        let startProgress = min(max((timelinePosition - clipStart) / clipDuration, 0), 1)
        let maskID = mask.id
        let clipID = target.id
        let sessionID = UUID()
        colorMaskTrackingSessionID = sessionID
        colorMaskTrackingDirection = direction
        switch direction {
        case .forward: colorMaskTrackingMessage = "Tracking mask forward…"
        case .backward: colorMaskTrackingMessage = "Tracking mask backward…"
        }
        player?.pause()
        isPlaying = false

        colorMaskTrackingTask = Task { [weak self] in
            guard let self else { return }
            do {
                let samples = try await EditorColorMaskTracker.track(
                    mask: mask.resolved(at: startProgress),
                    asset: item.asset,
                    videoComposition: item.videoComposition,
                    clipStart: clipStart,
                    clipDuration: clipDuration,
                    startProgress: startProgress,
                    direction: direction
                )
                try Task.checkCancellation()
                guard self.colorMaskTrackingSessionID == sessionID,
                      self.selectedColorTargetID == clipID else { return }
                self.updateSelectedClipColor { adjustment in
                    guard let index = adjustment.masks.firstIndex(where: { $0.id == maskID }) else {
                        return
                    }
                    var trackedMask = adjustment.masks[index]
                    let retained = trackedMask.trackingKeyframes.filter { keyframe in
                        switch direction {
                        case .forward: return keyframe.progress < startProgress
                        case .backward: return keyframe.progress > startProgress
                        }
                    }
                    trackedMask.trackingKeyframes = self.deduplicatedTrackingSamples(retained + samples)
                    adjustment.masks[index] = trackedMask
                }
                self.commitColorAdjustmentEdit()
                self.colorMaskTrackingMessage = "Tracking complete · \(samples.count) motion samples"
            } catch is CancellationError {
                if self.colorMaskTrackingSessionID == sessionID {
                    self.colorMaskTrackingMessage = "Tracking cancelled"
                }
            } catch {
                if self.colorMaskTrackingSessionID == sessionID {
                    self.colorMaskTrackingMessage = error.localizedDescription
                }
            }
            guard self.colorMaskTrackingSessionID == sessionID else { return }
            self.colorMaskTrackingSessionID = nil
            self.colorMaskTrackingDirection = nil
            self.colorMaskTrackingTask = nil
        }
    }

    func cancelColorMaskTracking() {
        guard colorMaskTrackingTask != nil else { return }
        colorMaskTrackingTask?.cancel()
        colorMaskTrackingTask = nil
        colorMaskTrackingSessionID = nil
        colorMaskTrackingDirection = nil
        colorMaskTrackingMessage = "Tracking cancelled"
    }

    func clearSelectedColorMaskTracking() {
        guard let id = selectedColorMaskID else { return }
        updateSelectedClipColor { adjustment in
            guard let index = adjustment.masks.firstIndex(where: { $0.id == id }) else { return }
            adjustment.masks[index].trackingKeyframes = []
        }
        commitColorAdjustmentEdit()
        colorMaskTrackingMessage = "Mask tracking cleared"
    }

    private func deduplicatedTrackingSamples(
        _ samples: [EditorColorMaskTrackingKeyframe]
    ) -> [EditorColorMaskTrackingKeyframe] {
        var result: [EditorColorMaskTrackingKeyframe] = []
        for sample in samples.sorted(by: { $0.progress < $1.progress }) {
            if let last = result.last, abs(last.progress - sample.progress) < 0.000_01 {
                result[result.count - 1] = sample
            } else {
                result.append(sample)
            }
        }
        return result
    }

    func copySelectedClipColor() {
        copiedColorAdjustment = selectedColorAdjustment
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    func pasteColorToSelectedClip() {
        guard let copiedColorAdjustment else { return }
        updateSelectedClipColor { $0 = copiedColorAdjustment }
        commitColorAdjustmentEdit()
    }

    func applySelectedColorToAllClips() {
        guard let adjustment = selectedColorAdjustment else { return }
        beginColorAdjustmentEditIfNeeded()
        for index in clips.indices {
            clips[index].colorAdjustment = adjustment
        }
        for index in overlayClips.indices {
            overlayClips[index].colorAdjustment = adjustment
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
        if let id = selectedOverlayClipID,
           let index = overlayClips.firstIndex(where: { $0.id == id }) {
            update(&overlayClips[index].colorAdjustment)
        } else if let id = selectedClipID,
                  let index = clips.firstIndex(where: { $0.id == id }) {
            update(&clips[index].colorAdjustment)
        } else {
            return
        }
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
        guard reframePositionDragOrigin == nil, let clip = selectedReframeClip else { return }
        reframePositionDragOrigin = (clip.reframeXOffset, clip.reframeYOffset)
    }

    func updateSelectedClipReframeDrag(translation: CGSize, canvasSize: CGSize) {
        guard let origin = reframePositionDragOrigin,
              canvasSize.width > 0,
              canvasSize.height > 0 else { return }
        let x = min(max(origin.x + translation.width / canvasSize.width, -1), 1)
        let y = min(max(origin.y + translation.height / canvasSize.height, -1), 1)
        if let id = selectedOverlayClipID,
           let index = overlayClips.firstIndex(where: { $0.id == id }) {
            overlayClips[index].reframeXOffset = x
            overlayClips[index].reframeYOffset = y
        } else if let id = selectedClipID,
                  let index = clips.firstIndex(where: { $0.id == id }) {
            clips[index].reframeXOffset = x
            clips[index].reframeYOffset = y
        } else {
            return
        }
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
        if let id = selectedOverlayClipID,
           let index = overlayClips.firstIndex(where: { $0.id == id }) {
            var proxy = overlayClips[index].thumbnailClip
            update(&proxy)
            overlayClips[index].cropAspect = proxy.cropAspect
            overlayClips[index].reframeMode = proxy.reframeMode
            overlayClips[index].rotationQuarterTurns = proxy.rotationQuarterTurns
            overlayClips[index].straightenDegrees = proxy.straightenDegrees
            overlayClips[index].isFlippedHorizontally = proxy.isFlippedHorizontally
            overlayClips[index].isFlippedVertically = proxy.isFlippedVertically
            overlayClips[index].reframeScale = proxy.reframeScale
            overlayClips[index].reframeXOffset = proxy.reframeXOffset
            overlayClips[index].reframeYOffset = proxy.reframeYOffset
        } else if let id = selectedClipID,
                  let index = clips.firstIndex(where: { $0.id == id }) {
            update(&clips[index])
        } else {
            return
        }
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

    // MARK: Media overlays

    func addOverlayClips(from media: [MediaItem]) {
        let supportedMedia = media.filter {
            $0.asset.mediaType == .video || $0.asset.mediaType == .image
        }
        guard !supportedMedia.isEmpty else { return }

        registerUndoIfNeeded()
        var insertionTime = timelinePosition
        var added: [EditorOverlayClip] = []
        var nextLane = (overlayClips.map(\.laneIndex).max() ?? -1) + 1
        var nextZIndex = (overlayClips.map(\.zIndex).max() ?? -1) + 1
        for item in supportedMedia {
            let clip = EditorOverlayClip(
                asset: item.asset,
                timelineStart: insertionTime,
                laneIndex: nextLane,
                zIndex: nextZIndex
            )
            overlayClips.append(clip)
            added.append(clip)
            insertionTime += clip.duration
            nextLane += 1
            nextZIndex += 1
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

    func sendSelectedOverlayBackward() {
        moveSelectedOverlayLayer(by: -1)
    }

    func bringSelectedOverlayForward() {
        moveSelectedOverlayLayer(by: 1)
    }

    private func moveSelectedOverlayLayer(by offset: Int) {
        guard let selectedOverlayClip,
              let currentIndex = orderedOverlayLanes.firstIndex(where: {
                  $0.laneIndex == selectedOverlayClip.laneIndex
              }) else { return }
        let destinationIndex = currentIndex + offset
        guard orderedOverlayLanes.indices.contains(destinationIndex) else { return }

        let selectedLane = orderedOverlayLanes[currentIndex]
        let adjacentLane = orderedOverlayLanes[destinationIndex]
        registerUndoIfNeeded()
        for index in overlayClips.indices {
            if overlayClips[index].laneIndex == selectedLane.laneIndex {
                overlayClips[index].zIndex = adjacentLane.zIndex
            } else if overlayClips[index].laneIndex == adjacentLane.laneIndex {
                overlayClips[index].zIndex = selectedLane.zIndex
            }
        }
        invalidateComposition()
        scheduleSave()
        Task { await alignPlaybackToTimeline() }
        UISelectionFeedbackGenerator().selectionChanged()
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

    func duplicateSelectedOverlayClip() {
        guard let id = selectedOverlayClipID,
              let index = overlayClips.firstIndex(where: { $0.id == id }) else { return }
        registerUndoIfNeeded()
        let source = overlayClips[index]
        let copy = EditorOverlayClip(
            asset: source.asset,
            originalDuration: source.originalDuration,
            trimStart: source.trimStart,
            trimEnd: source.trimEnd,
            timelineStart: source.timelineEnd,
            laneIndex: source.laneIndex,
            zIndex: source.zIndex,
            speed: source.speed,
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
            compositing: source.compositing,
            keyframes: source.keyframes,
            motionTracks: source.motionTracks.map { track in
                var copy = track
                copy.id = UUID()
                return copy
            },
            stabilization: source.stabilization,
            attachedClipID: source.attachedClipID,
            attachedTrackID: source.attachedTrackID,
            attachRotation: source.attachRotation,
            attachScale: source.attachScale
        )
        overlayClips.insert(copy, at: index + 1)
        selectedOverlayClipID = copy.id
        timelinePosition = copy.timelineStart
        invalidateComposition()
        scheduleSave()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task { await alignPlaybackToTimeline() }
    }

    /// Replaces an overlay's source while retaining its timing, grade, crop,
    /// transform, layer order, opacity, audio, and keyframe edits.
    func replaceSelectedOverlayClip(with media: MediaItem) {
        guard let id = selectedOverlayClipID,
              let index = overlayClips.firstIndex(where: { $0.id == id }) else { return }
        registerUndoIfNeeded()
        let old = overlayClips[index]
        let rawDuration = media.asset.mediaType == .video
            ? media.asset.duration
            : EditorClip.photoDefaultDuration
        let minimumSpan = EditorClip.minimumSourceSpan(speed: old.speed)
        let sourceSpan = min(old.trimEnd - old.trimStart, rawDuration)
        let start = min(old.trimStart, max(0, rawDuration - minimumSpan))
        let end = min(rawDuration, max(start + minimumSpan, start + sourceSpan))
        overlayClips[index] = EditorOverlayClip(
            id: old.id,
            asset: media.asset,
            originalDuration: rawDuration,
            trimStart: start,
            trimEnd: end,
            timelineStart: old.timelineStart,
            laneIndex: old.laneIndex,
            zIndex: old.zIndex,
            speed: old.speed,
            scale: old.scale,
            xOffset: old.xOffset,
            yOffset: old.yOffset,
            opacity: old.opacity,
            volume: old.volume,
            cropAspect: old.cropAspect,
            reframeMode: old.reframeMode,
            rotationQuarterTurns: old.rotationQuarterTurns,
            straightenDegrees: old.straightenDegrees,
            isFlippedHorizontally: old.isFlippedHorizontally,
            isFlippedVertically: old.isFlippedVertically,
            reframeScale: old.reframeScale,
            reframeXOffset: old.reframeXOffset,
            reframeYOffset: old.reframeYOffset,
            colorAdjustment: old.colorAdjustment,
            compositing: old.compositing,
            keyframes: old.keyframes,
            attachedClipID: old.attachedClipID,
            attachedTrackID: old.attachedTrackID,
            attachRotation: old.attachRotation,
            attachScale: old.attachScale
        )
        timelinePosition = min(max(old.timelineStart, timelinePosition), overlayClips[index].timelineEnd)
        invalidateComposition()
        scheduleSave()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
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
        var clip = overlayClips[index]
        let minimumSpan = EditorClip.minimumSourceSpan(speed: clip.speed)

        if clip.isPhoto {
            let start = max(0, min(trimStart, trimEnd - minimumSpan))
            let end = max(trimEnd, start + minimumSpan)
            clip.originalDuration = end
            clip.trimStart = start
            clip.trimEnd = end
        } else {
            let start = min(max(0, trimStart), clip.originalDuration - minimumSpan)
            let end = max(min(clip.originalDuration, trimEnd), start + minimumSpan)
            clip.trimStart = start
            clip.trimEnd = end
        }

        overlayClips[index] = clip
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
        overlayClips[index].timelineStart = snappedTime(timelineStart, excluding: clipID)
        invalidateComposition()
    }

    func commitOverlayMove() {
        let before = overlayMoveUndoSnapshot
        overlayMoveUndoSnapshot = nil
        commitOverlayUndoSnapshot(before)
        clearSnapGuide()
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

    var selectedCompositing: EditorOverlayCompositing? {
        selectedOverlayClip?.compositing ?? selectedClip?.compositing
    }

    func updateSelectedCompositing(
        _ update: (inout EditorOverlayCompositing) -> Void
    ) {
        if overlayCompositingUndoSnapshot == nil {
            overlayCompositingUndoSnapshot = currentSnapshot()
        }
        guard var settings = selectedCompositing else { return }
        update(&settings)
        settings.sanitize()
        if let id = selectedOverlayClipID,
           let index = overlayClips.firstIndex(where: { $0.id == id }) {
            guard settings != overlayClips[index].compositing else { return }
            overlayClips[index].compositing = settings
        } else if let id = selectedClipID,
                  let index = clips.firstIndex(where: { $0.id == id }) {
            guard settings != clips[index].compositing else { return }
            clips[index].compositing = settings
        } else { return }
        invalidateComposition()
        scheduleOverlayCompositingPreviewRefresh()
    }

    func resetSelectedCompositing() {
        updateSelectedCompositing { $0 = .standard }
    }

    func commitOverlayCompositing() {
        finalizeOverlayCompositingUndo()
        Task { await alignPlaybackToTimeline() }
    }

    private func finalizeOverlayCompositingUndo() {
        overlayCompositingPreviewTask?.cancel()
        overlayCompositingPreviewTask = nil
        let before = overlayCompositingUndoSnapshot
        overlayCompositingUndoSnapshot = nil
        commitOverlayUndoSnapshot(before)
    }

    private func scheduleOverlayCompositingPreviewRefresh() {
        overlayCompositingPreviewTask?.cancel()
        overlayCompositingPreviewTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(90))
            guard !Task.isCancelled, let self else { return }
            await self.alignPlaybackToTimeline()
        }
    }

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

    private func finalizeMotionTrackingUndo() {
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

    private func remapMotionAttachmentsAfterSplit(
        left: EditorClip,
        right: EditorClip,
        splitTime: TimeInterval
    ) {
        let mappedIDs = zip(left.motionTracks, right.motionTracks).reduce(
            into: [UUID: UUID]()
        ) { result, pair in
            result[pair.0.id] = pair.1.id
        }
        for index in textOverlays.indices {
            guard textOverlays[index].attachedClipID == left.id,
                  textOverlays[index].startTime >= splitTime else { continue }
            textOverlays[index].attachedClipID = right.id
            if let oldTrack = textOverlays[index].attachedTrackID {
                textOverlays[index].attachedTrackID = mappedIDs[oldTrack] ?? oldTrack
            }
        }
        for index in overlayClips.indices {
            guard overlayClips[index].attachedClipID == left.id,
                  overlayClips[index].timelineStart >= splitTime else { continue }
            overlayClips[index].attachedClipID = right.id
            if let oldTrack = overlayClips[index].attachedTrackID {
                overlayClips[index].attachedTrackID = mappedIDs[oldTrack] ?? oldTrack
            }
        }
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
            guard ramp.points.indices.contains(index) else { return ramp }
            let lowerBound = index > 0 ? ramp.points[index - 1].position + 0.02 : 0
            let upperBound = index < ramp.points.count - 1
                ? ramp.points[index + 1].position - 0.02
                : 1
            let resolvedPosition: Double
            if index == 0 {
                resolvedPosition = 0
            } else if index == ramp.points.count - 1 {
                resolvedPosition = 1
            } else {
                resolvedPosition = min(max(position, lowerBound), upperBound)
            }
            ramp.points[index] = EditorSpeedRampPoint(
                position: resolvedPosition,
                speed: speed
            )
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
        clips[index].speedRamp = transform(clips[index].speedRamp)
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
        guard let overlay = textOverlays.first(where: { $0.id == id }) else { return }
        let resolved = overlay.resolved(at: timelinePosition)
        textEditDragOrigin = (resolved.xOffset, resolved.yOffset)
    }

    func updateTextOverlayPositionDrag(
        id: UUID,
        translation: CGSize,
        canvasScale: CGFloat
    ) {
        guard let origin = textEditDragOrigin,
              canvasScale > 0,
              let idx = textOverlays.firstIndex(where: { $0.id == id }) else { return }
        let x = origin.x + translation.width / canvasScale
        let y = origin.y + translation.height / canvasScale
        textOverlays[idx].xOffset = x
        textOverlays[idx].yOffset = y

        // `resolved()` reads keyframed X/Y when those tracks exist, ignoring
        // the base offset. Write through at the playhead so the glyph actually
        // follows the finger instead of appearing stuck.
        let localTime = min(
            max(0, timelinePosition - textOverlays[idx].startTime),
            textOverlays[idx].duration
        )
        var tracks = textOverlays[idx].keyframes
        var wroteKeyframe = false
        if !tracks.track(for: .textPositionX).isEmpty {
            var track = tracks.track(for: .textPositionX)
            _ = track.upsert(at: localTime, value: Double(x))
            tracks.replace(track)
            wroteKeyframe = true
        }
        if !tracks.track(for: .textPositionY).isEmpty {
            var track = tracks.track(for: .textPositionY)
            _ = track.upsert(at: localTime, value: Double(y))
            tracks.replace(track)
            wroteKeyframe = true
        }
        if wroteKeyframe {
            textOverlays[idx].keyframes = tracks
        }
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

    func duplicateSelectedTextOverlay() {
        guard let source = selectedTextOverlay else { return }
        let start = min(source.endTime, totalDuration)
        let duration = source.duration
        let copy = EditorTextOverlay(
            text: source.text, startTime: start,
            endTime: min(totalDuration, start + duration), fontSize: source.fontSize,
            fontFamily: source.fontFamily, fontStyle: source.fontStyle,
            textColor: source.textColor, opacity: source.opacity,
            horizontalAlignment: source.horizontalAlignment,
            verticalAlignment: source.verticalAlignment, xOffset: source.xOffset,
            yOffset: source.yOffset, keyframes: source.keyframes,
            attachedClipID: source.attachedClipID,
            attachedTrackID: source.attachedTrackID,
            attachRotation: source.attachRotation,
            attachScale: source.attachScale
        )
        guard copy.duration > 0.1 else { return }
        registerUndoIfNeeded()
        textOverlays.append(copy)
        selectedTextOverlayID = copy.id
        scheduleSave()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    func selectTextOverlay(_ id: UUID) {
        if selectedTextOverlayID == id {
            selectedTextOverlayID = nil
        } else {
            if selectedTool == .track || selectedTool == .stabilize {
                finalizeMotionTrackingUndo()
            }
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
        textOverlays[idx].startTime = snappedTime(start, excluding: id)
        textOverlays[idx].endTime = snappedTime(end, excluding: id)
    }

    func commitTextOverlayTimeRange() {
        if let before = textTimeRangeUndoSnapshot {
            if before != currentSnapshot() {
                undoManager.pushUndoState(before)
                refreshUndoState()
            }
            textTimeRangeUndoSnapshot = nil
        }
        clearSnapGuide()
        scheduleSave()
    }

    func moveTextOverlayOnTimeline(id: UUID, startTime: TimeInterval) {
        if textMoveUndoSnapshot == nil {
            textMoveUndoSnapshot = currentSnapshot()
        }
        guard let idx = textOverlays.firstIndex(where: { $0.id == id }) else { return }
        let duration = textOverlays[idx].duration
        let clampedStart = snappedTime(startTime, excluding: id)
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
        clearSnapGuide()
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
        let minSpan = EditorClip.minimumSourceSpan(speed: clip.averageSpeed)

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

        let splitSource = info.clip.sourceTime(forExportedLocal: info.localTime)
        guard let parts = info.clip.split(atSourceTime: splitSource) else { return }

        registerUndoIfNeeded()

        pausePlaybackForEdit()

        let index = info.index
        clips.remove(at: index)
        clips.insert(contentsOf: [parts.left, parts.right], at: index)
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
            volume: source.volume, cropAspect: source.cropAspect, reframeMode: source.reframeMode,
            rotationQuarterTurns: source.rotationQuarterTurns, straightenDegrees: source.straightenDegrees,
            isFlippedHorizontally: source.isFlippedHorizontally,
            isFlippedVertically: source.isFlippedVertically, reframeScale: source.reframeScale,
            reframeXOffset: source.reframeXOffset, reframeYOffset: source.reframeYOffset,
            colorAdjustment: source.colorAdjustment, compositing: source.compositing,
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
            colorAdjustment: old.colorAdjustment, compositing: old.compositing,
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

    func duplicateSelectedAudioClip() {
        guard let id = selectedAudioClipID, let index = audioClips.firstIndex(where: { $0.id == id }) else { return }
        registerUndoIfNeeded()
        let source = audioClips[index]
        let copy = EditorAudioClip(
            title: source.title + " Copy", fileURL: source.fileURL,
            originalDuration: source.originalDuration, trimStart: source.trimStart,
            trimEnd: source.trimEnd, timelineStart: source.timelineEnd,
            volume: source.volume, fadeInDuration: source.fadeInDuration,
            fadeOutDuration: source.fadeOutDuration, keyframes: source.keyframes
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
                let canvasSnapshot = canvasSettings
                let exportRangeSnapshot = exportRange
                let url = try await EditorExportService.export(
                    clips: clipsSnapshot,
                    textOverlays: textOverlaysSnapshot,
                    audioClips: audioClipsSnapshot,
                    overlayClips: overlayClipsSnapshot,
                    openingTransitionKind: openingKindSnapshot,
                    openingTransitionDuration: openingDurationSnapshot,
                    closingTransitionKind: closingKindSnapshot,
                    closingTransitionDuration: closingDurationSnapshot,
                    canvasSettings: canvasSnapshot,
                    timeRange: exportRangeSnapshot,
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
        timelinePosition = snappedTime(time)
    }

    func commitTimelineAfterScrub() {
        clearSnapGuide()
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
        cancelMotionTracking()
        cancelColorMaskTracking()
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
            overlayClips: overlayClips,
            canvasSettings: canvasSettings,
            exportInPoint: exportInPoint,
            exportOutPoint: exportOutPoint
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
        canvasSettings = snapshot.canvasSettings
        exportInPoint = snapshot.exportInPoint
        exportOutPoint = snapshot.exportOutPoint
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
            selectedOverlayClipID: selectedOverlayClipID,
            canvasSettings: canvasSettings,
            exportInPoint: exportInPoint,
            exportOutPoint: exportOutPoint
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

    /// Magnetic snapping shared by playhead and movable overlay lanes. The point threshold
    /// is converted to time so it naturally becomes more precise as the timeline zooms in.
    private func snappedTime(
        _ proposed: TimeInterval,
        excluding excludedID: UUID? = nil,
        pixelsPerSecond: CGFloat = 18,
        thresholdPoints: CGFloat = 8
    ) -> TimeInterval {
        let clamped = min(max(0, proposed), totalDuration)
        var candidates: [TimeInterval] = [0, videoDuration, totalDuration]
        var cursor: TimeInterval = 0
        for clip in clips {
            cursor += clip.duration
            if clip.id != excludedID { candidates.append(cursor) }
        }
        for clip in audioClips where clip.id != excludedID {
            candidates.append(contentsOf: [clip.timelineStart, clip.timelineEnd])
        }
        for overlay in textOverlays where overlay.id != excludedID {
            candidates.append(contentsOf: [overlay.startTime, overlay.endTime])
        }
        for clip in overlayClips where clip.id != excludedID {
            candidates.append(contentsOf: [clip.timelineStart, clip.timelineEnd])
        }
        if let exportInPoint { candidates.append(exportInPoint) }
        if let exportOutPoint { candidates.append(exportOutPoint) }

        let threshold = TimeInterval(thresholdPoints / max(pixelsPerSecond, 1))
        guard let nearest = candidates.min(by: { abs($0 - clamped) < abs($1 - clamped) }),
              abs(nearest - clamped) <= threshold else {
            snapGuideTime = nil
            lastHapticSnapTime = nil
            return clamped
        }
        snapGuideTime = nearest
        if lastHapticSnapTime != nearest {
            UISelectionFeedbackGenerator().selectionChanged()
            lastHapticSnapTime = nearest
        }
        return nearest
    }

    private func clearSnapGuide() {
        snapGuideTime = nil
        lastHapticSnapTime = nil
    }

    private func clipsFingerprint() -> String {
        let clipsHash = clips.map { clip in
            "\(clip.id.uuidString)|\(clip.trimStart)|\(clip.trimEnd)|\(clip.speed)|\(String(describing: clip.speedRamp))|\(clip.volume)|\(clip.cropAspect.rawValue)|\(clip.reframeMode.rawValue)|\(clip.rotationQuarterTurns)|\(clip.straightenDegrees)|\(clip.isFlippedHorizontally)|\(clip.isFlippedVertically)|\(clip.reframeScale)|\(clip.reframeXOffset)|\(clip.reframeYOffset)|\(clip.colorAdjustment)|\(clip.compositing)|\(clip.keyframes)|\(clip.motionTracks)|\(clip.stabilization)|\(clip.transitionKind.rawValue)|\(clip.transitionDuration)|\(clip.duration)|\(clip.asset.localIdentifier)"
        }.joined(separator: ";")
        let audioHash = audioClips.map {
            "\($0.id.uuidString)|\($0.trimStart)|\($0.trimEnd)|\($0.timelineStart)|\($0.volume)|\($0.fadeInDuration)|\($0.fadeOutDuration)|\($0.keyframes)|\($0.fileURL.path)"
        }.joined(separator: ";")
        let overlayHash = overlayClips.map {
            "\($0.id.uuidString)|\($0.trimStart)|\($0.trimEnd)|\($0.timelineStart)|\($0.laneIndex)|\($0.zIndex)|\($0.speed)|\($0.scale)|\($0.xOffset)|\($0.yOffset)|\($0.opacity)|\($0.volume)|\($0.cropAspect.rawValue)|\($0.reframeMode.rawValue)|\($0.rotationQuarterTurns)|\($0.straightenDegrees)|\($0.isFlippedHorizontally)|\($0.isFlippedVertically)|\($0.reframeScale)|\($0.reframeXOffset)|\($0.reframeYOffset)|\($0.colorAdjustment)|\($0.compositing)|\($0.keyframes)|\($0.motionTracks)|\($0.stabilization)|\($0.attachedClipID?.uuidString ?? "")|\($0.attachedTrackID?.uuidString ?? "")|\($0.asset.localIdentifier)"
        }.joined(separator: ";")
        let openingHash = "\(openingTransitionKind.rawValue)|\(openingTransitionDuration)"
        let closingHash = "\(closingTransitionKind.rawValue)|\(closingTransitionDuration)"
        return clipsHash + "|||" + audioHash + "|||" + overlayHash + "|||" + openingHash + "|||" + closingHash + "|||\(canvasSettings)"
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
        let canvasSnapshot = canvasSettings

        let item: AVPlayerItem?
        if audioClipsSnapshot.isEmpty,
           overlayClipsSnapshot.isEmpty,
           openingKindSnapshot == .none,
           closingKindSnapshot == .none,
           canvasSnapshot == .default,
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
                    closingTransitionDuration: closingDurationSnapshot,
                    canvasSettings: canvasSnapshot
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
