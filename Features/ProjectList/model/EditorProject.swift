//
//  EditorProject.swift
//  Mixtape
//

import Foundation
import Photos

// MARK: - Persisted DTOs (Codable — no PHAsset)

struct SavedEditorClip: Codable, Identifiable, Hashable {
    let id: UUID
    let assetLocalIdentifier: String
    let originalDuration: TimeInterval
    var trimStart: TimeInterval
    var trimEnd: TimeInterval
    var speed: Float
    var speedRamp: EditorSpeedRamp?
    var playback: EditorClipPlayback
    var volume: Float
    var audioTrimStart: TimeInterval?
    var audioTrimEnd: TimeInterval?
    var isAudioLinked: Bool
    var cropAspect: EditorCropAspect
    var reframeMode: EditorReframeMode
    var rotationQuarterTurns: Int
    var straightenDegrees: Double
    var isFlippedHorizontally: Bool
    var isFlippedVertically: Bool
    var reframeScale: CGFloat
    var reframeXOffset: CGFloat
    var reframeYOffset: CGFloat
    var colorAdjustment: EditorColorAdjustment
    var compositing: EditorOverlayCompositing
    var keyframes: EditorKeyframeTracks
    var motionTracks: [EditorMotionTrack]
    var stabilization: EditorStabilizationSettings
    var transitionKind: EditorTransitionKind
    var transitionDuration: TimeInterval

    init(from clip: EditorClip) {
        id = clip.id
        assetLocalIdentifier = clip.asset.localIdentifier
        originalDuration = clip.originalDuration
        trimStart = clip.trimStart
        trimEnd = clip.trimEnd
        speed = clip.speed
        speedRamp = clip.speedRamp
        playback = clip.playback
        volume = clip.volume
        audioTrimStart = clip.audioTrimStart
        audioTrimEnd = clip.audioTrimEnd
        isAudioLinked = clip.isAudioLinked
        cropAspect = clip.cropAspect
        reframeMode = clip.reframeMode
        rotationQuarterTurns = clip.rotationQuarterTurns
        straightenDegrees = clip.straightenDegrees
        isFlippedHorizontally = clip.isFlippedHorizontally
        isFlippedVertically = clip.isFlippedVertically
        reframeScale = clip.reframeScale
        reframeXOffset = clip.reframeXOffset
        reframeYOffset = clip.reframeYOffset
        colorAdjustment = clip.colorAdjustment
        compositing = clip.compositing
        keyframes = clip.keyframes
        motionTracks = clip.motionTracks
        stabilization = clip.stabilization
        transitionKind = clip.transitionKind
        transitionDuration = clip.transitionDuration
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        assetLocalIdentifier = try c.decode(String.self, forKey: .assetLocalIdentifier)
        originalDuration = try c.decode(TimeInterval.self, forKey: .originalDuration)
        trimStart = try c.decode(TimeInterval.self, forKey: .trimStart)
        trimEnd = try c.decode(TimeInterval.self, forKey: .trimEnd)
        speed = try c.decode(Float.self, forKey: .speed)
        speedRamp = try c.decodeIfPresent(EditorSpeedRamp.self, forKey: .speedRamp)
        playback = try c.decodeIfPresent(EditorClipPlayback.self, forKey: .playback) ?? .forward
        volume = try c.decode(Float.self, forKey: .volume)
        audioTrimStart = try c.decodeIfPresent(TimeInterval.self, forKey: .audioTrimStart)
        audioTrimEnd = try c.decodeIfPresent(TimeInterval.self, forKey: .audioTrimEnd)
        isAudioLinked = try c.decodeIfPresent(Bool.self, forKey: .isAudioLinked) ?? true
        cropAspect = try c.decodeIfPresent(EditorCropAspect.self, forKey: .cropAspect) ?? .original
        reframeMode = try c.decodeIfPresent(EditorReframeMode.self, forKey: .reframeMode) ?? .fit
        rotationQuarterTurns = try c.decodeIfPresent(Int.self, forKey: .rotationQuarterTurns) ?? 0
        straightenDegrees = try c.decodeIfPresent(Double.self, forKey: .straightenDegrees) ?? 0
        isFlippedHorizontally = try c.decodeIfPresent(Bool.self, forKey: .isFlippedHorizontally) ?? false
        isFlippedVertically = try c.decodeIfPresent(Bool.self, forKey: .isFlippedVertically) ?? false
        reframeScale = try c.decodeIfPresent(CGFloat.self, forKey: .reframeScale) ?? 1
        reframeXOffset = try c.decodeIfPresent(CGFloat.self, forKey: .reframeXOffset) ?? 0
        reframeYOffset = try c.decodeIfPresent(CGFloat.self, forKey: .reframeYOffset) ?? 0
        colorAdjustment = try c.decodeIfPresent(
            EditorColorAdjustment.self,
            forKey: .colorAdjustment
        ) ?? .neutral
        compositing = try c.decodeIfPresent(
            EditorOverlayCompositing.self,
            forKey: .compositing
        ) ?? .standard
        keyframes = try c.decodeIfPresent(EditorKeyframeTracks.self, forKey: .keyframes) ?? .empty
        motionTracks = try c.decodeIfPresent([EditorMotionTrack].self, forKey: .motionTracks) ?? []
        stabilization = try c.decodeIfPresent(
            EditorStabilizationSettings.self,
            forKey: .stabilization
        ) ?? .disabled
        transitionDuration = try c.decodeIfPresent(TimeInterval.self, forKey: .transitionDuration) ?? 0
        if let rawKind = try c.decodeIfPresent(String.self, forKey: .transitionKind) {
            // `zoom` was shipped briefly before the catalog split it into Zoom In/Out.
            transitionKind = rawKind == "zoom"
                ? .zoomIn
                : (EditorTransitionKind(rawValue: rawKind) ?? .none)
        } else {
            transitionKind = transitionDuration > 0 ? .dipToBlack : .none
        }
    }
}

