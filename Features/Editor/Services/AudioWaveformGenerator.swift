//
//  AudioWaveformGenerator.swift
//  Mixtape
//
//  Real PCM peak waveforms for timeline audio clips. Decodes each file once, caches the
//  full-file peak envelope, and lets the timeline slice that envelope to the clip's trim
//  window so the bars match what you actually hear.
//

import AVFoundation
import CoreMedia
import Foundation

/// Peak envelope for one audio file, sampled uniformly across `duration`.
/// Values are normalized 0...1 against the file's own peak, so a quiet section stays quiet
/// relative to the rest of the track.
struct AudioWaveform: Sendable, Equatable {
    var peaks: [Float]
    var duration: TimeInterval

    /// Downsamples the trim window `start..<end` into `count` bar heights (0...1).
    func buckets(start: TimeInterval, end: TimeInterval, count: Int) -> [CGFloat] {
        let barCount = max(count, 1)
        guard !peaks.isEmpty, duration > 0, end > start else {
            return [CGFloat](repeating: 0, count: barCount)
        }

        let last = Double(peaks.count)
        let startFrac = min(max(start / duration, 0), 1)
        let endFrac = min(max(end / duration, startFrac + 0.000_1), 1)
        let lo = startFrac * last
        let hi = max(lo + 0.000_1, endFrac * last)
        let span = hi - lo

        return (0..<barCount).map { index in
            let bucketStart = lo + span * Double(index) / Double(barCount)
            let bucketEnd = lo + span * Double(index + 1) / Double(barCount)
            let first = min(peaks.count - 1, max(0, Int(bucketStart)))
            let lastIndex = min(peaks.count - 1, max(first, Int(ceil(bucketEnd)) - 1))
            var peak: Float = 0
            for sampleIndex in first...lastIndex {
                peak = max(peak, peaks[sampleIndex])
            }
            return CGFloat(peak)
        }
    }
}

