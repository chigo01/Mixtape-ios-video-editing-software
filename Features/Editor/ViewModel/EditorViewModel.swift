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
    /// Per-lane gain/mute (Priority 13 gain staging), keyed by `EditorAudioClip.laneIndex`.
    var audioTrackSettings: [Int: EditorAudioTrackSettings] = [:]
    /// Final output gain applied on top of every track's own volume/keyframes.
    var masterVolume: Float = 1.0
    var overlayClips: [EditorOverlayClip]
    var canvasSettings: EditorCanvasSettings
    var exportInPoint: TimeInterval?
    var exportOutPoint: TimeInterval?
    private(set) var sequences: [EditorSequence]
    private(set) var markers: [EditorTimelineMarker]
    var selectedTimelineItems: Set<EditorTimelineItemReference>
    var selectedSequenceID: UUID?
    var activeSequenceID: UUID?
    var isMultiSelectMode = false

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
    private(set) var reverseGenerationProgress: Double?
    private(set) var reverseGenerationClipID: UUID?
    var reverseGenerationErrorMessage: String?
    @ObservationIgnored private var reverseGenerationTask: Task<Void, Never>?

    // MARK: Text overlay editing

    var selectedTextOverlayID: UUID?
    var isTextEditorPresented: Bool = false
    private(set) var isTranscribingCaptions = false
    private(set) var captionStatusMessage: String?
    var captionErrorMessage: String?
    @ObservationIgnored private var captionTask: Task<Void, Never>?

    // MARK: Audio editing

    var selectedAudioClipID: UUID?
    /// Clip currently being marked for a punch-in re-record (Priority 14 follow-up); `nil` when
    /// no marking is in progress. Transient UI state, not persisted or undoable.
    var punchInClipID: UUID?
    private(set) var punchInStartTime: TimeInterval?
    /// Set once both the in- and out-points are marked; `EditorScreen` observes this to present
    /// the recorder in punch mode, then clears it after the sheet is dismissed.
    var punchInPendingRange: PunchInRange?

    struct PunchInRange: Equatable {
        let clipID: UUID
        let start: TimeInterval
        let end: TimeInterval
    }

    /// Clip + effect currently being rendered (offline, one-time — see
    /// `EditorAudioEffectRenderer`); drives a spinner on the matching cell in
    /// `EditorAudioEffectPanel`. `nil` the rest of the time.
    var renderingAudioEffectClipID: UUID?
    private(set) var renderingAudioEffect: EditorAudioEffect?
    var audioEffectErrorMessage: String?
    @ObservationIgnored private var audioEffectRenderTask: Task<Void, Never>?

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
    private var mixUndoSnapshot: EditorTimelineSnapshot?
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
        self.selectedTextOverlayID = project.selectedTextOverlayID
        self.audioClips = project.audioClips.compactMap { $0.toAudioClip() }
        self.audioTrackSettings = project.audioTrackSettings
        self.masterVolume = project.masterVolume
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
        self.sequences = project.sequences
        self.markers = project.markers.sorted { $0.time < $1.time }
        self.selectedTimelineItems = Set(project.selectedTimelineItems)
        self.selectedSequenceID = project.selectedSequenceID
        self.activeSequenceID = project.activeSequenceID
        let validSequenceIDs = Set(project.sequences.map(\.id))
        if activeSequenceID.map({ !validSequenceIDs.contains($0) }) == true { activeSequenceID = nil }
        if selectedSequenceID.map({ !validSequenceIDs.contains($0) }) == true { selectedSequenceID = nil }
        if !selectedTimelineItems.isEmpty {
            self.isMultiSelectMode = true
            self.selectedTool = .sequence
            self.selectedClipID = nil
            self.selectedTextOverlayID = nil
            self.selectedAudioClipID = nil
            self.selectedOverlayClipID = nil
        }
        pruneSequenceStructure()
        selectedTimelineItems = Set(selectedTimelineItems.filter { reference in
            reference.kind == .sequence
                ? sequences.contains(where: { $0.id == reference.itemID })
                : allLeafReferences.contains(reference)
        })
        if selectedTimelineItems.isEmpty, isMultiSelectMode {
            isMultiSelectMode = false
            selectedTool = nil
            selectedSequenceID = nil
            selectedClipID = clips.first?.id
        }
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
        selectedTextOverlayID = nil
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
        selectedClipID = nil
        selectedTextOverlayID = nil
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
        case .captions:
            selectTool(.captions)
        case .sequence:
            beginMultiSelection()
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
        selectedTimelineItems.remove(.overlay(id))
        pruneSequenceStructure()
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
            playback: source.playback,
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
            playback: .forward,
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

        guard let parts = clip.split(atTimelineTime: timelinePosition - clip.timelineStart) else {
            return
        }
        registerUndoIfNeeded()
        overlayClips[index] = parts.left
        overlayClips.insert(parts.right, at: index + 1)
        remapSequenceMembershipAfterSplit(
            original: .overlay(parts.left.id),
            right: .overlay(parts.right.id)
        )
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

        let requestedStart = clip.playback.isReverse
            ? clip.originalDuration - trimEnd
            : trimStart
        let requestedEnd = clip.playback.isReverse
            ? clip.originalDuration - trimStart
            : trimEnd

        if clip.isPhoto {
            let start = max(0, min(requestedStart, requestedEnd - minimumSpan))
            let end = max(requestedEnd, start + minimumSpan)
            clip.originalDuration = end
            clip.trimStart = start
            clip.trimEnd = end
        } else {
            let start = min(max(0, requestedStart), clip.originalDuration - minimumSpan)
            let end = max(min(clip.originalDuration, requestedEnd), start + minimumSpan)
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
            let sourceDelta = overlayClips[index].playback.isReverse
                ? baseline.trimEnd - overlayClips[index].trimEnd
                : overlayClips[index].trimStart - baseline.trimStart
            overlayClips[index].timelineStart = max(
                0,
                baseline.timelineStart
                    + sourceDelta / TimeInterval(max(overlayClips[index].speed, 0.001))
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

    func transcribeCaptions(
        localeIdentifier: String? = nil,
        source: EditorCaptionAudioSource = .video
    ) {
        guard !isTranscribingCaptions else { return }
        captionTask?.cancel()
        captionErrorMessage = nil
        captionStatusMessage = source == .video
            ? "Preparing video dialogue…"
            : "Preparing the edited audio mix…"
        let clipsSnapshot = clips
        let audioSnapshot = audioClips
        let overlaysSnapshot = overlayClips
        let trackSettingsSnapshot = audioTrackSettings
        let masterSnapshot = masterVolume

        captionTask = Task {
            isTranscribingCaptions = true
            defer {
                isTranscribingCaptions = false
                captionStatusMessage = nil
            }
            do {
                captionStatusMessage = "Recognizing speech…"
                let result = try await EditorCaptionService.transcribe(
                    clips: clipsSnapshot,
                    audioClips: audioSnapshot,
                    overlayClips: overlaysSnapshot,
                    audioTrackSettings: trackSettingsSnapshot,
                    masterVolume: masterSnapshot,
                    requestedLocaleIdentifier: localeIdentifier,
                    source: source
                )
                try Task.checkCancellation()
                let captions = EditorCaptionService.makeCaptionOverlays(from: result)
                replaceAllCaptions(with: captions)
                captionStatusMessage = "Created \(captions.count) caption segments"
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch is CancellationError {
                return
            } catch {
                captionErrorMessage = error.localizedDescription
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }

    func cancelCaptionTranscription() {
        captionTask?.cancel()
        captionTask = nil
        isTranscribingCaptions = false
        captionStatusMessage = nil
    }

    func importCaptions(from data: Data) throws {
        replaceAllCaptions(with: try EditorSRTCodec.decode(data))
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    func replaceAllCaptions(with captions: [EditorTextOverlay]) {
        registerUndoIfNeeded()
        let captionIDs = Set(textOverlays.filter(\.isCaption).map(\.id))
        textOverlays.removeAll { captionIDs.contains($0.id) }
        textOverlays.append(contentsOf: captions)
        selectedTextOverlayID = nil
        scheduleSave()
    }

    func updateCaptionText(id: UUID, text: String) {
        guard let index = textOverlays.firstIndex(where: { $0.id == id && $0.isCaption }) else { return }
        registerUndoIfNeeded()
        textOverlays[index].text = text
        textOverlays[index].captionWords = retimedCaptionWords(
            for: text,
            in: textOverlays[index],
            preserving: textOverlays[index].captionWords
        )
        scheduleSave()
    }

    func updateCaptionWordText(captionID: UUID, wordID: UUID, text: String) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty,
              let captionIndex = textOverlays.firstIndex(where: { $0.id == captionID && $0.isCaption }),
              let wordIndex = textOverlays[captionIndex].captionWords.firstIndex(where: { $0.id == wordID }),
              textOverlays[captionIndex].captionWords[wordIndex].text != value else { return }
        registerUndoIfNeeded()
        textOverlays[captionIndex].captionWords[wordIndex].text = value
        textOverlays[captionIndex].text = textOverlays[captionIndex].captionWords
            .map(\.text).joined(separator: " ")
        scheduleSave()
    }

    /// Moves the boundary after one word while maintaining a valid, contiguous
    /// pair. This provides precise timing correction without allowing inverted
    /// or zero-length words.
    func nudgeCaptionWordBoundary(
        captionID: UUID,
        afterWordID wordID: UUID,
        by delta: TimeInterval
    ) {
        guard let captionIndex = textOverlays.firstIndex(where: { $0.id == captionID && $0.isCaption }),
              let wordIndex = textOverlays[captionIndex].captionWords.firstIndex(where: { $0.id == wordID }),
              wordIndex + 1 < textOverlays[captionIndex].captionWords.count else { return }
        let words = textOverlays[captionIndex].captionWords
        let minimumWordDuration: TimeInterval = 0.03
        let currentBoundary = words[wordIndex].endTime
        let lower = words[wordIndex].startTime + minimumWordDuration
        let upper = words[wordIndex + 1].endTime - minimumWordDuration
        let boundary = min(max(currentBoundary + delta, lower), upper)
        guard abs(boundary - currentBoundary) > 0.000_001 else { return }
        registerUndoIfNeeded()
        textOverlays[captionIndex].captionWords[wordIndex].endTime = boundary
        textOverlays[captionIndex].captionWords[wordIndex + 1].startTime = boundary
        scheduleSave()
    }

    func removeCaptionWord(captionID: UUID, wordID: UUID) {
        guard let captionIndex = textOverlays.firstIndex(where: { $0.id == captionID && $0.isCaption }),
              let wordIndex = textOverlays[captionIndex].captionWords.firstIndex(where: { $0.id == wordID }) else { return }
        guard textOverlays[captionIndex].captionWords.count > 1 else {
            deleteTextOverlay(id: captionID)
            return
        }
        registerUndoIfNeeded()
        textOverlays[captionIndex].captionWords.remove(at: wordIndex)
        let words = textOverlays[captionIndex].captionWords
        textOverlays[captionIndex].startTime = words.first?.startTime ?? textOverlays[captionIndex].startTime
        textOverlays[captionIndex].endTime = words.last?.endTime ?? textOverlays[captionIndex].endTime
        textOverlays[captionIndex].text = words.map(\.text).joined(separator: " ")
        scheduleSave()
    }

    func removeCaptionWords(_ wordIDs: Set<UUID>) {
        guard !wordIDs.isEmpty,
              textOverlays.contains(where: { overlay in
                  overlay.isCaption && overlay.captionWords.contains { wordIDs.contains($0.id) }
              }) else { return }
        registerUndoIfNeeded()
        let captionIDs = Set(textOverlays.filter(\.isCaption).map(\.id))
        for index in textOverlays.indices where textOverlays[index].isCaption {
            textOverlays[index].captionWords.removeAll { wordIDs.contains($0.id) }
            let words = textOverlays[index].captionWords
            if let first = words.first, let last = words.last {
                textOverlays[index].startTime = first.startTime
                textOverlays[index].endTime = last.endTime
                textOverlays[index].text = words.map(\.text).joined(separator: " ")
            }
        }
        let emptiedCaptionIDs = Set(textOverlays.filter {
            captionIDs.contains($0.id) && $0.captionWords.isEmpty
        }.map(\.id))
        textOverlays.removeAll { emptiedCaptionIDs.contains($0.id) }
        if let selectedTextOverlayID, emptiedCaptionIDs.contains(selectedTextOverlayID) {
            self.selectedTextOverlayID = nil
        }
        scheduleSave()
    }

    func splitCaption(id: UUID, near timelineTime: TimeInterval? = nil) {
        guard let index = textOverlays.firstIndex(where: { $0.id == id && $0.isCaption }) else { return }
        let source = textOverlays[index]
        guard source.captionWords.count >= 2 else { return }
        let target = timelineTime ?? timelinePosition
        let possibleBreaks = Array(1..<source.captionWords.count)
        let splitIndex: Int
        if target > source.startTime, target < source.endTime {
            splitIndex = possibleBreaks.min {
                abs(source.captionWords[$0].startTime - target)
                    < abs(source.captionWords[$1].startTime - target)
            } ?? source.captionWords.count / 2
        } else {
            splitIndex = source.captionWords.count / 2
        }
        let leftWords = Array(source.captionWords[..<splitIndex])
        let rightWords = Array(source.captionWords[splitIndex...])
        guard let leftEnd = leftWords.last?.endTime,
              let rightStart = rightWords.first?.startTime else { return }

        registerUndoIfNeeded()
        let left = captionOverlay(
            basedOn: source,
            id: source.id,
            words: leftWords,
            start: source.startTime,
            end: max(leftEnd, source.startTime + 0.03)
        )
        let right = captionOverlay(
            basedOn: source,
            words: rightWords,
            start: min(rightStart, source.endTime - 0.03),
            end: source.endTime
        )
        textOverlays.replaceSubrange(index...index, with: [left, right])
        remapSequenceMembershipAfterSplit(original: .text(left.id), right: .text(right.id))
        selectedTextOverlayID = right.id
        scheduleSave()
    }

    func mergeCaptionWithNext(id: UUID) {
        let orderedIDs = captionOverlays.map(\.id)
        guard let orderedIndex = orderedIDs.firstIndex(of: id),
              orderedIndex + 1 < orderedIDs.count,
              let firstIndex = textOverlays.firstIndex(where: { $0.id == id }),
              let secondIndex = textOverlays.firstIndex(where: { $0.id == orderedIDs[orderedIndex + 1] }) else { return }
        let first = textOverlays[firstIndex]
        let second = textOverlays[secondIndex]
        let words = first.captionWords + second.captionWords
        registerUndoIfNeeded()
        textOverlays[firstIndex] = captionOverlay(
            basedOn: first,
            id: first.id,
            words: words,
            start: first.startTime,
            end: max(first.endTime, second.endTime)
        )
        textOverlays.remove(at: secondIndex)
        selectedTimelineItems.remove(.text(second.id))
        pruneSequenceStructure()
        selectedTextOverlayID = first.id
        scheduleSave()
    }

    func deleteAllCaptions() {
        guard textOverlays.contains(where: \.isCaption) else { return }
        registerUndoIfNeeded()
        let captionIDs = Set(textOverlays.filter(\.isCaption).map(\.id))
        textOverlays.removeAll { captionIDs.contains($0.id) }
        if let selectedTextOverlayID, captionIDs.contains(selectedTextOverlayID) {
            self.selectedTextOverlayID = nil
            isTextEditorPresented = false
        }
        scheduleSave()
    }

    func applyCaptionStyle(_ source: EditorTextOverlay, toAll: Bool) {
        registerUndoIfNeeded()
        for index in textOverlays.indices where textOverlays[index].isCaption
            && (toAll || textOverlays[index].id == source.id) {
            textOverlays[index].fontSize = source.fontSize
            textOverlays[index].fontFamily = source.fontFamily
            textOverlays[index].fontStyle = source.fontStyle
            textOverlays[index].textColor = source.textColor
            textOverlays[index].captionHighlightColor = source.captionHighlightColor
            textOverlays[index].opacity = source.opacity
            textOverlays[index].horizontalAlignment = source.horizontalAlignment
            textOverlays[index].verticalAlignment = source.verticalAlignment
            textOverlays[index].xOffset = source.xOffset
            textOverlays[index].yOffset = source.yOffset
        }
        scheduleSave()
    }

    func applyCaptionAnimation(_ animation: EditorTextAnimation, toAll: Bool = true) {
        guard textOverlays.contains(where: \.isCaption) else { return }
        if textEditUndoSnapshot == nil { registerUndoIfNeeded() }
        for index in textOverlays.indices where textOverlays[index].isCaption
            && (toAll || textOverlays[index].id == selectedTextOverlayID) {
            textOverlays[index].animation = animation
        }
        scheduleSave()
    }

    func seekToCaption(_ id: UUID) {
        guard let caption = textOverlays.first(where: { $0.id == id && $0.isCaption }) else { return }
        selectedTextOverlayID = id
        seekTimeline(to: caption.startTime)
    }

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
        let current = textOverlays[idx]
        var updated = overlay

        // Captions render and export from their timed words, while the regular
        // text editor edits `text`. Keep both representations in lockstep so a
        // correction is immediately visible everywhere. Preserve the old words
        // during a transient empty edit; dismissing the editor still deletes it.
        let normalizedText = overlay.text
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .joined(separator: " ")
        let renderedCaptionText = overlay.captionWords.map(\.text).joined(separator: " ")
        if current.isCaption, !normalizedText.isEmpty,
           normalizedText != renderedCaptionText {
            updated.captionWords = retimedCaptionWords(
                for: overlay.text,
                in: overlay,
                preserving: current.captionWords
            )
        }

        textOverlays[idx] = updated
        scheduleSave()
    }

    private func retimedCaptionWords(
        for text: String,
        in overlay: EditorTextOverlay,
        preserving existingWords: [EditorCaptionWord]
    ) -> [EditorCaptionWord] {
        let tokens = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !tokens.isEmpty else { return [] }

        // A normal spelling correction does not change the word count. Retain
        // the recognizer's word-level timing (and stable IDs used by karaoke
        // highlighting) instead of needlessly redistributing the whole line.
        if tokens.count == existingWords.count {
            return zip(tokens, existingWords).map { token, existing in
                EditorCaptionWord(
                    id: existing.id,
                    text: token,
                    startTime: existing.startTime,
                    endTime: existing.endTime,
                    confidence: existing.confidence
                )
            }
        }

        let start = overlay.startTime
        let end = max(start, overlay.endTime)
        let step = (end - start) / Double(tokens.count)
        return tokens.enumerated().map { offset, token in
            EditorCaptionWord(
                text: token,
                startTime: start + Double(offset) * step,
                endTime: offset == tokens.count - 1
                    ? end
                    : start + Double(offset + 1) * step,
                confidence: offset < existingWords.count
                    ? existingWords[offset].confidence
                    : 1
            )
        }
    }

    private func captionOverlay(
        basedOn source: EditorTextOverlay,
        id: UUID = UUID(),
        words: [EditorCaptionWord],
        start: TimeInterval,
        end: TimeInterval
    ) -> EditorTextOverlay {
        EditorTextOverlay(
            id: id,
            text: words.map(\.text).joined(separator: " "),
            startTime: start,
            endTime: end,
            fontSize: source.fontSize,
            fontFamily: source.fontFamily,
            fontStyle: source.fontStyle,
            textColor: source.textColor,
            opacity: source.opacity,
            horizontalAlignment: source.horizontalAlignment,
            verticalAlignment: source.verticalAlignment,
            xOffset: source.xOffset,
            yOffset: source.yOffset,
            keyframes: source.keyframes,
            animation: source.animation,
            attachedClipID: source.attachedClipID,
            attachedTrackID: source.attachedTrackID,
            attachRotation: source.attachRotation,
            attachScale: source.attachScale,
            captionWords: words,
            captionHighlightColor: source.captionHighlightColor,
            captionLocaleIdentifier: source.captionLocaleIdentifier,
            trackedRotationDegrees: source.trackedRotationDegrees
        )
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
        selectedTimelineItems.remove(.text(id))
        pruneSequenceStructure()
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
        let captionTimeOffset = start - source.startTime
        let copiedCaptionWords = source.captionWords.map { word in
            EditorCaptionWord(
                text: word.text,
                startTime: word.startTime + captionTimeOffset,
                endTime: word.endTime + captionTimeOffset,
                confidence: word.confidence
            )
        }
        let copy = EditorTextOverlay(
            text: source.text, startTime: start,
            endTime: min(totalDuration, start + duration), fontSize: source.fontSize,
            fontFamily: source.fontFamily, fontStyle: source.fontStyle,
            textColor: source.textColor, opacity: source.opacity,
            horizontalAlignment: source.horizontalAlignment,
            verticalAlignment: source.verticalAlignment, xOffset: source.xOffset,
            yOffset: source.yOffset, keyframes: source.keyframes,
            animation: source.animation,
            attachedClipID: source.attachedClipID,
            attachedTrackID: source.attachedTrackID,
            attachRotation: source.attachRotation,
            attachScale: source.attachScale,
            captionWords: copiedCaptionWords,
            captionHighlightColor: source.captionHighlightColor,
            captionLocaleIdentifier: source.captionLocaleIdentifier
        )
        guard copy.duration > 0.1 else { return }
        registerUndoIfNeeded()
        textOverlays.append(copy)
        selectedTextOverlayID = copy.id
        scheduleSave()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    func selectTextOverlay(_ id: UUID) {
        if handleMultiSelection(.text(id)) { return }
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
        normalizeCaptionWordsForCurrentRanges()
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
        let delta = clampedStart - textOverlays[idx].startTime
        if textOverlays[idx].isCaption, abs(delta) > 0.000_001 {
            for wordIndex in textOverlays[idx].captionWords.indices {
                textOverlays[idx].captionWords[wordIndex].startTime += delta
                textOverlays[idx].captionWords[wordIndex].endTime += delta
            }
        }
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

    private func normalizeCaptionWordsForCurrentRanges() {
        for index in textOverlays.indices where textOverlays[index].isCaption {
            let start = textOverlays[index].startTime
            let end = textOverlays[index].endTime
            var words = textOverlays[index].captionWords.filter {
                $0.endTime > start && $0.startTime < end
            }
            guard !words.isEmpty else { continue }
            words[0].startTime = max(words[0].startTime, start)
            words[words.count - 1].endTime = min(words[words.count - 1].endTime, end)
            textOverlays[index].captionWords = words
            textOverlays[index].text = words.map(\.text).joined(separator: " ")
        }
    }

    // MARK: Selection and sequence structure

    var selectionCount: Int { expandedSelection.count }
    var hasSelectionRange: Bool { exportRange != nil }
    var canCreateSequence: Bool { selectedTimelineItems.count >= 2 }

    var activeSequence: EditorSequence? {
        guard let activeSequenceID else { return nil }
        return sequences.first { $0.id == activeSequenceID }
    }

    var selectedSequence: EditorSequence? {
        guard let selectedSequenceID else { return nil }
        return sequences.first { $0.id == selectedSequenceID }
    }

    var visibleSequences: [EditorSequence] {
        sequences.filter { $0.parentSequenceID == activeSequenceID }
    }

    func beginMultiSelection() {
        finalizeSelectionToolEdits()
        isMultiSelectMode = true
        selectedTool = .sequence
        selectedClipID = nil
        selectedTextOverlayID = nil
        selectedAudioClipID = nil
        selectedOverlayClipID = nil
        isTextEditorPresented = false
    }

    func endMultiSelection(clearSelection: Bool = true) {
        isMultiSelectMode = false
        if clearSelection {
            selectedTimelineItems.removeAll()
            selectedSequenceID = nil
        }
        if selectedTool == .sequence { selectedTool = nil }
        scheduleSave()
    }

    private func finalizeSelectionToolEdits() {
        if selectedTool == .speed { finalizeSpeedEditUndo() }
        if selectedTool == .duration { finalizePhotoDurationEditUndo() }
        if selectedTool == .crop { finalizeReframeEditUndo() }
        if selectedTool == .filter { finalizeColorAdjustmentUndo() }
        if selectedTool == .compositing { finalizeOverlayCompositingUndo() }
        if selectedTool == .track || selectedTool == .stabilize { finalizeMotionTrackingUndo() }
        finalizeAudioVolumeEditUndo()
        finalizeOverlayTransform()
        cancelMotionTracking()
    }

    @discardableResult
    private func handleMultiSelection(_ reference: EditorTimelineItemReference) -> Bool {
        guard isMultiSelectMode else {
            selectedTimelineItems.removeAll()
            selectedSequenceID = nil
            return false
        }
        guard isItemInActiveSequence(reference) else { return true }
        if selectedTimelineItems.contains(reference) {
            selectedTimelineItems.remove(reference)
        } else {
            selectedTimelineItems.insert(reference)
        }
        selectedSequenceID = reference.kind == .sequence ? reference.itemID : nil
        UISelectionFeedbackGenerator().selectionChanged()
        scheduleSave()
        return true
    }

    func isItemSelected(_ reference: EditorTimelineItemReference) -> Bool {
        selectedTimelineItems.contains(reference) || expandedSelection.contains(reference)
    }

    func isItemInActiveSequence(_ reference: EditorTimelineItemReference) -> Bool {
        guard let activeSequenceID else { return true }
        return leafReferences(in: activeSequenceID).contains(reference)
    }

    func selectAllInActiveSequence() {
        beginMultiSelection()
        if let activeSequenceID {
            selectedTimelineItems = leafReferences(in: activeSequenceID)
        } else {
            selectedTimelineItems = allLeafReferences
        }
        selectedSequenceID = nil
        scheduleSave()
    }

    func selectItemsInExportRange() {
        guard let range = exportRange else { return }
        beginMultiSelection()
        let candidates = activeSequenceID.map { leafReferences(in: $0) } ?? allLeafReferences
        selectedTimelineItems = Set(candidates.filter { reference in
            guard let itemRange = timeRange(for: reference) else { return false }
            return itemRange.upperBound > range.lowerBound && itemRange.lowerBound < range.upperBound
        })
        selectedSequenceID = nil
        scheduleSave()
    }

    func selectSequence(_ id: UUID) {
        guard sequences.contains(where: { $0.id == id }) else { return }
        beginMultiSelection()
        selectedTimelineItems = [.sequence(id)]
        selectedSequenceID = id
        scheduleSave()
    }

    func groupSelectedItems() { createSequence(kind: .group) }
    func createCompoundClip() { createSequence(kind: .compound) }

    private func createSequence(kind: EditorSequenceKind) {
        let roots = Array(selectedTimelineItems).sorted { $0.id < $1.id }
        guard roots.count >= 2 else { return }
        registerUndoIfNeeded()
        let title = kind == .compound
            ? "Compound \(sequences.filter { $0.kind == .compound }.count + 1)"
            : "Group \(sequences.filter { $0.kind == .group }.count + 1)"
        let sequence = EditorSequence(
            title: title,
            kind: kind,
            members: roots,
            parentSequenceID: activeSequenceID
        )
        if kind == .compound {
            let rootsSet = Set(roots)
            for index in sequences.indices
            where sequences[index].kind == .compound
                && sequences[index].id != activeSequenceID
                && sequences[index].parentSequenceID == activeSequenceID {
                sequences[index].members.removeAll { rootsSet.contains($0) }
            }
        }
        if let activeSequenceID,
           let parentIndex = sequences.firstIndex(where: { $0.id == activeSequenceID }) {
            let rootsSet = Set(roots)
            sequences[parentIndex].members.removeAll { rootsSet.contains($0) }
            sequences[parentIndex].members.append(.sequence(sequence.id))
        }
        for reference in roots where reference.kind == .sequence {
            if let childIndex = sequences.firstIndex(where: { $0.id == reference.itemID }) {
                sequences[childIndex].parentSequenceID = sequence.id
            }
        }
        sequences.append(sequence)
        pruneSequenceStructure()
        selectedTimelineItems = [.sequence(sequence.id)]
        selectedSequenceID = sequence.id
        scheduleSave()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    func dissolveSelectedSequence() {
        guard let sequence = selectedSequence,
              let index = sequences.firstIndex(where: { $0.id == sequence.id }) else { return }
        registerUndoIfNeeded()
        if let parentID = sequence.parentSequenceID,
           let parentIndex = sequences.firstIndex(where: { $0.id == parentID }) {
            let insertionIndex = sequences[parentIndex].members.firstIndex(of: .sequence(sequence.id))
                ?? sequences[parentIndex].members.endIndex
            sequences[parentIndex].members.removeAll { $0 == .sequence(sequence.id) }
            sequences[parentIndex].members.insert(contentsOf: sequence.members, at: insertionIndex)
        }
        for member in sequence.members where member.kind == .sequence {
            if let childIndex = sequences.firstIndex(where: { $0.id == member.itemID }) {
                sequences[childIndex].parentSequenceID = sequence.parentSequenceID
            }
        }
        sequences.remove(at: index)
        if activeSequenceID == sequence.id { activeSequenceID = sequence.parentSequenceID }
        selectedTimelineItems = Set(sequence.members)
        selectedSequenceID = nil
        scheduleSave()
    }

    func enterSelectedSequence() {
        guard let selectedSequence else { return }
        activeSequenceID = selectedSequence.id
        selectedTimelineItems.removeAll()
        selectedSequenceID = nil
        scheduleSave()
    }

    func exitActiveSequence() {
        guard let activeSequence else { return }
        activeSequenceID = activeSequence.parentSequenceID
        selectedTimelineItems = [.sequence(activeSequence.id)]
        selectedSequenceID = activeSequence.id
        isMultiSelectMode = true
        selectedTool = .sequence
        selectedClipID = nil
        selectedTextOverlayID = nil
        selectedAudioClipID = nil
        selectedOverlayClipID = nil
        scheduleSave()
    }

    func renameSequence(id: UUID, title: String) {
        guard let index = sequences.firstIndex(where: { $0.id == id }) else { return }
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, normalized != sequences[index].title else { return }
        registerUndoIfNeeded()
        sequences[index].title = normalized
        scheduleSave()
    }

    func addMarkerAtPlayhead() {
        registerUndoIfNeeded()
        var number = 1
        let existingNames = Set(markers.map(\.name))
        while existingNames.contains("Marker \(number)") { number += 1 }
        let marker = EditorTimelineMarker(
            name: "Marker \(number)",
            time: min(max(0, timelinePosition), totalDuration)
        )
        markers.append(marker)
        markers.sort { $0.time < $1.time }
        scheduleSave()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func renameMarker(id: UUID, name: String) {
        guard let index = markers.firstIndex(where: { $0.id == id }) else { return }
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, normalized != markers[index].name else { return }
        registerUndoIfNeeded()
        markers[index].name = normalized
        scheduleSave()
    }

    func deleteMarker(id: UUID) {
        guard markers.contains(where: { $0.id == id }) else { return }
        registerUndoIfNeeded()
        markers.removeAll { $0.id == id }
        scheduleSave()
    }

    func moveSelectionEarlier() { moveSelection(direction: -1) }
    func moveSelectionLater() { moveSelection(direction: 1) }

    private func moveSelection(direction: Int) {
        let references = expandedSelection
        guard !references.isEmpty, direction != 0 else { return }
        registerUndoIfNeeded()
        let primaryIDs = Set(references.filter { $0.kind == .primaryClip }.map(\.itemID))
        let anchorID = clips.first(where: { primaryIDs.contains($0.id) })?.id
        let oldAnchorStart = anchorID.flatMap { id in
            clips.firstIndex(where: { $0.id == id }).map { timelineOffsetForClipIndex($0) }
        }
        if !primaryIDs.isEmpty, primaryIDs.count < clips.count {
            if direction < 0 {
                for index in clips.indices.dropFirst() where primaryIDs.contains(clips[index].id)
                    && !primaryIDs.contains(clips[index - 1].id) {
                    clips.swapAt(index, index - 1)
                }
            } else if clips.count > 1 {
                for index in clips.indices.dropLast().reversed() where primaryIDs.contains(clips[index].id)
                    && !primaryIDs.contains(clips[index + 1].id) {
                    clips.swapAt(index, index + 1)
                }
            }
        }

        let primaryTimelineDelta: TimeInterval? = anchorID.flatMap { id in
            guard let oldAnchorStart,
                  let index = clips.firstIndex(where: { $0.id == id }) else { return nil }
            return timelineOffsetForClipIndex(index) - oldAnchorStart
        }

        let timed = references.filter { $0.kind != .primaryClip && $0.kind != .sequence }
        let proposed = primaryTimelineDelta ?? (TimeInterval(direction) * 0.10)
        let earliest = timed.compactMap { timeRange(for: $0)?.lowerBound }.min() ?? 0
        let delta = proposed < 0 ? max(proposed, -earliest) : proposed
        let textIDs = Set(timed.filter { $0.kind == .textOverlay }.map(\.itemID))
        let audioIDs = Set(timed.filter { $0.kind == .audioClip }.map(\.itemID))
        let overlayIDs = Set(timed.filter { $0.kind == .overlayClip }.map(\.itemID))
        for index in textOverlays.indices where textIDs.contains(textOverlays[index].id) {
            textOverlays[index].startTime += delta
            textOverlays[index].endTime += delta
            for wordIndex in textOverlays[index].captionWords.indices {
                textOverlays[index].captionWords[wordIndex].startTime += delta
                textOverlays[index].captionWords[wordIndex].endTime += delta
            }
        }
        for index in audioClips.indices where audioIDs.contains(audioClips[index].id) {
            audioClips[index].timelineStart += delta
        }
        for index in overlayClips.indices where overlayIDs.contains(overlayClips[index].id) {
            overlayClips[index].timelineStart += delta
        }
        finishSequenceMutation(rebuildComposition: !primaryIDs.isEmpty || !audioIDs.isEmpty || !overlayIDs.isEmpty)
    }

    func deleteSelectedTimelineItems() {
        let references = expandedSelection
        guard !references.isEmpty else { return }
        let requestedPrimaryIDs = Set(references.filter { $0.kind == .primaryClip }.map(\.itemID))
        var primaryIDs = requestedPrimaryIDs
        if primaryIDs.count >= clips.count, let retained = clips.last?.id { primaryIDs.remove(retained) }
        let textIDs = Set(references.filter { $0.kind == .textOverlay }.map(\.itemID))
        let audioIDs = Set(references.filter { $0.kind == .audioClip }.map(\.itemID))
        let overlayIDs = Set(references.filter { $0.kind == .overlayClip }.map(\.itemID))
        guard !primaryIDs.isEmpty || !textIDs.isEmpty || !audioIDs.isEmpty || !overlayIDs.isEmpty else { return }
        registerUndoIfNeeded()

        var cursor: TimeInterval = 0
        var removedRanges: [ClosedRange<TimeInterval>] = []
        for clip in clips {
            let range = cursor...(cursor + clip.duration)
            if primaryIDs.contains(clip.id) { removedRanges.append(range) }
            cursor = range.upperBound
        }
        let removedAudioURLs = audioClips.filter { audioIDs.contains($0.id) }.map(\.fileURL)
        textOverlays.removeAll { textIDs.contains($0.id) }
        audioClips.removeAll { audioIDs.contains($0.id) }
        overlayClips.removeAll { overlayIDs.contains($0.id) }
        clips.removeAll { primaryIDs.contains($0.id) }
        for range in removedRanges.sorted(by: { $0.lowerBound > $1.lowerBound }) {
            rippleDeleteTimedItems(from: range.lowerBound, to: range.upperBound)
        }
        removedAudioURLs.forEach(releaseAudioFileIfUnused)
        selectedTimelineItems.removeAll()
        selectedSequenceID = nil
        pruneSequenceStructure()
        finishSequenceMutation(rebuildComposition: true)
    }

    func duplicateSelectedTimelineItems() {
        let references = expandedSelection
        guard !references.isEmpty else { return }
        let ranges = references.compactMap { timeRange(for: $0) }
        let selectionStart = ranges.map(\.lowerBound).min() ?? 0
        let selectionEnd = ranges.map(\.upperBound).max() ?? selectionStart
        let duplicateOffset = max(0.10, selectionEnd - selectionStart)
        let selectedTextSources = textOverlays.filter { references.contains(.text($0.id)) }
        let selectedAudioSources = audioClips.filter { references.contains(.audio($0.id)) }
        let selectedOverlaySources = overlayClips.filter { references.contains(.overlay($0.id)) }
        registerUndoIfNeeded()
        var copiedReferences = Set<EditorTimelineItemReference>()
        var itemCopyMap: [EditorTimelineItemReference: EditorTimelineItemReference] = [:]
        var hostIDMap: [UUID: UUID] = [:]
        var trackIDMap: [UUID: UUID] = [:]
        var copiedTextIDs = Set<UUID>()
        var copiedOverlayIDs = Set<UUID>()

        let primaryIDs = Set(references.filter { $0.kind == .primaryClip }.map(\.itemID))
        for index in clips.indices.reversed() where primaryIDs.contains(clips[index].id) {
            let source = clips[index]
            let boundary = timelineOffsetForClipIndex(index) + source.duration
            let copy = duplicatedPrimaryClip(source)
            clips.insert(copy, at: index + 1)
            rippleInsertTimedItems(at: boundary, duration: copy.duration)
            copiedReferences.insert(.primary(copy.id))
            itemCopyMap[.primary(source.id)] = .primary(copy.id)
            hostIDMap[source.id] = copy.id
            for (oldTrack, newTrack) in zip(source.motionTracks, copy.motionTracks) {
                trackIDMap[oldTrack.id] = newTrack.id
            }
        }
        for source in selectedTextSources {
            let copy = duplicatedTextOverlay(source, timelineOffset: duplicateOffset)
            textOverlays.append(copy)
            copiedReferences.insert(.text(copy.id))
            itemCopyMap[.text(source.id)] = .text(copy.id)
            copiedTextIDs.insert(copy.id)
        }
        for source in selectedAudioSources {
            let copy = EditorAudioClip(
                title: source.title + " Copy", fileURL: source.fileURL,
                originalDuration: source.originalDuration, trimStart: source.trimStart,
                trimEnd: source.trimEnd, timelineStart: source.timelineStart + duplicateOffset,
                laneIndex: source.laneIndex, volume: source.volume,
                fadeInDuration: source.fadeInDuration, fadeOutDuration: source.fadeOutDuration,
                keyframes: source.keyframes, attribution: source.attribution, effect: source.effect
            )
            audioClips.append(copy)
            copiedReferences.insert(.audio(copy.id))
            itemCopyMap[.audio(source.id)] = .audio(copy.id)
        }
        for source in selectedOverlaySources {
            let copy = duplicatedOverlayClip(source, timelineOffset: duplicateOffset)
            overlayClips.append(copy)
            copiedReferences.insert(.overlay(copy.id))
            itemCopyMap[.overlay(source.id)] = .overlay(copy.id)
            copiedOverlayIDs.insert(copy.id)
            hostIDMap[source.id] = copy.id
            for (oldTrack, newTrack) in zip(source.motionTracks, copy.motionTracks) {
                trackIDMap[oldTrack.id] = newTrack.id
            }
        }
        for index in textOverlays.indices where copiedTextIDs.contains(textOverlays[index].id) {
            if let oldHost = textOverlays[index].attachedClipID {
                textOverlays[index].attachedClipID = hostIDMap[oldHost] ?? oldHost
            }
            if let oldTrack = textOverlays[index].attachedTrackID {
                textOverlays[index].attachedTrackID = trackIDMap[oldTrack] ?? oldTrack
            }
        }
        for index in overlayClips.indices where copiedOverlayIDs.contains(overlayClips[index].id) {
            if let oldHost = overlayClips[index].attachedClipID {
                overlayClips[index].attachedClipID = hostIDMap[oldHost] ?? oldHost
            }
            if let oldTrack = overlayClips[index].attachedTrackID {
                overlayClips[index].attachedTrackID = trackIDMap[oldTrack] ?? oldTrack
            }
        }
        let selectedSequenceRoots = selectedTimelineItems.filter { $0.kind == .sequence }
        let copiedSequenceRoots = selectedSequenceRoots.compactMap {
            duplicateSequenceTree(
                sourceID: $0.itemID,
                parentID: activeSequenceID,
                itemCopyMap: itemCopyMap
            )
        }
        if !copiedSequenceRoots.isEmpty {
            if let activeSequenceID,
               let parentIndex = sequences.firstIndex(where: { $0.id == activeSequenceID }) {
                sequences[parentIndex].members.append(
                    contentsOf: copiedSequenceRoots.map(EditorTimelineItemReference.sequence)
                )
            }
            selectedTimelineItems = Set(copiedSequenceRoots.map(EditorTimelineItemReference.sequence))
            selectedSequenceID = copiedSequenceRoots.count == 1 ? copiedSequenceRoots[0] : nil
        } else if copiedReferences.count >= 2 {
            let sourceKind = selectedSequence?.kind ?? .group
            let copySequence = EditorSequence(
                title: "\(selectedSequence?.title ?? "Selection") Copy",
                kind: sourceKind,
                members: Array(copiedReferences).sorted { $0.id < $1.id },
                parentSequenceID: activeSequenceID
            )
            sequences.append(copySequence)
            if let activeSequenceID,
               let parentIndex = sequences.firstIndex(where: { $0.id == activeSequenceID }) {
                sequences[parentIndex].members.append(.sequence(copySequence.id))
            }
            selectedTimelineItems = [.sequence(copySequence.id)]
            selectedSequenceID = copySequence.id
        } else {
            selectedTimelineItems = copiedReferences
            selectedSequenceID = nil
        }
        finishSequenceMutation(rebuildComposition: true)
    }

    private func duplicateSequenceTree(
        sourceID: UUID,
        parentID: UUID?,
        itemCopyMap: [EditorTimelineItemReference: EditorTimelineItemReference],
        visited: Set<UUID> = []
    ) -> UUID? {
        guard !visited.contains(sourceID),
              let source = sequences.first(where: { $0.id == sourceID }) else { return nil }
        var visited = visited
        visited.insert(sourceID)
        let newID = UUID()
        var copiedMembers: [EditorTimelineItemReference] = []
        for member in source.members {
            if member.kind == .sequence,
               let childID = duplicateSequenceTree(
                   sourceID: member.itemID,
                   parentID: newID,
                   itemCopyMap: itemCopyMap,
                   visited: visited
               ) {
                copiedMembers.append(.sequence(childID))
            } else if let copied = itemCopyMap[member] {
                copiedMembers.append(copied)
            }
        }
        guard !copiedMembers.isEmpty else { return nil }
        sequences.append(EditorSequence(
            id: newID,
            title: source.title + " Copy",
            kind: source.kind,
            members: copiedMembers,
            parentSequenceID: parentID
        ))
        return newID
    }

    func timeRange(for reference: EditorTimelineItemReference) -> ClosedRange<TimeInterval>? {
        switch reference.kind {
        case .primaryClip:
            guard let index = clips.firstIndex(where: { $0.id == reference.itemID }) else { return nil }
            let start = timelineOffsetForClipIndex(index)
            return start...(start + clips[index].duration)
        case .textOverlay:
            guard let item = textOverlays.first(where: { $0.id == reference.itemID }) else { return nil }
            return item.startTime...item.endTime
        case .audioClip:
            guard let item = audioClips.first(where: { $0.id == reference.itemID }) else { return nil }
            return item.timelineStart...item.timelineEnd
        case .overlayClip:
            guard let item = overlayClips.first(where: { $0.id == reference.itemID }) else { return nil }
            return item.timelineStart...item.timelineEnd
        case .sequence:
            return sequenceTimeRange(id: reference.itemID)
        }
    }

    func sequenceTimeRange(id: UUID) -> ClosedRange<TimeInterval>? {
        let ranges = leafReferences(in: id).compactMap { timeRange(for: $0) }
        guard let start = ranges.map(\.lowerBound).min(), let end = ranges.map(\.upperBound).max() else { return nil }
        return start...end
    }

    private var allLeafReferences: Set<EditorTimelineItemReference> {
        Set(clips.map { EditorTimelineItemReference.primary($0.id) }
            + textOverlays.map { EditorTimelineItemReference.text($0.id) }
            + audioClips.map { EditorTimelineItemReference.audio($0.id) }
            + overlayClips.map { EditorTimelineItemReference.overlay($0.id) })
    }

    private var expandedSelection: Set<EditorTimelineItemReference> {
        var result = Set<EditorTimelineItemReference>()
        for reference in selectedTimelineItems {
            if reference.kind == .sequence {
                result.formUnion(leafReferences(in: reference.itemID))
            } else {
                result.insert(reference)
            }
        }
        return result
    }

    private func leafReferences(in sequenceID: UUID, visited: Set<UUID> = []) -> Set<EditorTimelineItemReference> {
        guard !visited.contains(sequenceID),
              let sequence = sequences.first(where: { $0.id == sequenceID }) else { return [] }
        var visited = visited
        visited.insert(sequenceID)
        var result = Set<EditorTimelineItemReference>()
        for member in sequence.members {
            if member.kind == .sequence {
                result.formUnion(leafReferences(in: member.itemID, visited: visited))
            } else if allLeafReferences.contains(member) {
                result.insert(member)
            }
        }
        return result
    }

    private func pruneSequenceStructure() {
        let leaves = allLeafReferences
        var didChange = true
        while didChange {
            didChange = false
            let validIDs = Set(sequences.map(\.id))
            for index in sequences.indices {
                let oldCount = sequences[index].members.count
                sequences[index].members.removeAll {
                    $0.kind == .sequence ? !validIDs.contains($0.itemID) : !leaves.contains($0)
                }
                didChange = didChange || sequences[index].members.count != oldCount
            }
            let oldSequenceCount = sequences.count
            sequences.removeAll { $0.members.isEmpty }
            didChange = didChange || sequences.count != oldSequenceCount
        }
        let validSequenceIDs = Set(sequences.map(\.id))
        for index in sequences.indices where sequences[index].parentSequenceID.map({ !validSequenceIDs.contains($0) }) == true {
            sequences[index].parentSequenceID = nil
        }
        if let activeSequenceID, !validSequenceIDs.contains(activeSequenceID) { self.activeSequenceID = nil }
        if let selectedSequenceID, !validSequenceIDs.contains(selectedSequenceID) {
            self.selectedSequenceID = nil
            selectedTimelineItems.remove(.sequence(selectedSequenceID))
        }
    }

    private func remapSequenceMembershipAfterSplit(
        original: EditorTimelineItemReference,
        right: EditorTimelineItemReference
    ) {
        for index in sequences.indices {
            guard let memberIndex = sequences[index].members.firstIndex(of: original),
                  !sequences[index].members.contains(right) else { continue }
            sequences[index].members.insert(right, at: memberIndex + 1)
        }
        if selectedTimelineItems.contains(original) { selectedTimelineItems.insert(right) }
    }

    private func remapSequenceMembershipForFreeze(
        originalID: UUID,
        displayedIDs: [UUID]
    ) {
        remapSequenceMembershipForFreeze(
            original: .primary(originalID),
            replacements: displayedIDs.map(EditorTimelineItemReference.primary)
        )
    }

    private func remapSequenceMembershipForFreeze(
        original: EditorTimelineItemReference,
        replacements: [EditorTimelineItemReference]
    ) {
        for index in sequences.indices {
            guard let memberIndex = sequences[index].members.firstIndex(of: original) else { continue }
            sequences[index].members.remove(at: memberIndex)
            var insertionIndex = memberIndex
            for replacement in replacements where !sequences[index].members.contains(replacement) {
                sequences[index].members.insert(replacement, at: insertionIndex)
                insertionIndex += 1
            }
        }
        if selectedTimelineItems.contains(original) {
            selectedTimelineItems.formUnion(replacements)
        }
    }

    private func finishSequenceMutation(rebuildComposition: Bool) {
        timelinePosition = min(max(0, timelinePosition), totalDuration)
        normalizeExportRange()
        if rebuildComposition { invalidateComposition() }
        scheduleSave()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if rebuildComposition { Task { await alignPlaybackToTimeline() } }
    }

    private func duplicatedPrimaryClip(_ source: EditorClip) -> EditorClip {
        EditorClip(
            asset: source.asset, originalDuration: source.originalDuration,
            trimStart: source.trimStart, trimEnd: source.trimEnd, speed: source.speed,
            speedRamp: source.speedRamp, playback: source.playback, volume: source.volume,
            audioTrimStart: source.audioTrimStart, audioTrimEnd: source.audioTrimEnd,
            isAudioLinked: source.isAudioLinked, cropAspect: source.cropAspect,
            reframeMode: source.reframeMode, rotationQuarterTurns: source.rotationQuarterTurns,
            straightenDegrees: source.straightenDegrees,
            isFlippedHorizontally: source.isFlippedHorizontally,
            isFlippedVertically: source.isFlippedVertically,
            reframeScale: source.reframeScale, reframeXOffset: source.reframeXOffset,
            reframeYOffset: source.reframeYOffset, colorAdjustment: source.colorAdjustment,
            compositing: source.compositing, keyframes: source.keyframes,
            motionTracks: source.motionTracks.map { track in var copy = track; copy.id = UUID(); return copy },
            stabilization: source.stabilization, transitionKind: source.transitionKind,
            transitionDuration: source.transitionDuration
        )
    }

    private func duplicatedTextOverlay(
        _ source: EditorTextOverlay,
        timelineOffset offset: TimeInterval
    ) -> EditorTextOverlay {
        return EditorTextOverlay(
            text: source.text, startTime: source.startTime + offset, endTime: source.endTime + offset,
            fontSize: source.fontSize, fontFamily: source.fontFamily, fontStyle: source.fontStyle,
            textColor: source.textColor, opacity: source.opacity,
            horizontalAlignment: source.horizontalAlignment, verticalAlignment: source.verticalAlignment,
            xOffset: source.xOffset, yOffset: source.yOffset, keyframes: source.keyframes,
            animation: source.animation, attachedClipID: source.attachedClipID,
            attachedTrackID: source.attachedTrackID, attachRotation: source.attachRotation,
            attachScale: source.attachScale,
            captionWords: source.captionWords.map {
                EditorCaptionWord(text: $0.text, startTime: $0.startTime + offset,
                                  endTime: $0.endTime + offset, confidence: $0.confidence)
            },
            captionHighlightColor: source.captionHighlightColor,
            captionLocaleIdentifier: source.captionLocaleIdentifier,
            trackedRotationDegrees: source.trackedRotationDegrees
        )
    }

    private func duplicatedOverlayClip(
        _ source: EditorOverlayClip,
        timelineOffset: TimeInterval
    ) -> EditorOverlayClip {
        EditorOverlayClip(
            asset: source.asset, originalDuration: source.originalDuration,
            trimStart: source.trimStart, trimEnd: source.trimEnd,
            timelineStart: source.timelineStart + timelineOffset,
            laneIndex: source.laneIndex, zIndex: source.zIndex,
            speed: source.speed, playback: source.playback,
            scale: source.scale, xOffset: source.xOffset,
            yOffset: source.yOffset, opacity: source.opacity, volume: source.volume,
            cropAspect: source.cropAspect, reframeMode: source.reframeMode,
            rotationQuarterTurns: source.rotationQuarterTurns,
            straightenDegrees: source.straightenDegrees,
            isFlippedHorizontally: source.isFlippedHorizontally,
            isFlippedVertically: source.isFlippedVertically,
            reframeScale: source.reframeScale, reframeXOffset: source.reframeXOffset,
            reframeYOffset: source.reframeYOffset, colorAdjustment: source.colorAdjustment,
            compositing: source.compositing, keyframes: source.keyframes,
            motionTracks: source.motionTracks.map { track in var copy = track; copy.id = UUID(); return copy },
            stabilization: source.stabilization, attachedClipID: source.attachedClipID,
            attachedTrackID: source.attachedTrackID, attachRotation: source.attachRotation,
            attachScale: source.attachScale
        )
    }

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

    private func rippleInsertTimedItems(at boundary: TimeInterval, duration: TimeInterval) {
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
    }

    private func rippleDeleteTimedItems(from start: TimeInterval, to end: TimeInterval) {
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

    /// Inserts a sound/music library item (`AudioLibraryPickerView`) as a normal timeline clip.
    /// Library items already live inside the app bundle — no security-scoped access, no copy
    /// into `MixtapeAudio/` needed, since the bundle file is permanently available. From here
    /// on the inserted clip is indistinguishable from an imported one: trim, move, split,
    /// duplicate, volume, keyframes, undo, and persistence all just work.
    func insertAudioLibraryItem(
        title: String,
        fileURL: URL,
        duration: TimeInterval,
        attribution: String? = nil,
        insertion: AudioInsertion = .newTrackAtPlayhead
    ) {
        registerUndoIfNeeded()
        let (timelineStart, laneIndex) = resolveAudioInsertion(insertion)

        let clip = EditorAudioClip(
            title: title,
            fileURL: fileURL,
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

    private func finalizeAudioVolumeEditUndo() {
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

    private func releaseAudioFileIfUnused(_ url: URL) {
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
                let audioTrackSettingsSnapshot = audioTrackSettings
                let masterVolumeSnapshot = masterVolume
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
                    projectTitle: projectTitleSnapshot,
                    audioTrackSettings: audioTrackSettingsSnapshot,
                    masterVolume: masterVolumeSnapshot
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
        cancelReverseGeneration()
        cancelCaptionTranscription()
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
            selectedTextOverlayID: selectedTextOverlayID,
            selectedAudioClipID: selectedAudioClipID,
            selectedOverlayClipID: selectedOverlayClipID,
            textOverlays: textOverlays,
            audioClips: audioClips,
            audioTrackSettings: audioTrackSettings,
            masterVolume: masterVolume,
            overlayClips: overlayClips,
            canvasSettings: canvasSettings,
            exportInPoint: exportInPoint,
            exportOutPoint: exportOutPoint,
            sequences: sequences,
            markers: markers,
            selectedTimelineItems: selectedTimelineItems,
            selectedSequenceID: selectedSequenceID,
            activeSequenceID: activeSequenceID
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
        selectedTextOverlayID = snapshot.selectedTextOverlayID
        selectedAudioClipID = snapshot.selectedAudioClipID
        selectedOverlayClipID = snapshot.selectedOverlayClipID
        textOverlays = snapshot.textOverlays
        audioClips = snapshot.audioClips
        audioTrackSettings = snapshot.audioTrackSettings
        masterVolume = snapshot.masterVolume
        overlayClips = snapshot.overlayClips
        canvasSettings = snapshot.canvasSettings
        exportInPoint = snapshot.exportInPoint
        exportOutPoint = snapshot.exportOutPoint
        sequences = snapshot.sequences
        markers = snapshot.markers
        selectedTimelineItems = snapshot.selectedTimelineItems
        selectedSequenceID = snapshot.selectedSequenceID
        activeSequenceID = snapshot.activeSequenceID
        isMultiSelectMode = !selectedTimelineItems.isEmpty
        if isMultiSelectMode {
            selectedTool = .sequence
            selectedClipID = nil
            selectedTextOverlayID = nil
            selectedAudioClipID = nil
            selectedOverlayClipID = nil
        } else if selectedTool == .sequence {
            selectedTool = nil
        }
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
            selectedTextOverlayID: selectedTextOverlayID,
            selectedAudioClipID: selectedAudioClipID,
            selectedOverlayClipID: selectedOverlayClipID,
            sequences: sequences,
            markers: markers,
            selectedTimelineItems: Array(selectedTimelineItems).sorted { $0.id < $1.id },
            selectedSequenceID: selectedSequenceID,
            activeSequenceID: activeSequenceID,
            canvasSettings: canvasSettings,
            exportInPoint: exportInPoint,
            exportOutPoint: exportOutPoint,
            audioTrackSettings: audioTrackSettings,
            masterVolume: masterVolume
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
        candidates.append(contentsOf: markers.map(\.time))

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
            "\(clip.id.uuidString)|\(clip.trimStart)|\(clip.trimEnd)|\(clip.speed)|\(String(describing: clip.speedRamp))|\(clip.playback)|\(clip.volume)|\(clip.audioTrimStart ?? -1)|\(clip.audioTrimEnd ?? -1)|\(clip.isAudioLinked)|\(clip.cropAspect.rawValue)|\(clip.reframeMode.rawValue)|\(clip.rotationQuarterTurns)|\(clip.straightenDegrees)|\(clip.isFlippedHorizontally)|\(clip.isFlippedVertically)|\(clip.reframeScale)|\(clip.reframeXOffset)|\(clip.reframeYOffset)|\(clip.colorAdjustment)|\(clip.compositing)|\(clip.keyframes)|\(clip.motionTracks)|\(clip.stabilization)|\(clip.transitionKind.rawValue)|\(clip.transitionDuration)|\(clip.duration)|\(clip.asset.localIdentifier)"
        }.joined(separator: ";")
        let audioHash = audioClips.map {
            "\($0.id.uuidString)|\($0.trimStart)|\($0.trimEnd)|\($0.timelineStart)|\($0.volume)|\($0.fadeInDuration)|\($0.fadeOutDuration)|\($0.keyframes)|\($0.fileURL.path)|\($0.effect.rawValue)"
        }.joined(separator: ";")
        let overlayHash = overlayClips.map {
            "\($0.id.uuidString)|\($0.trimStart)|\($0.trimEnd)|\($0.timelineStart)|\($0.laneIndex)|\($0.zIndex)|\($0.speed)|\($0.playback)|\($0.scale)|\($0.xOffset)|\($0.yOffset)|\($0.opacity)|\($0.volume)|\($0.cropAspect.rawValue)|\($0.reframeMode.rawValue)|\($0.rotationQuarterTurns)|\($0.straightenDegrees)|\($0.isFlippedHorizontally)|\($0.isFlippedVertically)|\($0.reframeScale)|\($0.reframeXOffset)|\($0.reframeYOffset)|\($0.colorAdjustment)|\($0.compositing)|\($0.keyframes)|\($0.motionTracks)|\($0.stabilization)|\($0.attachedClipID?.uuidString ?? "")|\($0.attachedTrackID?.uuidString ?? "")|\($0.asset.localIdentifier)"
        }.joined(separator: ";")
        let openingHash = "\(openingTransitionKind.rawValue)|\(openingTransitionDuration)"
        let closingHash = "\(closingTransitionKind.rawValue)|\(closingTransitionDuration)"
        let mixHash = audioTrackSettings.keys.sorted()
            .map { "\($0):\(audioTrackSettings[$0]!.gain)|\(audioTrackSettings[$0]!.isMuted)|\(audioTrackSettings[$0]!.isSoloed)" }
            .joined(separator: ";") + "|||\(masterVolume)"
        return clipsHash + "|||" + audioHash + "|||" + overlayHash + "|||" + openingHash + "|||" + closingHash + "|||\(canvasSettings)" + "|||" + mixHash
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
        let audioTrackSettingsSnapshot = audioTrackSettings
        let masterVolumeSnapshot = masterVolume

        let item: AVPlayerItem?
        if audioClipsSnapshot.isEmpty,
           overlayClipsSnapshot.isEmpty,
           openingKindSnapshot == .none,
           closingKindSnapshot == .none,
           canvasSnapshot == .default,
           abs(masterVolumeSnapshot - 1.0) < 0.001,
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
                    canvasSettings: canvasSnapshot,
                    audioTrackSettings: audioTrackSettingsSnapshot,
                    masterVolume: masterVolumeSnapshot
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
