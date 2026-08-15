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
    var volume: Float
    var fadeInDuration: TimeInterval
    var fadeOutDuration: TimeInterval
    var keyframes: EditorKeyframeTracks
    let waveform: [CGFloat]

    init(
        id: UUID = UUID(),
        title: String,
        fileURL: URL,
        originalDuration: TimeInterval,
        trimStart: TimeInterval = 0,
        trimEnd: TimeInterval? = nil,
        timelineStart: TimeInterval = 0,
        volume: Float = 1.0,
        fadeInDuration: TimeInterval = 0,
        fadeOutDuration: TimeInterval = 0,
        keyframes: EditorKeyframeTracks = .empty
    ) {
        self.id = id
        self.title = title
        self.fileURL = fileURL
        self.originalDuration = originalDuration
        self.trimStart = trimStart
        self.trimEnd = trimEnd ?? originalDuration
        self.timelineStart = timelineStart
        self.volume = volume
        self.fadeInDuration = min(max(0, fadeInDuration), self.trimEnd - self.trimStart)
        self.fadeOutDuration = min(max(0, fadeOutDuration), self.trimEnd - self.trimStart)
        self.keyframes = keyframes
        self.waveform = Self.generateWaveform(seed: title.hashValue, count: 96)
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
            volume: volume,
            fadeInDuration: min(fadeInDuration, sourceTime - trimStart),
            fadeOutDuration: 0,
            keyframes: splitKeyframes.left
        )
        let right = EditorAudioClip(
            title: title,
            fileURL: fileURL,
            originalDuration: originalDuration,
            trimStart: sourceTime,
            trimEnd: trimEnd,
            timelineStart: timelineStart + left.duration,
            volume: volume,
            fadeInDuration: 0,
            fadeOutDuration: min(fadeOutDuration, trimEnd - sourceTime),
            keyframes: splitKeyframes.right
        )
        return (left, right)
    }

    func sourceTime(forTimelineLocal local: TimeInterval) -> TimeInterval {
        min(max(trimStart + local, trimStart), trimEnd)
    }

    private static func generateWaveform(seed: Int, count: Int) -> [CGFloat] {
        var rng = SeededGenerator(seed: UInt64(bitPattern: Int64(seed)))
        return (0..<count).map { i in
            let envelope = sin(.pi * Double(i) / Double(max(count - 1, 1)))
            let noise = Double.random(in: 0.35...1.0, using: &rng)
            return CGFloat(max(0.12, envelope * noise))
        }
    }
}

private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { self.state = seed == 0 ? 0xDEAD_BEEF : seed }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
