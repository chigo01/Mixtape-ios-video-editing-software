//
//  AudioWaveformGenerator.swift
//  Mixtape
//
//  Priority 13 (Features/Editor/README.md): real, cached waveforms for imported/library audio,
//  replacing the placeholder procedural noise EditorAudioClip used to carry as decoration.
//

import AVFoundation
import Foundation

/// Reads actual PCM peak data from an audio file and downsamples it to a fixed number of
/// buckets for timeline display. Results are cached in memory and on disk (keyed by file path,
/// since the audio files this app deals with — imports under `MixtapeAudio/`, library downloads
/// under `MixtapeAudioLibraryCache/`, bundled resources — are never overwritten in place once
/// created) so re-selecting a clip or relaunching the app doesn't re-decode the file.
actor AudioWaveformGenerator {
    static let shared = AudioWaveformGenerator()

    private var memoryCache: [String: [CGFloat]] = [:]
    private let diskCacheDirectory: URL

    private init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        diskCacheDirectory = base.appendingPathComponent("MixtapeWaveforms", isDirectory: true)
        try? FileManager.default.createDirectory(at: diskCacheDirectory, withIntermediateDirectories: true)
    }

    /// Returns `bucketCount` peak-amplitude samples, normalized 0...1, for `url`. Never throws —
    /// a file that can't be decoded (missing, unsupported format, mid-write) falls back to a
    /// flat placeholder so the timeline lane always has something reasonable to draw.
    func waveform(for url: URL, bucketCount: Int = 120) async -> [CGFloat] {
        let key = cacheKey(url: url, bucketCount: bucketCount)

        if let cached = memoryCache[key] { return cached }
        if let onDisk = loadFromDisk(key: key) {
            memoryCache[key] = onDisk
            return onDisk
        }

        let computed = (try? computeWaveform(url: url, bucketCount: bucketCount))
            ?? Self.placeholder(bucketCount: bucketCount)
        memoryCache[key] = computed
        saveToDisk(key: key, samples: computed)
        return computed
    }

    private func computeWaveform(url: URL, bucketCount: Int) throws -> [CGFloat] {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let totalFrames = Int(file.length)
        guard totalFrames > 0, format.channelCount > 0 else {
            return Self.placeholder(bucketCount: bucketCount)
        }

        let framesPerBucket = max(1, totalFrames / bucketCount)
        let chunkSize: AVAudioFrameCount = 32_768
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkSize) else {
            return Self.placeholder(bucketCount: bucketCount)
        }

        var buckets = [CGFloat](repeating: 0, count: bucketCount)
        var bucketIndex = 0
        var framesInBucket = 0
        var bucketPeak: Float = 0
        let channelCount = Int(format.channelCount)

        while true {
            try file.read(into: buffer, frameCount: chunkSize)
            let framesRead = Int(buffer.frameLength)
            guard framesRead > 0, let channelData = buffer.floatChannelData else { break }

            for frame in 0..<framesRead {
                var sampleMax: Float = 0
                for channel in 0..<channelCount {
                    sampleMax = max(sampleMax, abs(channelData[channel][frame]))
                }
                bucketPeak = max(bucketPeak, sampleMax)
                framesInBucket += 1
                if framesInBucket >= framesPerBucket, bucketIndex < bucketCount - 1 {
                    buckets[bucketIndex] = CGFloat(bucketPeak)
                    bucketIndex += 1
                    bucketPeak = 0
                    framesInBucket = 0
                }
            }
        }
        buckets[min(bucketIndex, bucketCount - 1)] = max(buckets[min(bucketIndex, bucketCount - 1)], CGFloat(bucketPeak))

        let maxValue = buckets.max() ?? 0
        guard maxValue > 0.0001 else { return [CGFloat](repeating: 0.08, count: bucketCount) }
        return buckets.map { max(0.05, $0 / maxValue) }
    }

    private static func placeholder(bucketCount: Int) -> [CGFloat] {
        (0..<max(bucketCount, 1)).map { i in
            CGFloat(0.2 + 0.1 * sin(Double(i) * 0.6))
        }
    }

    private func cacheKey(url: URL, bucketCount: Int) -> String {
        "\(Self.stableHash(url.path))_\(bucketCount)"
    }

    private func loadFromDisk(key: String) -> [CGFloat]? {
        let url = diskCacheDirectory.appendingPathComponent(key).appendingPathExtension("json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([CGFloat].self, from: data)
    }

    private func saveToDisk(key: String, samples: [CGFloat]) {
        let url = diskCacheDirectory.appendingPathComponent(key).appendingPathExtension("json")
        guard let data = try? JSONEncoder().encode(samples) else { return }
        try? data.write(to: url)
    }

    /// FNV-1a — deterministic across launches (unlike `String.hashValue`, which is randomized
    /// per process and unsuitable as a persistent disk-cache key).
    private static func stableHash(_ string: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}
