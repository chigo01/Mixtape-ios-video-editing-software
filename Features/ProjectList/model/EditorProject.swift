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
    var volume: Float
    var transitionKind: EditorTransitionKind
    var transitionDuration: TimeInterval

    init(from clip: EditorClip) {
        id = clip.id
        assetLocalIdentifier = clip.asset.localIdentifier
        originalDuration = clip.originalDuration
        trimStart = clip.trimStart
        trimEnd = clip.trimEnd
        speed = clip.speed
        volume = clip.volume
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
        volume = try c.decode(Float.self, forKey: .volume)
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
            yOffset: yOffset
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
    var volume: Float
    var fadeInDuration: TimeInterval
    var fadeOutDuration: TimeInterval

    init(from clip: EditorAudioClip) {
        id = clip.id
        title = clip.title
        fileURLPath = clip.fileURL.path
        originalDuration = clip.originalDuration
        trimStart = clip.trimStart
        trimEnd = clip.trimEnd
        timelineStart = clip.timelineStart
        volume = clip.volume
        fadeInDuration = clip.fadeInDuration
        fadeOutDuration = clip.fadeOutDuration
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
        volume = try c.decode(Float.self, forKey: .volume)
        fadeInDuration = try c.decodeIfPresent(TimeInterval.self, forKey: .fadeInDuration) ?? 0
        fadeOutDuration = try c.decodeIfPresent(TimeInterval.self, forKey: .fadeOutDuration) ?? 0
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
            volume: volume,
            fadeInDuration: fadeInDuration,
            fadeOutDuration: fadeOutDuration
        )
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
    var openingTransitionKind: EditorTransitionKind
    var openingTransitionDuration: TimeInterval
    var closingTransitionKind: EditorTransitionKind
    var closingTransitionDuration: TimeInterval
    var timelinePosition: TimeInterval
    var selectedClipID: UUID?
    var selectedAudioClipID: UUID?

    enum CodingKeys: String, CodingKey {
        case id, title, createdAt, modifiedAt, clips, textOverlays
        case audioClips, audioTrack, timelinePosition, selectedClipID, selectedAudioClipID
        case openingTransitionKind, openingTransitionDuration
        case closingTransitionKind, closingTransitionDuration
    }

    init(
        id: UUID,
        title: String,
        createdAt: Date,
        modifiedAt: Date,
        clips: [SavedEditorClip],
        textOverlays: [SavedTextOverlay],
        audioClips: [SavedAudioClip],
        openingTransitionKind: EditorTransitionKind = .none,
        openingTransitionDuration: TimeInterval = 0,
        closingTransitionKind: EditorTransitionKind = .none,
        closingTransitionDuration: TimeInterval = 0,
        timelinePosition: TimeInterval,
        selectedClipID: UUID?,
        selectedAudioClipID: UUID? = nil
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.clips = clips
        self.textOverlays = textOverlays
        self.audioClips = audioClips
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
        self.selectedAudioClipID = selectedAudioClipID
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
        selectedAudioClipID = try c.decodeIfPresent(UUID.self, forKey: .selectedAudioClipID)

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
        try c.encode(openingTransitionKind, forKey: .openingTransitionKind)
        try c.encode(openingTransitionDuration, forKey: .openingTransitionDuration)
        try c.encode(closingTransitionKind, forKey: .closingTransitionKind)
        try c.encode(closingTransitionDuration, forKey: .closingTransitionDuration)
        try c.encode(timelinePosition, forKey: .timelinePosition)
        try c.encodeIfPresent(selectedClipID, forKey: .selectedClipID)
        try c.encodeIfPresent(selectedAudioClipID, forKey: .selectedAudioClipID)
    }

    var formattedDuration: String {
        let total = Int(clips.reduce(0.0) { partial, clip in
            let trimmed = max(0, clip.trimEnd - clip.trimStart)
            let timeline = clip.speed > 0 ? trimmed / TimeInterval(clip.speed) : trimmed
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
            openingTransitionKind: .none,
            openingTransitionDuration: 0,
            closingTransitionKind: .none,
            closingTransitionDuration: 0,
            timelinePosition: 0,
            selectedClipID: savedClips.first?.id,
            selectedAudioClipID: nil
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
                volume: item.volume,
                transitionKind: item.transitionKind,
                transitionDuration: item.transitionDuration
            )
        }
    }
}
