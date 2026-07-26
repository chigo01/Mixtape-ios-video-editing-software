//
//  ClipThumbnailService.swift
//  Mixtape
//

import AVFoundation
import Photos
import UIKit

/// Generates tiled filmstrip frames for timeline clip thumbnails.
actor ClipThumbnailService {
    static let shared = ClipThumbnailService()

    private var cache: [String: [UIImage]] = [:]

    func filmstrip(for clip: EditorClip, width: CGFloat, height: CGFloat) async -> [UIImage] {
        let frameCount = max(1, min(10, Int(width / 26)))
        let key = "\(clip.id)|\(clip.trimStart)|\(clip.trimEnd)|\(clip.speed)|\(frameCount)|\(Int(width))"
        if let cached = cache[key] { return cached }

        let frames: [UIImage]
        if clip.isVideo {
            frames = await videoFrames(for: clip, count: frameCount, height: height)
        } else {
            frames = await photoFrames(for: clip, count: frameCount, height: height)
        }

        cache[key] = frames
        return frames
    }

    private func videoFrames(for clip: EditorClip, count: Int, height: CGFloat) async -> [UIImage] {
        let asset = await requestAVAsset(for: clip.asset) ?? AVAsset()
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let scale = await MainActor.run { UIScreen.main.scale }
        generator.maximumSize = CGSize(width: 120, height: height * scale)

        let span = max(0, clip.trimEnd - clip.trimStart)
        guard span > 0 else { return [] }

        var frames: [UIImage] = []
        frames.reserveCapacity(count)
        for index in 0..<count {
            let fraction = count == 1 ? 0.0 : Double(index) / Double(count - 1)
            let seconds = clip.trimStart + span * fraction
            let time = CMTime(seconds: seconds, preferredTimescale: 600)
            guard let cgImage = try? await generator.image(at: time).image else { continue }
            frames.append(UIImage(cgImage: cgImage))
        }
        return frames
    }

    private func photoFrames(for clip: EditorClip, count: Int, height: CGFloat) async -> [UIImage] {
        guard let image = await requestPhoto(for: clip.asset, height: height) else { return [] }
        return Array(repeating: image, count: count)
    }

    private func requestAVAsset(for asset: PHAsset) async -> AVAsset? {
        let options = PHVideoRequestOptions()
        options.deliveryMode = .fastFormat
        options.isNetworkAccessAllowed = true
        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
                continuation.resume(returning: avAsset)
            }
        }
    }

    private func requestPhoto(for asset: PHAsset, height: CGFloat) async -> UIImage? {
        let options = PHImageRequestOptions()
        // Opportunistic delivery may invoke the result handler twice (a degraded
        // preview followed by the final image), but this async bridge must resume
        // its continuation exactly once.
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        let scale = await MainActor.run { UIScreen.main.scale }
        let target = CGSize(width: height * scale, height: height * scale)
        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: target,
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }
}
