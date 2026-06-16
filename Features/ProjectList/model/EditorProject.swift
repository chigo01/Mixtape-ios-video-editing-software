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

    init(from clip: EditorClip) {
        id = clip.id
        assetLocalIdentifier = clip.asset.localIdentifier
        originalDuration = clip.originalDuration
        trimStart = clip.trimStart
        trimEnd = clip.trimEnd
        speed = clip.speed
        volume = clip.volume
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

struct SavedAudioTrack: Codable, Identifiable, Hashable {
    let id: UUID
    var title: String
    var duration: TimeInterval
    var volume: Float

    init(from track: EditorAudioTrack) {
        id = track.id
        title = track.title
        duration = track.duration
        volume = track.volume
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
    var audioTrack: SavedAudioTrack?
    var timelinePosition: TimeInterval
    var selectedClipID: UUID?

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
            audioTrack: nil,
            timelinePosition: 0,
            selectedClipID: savedClips.first?.id
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
                volume: item.volume
            )
        }
    }
}
