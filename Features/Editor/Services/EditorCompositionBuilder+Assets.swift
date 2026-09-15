//
//  EditorCompositionBuilder+Assets.swift
//  Mixtape
//

import AVFoundation
import Photos
import UIKit

extension EditorCompositionBuilder {
    // MARK: - Asset loading

    static func loadVideoAsset(
        for asset: PHAsset,
        proxySettings: EditorProxySettings = .default,
        allowProxy: Bool = false
    ) async -> AVAsset? {
        if allowProxy,
           proxySettings.isEnabled,
           let proxyURL = EditorMediaCache.cachedProxyURL(for: asset, quality: proxySettings.quality) {
            return AVURLAsset(url: proxyURL)
        }
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
    static func photoVideoURL(for asset: PHAsset, duration: TimeInterval) async -> URL? {
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

    /// Samples the exact edited source frame and turns it into a silent video
    /// segment. Keeping this in the shared builder guarantees preview/export
    /// use the same frame, transform, grade, masks, and keyframes.
    static func freezeVideoURL(
        for asset: AVAsset,
        assetIdentifier: String,
        sourceTime: TimeInterval,
        duration: TimeInterval
    ) async -> URL? {
        let key = "\(assetIdentifier)|\(sourceTime)|\(duration)"
        if let cached = freezeVideoCache[key],
           FileManager.default.fileExists(atPath: cached.path) {
            return cached
        }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let loadedDuration = try? await asset.load(.duration)
        let assetDuration = loadedDuration?.seconds ?? sourceTime
        let safeSourceTime = min(
            max(0, sourceTime),
            max(0, assetDuration - (1 / Double(timescale)))
        )
        let time = CMTime(seconds: safeSourceTime, preferredTimescale: timescale)
        guard let result = try? await generator.image(at: time),
              let url = await writeStillVideo(
                image: UIImage(cgImage: result.image),
                duration: duration,
                cacheKey: key
              ) else { return nil }
        freezeVideoCache[key] = url
        return url
    }

    private static func writeStillVideo(
        image: UIImage,
        duration: TimeInterval,
        cacheKey: String
    ) async -> URL? {
        let maximumEdge: CGFloat = 1920
        let scale = min(1, maximumEdge / max(image.size.width, image.size.height, 1))
        let width = max(2, Int((image.size.width * scale).rounded()) / 2 * 2)
        let height = max(2, Int((image.size.height * scale).rounded()) / 2 * 2)
        let renderedSize = CGSize(width: width, height: height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let rendered = UIGraphicsImageRenderer(size: renderedSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: renderedSize))
        }

        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MixtapeFreezeFrames", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let safeKey = Data(cacheKey.utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
        let url = directory.appendingPathComponent("\(safeKey).mov")
        if FileManager.default.fileExists(atPath: url.path) { return url }

        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mov) else { return nil }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ])
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
        guard writer.startWriting() else { return nil }
        writer.startSession(atSourceTime: .zero)
        guard let buffer = pixelBuffer(from: rendered, width: width, height: height) else {
            writer.cancelWriting()
            return nil
        }
        let appended = adaptor.append(buffer, withPresentationTime: .zero)
        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(seconds: max(duration, 0.05), preferredTimescale: timescale))
        let result: URL? = await withCheckedContinuation { continuation in
            writer.finishWriting {
                let bytes = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
                continuation.resume(returning: appended && (bytes ?? 0) > 0 ? url : nil)
            }
        }
        return result
    }

    private static func writePhotoVideo(image: UIImage, duration: TimeInterval) async -> URL? {
        let oriented = normalizedPortraitImage(image)
        let width = Int(previewCanvasSize.width)
        let height = Int(previewCanvasSize.height)

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

        let didAppend = ok
        let outputURL = url

        return await withCheckedContinuation { continuation in
            writer.finishWriting {
                // Avoid capturing `writer` here — its completion handler is @Sendable.
                // File size is enough to confirm a successful write for this temp clip.
                var isValid = false
                if didAppend,
                   let size = try? outputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    isValid = size > 0
                }
                continuation.resume(returning: isValid ? outputURL : nil)
            }
        }
    }

    static func solidVideoURL(
        color: UIColor,
        colorKey: String,
        renderSize: CGSize
    ) async -> URL? {
        let width = max(2, Int(renderSize.width.rounded()))
        let height = max(2, Int(renderSize.height.rounded()))
        let key = "\(colorKey)-\(width)x\(height)"
        if let cached = solidVideoCache[key],
           FileManager.default.fileExists(atPath: cached.path) {
            return cached
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mixtape-\(key)-\(UUID().uuidString).mov")
        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mov) else {
            return nil
        }

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
        guard writer.startWriting() else { return nil }
        writer.startSession(atSourceTime: .zero)

        guard let buffer = solidColorPixelBuffer(color: color, width: width, height: height) else {
            writer.cancelWriting()
            return nil
        }

        let didAppend = adaptor.append(buffer, withPresentationTime: .zero)
        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(seconds: 1, preferredTimescale: timescale))

        let outputURL = url
        let completedURL: URL? = await withCheckedContinuation { continuation in
            writer.finishWriting {
                let fileSize = try? outputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize
                continuation.resume(
                    returning: didAppend && (fileSize ?? 0) > 0 ? outputURL : nil
                )
            }
        }
        if let completedURL {
            solidVideoCache[key] = completedURL
        }
        return completedURL
    }

    static func canvasImageVideoURL(
        image: UIImage,
        path: String,
        renderSize: CGSize
    ) async -> URL? {
        let width = max(2, Int(renderSize.width.rounded()) / 2 * 2)
        let height = max(2, Int(renderSize.height.rounded()) / 2 * 2)
        let key = "\(path)-\(width)x\(height)"
        if let cached = canvasImageVideoCache[key], FileManager.default.fileExists(atPath: cached.path) {
            return cached
        }

        let size = CGSize(width: width, height: height)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            UIColor.black.setFill(); UIBezierPath(rect: CGRect(origin: .zero, size: size)).fill()
            let scale = max(size.width / max(image.size.width, 1), size.height / max(image.size.height, 1))
            let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            image.draw(in: CGRect(
                x: (size.width - drawSize.width) / 2,
                y: (size.height - drawSize.height) / 2,
                width: drawSize.width,
                height: drawSize.height
            ))
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mixtape-canvas-\(UUID().uuidString).mov")
        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mov) else { return nil }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ])
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
        guard writer.startWriting() else { return nil }
        writer.startSession(atSourceTime: .zero)
        guard let buffer = pixelBuffer(from: rendered, width: width, height: height) else {
            writer.cancelWriting(); return nil
        }
        let didAppend = adaptor.append(buffer, withPresentationTime: .zero)
        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(seconds: 1, preferredTimescale: timescale))
        let result: URL? = await withCheckedContinuation { continuation in
            writer.finishWriting {
                let bytes = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
                continuation.resume(returning: didAppend && (bytes ?? 0) > 0 ? url : nil)
            }
        }
        if let result { canvasImageVideoCache[key] = result }
        return result
    }

    private static func solidColorPixelBuffer(
        color: UIColor,
        width: Int,
        height: Int
    ) -> CVPixelBuffer? {
        guard let pool = createPixelBufferPool(width: width, height: height) else {
            return nil
        }

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

        context.setFillColor(color.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return pixelBuffer
    }

    private static func normalizedPortraitImage(_ image: UIImage) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: previewCanvasSize, format: format)
        return renderer.image { _ in
            UIColor.black.setFill()
            UIBezierPath(rect: CGRect(origin: .zero, size: previewCanvasSize)).fill()
            let aspect = min(previewCanvasSize.width / image.size.width, previewCanvasSize.height / image.size.height)
            let drawSize = CGSize(width: image.size.width * aspect, height: image.size.height * aspect)
            let origin = CGPoint(
                x: (previewCanvasSize.width - drawSize.width) / 2,
                y: (previewCanvasSize.height - drawSize.height) / 2
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
        freezeVideoCache.removeAll()
        solidVideoCache.removeAll()
        warmedPlayerItem = nil
        warmedFingerprint = nil
    }
}
