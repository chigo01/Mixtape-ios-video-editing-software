//
//  EditorAudioClip.swift
//  Mixtape
//

import Foundation

struct EditorAudioClip: Identifiable, Hashable {
    let id: UUID
    var title: String
    var fileURL: URL
    let originalDuration: TimeInterval
    var trimStart: TimeInterval
    var trimEnd: TimeInterval
    var timelineStart: TimeInterval
    /// Which audio track this clip renders on. Clips on different lanes are free to overlap
    /// in time — each becomes an independent composition audio track (see `EditorCompositionBuilder`),
    /// so overlapping lanes mix together rather than colliding. Mirrors `EditorOverlayClip.laneIndex`.
    var laneIndex: Int
    var volume: Float
    var fadeInDuration: TimeInterval
    var fadeOutDuration: TimeInterval
    var keyframes: EditorKeyframeTracks
    /// Required-attribution text for clips inserted from a Creative Commons source (e.g.
    /// Freesound CC-BY results) — `nil` for imported files, bundled library sounds (CC0-
    /// equivalent, originally synthesized), and anything else with no attribution obligation.
    /// Surfaced in the audio action bar so it isn't lost once the clip leaves the library sheet.
    var attribution: String?

    init(
        id: UUID = UUID(),
        title: String,
        fileURL: URL,
        originalDuration: TimeInterval,
        trimStart: TimeInterval = 0,
        trimEnd: TimeInterval? = nil,
        timelineStart: TimeInterval = 0,
        laneIndex: Int = 0,
        volume: Float = 1.0,
        fadeInDuration: TimeInterval = 0,
        fadeOutDuration: TimeInterval = 0,
        keyframes: EditorKeyframeTracks = .empty,
        attribution: String? = nil
    ) {
        self.id = id
        self.title = title
        self.fileURL = fileURL
        self.originalDuration = originalDuration
        self.trimStart = trimStart
        self.trimEnd = trimEnd ?? originalDuration
        self.timelineStart = timelineStart
        self.laneIndex = laneIndex
        self.volume = volume
        self.fadeInDuration = min(max(0, fadeInDuration), self.trimEnd - self.trimStart)
        self.fadeOutDuration = min(max(0, fadeOutDuration), self.trimEnd - self.trimStart)
        self.keyframes = keyframes
        self.attribution = attribution
    }

    static let minimumSpan: TimeInterval = 0.25

    var duration: TimeInterval {
        max(0, trimEnd - trimStart)
    }

    var timelineEnd: TimeInterval {
        timelineStart + duration
    }

    func split(atSourceTime sourceTime: TimeInterval) -> (left: EditorAudioClip, right: EditorAudioClip)? {
        guard sourceTime >= trimStart + Self.minimumSpan,
              sourceTime <= trimEnd - Self.minimumSpan else { return nil }

        let splitKeyframes = keyframes.split(at: sourceTime - trimStart)

        let left = EditorAudioClip(
            id: id,
            title: title,
            fileURL: fileURL,
            originalDuration: originalDuration,
            trimStart: trimStart,
            trimEnd: sourceTime,
            timelineStart: timelineStart,
            laneIndex: laneIndex,
            volume: volume,
            fadeInDuration: min(fadeInDuration, sourceTime - trimStart),
            fadeOutDuration: 0,
            keyframes: splitKeyframes.left,
            attribution: attribution
        )
        let right = EditorAudioClip(
            title: title,
            fileURL: fileURL,
            originalDuration: originalDuration,
            trimStart: sourceTime,
            trimEnd: trimEnd,
            timelineStart: timelineStart + left.duration,
            laneIndex: laneIndex,
            volume: volume,
            fadeInDuration: 0,
            fadeOutDuration: min(fadeOutDuration, trimEnd - sourceTime),
            keyframes: splitKeyframes.right,
            attribution: attribution
        )
        return (left, right)
    }

    func sourceTime(forTimelineLocal local: TimeInterval) -> TimeInterval {
        min(max(trimStart + local, trimStart), trimEnd)
    }
}