struct SavedTextOverlay: Codable, Identifiable, Hashable {
    let id: UUID
    var text: String
    var startTime: TimeInterval
    var endTime: TimeInterval

    // Style properties (defaults for backward compat with older projects)
    var fontSize: CGFloat
    var fontFamily: TextOverlayFontFamily
    var fontStyle: TextOverlayFontStyle
    var textColor: TextOverlayColor
    var opacity: Double
    var horizontalAlignment: TextOverlayHAlignment
    var verticalAlignment: TextOverlayVAlignment
    var xOffset: CGFloat
    var yOffset: CGFloat
    var keyframes: EditorKeyframeTracks
    var animation: EditorTextAnimation
    var attachedClipID: UUID?
    var attachedTrackID: UUID?
    var attachRotation: Bool
    var attachScale: Bool
    var captionWords: [EditorCaptionWord]
    var captionHighlightColor: TextOverlayColor
    var captionLocaleIdentifier: String?

    init(from overlay: EditorTextOverlay) {
        id = overlay.id
        text = overlay.text
        startTime = overlay.startTime
        endTime = overlay.endTime
        fontSize = overlay.fontSize
        fontFamily = overlay.fontFamily
        fontStyle = overlay.fontStyle
        textColor = overlay.textColor
        opacity = overlay.opacity
        horizontalAlignment = overlay.horizontalAlignment
        verticalAlignment = overlay.verticalAlignment
        xOffset = overlay.xOffset
        yOffset = overlay.yOffset
        keyframes = overlay.keyframes
        animation = overlay.animation
        attachedClipID = overlay.attachedClipID
        attachedTrackID = overlay.attachedTrackID
        attachRotation = overlay.attachRotation
        attachScale = overlay.attachScale
        captionWords = overlay.captionWords
        captionHighlightColor = overlay.captionHighlightColor
        captionLocaleIdentifier = overlay.captionLocaleIdentifier
    }

    func toOverlay() -> EditorTextOverlay {
        EditorTextOverlay(
            id: id,
            text: text,
            startTime: startTime,
            endTime: endTime,
            fontSize: fontSize,
            fontFamily: fontFamily,
            fontStyle: fontStyle,
            textColor: textColor,
            opacity: opacity,
            horizontalAlignment: horizontalAlignment,
            verticalAlignment: verticalAlignment,
            xOffset: xOffset,
            yOffset: yOffset,
            keyframes: keyframes,
            animation: animation,
            attachedClipID: attachedClipID,
            attachedTrackID: attachedTrackID,
            attachRotation: attachRotation,
            attachScale: attachScale,
            captionWords: captionWords,
            captionHighlightColor: captionHighlightColor,
            captionLocaleIdentifier: captionLocaleIdentifier
        )
    }

