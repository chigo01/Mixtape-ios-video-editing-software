//
//  EditorExportService.swift
//  Mixtape
//

import AVFoundation
import Photos
import VideoToolbox

enum EditorExportError: LocalizedError {
    case compositionFailed
    case exportSessionFailed
    case exportFailed(String)
    case exportCancelled
    case photoLibraryDenied

    var errorDescription: String? {
        switch self {
        case .compositionFailed: return "Could not build the export timeline."
        case .exportSessionFailed: return "Could not start the export session."
        case .exportFailed(let detail): return "Export failed: \(detail)"
        case .exportCancelled: return "Export cancelled."
        case .photoLibraryDenied: return "Photo library access is required to save your video."
        }
    }
}

enum EditorExportService {

    private static var activeReader: AVAssetReader?
    private static var activeWriter: AVAssetWriter?

    static func cancelCurrentExport() {
        activeReader?.cancelReading()
        activeWriter?.cancelWriting()
        activeReader = nil
        activeWriter = nil
    }

    /// Renders the current timeline to a temporary file using the chosen export settings.
    static func export(
        clips: [EditorClip],
        textOverlays: [EditorTextOverlay] = [],
        audioClips: [EditorAudioClip] = [],
        settings: EditorExportSettings,
        projectTitle: String,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        guard let built = await EditorCompositionBuilder.build(
            from: clips,
            textOverlays: textOverlays,
            audioClips: audioClips,
            frameRate: Int32(settings.frameRate.rawValue),
            canvasSize: settings.resolution.canvasSize
        ) else {
            throw EditorExportError.compositionFailed
        }

        guard let videoComposition = built.videoComposition else {
            throw EditorExportError.compositionFailed
        }

        let outputURL = uniqueExportURL(
            fileName: exportFileName(for: projectTitle, format: settings.format)
        )

        try await exportWithWriter(
            composition: built.composition,
            videoComposition: videoComposition,
            audioMix: built.audioMix,
            outputURL: outputURL,
            fileType: settings.format.fileType,
            settings: settings,
            progress: progress
        )

        return outputURL
    }

