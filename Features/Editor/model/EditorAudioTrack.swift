//
//  EditorAudioTrack.swift
//  Mixtape
//
//  Created by Favour Baruch on 14/05/2026.
//

import Foundation

struct EditorAudioTrack: Identifiable, Hashable {
    let id: UUID
    var title: String
    var duration: TimeInterval
    var volume: Float
    /// Stable per-bar heights in [0...1]. Sampling a real waveform is out of scope here;
    /// these are seeded by the title so they look consistent run-to-run.
    let waveform: [CGFloat]

    init(title: String, duration: TimeInterval, volume: Float = 1.0) {
        self.id = UUID()
        self.title = title
        self.duration = duration
        self.volume = volume
        self.waveform = Self.generateWaveform(seed: title.hashValue, count: 96)
    }

    private static func generateWaveform(seed: Int, count: Int) -> [CGFloat] {
        var rng = SeededGenerator(seed: UInt64(bitPattern: Int64(seed)))
        return (0..<count).map { i in
            let envelope = sin(.pi * Double(i) / Double(count - 1))
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