    // Backward-compatible decoding: older JSON files won't have style fields.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        text = try c.decode(String.self, forKey: .text)
        startTime = try c.decode(TimeInterval.self, forKey: .startTime)
        endTime = try c.decode(TimeInterval.self, forKey: .endTime)
        fontSize = try c.decodeIfPresent(CGFloat.self, forKey: .fontSize) ?? 36
        fontFamily = try c.decodeIfPresent(TextOverlayFontFamily.self, forKey: .fontFamily) ?? .system
        fontStyle = try c.decodeIfPresent(TextOverlayFontStyle.self, forKey: .fontStyle) ?? .plain
        textColor = try c.decodeIfPresent(TextOverlayColor.self, forKey: .textColor) ?? .white
        opacity = try c.decodeIfPresent(Double.self, forKey: .opacity) ?? 1.0
        horizontalAlignment = try c.decodeIfPresent(TextOverlayHAlignment.self, forKey: .horizontalAlignment) ?? .center
        verticalAlignment = try c.decodeIfPresent(TextOverlayVAlignment.self, forKey: .verticalAlignment) ?? .center
        xOffset = try c.decodeIfPresent(CGFloat.self, forKey: .xOffset) ?? 0.0
        yOffset = try c.decodeIfPresent(CGFloat.self, forKey: .yOffset) ?? 0.0
        keyframes = try c.decodeIfPresent(EditorKeyframeTracks.self, forKey: .keyframes) ?? .empty
        animation = try c.decodeIfPresent(EditorTextAnimation.self, forKey: .animation) ?? .none
        attachedClipID = try c.decodeIfPresent(UUID.self, forKey: .attachedClipID)
        attachedTrackID = try c.decodeIfPresent(UUID.self, forKey: .attachedTrackID)
        attachRotation = try c.decodeIfPresent(Bool.self, forKey: .attachRotation) ?? false
        attachScale = try c.decodeIfPresent(Bool.self, forKey: .attachScale) ?? false
        captionWords = try c.decodeIfPresent([EditorCaptionWord].self, forKey: .captionWords) ?? []
        captionHighlightColor = try c.decodeIfPresent(
            TextOverlayColor.self,
            forKey: .captionHighlightColor
        ) ?? .yellow
        captionLocaleIdentifier = try c.decodeIfPresent(
            String.self,
            forKey: .captionLocaleIdentifier
        )
    }
}

struct SavedAudioClip: Codable, Identifiable, Hashable {
    let id: UUID
    var title: String
    var fileURLPath: String
    var originalDuration: TimeInterval
    var trimStart: TimeInterval
    var trimEnd: TimeInterval
    var timelineStart: TimeInterval
    var laneIndex: Int
    var volume: Float
    var fadeInDuration: TimeInterval
    var fadeOutDuration: TimeInterval
    var keyframes: EditorKeyframeTracks
    var attribution: String?
    var effect: EditorAudioEffect?

    init(from clip: EditorAudioClip) {
        id = clip.id
        title = clip.title
        fileURLPath = clip.fileURL.path
        originalDuration = clip.originalDuration
        trimStart = clip.trimStart
        trimEnd = clip.trimEnd
        timelineStart = clip.timelineStart
        laneIndex = clip.laneIndex
        volume = clip.volume
        fadeInDuration = clip.fadeInDuration
        fadeOutDuration = clip.fadeOutDuration
        keyframes = clip.keyframes
        attribution = clip.attribution
        effect = clip.effect == .none ? nil : clip.effect
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        fileURLPath = try c.decode(String.self, forKey: .fileURLPath)
        originalDuration = try c.decode(TimeInterval.self, forKey: .originalDuration)
        trimStart = try c.decode(TimeInterval.self, forKey: .trimStart)
        trimEnd = try c.decode(TimeInterval.self, forKey: .trimEnd)
        timelineStart = try c.decode(TimeInterval.self, forKey: .timelineStart)
        laneIndex = try c.decodeIfPresent(Int.self, forKey: .laneIndex) ?? 0
        volume = try c.decode(Float.self, forKey: .volume)
        fadeInDuration = try c.decodeIfPresent(TimeInterval.self, forKey: .fadeInDuration) ?? 0
        fadeOutDuration = try c.decodeIfPresent(TimeInterval.self, forKey: .fadeOutDuration) ?? 0
        keyframes = try c.decodeIfPresent(EditorKeyframeTracks.self, forKey: .keyframes) ?? .empty
        attribution = try c.decodeIfPresent(String.self, forKey: .attribution)
        effect = try c.decodeIfPresent(EditorAudioEffect.self, forKey: .effect)
    }

