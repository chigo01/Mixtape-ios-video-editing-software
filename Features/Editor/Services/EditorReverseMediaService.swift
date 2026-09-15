//
//  EditorReverseMediaService.swift
//  Mixtape
//

import AVFoundation
import Photos
import UIKit

// MARK: - Reverse render cache

enum EditorReverseMediaError: LocalizedError {
    case unavailableSource
    case missingVideo
    case cannotCreateComposition
    case cannotCreateExporter
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .unavailableSource: return "The original video could not be downloaded from Photos."
        case .missingVideo: return "The selected asset does not contain a readable video track."
        case .cannotCreateComposition: return "The reverse timeline could not be prepared."
        case .cannotCreateExporter: return "This video cannot be encoded on the current device."
        case let .exportFailed(message): return message
        }
    }
}

/// Creates deterministic, disposable reverse renders. The original PHAsset and
/// source range remain in the project, so a purged cache is regenerated after
/// reopen/relink instead of turning into missing media.
actor EditorReverseMediaService {
    static let shared = EditorReverseMediaService()

    private var activeExports: [String: AVAssetExportSession] = [:]

    static func cachedURL(
        for asset: PHAsset,
        sourceStart: TimeInterval,
        sourceEnd: TimeInterval,
        audioPolicy: EditorReverseAudioPolicy,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> URL {
        try await shared.renderedURL(
            for: asset,
            sourceStart: sourceStart,
            sourceEnd: sourceEnd,
            audioPolicy: audioPolicy,
            progress: progress
        )
    }

    static func cancel(for assetIdentifier: String) async {
        await shared.cancel(assetIdentifier: assetIdentifier)
    }

    private func renderedURL(
        for asset: PHAsset,
        sourceStart: TimeInterval,
        sourceEnd: TimeInterval,
        audioPolicy: EditorReverseAudioPolicy,
        progress: (@Sendable (Double) -> Void)?
    ) async throws -> URL {
        let lower = max(0, min(sourceStart, sourceEnd))
        let upper = min(asset.duration, max(sourceStart, sourceEnd))
        guard upper - lower >= 0.05 else { throw EditorReverseMediaError.missingVideo }

        let key = cacheKey(
            identifier: asset.localIdentifier,
            start: lower,
            end: upper,
            audioPolicy: audioPolicy
        )
        let outputURL = try cacheDirectory().appendingPathComponent("\(key).mov")
        if isUsableFile(outputURL) {
            progress?(1)
            return outputURL
        }

        let avAsset = try await requestAsset(for: asset)
        guard let sourceVideo = try await avAsset.loadTracks(withMediaType: .video).first else {
            throw EditorReverseMediaError.missingVideo
        }
        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
              ) else { throw EditorReverseMediaError.cannotCreateComposition }

        videoTrack.preferredTransform = try await sourceVideo.load(.preferredTransform)
        let nominalRate = Double(try await sourceVideo.load(.nominalFrameRate))
        let framesPerSecond = min(max(nominalRate > 0 ? nominalRate : 30, 15), 60)
        let sliceDuration = 1 / framesPerSecond
        let span = upper - lower
        let sliceCount = max(1, Int(ceil(span / sliceDuration)))
        var reversedSlices: [(range: CMTimeRange, destination: CMTime)] = []
        reversedSlices.reserveCapacity(sliceCount)
        var destinationSeconds: TimeInterval = 0

        for outputIndex in 0..<sliceCount {
            try Task.checkCancellation()
            let reverseIndex = sliceCount - 1 - outputIndex
            let sliceStart = lower + Double(reverseIndex) * sliceDuration
            let actualDuration = min(sliceDuration, upper - sliceStart)
            guard actualDuration > 0 else { continue }
            let range = CMTimeRange(
                start: CMTime(seconds: sliceStart, preferredTimescale: 600),
                duration: CMTime(seconds: actualDuration, preferredTimescale: 600)
            )
            let destination = CMTime(seconds: destinationSeconds, preferredTimescale: 600)
            reversedSlices.append((range, destination))
            try videoTrack.insertTimeRange(range, of: sourceVideo, at: destination)
            destinationSeconds += actualDuration
            if outputIndex.isMultiple(of: 12) {
                progress?(0.2 * Double(outputIndex + 1) / Double(sliceCount))
            }
        }

        if audioPolicy == .reverse,
           let sourceAudio = try await avAsset.loadTracks(withMediaType: .audio).first,
           let audioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
           ) {
            // Frame-sized slices keep reverse audio aligned with the reversed
            // picture while avoiding an unbounded decoded-audio memory buffer.
            for slice in reversedSlices {
                try Task.checkCancellation()
                try? audioTrack.insertTimeRange(slice.range, of: sourceAudio, at: slice.destination)
            }
        }

        try? FileManager.default.removeItem(at: outputURL)
        guard let exporter = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else { throw EditorReverseMediaError.cannotCreateExporter }
        exporter.outputURL = outputURL
        exporter.outputFileType = exporter.supportedFileTypes.contains(.mov) ? .mov : .mp4
        exporter.shouldOptimizeForNetworkUse = false
        activeExports[asset.localIdentifier] = exporter

        let progressTask = Task {
            while !Task.isCancelled {
                progress?(0.2 + 0.8 * Double(exporter.progress))
                try? await Task.sleep(for: .milliseconds(120))
            }
        }
        defer {
            progressTask.cancel()
            activeExports[asset.localIdentifier] = nil
        }

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, Error>) in
                exporter.exportAsynchronously {
                    switch exporter.status {
                    case .completed:
                        continuation.resume()
                    case .cancelled:
                        continuation.resume(throwing: CancellationError())
                    default:
                        continuation.resume(throwing: EditorReverseMediaError.exportFailed(
                            exporter.error?.localizedDescription ?? "Reverse generation failed."
                        ))
                    }
                }
            }
        } onCancel: {
            exporter.cancelExport()
        }

        guard isUsableFile(outputURL) else {
            throw EditorReverseMediaError.exportFailed("Reverse generation produced an empty file.")
        }
        progress?(1)
        return outputURL
    }

    private func cancel(assetIdentifier: String) {
        activeExports[assetIdentifier]?.cancelExport()
    }

    private func requestAsset(for asset: PHAsset) async throws -> AVAsset {
        let options = PHVideoRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        return try await withCheckedThrowingContinuation { continuation in
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) {
                avAsset, _, info in
                if let avAsset {
                    continuation.resume(returning: avAsset)
                } else {
                    let message = (info?[PHImageErrorKey] as? Error)?.localizedDescription
                    continuation.resume(throwing: EditorReverseMediaError.exportFailed(
                        message ?? EditorReverseMediaError.unavailableSource.localizedDescription
                    ))
                }
            }
        }
    }

    private func cacheDirectory() throws -> URL {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MixtapeReverseMedia", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func cacheKey(
        identifier: String,
        start: TimeInterval,
        end: TimeInterval,
        audioPolicy: EditorReverseAudioPolicy
    ) -> String {
        let raw = "v1|\(identifier)|\(Int((start * 1_000).rounded()))|\(Int((end * 1_000).rounded()))|\(audioPolicy.rawValue)"
        return Data(raw.utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
    }

    private func isUsableFile(_ url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path),
              let bytes = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return false }
        return bytes > 0
    }
}

