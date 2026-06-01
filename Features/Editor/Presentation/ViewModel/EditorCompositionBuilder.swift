//
//  EditorCompositionBuilder.swift
//  Mixtape
//

import AVFoundation
import Photos
import UIKit

enum EditorCompositionBuilder {

    private static let timescale: CMTimeScale = 600
    /// Portrait canvas matching `EditorPreviewLayout` (9:16).
    private static let renderSize = CGSize(width: 1080, height: 1920)
    private static var assetCache: [String: AVAsset] = [:]
    private static var photoVideoCache: [String: URL] = [:]

    private struct VideoSegment {
        let timeRange: CMTimeRange
        let transform: CGAffineTransform
    }

    /// Builds one continuous composition for the whole timeline (CapCut-style seamless preview).
    static func makePlayerItem(from clips: [EditorClip]) async -> AVPlayerItem? {
        guard !clips.isEmpty else { return nil }

        let composition = AVMutableComposition()
        guard
            let compositionVideoTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
        else { return nil }

        let compositionAudioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )

        var cursor = CMTime.zero
        var videoSegments: [VideoSegment] = []

        for clip in clips {
            let segmentDuration = CMTime(seconds: clip.duration, preferredTimescale: timescale)
            guard segmentDuration.seconds > 0 else { continue }

            let segmentRange = CMTimeRange(start: cursor, duration: segmentDuration)

            if clip.isVideo {
                guard let avAsset = await loadVideoAsset(for: clip.asset) else {
                    cursor = cursor + segmentDuration
                    continue
                }

                let sourceStart = CMTime(seconds: clip.trimStart, preferredTimescale: timescale)
                let sourceDuration = CMTime(
                    seconds: max(0, clip.trimEnd - clip.trimStart),
                    preferredTimescale: timescale
                )
                let sourceRange = CMTimeRange(start: sourceStart, duration: sourceDuration)

                if let sourceVideo = avAsset.tracks(withMediaType: .video).first {
                    try? compositionVideoTrack.insertTimeRange(
                        sourceRange,
                        of: sourceVideo,
                        at: cursor
                    )
                    let transform = aspectFitTransform(for: sourceVideo, renderSize: renderSize)
                    videoSegments.append(VideoSegment(timeRange: segmentRange, transform: transform))
                }

                if let compositionAudioTrack,
                   let sourceAudio = avAsset.tracks(withMediaType: .audio).first {
                    try? compositionAudioTrack.insertTimeRange(
                        sourceRange,
                        of: sourceAudio,
                        at: cursor
                    )
                }
            } else if let photoURL = await photoVideoURL(for: clip.asset, duration: clip.duration) {
                let photoAsset = AVURLAsset(url: photoURL)
                if let sourceVideo = photoAsset.tracks(withMediaType: .video).first {
                    let fullRange = CMTimeRange(start: .zero, duration: segmentDuration)
                    try? compositionVideoTrack.insertTimeRange(fullRange, of: sourceVideo, at: cursor)
                    let transform = aspectFitTransform(for: sourceVideo, renderSize: renderSize)
                    videoSegments.append(VideoSegment(timeRange: segmentRange, transform: transform))
                }
            }

            cursor = cursor + segmentDuration
        }

        guard cursor.seconds > 0 else { return nil }

        let item = AVPlayerItem(asset: composition)
        item.audioTimePitchAlgorithm = .spectral

        if !videoSegments.isEmpty {
            item.videoComposition = makeVideoComposition(
                compositionTrack: compositionVideoTrack,
                segments: videoSegments
            )
        }