    func toAudioClip() -> EditorAudioClip? {
        let url = URL(fileURLWithPath: fileURLPath)
        guard FileManager.default.fileExists(atPath: fileURLPath) else { return nil }
        return EditorAudioClip(
            id: id,
            title: title,
            fileURL: url,
            originalDuration: originalDuration,
            trimStart: trimStart,
            trimEnd: trimEnd,
            timelineStart: timelineStart,
            laneIndex: laneIndex,
            volume: volume,
            fadeInDuration: fadeInDuration,
            fadeOutDuration: fadeOutDuration,
            keyframes: keyframes,
            attribution: attribution,
            effect: effect ?? .none
        )
    }
}

struct SavedOverlayClip: Codable, Identifiable, Hashable {
    let id: UUID
    let assetLocalIdentifier: String
    let originalDuration: TimeInterval
    var trimStart: TimeInterval
    var trimEnd: TimeInterval
    var timelineStart: TimeInterval
    var laneIndex: Int
    var zIndex: Int
    var speed: Float
    var playback: EditorClipPlayback
    var scale: CGFloat
    var xOffset: CGFloat
    var yOffset: CGFloat
    var opacity: Double
    var volume: Float
    var cropAspect: EditorCropAspect
    var reframeMode: EditorReframeMode
    var rotationQuarterTurns: Int
    var straightenDegrees: Double
    var isFlippedHorizontally: Bool
    var isFlippedVertically: Bool
    var reframeScale: CGFloat
    var reframeXOffset: CGFloat
    var reframeYOffset: CGFloat
    var colorAdjustment: EditorColorAdjustment
    var compositing: EditorOverlayCompositing
    var keyframes: EditorKeyframeTracks
    var motionTracks: [EditorMotionTrack]
    var stabilization: EditorStabilizationSettings
    var attachedClipID: UUID?
    var attachedTrackID: UUID?
    var attachRotation: Bool
    var attachScale: Bool