    static func saveVideoToPhotoLibrary(url: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw EditorExportError.photoLibraryDenied
        }

        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        }
    }

    // MARK: - Writer export (explicit bitrate + optional HEVC HDR)

    private static func exportWithWriter(
        composition: AVAsset,
        videoComposition: AVVideoComposition,
        audioMix: AVAudioMix?,
        outputURL: URL,
        fileType: AVFileType,
        settings: EditorExportSettings,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }

        let reader = try AVAssetReader(asset: composition)
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: fileType)
        activeReader = reader
        activeWriter = writer

        defer {
            activeReader = nil
            activeWriter = nil
        }

        let duration = try await composition.load(.duration)
        let durationSeconds = max(duration.seconds, 0.01)
        let renderSize = videoComposition.renderSize

        let videoTracks = try await composition.loadTracks(withMediaType: .video)
        guard !videoTracks.isEmpty else {
            throw EditorExportError.exportSessionFailed
        }

        let videoOutput = AVAssetReaderVideoCompositionOutput(
            videoTracks: videoTracks,
            videoSettings: nil
        )
        videoOutput.videoComposition = videoComposition
        videoOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(videoOutput) else {
            throw EditorExportError.exportSessionFailed
        }
        reader.add(videoOutput)

        var audioOutput: AVAssetReaderAudioMixOutput?
        let audioTracks = try await composition.loadTracks(withMediaType: .audio)
        if !audioTracks.isEmpty {
            let output = AVAssetReaderAudioMixOutput(audioTracks: audioTracks, audioSettings: nil)
            output.audioMix = audioMix
            output.alwaysCopiesSampleData = false
            if reader.canAdd(output) {
                reader.add(output)
                audioOutput = output
            }
        }

        var compressionProperties: [String: Any] = [
            AVVideoAverageBitRateKey: settings.targetVideoBitratebps,
            AVVideoExpectedSourceFrameRateKey: settings.frameRate.rawValue,
            AVVideoMaxKeyFrameIntervalKey: settings.frameRate.rawValue * 2
        ]

        let codec = preferredVideoCodec(hdr: settings.includeHDR)
        if codec == .hevc, settings.includeHDR {
            compressionProperties[AVVideoProfileLevelKey] = kVTProfileLevel_HEVC_Main10_AutoLevel
        }

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: codec,
            AVVideoWidthKey: Int(renderSize.width),
            AVVideoHeightKey: Int(renderSize.height),
            AVVideoCompressionPropertiesKey: compressionProperties
        ]

        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(videoInput) else {
            throw EditorExportError.exportSessionFailed
        }
        writer.add(videoInput)

        var audioInput: AVAssetWriterInput?
        if audioOutput != nil {
            let input = AVAssetWriterInput(
                mediaType: .audio,
                outputSettings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: 44_100,
                    AVNumberOfChannelsKey: 2,
                    AVEncoderBitRateKey: 192_000
                ]
            )
            input.expectsMediaDataInRealTime = false
            if writer.canAdd(input) {
                writer.add(input)
                audioInput = input
            }
        }

        guard reader.startReading() else {
            throw EditorExportError.exportFailed(reader.error?.localizedDescription ?? "Reader failed.")
        }
        guard writer.startWriting() else {
            throw EditorExportError.exportFailed(writer.error?.localizedDescription ?? "Writer failed.")
        }
        writer.startSession(atSourceTime: .zero)

        let queue = DispatchQueue(label: "mixtape.export.writer")

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let group = DispatchGroup()
            var exportError: Error?

            group.enter()
            videoInput.requestMediaDataWhenReady(on: queue) {
                while videoInput.isReadyForMoreMediaData {
                    if reader.status == .cancelled || writer.status == .cancelled {
                        exportError = EditorExportError.exportCancelled
                        videoInput.markAsFinished()
                        group.leave()
                        return
                    }

                    guard let sample = videoOutput.copyNextSampleBuffer() else {
                        videoInput.markAsFinished()
                        group.leave()
                        return
                    }

                    if !videoInput.append(sample) {
                        exportError = writer.error ?? EditorExportError.exportFailed("Video encode failed.")
                        reader.cancelReading()
                        videoInput.markAsFinished()
                        group.leave()
                        return
                    }

                    let pts = CMSampleBufferGetPresentationTimeStamp(sample).seconds
                    if pts.isFinite {
                        progress(min(1, pts / durationSeconds))
                    }
                }
            }

            if let audioInput, let audioOutput {
                group.enter()
                audioInput.requestMediaDataWhenReady(on: queue) {
                    while audioInput.isReadyForMoreMediaData {
                        if reader.status == .cancelled || writer.status == .cancelled {
                            exportError = EditorExportError.exportCancelled
                            audioInput.markAsFinished()
                            group.leave()
                            return
                        }

                        guard let sample = audioOutput.copyNextSampleBuffer() else {
                            audioInput.markAsFinished()
                            group.leave()
                            return
                        }

                        if !audioInput.append(sample) {
                            exportError = writer.error ?? EditorExportError.exportFailed("Audio encode failed.")
                            reader.cancelReading()
                            audioInput.markAsFinished()
                            group.leave()
                            return
                        }
                    }
                }
            }

            group.notify(queue: queue) {
                if let exportError {
                    writer.cancelWriting()
                    continuation.resume(throwing: exportError)
                    return
                }

                if reader.status == .failed {
                    continuation.resume(throwing: EditorExportError.exportFailed(
                        reader.error?.localizedDescription ?? "Reader failed."
                    ))
                    return
                }

                writer.finishWriting {
                    if writer.status == .completed {
                        progress(1)
                        continuation.resume()
                    } else if writer.status == .cancelled {
                        continuation.resume(throwing: EditorExportError.exportCancelled)
                    } else {
                        continuation.resume(throwing: EditorExportError.exportFailed(
                            writer.error?.localizedDescription ?? "Writer failed."
                        ))
                    }
                }
            }
        }
    }

    private static func preferredVideoCodec(hdr: Bool) -> AVVideoCodecType {
        guard hdr else { return .h264 }
        if #available(iOS 11.0, *) {
            return .hevc
        }
        return .h264
    }

    // MARK: - Export file naming

    private static func exportFileName(for projectTitle: String, format: EditorExportFormat) -> String {
        "\(sanitizeFileName(projectTitle)).\(format.fileExtension)"
    }

    private static func sanitizeFileName(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? "Untitled Project" : trimmed

        let invalid = CharacterSet(charactersIn: "/\\:?*\"<>|")
        var result = base.components(separatedBy: invalid).joined(separator: "-")
        result = result.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        result = result.replacingOccurrences(of: #"-+"#, with: "-", options: .regularExpression)
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)

        if result.count > 120 {
            result = String(result.prefix(120)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return result.isEmpty ? "mixtape-export" : result
    }

    private static func uniqueExportURL(fileName: String) -> URL {
        let directory = FileManager.default.temporaryDirectory
        let candidate = directory.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: candidate.path) else { return candidate }

        let stem = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        let suffix = UUID().uuidString.prefix(8)
        return directory.appendingPathComponent("\(stem)-\(suffix).\(ext)")
    }
}