/// Reads actual PCM peak data from an audio file. Results are cached in memory and on disk
/// (keyed by file path + size) so trimming, re-selecting, or relaunching does not re-decode.
actor AudioWaveformGenerator {
    static let shared = AudioWaveformGenerator()

    /// Peak columns stored per second of source audio — dense enough to resample to the
    /// timeline's ~18 px/s zoom without looking stepped.
    private static let peaksPerSecond: Double = 80
    private static let maxPeaks = 24_000

    private var memoryCache: [String: AudioWaveform] = [:]
    private let diskCacheDirectory: URL

    private init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        diskCacheDirectory = base.appendingPathComponent("MixtapeWaveforms", isDirectory: true)
        try? FileManager.default.createDirectory(at: diskCacheDirectory, withIntermediateDirectories: true)
    }

    /// Full-file peak envelope for `url`, or `nil` if the file cannot be decoded.
    /// Failed decodes are not cached, so a file that was still being written can succeed later.
    func waveform(for url: URL) async -> AudioWaveform? {
        let key = cacheKey(url: url)

        if let cached = memoryCache[key] { return cached }
        if let onDisk = loadFromDisk(key: key) {
            memoryCache[key] = onDisk
            return onDisk
        }

        let computed = await Self.decode(url: url)
        if let computed, !computed.peaks.isEmpty {
            memoryCache[key] = computed
            saveToDisk(key: key, waveform: computed)
        }
        return computed
    }

    private static func decode(url: URL) async -> AudioWaveform? {
        if let waveform = try? decodeWithAudioFile(url: url) {
            return waveform
        }
        return try? await decodeWithAssetReader(url: url)
    }

    /// Fast path for wav/caf/aiff and most mp3/m4a files `AVAudioFile` can open as float PCM.
    private static func decodeWithAudioFile(url: URL) throws -> AudioWaveform {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let totalFrames = Int(file.length)
        let sampleRate = format.sampleRate
        guard totalFrames > 0, format.channelCount > 0, sampleRate > 0 else {
            throw WaveformError.emptyFile
        }

        let duration = Double(totalFrames) / sampleRate
        let bucketCount = peakCount(forDuration: duration)
        let framesPerBucket = max(1, Int((Double(totalFrames) / Double(bucketCount)).rounded(.up)))

        let chunkSize: AVAudioFrameCount = 32_768
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkSize) else {
            throw WaveformError.bufferAllocationFailed
        }

        var peaks = [Float](repeating: 0, count: bucketCount)
        var frameCursor = 0
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
                let bucket = min(bucketCount - 1, frameCursor / framesPerBucket)
                peaks[bucket] = max(peaks[bucket], sampleMax)
                frameCursor += 1
            }
        }

        guard frameCursor > 0 else { throw WaveformError.emptyFile }
        return AudioWaveform(peaks: normalized(peaks), duration: duration)
    }

    /// Fallback for compressed formats `AVAudioFile` refuses. Converts to interleaved float32 PCM.
    private static func decodeWithAssetReader(url: URL) async throws -> AudioWaveform {
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard let track = tracks.first else { throw WaveformError.emptyFile }

        let durationSeconds = try await asset.load(.duration).seconds
        guard durationSeconds.isFinite, durationSeconds > 0 else { throw WaveformError.emptyFile }

        let reader = try AVAssetReader(asset: asset)
        let outputSettings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw WaveformError.unsupportedFormat }
        reader.add(output)
        guard reader.startReading() else { throw WaveformError.unsupportedFormat }

        let bucketCount = peakCount(forDuration: durationSeconds)
        var peaks = [Float](repeating: 0, count: bucketCount)
        var sampleRate: Double = 44_100
        var channels = 1
        var frameCursor = 0
        var didReadFormat = false

        while reader.status == .reading, let sampleBuffer = output.copyNextSampleBuffer() {
            if !didReadFormat,
               let format = CMSampleBufferGetFormatDescription(sampleBuffer),
               let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee {
                if asbd.mSampleRate > 0 { sampleRate = asbd.mSampleRate }
                channels = max(1, Int(asbd.mChannelsPerFrame))
                didReadFormat = true
            }

            let framesPerBucket = max(1, Int((sampleRate / Self.peaksPerSecond).rounded()))
            visitFloatSamples(sampleBuffer) { floats, floatCount in
                let frameCount = floatCount / channels
                for frame in 0..<frameCount {
                    var sampleMax: Float = 0
                    let base = frame * channels
                    for channel in 0..<channels {
                        sampleMax = max(sampleMax, abs(floats[base + channel]))
                    }
                    let bucket = min(bucketCount - 1, frameCursor / framesPerBucket)
                    peaks[bucket] = max(peaks[bucket], sampleMax)
                    frameCursor += 1
                }
            }
        }

        guard frameCursor > 0 else { throw WaveformError.emptyFile }
        let measuredDuration = Double(frameCursor) / sampleRate
        return AudioWaveform(
            peaks: normalized(peaks),
            duration: measuredDuration > 0 ? measuredDuration : durationSeconds
        )
    }

    private static func visitFloatSamples(
        _ sampleBuffer: CMSampleBuffer,
        body: (UnsafePointer<Float>, Int) -> Void
    ) {
        guard let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
        var length = 0
        var pointer: UnsafeMutablePointer<Int8>?
        let status = CMBlockBufferGetDataPointer(
            dataBuffer,
            atOffset: 0,
            lengthAtOffsetOut: nil,
            totalLengthOut: &length,
            dataPointerOut: &pointer
        )
        guard status == kCMBlockBufferNoErr, let pointer, length >= MemoryLayout<Float>.size else { return }
        let floatCount = length / MemoryLayout<Float>.size
        body(UnsafeRawPointer(pointer).assumingMemoryBound(to: Float.self), floatCount)
    }

    private static func peakCount(forDuration duration: TimeInterval) -> Int {
        min(maxPeaks, max(1, Int((duration * peaksPerSecond).rounded(.up))))
    }

    private static func normalized(_ peaks: [Float]) -> [Float] {
        let maxValue = peaks.max() ?? 0
        guard maxValue > 0.000_1 else { return peaks }
        return peaks.map { $0 / maxValue }
    }

    private func cacheKey(url: URL) -> String {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?
            .intValue ?? 0
        return "\(Self.stableHash(url.path))_\(size)"
    }

    private func loadFromDisk(key: String) -> AudioWaveform? {
        let url = diskCacheDirectory.appendingPathComponent(key).appendingPathExtension("json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(DiskRecord.self, from: data).waveform
    }

    private func saveToDisk(key: String, waveform: AudioWaveform) {
        let url = diskCacheDirectory.appendingPathComponent(key).appendingPathExtension("json")
        guard let data = try? JSONEncoder().encode(DiskRecord(waveform: waveform)) else { return }
        try? data.write(to: url, options: .atomic)
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

    private enum WaveformError: Error {
        case emptyFile
        case bufferAllocationFailed
        case unsupportedFormat
    }

    private struct DiskRecord: Codable {
        var peaks: [Float]
        var duration: TimeInterval

        init(waveform: AudioWaveform) {
            peaks = waveform.peaks
            duration = waveform.duration
        }

        var waveform: AudioWaveform {
            AudioWaveform(peaks: peaks, duration: duration)
        }
    }
}