    init(from clip: EditorOverlayClip) {
        id = clip.id
        assetLocalIdentifier = clip.asset.localIdentifier
        originalDuration = clip.originalDuration
        trimStart = clip.trimStart
        trimEnd = clip.trimEnd
        timelineStart = clip.timelineStart
        laneIndex = clip.laneIndex
        zIndex = clip.zIndex
        speed = clip.speed
        playback = clip.playback
        scale = clip.scale
        xOffset = clip.xOffset
        yOffset = clip.yOffset
        opacity = clip.opacity
        volume = clip.volume
        cropAspect = clip.cropAspect
        reframeMode = clip.reframeMode
        rotationQuarterTurns = clip.rotationQuarterTurns
        straightenDegrees = clip.straightenDegrees
        isFlippedHorizontally = clip.isFlippedHorizontally
        isFlippedVertically = clip.isFlippedVertically
        reframeScale = clip.reframeScale
        reframeXOffset = clip.reframeXOffset
        reframeYOffset = clip.reframeYOffset
        colorAdjustment = clip.colorAdjustment
        compositing = clip.compositing
        keyframes = clip.keyframes
        motionTracks = clip.motionTracks
        stabilization = clip.stabilization
        attachedClipID = clip.attachedClipID
        attachedTrackID = clip.attachedTrackID
        attachRotation = clip.attachRotation
        attachScale = clip.attachScale
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        assetLocalIdentifier = try c.decode(String.self, forKey: .assetLocalIdentifier)
        originalDuration = try c.decode(TimeInterval.self, forKey: .originalDuration)
        trimStart = try c.decode(TimeInterval.self, forKey: .trimStart)
        trimEnd = try c.decode(TimeInterval.self, forKey: .trimEnd)
        timelineStart = try c.decode(TimeInterval.self, forKey: .timelineStart)
        laneIndex = try c.decodeIfPresent(Int.self, forKey: .laneIndex) ?? -1
        zIndex = try c.decodeIfPresent(Int.self, forKey: .zIndex) ?? laneIndex
        speed = try c.decodeIfPresent(Float.self, forKey: .speed) ?? 1
        playback = try c.decodeIfPresent(EditorClipPlayback.self, forKey: .playback) ?? .forward
        scale = try c.decodeIfPresent(CGFloat.self, forKey: .scale) ?? 0.55
        xOffset = try c.decodeIfPresent(CGFloat.self, forKey: .xOffset) ?? 0
        yOffset = try c.decodeIfPresent(CGFloat.self, forKey: .yOffset) ?? 0
        opacity = try c.decodeIfPresent(Double.self, forKey: .opacity) ?? 1
        volume = try c.decodeIfPresent(Float.self, forKey: .volume) ?? 1
        cropAspect = try c.decodeIfPresent(EditorCropAspect.self, forKey: .cropAspect) ?? .original
        reframeMode = try c.decodeIfPresent(EditorReframeMode.self, forKey: .reframeMode) ?? .fit
        rotationQuarterTurns = try c.decodeIfPresent(Int.self, forKey: .rotationQuarterTurns) ?? 0
        straightenDegrees = try c.decodeIfPresent(Double.self, forKey: .straightenDegrees) ?? 0
        isFlippedHorizontally = try c.decodeIfPresent(Bool.self, forKey: .isFlippedHorizontally) ?? false
        isFlippedVertically = try c.decodeIfPresent(Bool.self, forKey: .isFlippedVertically) ?? false
        reframeScale = try c.decodeIfPresent(CGFloat.self, forKey: .reframeScale) ?? 1
        reframeXOffset = try c.decodeIfPresent(CGFloat.self, forKey: .reframeXOffset) ?? 0
        reframeYOffset = try c.decodeIfPresent(CGFloat.self, forKey: .reframeYOffset) ?? 0
        colorAdjustment = try c.decodeIfPresent(EditorColorAdjustment.self, forKey: .colorAdjustment) ?? .neutral
        compositing = try c.decodeIfPresent(
            EditorOverlayCompositing.self,
            forKey: .compositing
        ) ?? .standard
        keyframes = try c.decodeIfPresent(EditorKeyframeTracks.self, forKey: .keyframes) ?? .empty
        motionTracks = try c.decodeIfPresent([EditorMotionTrack].self, forKey: .motionTracks) ?? []
        stabilization = try c.decodeIfPresent(
            EditorStabilizationSettings.self,
            forKey: .stabilization
        ) ?? .disabled
        attachedClipID = try c.decodeIfPresent(UUID.self, forKey: .attachedClipID)
        attachedTrackID = try c.decodeIfPresent(UUID.self, forKey: .attachedTrackID)
        attachRotation = try c.decodeIfPresent(Bool.self, forKey: .attachRotation) ?? false
        attachScale = try c.decodeIfPresent(Bool.self, forKey: .attachScale) ?? false
    }
}

/// Legacy single-track format — migrated to `audioClips` on load.
struct SavedAudioTrack: Codable, Identifiable, Hashable {
    let id: UUID
    var title: String
    var fileURLPath: String
    var duration: TimeInterval
    var volume: Float

    func toAudioClip() -> EditorAudioClip? {
        let url = URL(fileURLWithPath: fileURLPath)
        guard FileManager.default.fileExists(atPath: fileURLPath) else { return nil }
        return EditorAudioClip(
            id: id,
            title: title,
            fileURL: url,
            originalDuration: duration,
            trimStart: 0,
            trimEnd: duration,
            timelineStart: 0,
            volume: volume
        )
    }
}

// MARK: - Project document

struct EditorProject: Codable, Identifiable, Hashable {
    let id: UUID
    var title: String
    var createdAt: Date
    var modifiedAt: Date
    var clips: [SavedEditorClip]
    var textOverlays: [SavedTextOverlay]
    var audioClips: [SavedAudioClip]
    var overlayClips: [SavedOverlayClip]
    var openingTransitionKind: EditorTransitionKind
    var openingTransitionDuration: TimeInterval
    var closingTransitionKind: EditorTransitionKind
    var closingTransitionDuration: TimeInterval
    var timelinePosition: TimeInterval
    var selectedClipID: UUID?
    var selectedTextOverlayID: UUID?
    var selectedAudioClipID: UUID?
    var selectedOverlayClipID: UUID?
    var sequences: [EditorSequence]
    var markers: [EditorTimelineMarker]
    var selectedTimelineItems: [EditorTimelineItemReference]
    var selectedSequenceID: UUID?
    var activeSequenceID: UUID?
    var canvasSettings: EditorCanvasSettings
    var exportInPoint: TimeInterval?
    var exportOutPoint: TimeInterval?
    var audioTrackSettings: [Int: EditorAudioTrackSettings]
    var masterVolume: Float

