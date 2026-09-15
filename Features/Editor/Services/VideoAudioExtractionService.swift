import AVFoundation
import Foundation
import Photos

struct ExtractedVideoAudio: Sendable {
    let fileURL: URL
    let duration: TimeInterval
}

enum VideoAudioExtractionError: LocalizedError {
    case videoUnavailable
    case noAudioTrack
    case exportUnavailable
    case exportFailed

    var errorDescription: String? {
        switch self {
        case .videoUnavailable:
            return "That video could not be loaded. If it is in iCloud, check your connection and try again."
        case .noAudioTrack:
            return "That video does not contain an audio track."
        case .exportUnavailable:
            return "This video's audio format cannot be extracted."
        case .exportFailed:
            return "The audio could not be extracted from that video."
        }
    }
}

enum VideoAudioExtractionService {
    /// Loads the original PhotoKit asset, preserves its complete audio mix, and exports a durable
    /// M4A owned by Mixtape. The partial file is removed on failure or cancellation.
    static func extract(from photoAsset: PHAsset) async throws -> ExtractedVideoAudio {
        try Task.checkCancellation()
        let asset = try await requestOriginalAsset(for: photoAsset)
        try Task.checkCancellation()

        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard !audioTracks.isEmpty else { throw VideoAudioExtractionError.noAudioTrack }
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else { throw VideoAudioExtractionError.exportFailed }

        guard let exporter = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetAppleM4A
        ) else { throw VideoAudioExtractionError.exportUnavailable }

        let destination = try destinationURL()
        let cancellationBox = VideoAudioExportSessionBox(exporter)
        do {
            try await withTaskCancellationHandler {
                try await exporter.export(to: destination, as: .m4a)
            } onCancel: {
                cancellationBox.cancel()
            }
            try Task.checkCancellation()
            let exportedDuration = (try? await AVURLAsset(url: destination).load(.duration))?.seconds
            return ExtractedVideoAudio(
                fileURL: destination,
                duration: exportedDuration.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? duration
            )
        } catch is CancellationError {
            try? FileManager.default.removeItem(at: destination)
            throw CancellationError()
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw VideoAudioExtractionError.exportFailed
        }
    }

    private static func requestOriginalAsset(for asset: PHAsset) async throws -> AVAsset {
        let options = PHVideoRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.version = .original
        options.isNetworkAccessAllowed = true

        return try await withCheckedThrowingContinuation { continuation in
            PHImageManager.default().requestAVAsset(
                forVideo: asset,
                options: options
            ) { result, _, info in
                if let result {
                    continuation.resume(returning: result)
                } else if let error = info?[PHImageErrorKey] as? Error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(throwing: VideoAudioExtractionError.videoUnavailable)
                }
            }
        }
    }

    private static func destinationURL() throws -> URL {
        let fm = FileManager.default
        let base = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appendingPathComponent("MixtapeAudio", isDirectory: true)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
            .appendingPathComponent("extracted-\(UUID().uuidString)")
            .appendingPathExtension("m4a")
    }
}

private final class VideoAudioExportSessionBox: @unchecked Sendable {
    private let exporter: AVAssetExportSession

    init(_ exporter: AVAssetExportSession) {
        self.exporter = exporter
    }

    func cancel() {
        exporter.cancelExport()
    }
}