        return item
    }

    // MARK: - Video composition (orientation + aspect fit)

    private static func makeVideoComposition(
        compositionTrack: AVMutableCompositionTrack,
        segments: [VideoSegment]
    ) -> AVMutableVideoComposition {
        let composition = AVMutableVideoComposition()
        composition.renderSize = renderSize
        composition.frameDuration = CMTime(value: 1, timescale: 30)

        composition.instructions = segments.map { segment in
            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = segment.timeRange

            let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionTrack)
            layer.setTransform(segment.transform, at: segment.timeRange.start)

            instruction.layerInstructions = [layer]
            return instruction
        }

        return composition
    }

    /// Applies `preferredTransform` and scales the track into `renderSize` without stretching.
    private static func aspectFitTransform(for track: AVAssetTrack, renderSize: CGSize) -> CGAffineTransform {
        let naturalSize = track.naturalSize
        let preferred = track.preferredTransform

        let orientedRect = CGRect(origin: .zero, size: naturalSize).applying(preferred)
        let videoWidth = abs(orientedRect.width)
        let videoHeight = abs(orientedRect.height)
        guard videoWidth > 0, videoHeight > 0 else { return preferred }

        let scale = min(renderSize.width / videoWidth, renderSize.height / videoHeight)
        let scaledWidth = videoWidth * scale
        let scaledHeight = videoHeight * scale
        let tx = (renderSize.width - scaledWidth) / 2 - orientedRect.origin.x * scale
        let ty = (renderSize.height - scaledHeight) / 2 - orientedRect.origin.y * scale

        var transform = preferred.concatenating(CGAffineTransform(scaleX: scale, y: scale))
        transform = transform.concatenating(CGAffineTransform(translationX: tx, y: ty))
        return transform
    }

    // MARK: - Asset loading

    private static func loadVideoAsset(for asset: PHAsset) async -> AVAsset? {
        if let cached = assetCache[asset.localIdentifier] { return cached }

        let options = PHVideoRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true

        let avAsset: AVAsset? = await withCheckedContinuation { cont in
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { result, _, _ in
                cont.resume(returning: result)
            }
        }

        if let avAsset { assetCache[asset.localIdentifier] = avAsset }
        return avAsset
    }

    /// Still image → short silent video segment for the composition timeline.
    private static func photoVideoURL(for asset: PHAsset, duration: TimeInterval) async -> URL? {
        let key = "\(asset.localIdentifier)-\(duration)"
        if let cached = photoVideoCache[key] { return cached }

        let image: UIImage? = await withCheckedContinuation { cont in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 1080, height: 1920),
                contentMode: .aspectFill,
                options: options
            ) { result, _ in cont.resume(returning: result) }
        }

        guard let image, let url = await writePhotoVideo(image: image, duration: duration) else { return nil }
        photoVideoCache[key] = url
        return url
    }

    private static func writePhotoVideo(image: UIImage, duration: TimeInterval) async -> URL? {
        let oriented = normalizedPortraitImage(image)
        let width = Int(renderSize.width)
        let height = Int(renderSize.height)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mixtape-photo-\(UUID().uuidString).mov")

        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mov) else { return nil }

        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ]

        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height
            ]
        )

        guard writer.canAdd(input) else { return nil }
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        guard let buffer = pixelBuffer(from: oriented, width: width, height: height) else { return nil }

        let frameDuration = CMTime(seconds: duration, preferredTimescale: timescale)
        let ok = adaptor.append(buffer, withPresentationTime: .zero)
        input.markAsFinished()
        writer.endSession(atSourceTime: frameDuration)

        return await withCheckedContinuation { cont in
            writer.finishWriting {
                let success = ok && writer.status == .completed
                cont.resume(returning: success ? url : nil)
            }
        }
    }

    private static func normalizedPortraitImage(_ image: UIImage) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: renderSize, format: format)
        return renderer.image { _ in
            UIColor.black.setFill()
            UIBezierPath(rect: CGRect(origin: .zero, size: renderSize)).fill()
            let aspect = min(renderSize.width / image.size.width, renderSize.height / image.size.height)
            let drawSize = CGSize(width: image.size.width * aspect, height: image.size.height * aspect)
            let origin = CGPoint(
                x: (renderSize.width - drawSize.width) / 2,
                y: (renderSize.height - drawSize.height) / 2
            )
            image.draw(in: CGRect(origin: origin, size: drawSize))
        }
    }

    private static func pixelBuffer(from image: UIImage, width: Int, height: Int) -> CVPixelBuffer? {
        guard
            let cgImage = image.cgImage,
            let pool = createPixelBufferPool(width: width, height: height)
        else { return nil }

        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
        guard let pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(pixelBuffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else { return nil }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixelBuffer
    }

    private static func createPixelBufferPool(width: Int, height: Int) -> CVPixelBufferPool? {
        var pool: CVPixelBufferPool?
        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height
        ]
        CVPixelBufferPoolCreate(nil, nil, attrs as CFDictionary, &pool)
        return pool
    }

    static func clearCaches() {
        assetCache.removeAll()
        photoVideoCache.removeAll()
    }
}