    enum CodingKeys: String, CodingKey {
        case id, title, createdAt, modifiedAt, clips, textOverlays
        case audioClips, audioTrack, overlayClips, timelinePosition
        case selectedClipID, selectedTextOverlayID, selectedAudioClipID, selectedOverlayClipID
        case sequences, markers, selectedTimelineItems, selectedSequenceID, activeSequenceID
        case openingTransitionKind, openingTransitionDuration
        case closingTransitionKind, closingTransitionDuration
        case canvasSettings, exportInPoint, exportOutPoint
        case audioTrackSettings, masterVolume
    }

    init(
        id: UUID,
        title: String,
        createdAt: Date,
        modifiedAt: Date,
        clips: [SavedEditorClip],
        textOverlays: [SavedTextOverlay],
        audioClips: [SavedAudioClip],
        overlayClips: [SavedOverlayClip] = [],
        openingTransitionKind: EditorTransitionKind = .none,
        openingTransitionDuration: TimeInterval = 0,
        closingTransitionKind: EditorTransitionKind = .none,
        closingTransitionDuration: TimeInterval = 0,
        timelinePosition: TimeInterval,
        selectedClipID: UUID?,
        selectedTextOverlayID: UUID? = nil,
        selectedAudioClipID: UUID? = nil,
        selectedOverlayClipID: UUID? = nil,
        sequences: [EditorSequence] = [],
        markers: [EditorTimelineMarker] = [],
        selectedTimelineItems: [EditorTimelineItemReference] = [],
        selectedSequenceID: UUID? = nil,
        activeSequenceID: UUID? = nil,
        canvasSettings: EditorCanvasSettings = .default,
        exportInPoint: TimeInterval? = nil,
        exportOutPoint: TimeInterval? = nil,
        audioTrackSettings: [Int: EditorAudioTrackSettings] = [:],
        masterVolume: Float = 1.0
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.clips = clips
        self.textOverlays = textOverlays
        self.audioClips = audioClips
        self.overlayClips = overlayClips
        self.openingTransitionKind = openingTransitionKind
        self.openingTransitionDuration = openingTransitionKind == .none
            ? 0
            : max(0, openingTransitionDuration)
        self.closingTransitionKind = closingTransitionKind
        self.closingTransitionDuration = closingTransitionKind == .none
            ? 0
            : max(0, closingTransitionDuration)
        self.timelinePosition = timelinePosition
        self.selectedClipID = selectedClipID
        self.selectedTextOverlayID = selectedTextOverlayID
        self.selectedAudioClipID = selectedAudioClipID
        self.selectedOverlayClipID = selectedOverlayClipID
        self.sequences = sequences
        self.markers = markers
        self.selectedTimelineItems = selectedTimelineItems
        self.selectedSequenceID = selectedSequenceID
        self.activeSequenceID = activeSequenceID
        self.canvasSettings = canvasSettings
        self.exportInPoint = exportInPoint
        self.exportOutPoint = exportOutPoint
        self.audioTrackSettings = audioTrackSettings
        self.masterVolume = masterVolume
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        modifiedAt = try c.decode(Date.self, forKey: .modifiedAt)
        clips = try c.decode([SavedEditorClip].self, forKey: .clips)
        textOverlays = try c.decodeIfPresent([SavedTextOverlay].self, forKey: .textOverlays) ?? []
        let openingRawValue = try c.decodeIfPresent(
            String.self,
            forKey: .openingTransitionKind
        )
        openingTransitionKind = openingRawValue
            .flatMap(EditorTransitionKind.init(rawValue:))
            ?? .none
        openingTransitionDuration = openingTransitionKind == .none
            ? 0
            : max(
                0,
                try c.decodeIfPresent(
                    TimeInterval.self,
                    forKey: .openingTransitionDuration
                ) ?? 0
            )
        let closingRawValue = try c.decodeIfPresent(
            String.self,
            forKey: .closingTransitionKind
        )
        closingTransitionKind = closingRawValue
            .flatMap(EditorTransitionKind.init(rawValue:))
            ?? .none
        closingTransitionDuration = closingTransitionKind == .none
            ? 0
            : max(
                0,
                try c.decodeIfPresent(
                    TimeInterval.self,
                    forKey: .closingTransitionDuration
                ) ?? 0
            )
        timelinePosition = try c.decodeIfPresent(TimeInterval.self, forKey: .timelinePosition) ?? 0
        selectedClipID = try c.decodeIfPresent(UUID.self, forKey: .selectedClipID)
        selectedTextOverlayID = try c.decodeIfPresent(UUID.self, forKey: .selectedTextOverlayID)
        selectedAudioClipID = try c.decodeIfPresent(UUID.self, forKey: .selectedAudioClipID)
        selectedOverlayClipID = try c.decodeIfPresent(UUID.self, forKey: .selectedOverlayClipID)
        sequences = try c.decodeIfPresent([EditorSequence].self, forKey: .sequences) ?? []
        markers = try c.decodeIfPresent([EditorTimelineMarker].self, forKey: .markers) ?? []
        selectedTimelineItems = try c.decodeIfPresent(
            [EditorTimelineItemReference].self,
            forKey: .selectedTimelineItems
        ) ?? []
        selectedSequenceID = try c.decodeIfPresent(UUID.self, forKey: .selectedSequenceID)
        activeSequenceID = try c.decodeIfPresent(UUID.self, forKey: .activeSequenceID)
        overlayClips = try c.decodeIfPresent([SavedOverlayClip].self, forKey: .overlayClips) ?? []
        canvasSettings = try c.decodeIfPresent(EditorCanvasSettings.self, forKey: .canvasSettings) ?? .default
        exportInPoint = try c.decodeIfPresent(TimeInterval.self, forKey: .exportInPoint)
        exportOutPoint = try c.decodeIfPresent(TimeInterval.self, forKey: .exportOutPoint)
        audioTrackSettings = try c.decodeIfPresent(
            [Int: EditorAudioTrackSettings].self,
            forKey: .audioTrackSettings
        ) ?? [:]
        masterVolume = try c.decodeIfPresent(Float.self, forKey: .masterVolume) ?? 1.0

        if let saved = try c.decodeIfPresent([SavedAudioClip].self, forKey: .audioClips) {
            audioClips = saved
        } else if let legacy = try c.decodeIfPresent(SavedAudioTrack.self, forKey: .audioTrack),
                  let clip = legacy.toAudioClip() {
            audioClips = [SavedAudioClip(from: clip)]
        } else {
            audioClips = []
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(modifiedAt, forKey: .modifiedAt)
        try c.encode(clips, forKey: .clips)
        try c.encode(textOverlays, forKey: .textOverlays)
        try c.encode(audioClips, forKey: .audioClips)
        try c.encode(overlayClips, forKey: .overlayClips)
        try c.encode(openingTransitionKind, forKey: .openingTransitionKind)
        try c.encode(openingTransitionDuration, forKey: .openingTransitionDuration)
        try c.encode(closingTransitionKind, forKey: .closingTransitionKind)
        try c.encode(closingTransitionDuration, forKey: .closingTransitionDuration)
        try c.encode(timelinePosition, forKey: .timelinePosition)
        try c.encodeIfPresent(selectedClipID, forKey: .selectedClipID)
        try c.encodeIfPresent(selectedTextOverlayID, forKey: .selectedTextOverlayID)
        try c.encodeIfPresent(selectedAudioClipID, forKey: .selectedAudioClipID)
        try c.encodeIfPresent(selectedOverlayClipID, forKey: .selectedOverlayClipID)
        try c.encode(sequences, forKey: .sequences)
        try c.encode(markers, forKey: .markers)
        try c.encode(selectedTimelineItems, forKey: .selectedTimelineItems)
        try c.encodeIfPresent(selectedSequenceID, forKey: .selectedSequenceID)
        try c.encodeIfPresent(activeSequenceID, forKey: .activeSequenceID)
        try c.encode(canvasSettings, forKey: .canvasSettings)
        try c.encodeIfPresent(exportInPoint, forKey: .exportInPoint)
        try c.encodeIfPresent(exportOutPoint, forKey: .exportOutPoint)
        try c.encode(audioTrackSettings, forKey: .audioTrackSettings)
        try c.encode(masterVolume, forKey: .masterVolume)
    }

    var formattedDuration: String {
        let total = Int(clips.reduce(0.0) { partial, clip in
            let trimmed = max(0, clip.trimEnd - clip.trimStart)
            let timeline = clip.speedRamp?.timelineDuration(forSourceDuration: trimmed)
                ?? (clip.speed > 0 ? trimmed / TimeInterval(clip.speed) : trimmed)
            return partial + timeline
        }.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    static func new(from media: [MediaItem], title: String? = nil) -> EditorProject {
        let now = Date()
        let savedClips = media.map { SavedEditorClip(from: EditorClip(asset: $0.asset)) }
        return EditorProject(
            id: UUID(),
            title: title ?? Self.defaultTitle(for: now),
            createdAt: now,
            modifiedAt: now,
            clips: savedClips,
            textOverlays: [],
            audioClips: [],
            overlayClips: [],
            openingTransitionKind: .none,
            openingTransitionDuration: 0,
            closingTransitionKind: .none,
            closingTransitionDuration: 0,
            timelinePosition: 0,
            selectedClipID: savedClips.first?.id,
            selectedAudioClipID: nil,
            selectedOverlayClipID: nil
        )
    }

    private static func defaultTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return "Project \(formatter.string(from: date))"
    }
}

// MARK: - PHAsset resolution

enum EditorProjectResolver {
    static func clips(from saved: [SavedEditorClip]) -> [EditorClip] {
        guard !saved.isEmpty else { return [] }
        let ids = saved.map(\.assetLocalIdentifier)
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        var lookup: [String: PHAsset] = [:]
        fetch.enumerateObjects { asset, _, _ in
            lookup[asset.localIdentifier] = asset
        }

        return saved.compactMap { item in
            guard let asset = lookup[item.assetLocalIdentifier] else { return nil }
            return EditorClip(
                id: item.id,
                asset: asset,
                originalDuration: item.originalDuration,
                trimStart: item.trimStart,
                trimEnd: item.trimEnd,
                speed: item.speed,
                speedRamp: item.speedRamp,
                playback: item.playback,
                volume: item.volume,
                audioTrimStart: item.audioTrimStart,
                audioTrimEnd: item.audioTrimEnd,
                isAudioLinked: item.isAudioLinked,
                cropAspect: item.cropAspect,
                reframeMode: item.reframeMode,
                rotationQuarterTurns: item.rotationQuarterTurns,
                straightenDegrees: item.straightenDegrees,
                isFlippedHorizontally: item.isFlippedHorizontally,
                isFlippedVertically: item.isFlippedVertically,
                reframeScale: item.reframeScale,
                reframeXOffset: item.reframeXOffset,
                reframeYOffset: item.reframeYOffset,
                colorAdjustment: item.colorAdjustment,
                compositing: item.compositing,
                keyframes: item.keyframes,
                motionTracks: item.motionTracks,
                stabilization: item.stabilization,
                transitionKind: item.transitionKind,
                transitionDuration: item.transitionDuration
            )
        }
    }

    static func overlayClips(from saved: [SavedOverlayClip]) -> [EditorOverlayClip] {
        guard !saved.isEmpty else { return [] }
        let ids = saved.map(\.assetLocalIdentifier)
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        var lookup: [String: PHAsset] = [:]
        fetch.enumerateObjects { asset, _, _ in
            lookup[asset.localIdentifier] = asset
        }

        return saved.compactMap { item in
            guard let asset = lookup[item.assetLocalIdentifier],
                  asset.mediaType == .video || asset.mediaType == .image else {
                return nil
            }
            return EditorOverlayClip(
                id: item.id,
                asset: asset,
                originalDuration: item.originalDuration,
                trimStart: item.trimStart,
                trimEnd: item.trimEnd,
                timelineStart: item.timelineStart,
                laneIndex: item.laneIndex,
                zIndex: item.zIndex,
                speed: item.speed,
                playback: item.playback,
                scale: item.scale,
                xOffset: item.xOffset,
                yOffset: item.yOffset,
                opacity: item.opacity,
                volume: item.volume,
                cropAspect: item.cropAspect,
                reframeMode: item.reframeMode,
                rotationQuarterTurns: item.rotationQuarterTurns,
                straightenDegrees: item.straightenDegrees,
                isFlippedHorizontally: item.isFlippedHorizontally,
                isFlippedVertically: item.isFlippedVertically,
                reframeScale: item.reframeScale,
                reframeXOffset: item.reframeXOffset,
                reframeYOffset: item.reframeYOffset,
                colorAdjustment: item.colorAdjustment,
                compositing: item.compositing,
                keyframes: item.keyframes,
                motionTracks: item.motionTracks,
                stabilization: item.stabilization,
                attachedClipID: item.attachedClipID,
                attachedTrackID: item.attachedTrackID,
                attachRotation: item.attachRotation,
                attachScale: item.attachScale
            )
        }
    }
}
