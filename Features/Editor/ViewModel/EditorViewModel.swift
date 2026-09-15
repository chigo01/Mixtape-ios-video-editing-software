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

    // MARK: On-device editing copilot

    var copilotStatus: String?
    var copilotError: String?
    var isCopilotWorking = false
    var copilotPlan: EditorCopilotPlan?
    var copilotEditPlan: EditorCopilotEditPlan?
    var copilotPreview: EditorViewModel?
    @ObservationIgnored var copilotTask: Task<Void, Never>?
    @ObservationIgnored var copilotJobID: UUID?
    @ObservationIgnored var copilotSource: EditorTimelineSnapshot?
    @ObservationIgnored var copilotDraft: EditorTimelineSnapshot?
    @ObservationIgnored var copilotTranscript: EditorCaptionTranscriptResult?
    @ObservationIgnored var copilotTranscriptSource: EditorTimelineSnapshot?
    @ObservationIgnored var copilotTranscriptLocale: String?
    @ObservationIgnored var isCopilotPreview = false
    @ObservationIgnored var isCopilotPreviewDiscarded = false
    /// Playhead at MixPilot generate time. Comparable snapshots zero this, so Apply
    /// must restore it instead of seeking to the first operation (captions start at 0).
    @ObservationIgnored var copilotRestoreTime: TimeInterval = 0
    /// Bumped after MixPilot apply so the timeline scroller recenters on the playhead.
    var timelineRevealNonce = 0

    // MARK: Timeline state

    var clips: [EditorClip]
    var openingTransitionKind: EditorTransitionKind
    var openingTransitionDuration: TimeInterval
    var closingTransitionKind: EditorTransitionKind
    var closingTransitionDuration: TimeInterval
    var selectedClipID: UUID?
    var textOverlays: [EditorTextOverlay]
    var graphicOverlays: [EditorGraphicOverlay]
    var audioClips: [EditorAudioClip]
    /// Per-lane gain/mute (Priority 13 gain staging), keyed by `EditorAudioClip.laneIndex`.
    var audioTrackSettings: [Int: EditorAudioTrackSettings] = [:]
    /// Final output gain applied on top of every track's own volume/keyframes.
    var masterVolume: Float = 1.0
    var overlayClips: [EditorOverlayClip]
    var adjustmentLayers: [EditorAdjustmentLayer]
    var selectedAdjustmentLayerID: UUID?
    var selectedVisualEffectID: UUID?
    var canvasSettings: EditorCanvasSettings
    var exportInPoint: TimeInterval?
    var exportOutPoint: TimeInterval?
    var sequences: [EditorSequence]
    var markers: [EditorTimelineMarker]
    var selectedTimelineItems: Set<EditorTimelineItemReference>
    var selectedSequenceID: UUID?
    var activeSequenceID: UUID?
    var isMultiSelectMode = false

    /// Global playhead: 0 … totalDuration across every clip in order.
    var timelinePosition: TimeInterval = 0
    var snapGuideTime: TimeInterval?

    var isPlaying: Bool = false
    var selectedTool: EditorTool?
    var showsReframeSafeAreaGuides: Bool = true
    var selectedColorMaskID: UUID?
    var isColorMaskEditing = false
    var showsColorMaskOverlay = true
    var colorMaskTrackingDirection: EditorColorMaskTrackingDirection?
    var colorMaskTrackingMessage: String?
    var selectedMotionTrackID: UUID?
    var isTrackingSubject = false
    var motionTrackingMessage: String?
    /// Live preview canvas size in points, kept fresh by
    /// `MotionTrackingSelectionLayer`'s `GeometryReader` while the tracking
    /// box is on screen. Text overlay offsets themselves are stored in
    /// `EditorTextOverlayLayout` reference points, not this size.
    @ObservationIgnored
    var activeTrackingCanvasSize: CGSize?
    var stabilizationAnalysisProgress: Double?
    var reverseGenerationProgress: Double?
    var reverseGenerationClipID: UUID?
    var reverseGenerationErrorMessage: String?
    @ObservationIgnored var reverseGenerationTask: Task<Void, Never>?

    // MARK: Text overlay editing

    var selectedTextOverlayID: UUID?
    var selectedGraphicOverlayID: UUID?
    var isTextEditorPresented: Bool = false
    var isTranscribingCaptions = false
    var captionStatusMessage: String?
    var captionErrorMessage: String?
    @ObservationIgnored var captionTask: Task<Void, Never>?
    @ObservationIgnored var captionJobID: UUID?

    // MARK: Audio editing

    var selectedAudioClipID: UUID?
    /// Clip currently being marked for a punch-in re-record (Priority 14 follow-up); `nil` when
    /// no marking is in progress. Transient UI state, not persisted or undoable.
    var punchInClipID: UUID?
    var punchInStartTime: TimeInterval?
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
    var renderingAudioEffect: EditorAudioEffect?
    var audioEffectErrorMessage: String?
    @ObservationIgnored var audioEffectRenderTask: Task<Void, Never>?

    // MARK: Video overlay editing

    var selectedOverlayClipID: UUID?

    // MARK: Project persistence

    private(set) var projectID: UUID
    let projectCreatedAt: Date
    var projectTitle: String

    // MARK: Proxy and render cache

    var proxySettings: EditorProxySettings
    var mediaCacheStats: EditorMediaCacheStats = .empty
    var proxyGenerationProgress: Double?
    var isBuildingRenderCache = false
    var cacheStatusMessage: String?
    @ObservationIgnored var proxyGenerationTask: Task<Void, Never>?
    @ObservationIgnored var renderCacheTask: Task<Void, Never>?
    var templateStatusMessage: String?

    // MARK: Export

    var isExporting: Bool = false
    var exportProgress: Double = 0
    var exportMessage: String?
    var exportedFileURL: URL?

    @ObservationIgnored
    var exportTask: Task<Void, Never>?

    // MARK: Undo

    var canUndo: Bool = false
    var canRedo: Bool = false

    // MARK: Player

    var player: AVPlayer?

    @ObservationIgnored
    var endObserver: NSObjectProtocol?
    @ObservationIgnored
    var tickTimer: Timer?
    @ObservationIgnored
    var compositionFingerprint: String?
    @ObservationIgnored
    let previewBuilds = EditorPreviewBuildCoordinator<AVPlayerItem>()
    @ObservationIgnored
    var previewRequestID = UUID()
    @ObservationIgnored
    let undoManager = EditorUndoManager()
    @ObservationIgnored
    var trimUndoSnapshot: EditorTimelineSnapshot?
    @ObservationIgnored
    var speedUndoSnapshot: EditorTimelineSnapshot?
    @ObservationIgnored
    var photoDurationUndoSnapshot: EditorTimelineSnapshot?
    @ObservationIgnored
    var reframeUndoSnapshot: EditorTimelineSnapshot?
    @ObservationIgnored
    var colorUndoSnapshot: EditorTimelineSnapshot?
    var copiedColorAdjustment: EditorColorAdjustment?
    @ObservationIgnored
    var colorPreviewTask: Task<Void, Never>?
    @ObservationIgnored
    var overlayCompositingPreviewTask: Task<Void, Never>?
    @ObservationIgnored
    var colorMaskTrackingTask: Task<Void, Never>?
    @ObservationIgnored
    var colorMaskTrackingSessionID: UUID?
    @ObservationIgnored
    var motionTrackingTask: Task<Void, Never>?
    @ObservationIgnored
    var motionTrackingSessionID: UUID?
    @ObservationIgnored
    var motionTrackingUndoSnapshot: EditorTimelineSnapshot?
    @ObservationIgnored
    var motionPreviewTask: Task<Void, Never>?
    @ObservationIgnored
    var reframePositionDragOrigin: (x: CGFloat, y: CGFloat)?
    @ObservationIgnored
    var textEditUndoSnapshot: EditorTimelineSnapshot?
    @ObservationIgnored
    var textEditDragOrigin: (x: CGFloat, y: CGFloat)?
    @ObservationIgnored
    var textTimeRangeUndoSnapshot: EditorTimelineSnapshot?
    @ObservationIgnored
    var textMoveUndoSnapshot: EditorTimelineSnapshot?
    @ObservationIgnored
    var volumeUndoSnapshot: EditorTimelineSnapshot?
    @ObservationIgnored
    var audioTrimUndoSnapshot: EditorTimelineSnapshot?
    @ObservationIgnored
    var audioMoveUndoSnapshot: EditorTimelineSnapshot?
    @ObservationIgnored
    var audioVolumeUndoSnapshot: EditorTimelineSnapshot?
    @ObservationIgnored
    var mixUndoSnapshot: EditorTimelineSnapshot?
    @ObservationIgnored
    var overlayTrimUndoSnapshot: EditorTimelineSnapshot?
    @ObservationIgnored
    var overlayMoveUndoSnapshot: EditorTimelineSnapshot?
    @ObservationIgnored
    var overlayTransformUndoSnapshot: EditorTimelineSnapshot?
    @ObservationIgnored
    var graphicEditUndoSnapshot: EditorTimelineSnapshot?
    @ObservationIgnored
    var graphicDragOrigin: (x: CGFloat, y: CGFloat)?
    @ObservationIgnored
    var overlayCompositingUndoSnapshot: EditorTimelineSnapshot?
    @ObservationIgnored
    var overlayPositionDragOrigin: (x: CGFloat, y: CGFloat)?
    @ObservationIgnored
    var transitionUndoSnapshot: EditorTimelineSnapshot?
    @ObservationIgnored
    var saveTask: Task<Void, Never>?
    @ObservationIgnored
    var lastHapticSnapTime: TimeInterval?

    // MARK: Init

    init(project: EditorProject) {
        self.projectID = project.id
        self.projectCreatedAt = project.createdAt
        self.projectTitle = project.title
        self.proxySettings = project.proxySettings
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
        self.graphicOverlays = project.graphicOverlays.filter { overlay in
            if case let .image(path) = overlay.source {
                return FileManager.default.fileExists(atPath: path)
            }
            return true
        }
        self.selectedGraphicOverlayID = project.selectedGraphicOverlayID
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
        self.adjustmentLayers = project.adjustmentLayers
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
            self.selectedGraphicOverlayID = nil
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
}
