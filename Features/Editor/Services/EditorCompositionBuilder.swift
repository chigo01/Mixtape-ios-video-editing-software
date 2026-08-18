//
//  EditorCompositionBuilder.swift
//  Mixtape
//

import AVFoundation
import Photos
import UIKit

struct EditorCompositionBuildResult {
    let composition: AVMutableComposition
    let videoComposition: AVVideoComposition?
    let audioMix: AVAudioMix?
    let duration: CMTime
}

enum EditorCompositionBuilder {

    private static let timescale: CMTimeScale = 600
    /// Portrait canvas matching `EditorPreviewLayout` (9:16).
    private static let previewCanvasSize = CGSize(width: 1080, height: 1920)
    private static var assetCache: [String: AVAsset] = [:]
    private static var photoVideoCache: [String: URL] = [:]
    private static var solidVideoCache: [String: URL] = [:]
    private static var canvasImageVideoCache: [String: URL] = [:]
    private static var warmedPlayerItem: AVPlayerItem?
    private static var warmedFingerprint: String?

    /// Stable key for matching a warmed composition to a freshly built clip list (IDs differ per init).
    static func timelineFingerprint(for clips: [EditorClip]) -> String {
        clips.map { clip in
            "\(clip.asset.localIdentifier)|\(clip.trimStart)|\(clip.trimEnd)|\(clip.speed)|\(String(describing: clip.speedRamp))|\(clip.cropAspect.rawValue)|\(clip.reframeMode.rawValue)|\(clip.rotationQuarterTurns)|\(clip.straightenDegrees)|\(clip.isFlippedHorizontally)|\(clip.isFlippedVertically)|\(clip.reframeScale)|\(clip.reframeXOffset)|\(clip.reframeYOffset)|\(clip.colorAdjustment)|\(clip.keyframes)|\(clip.transitionKind.rawValue)|\(clip.transitionDuration)|\(clip.duration)"
        }.joined(separator: ";")
    }

    /// Pre-build the preview composition while the user is still on the media picker.
    static func warmUp(from media: [MediaItem]) async {
        let clips = media.map { EditorClip(asset: $0.asset) }
        let fingerprint = timelineFingerprint(for: clips)
        guard warmedFingerprint != fingerprint || warmedPlayerItem == nil else { return }

        warmedPlayerItem = await Task.detached(priority: .userInitiated) {
            await makePlayerItem(from: clips)
        }.value
        warmedFingerprint = fingerprint
    }

    /// Returns a pre-built item when the editor opens with the same media the picker warmed.
    static func consumeWarmedPlayerItem(matching clips: [EditorClip]) -> AVPlayerItem? {
        let fingerprint = timelineFingerprint(for: clips)
        guard warmedFingerprint == fingerprint, let item = warmedPlayerItem else { return nil }
        warmedPlayerItem = nil
        warmedFingerprint = nil
        return item
    }

    private struct AudioVolumeSegment {
        let timeRange: CMTimeRange
        let volume: Float
        let keyframes: EditorKeyframeTracks
    }

    private struct VideoSegment {
        let timeRange: CMTimeRange
        let transform: CGAffineTransform
        let colorAdjustment: EditorColorAdjustment
        let animation: EditorRenderKeyframeAnimation?
        let transitionIn: EditorTransitionKind
        let transitionOut: EditorTransitionKind
        let fadeInDuration: TimeInterval
        let fadeOutDuration: TimeInterval
    }

    private struct OverlayVideoSegment {
        let track: AVMutableCompositionTrack
        let timeRange: CMTimeRange
        let transform: CGAffineTransform
        let opacity: Float
        let colorAdjustment: EditorColorAdjustment
        let animation: EditorRenderKeyframeAnimation?
    }

    private struct BackgroundVideoTracks {
        let black: AVMutableCompositionTrack?
        let white: AVMutableCompositionTrack?
    }

    /// Shared composition pipeline for preview and export.
    /// `frameRate` drives the video composition's `frameDuration` (export passes the user's setting).
    @MainActor
    static func build(
        from clips: [EditorClip],
        textOverlays: [EditorTextOverlay] = [],
        audioClips: [EditorAudioClip] = [],
        overlayClips: [EditorOverlayClip] = [],
        openingTransitionKind: EditorTransitionKind = .none,
        openingTransitionDuration: TimeInterval = 0,
        closingTransitionKind: EditorTransitionKind = .none,
        closingTransitionDuration: TimeInterval = 0,
        canvasSettings: EditorCanvasSettings = .default,
        frameRate: Int32 = 30,
        canvasSize: CGSize? = nil,
        isOfflineRender: Bool = false
    ) async -> EditorCompositionBuildResult? {
        guard !clips.isEmpty else { return nil }

        let renderSize = canvasSize ?? previewCanvasSize

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
        var audioVolumeSegments: [AudioVolumeSegment] = []

        for (clipIndex, clip) in clips.enumerated() {
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
                if let sourceVideo = try? await avAsset.loadTracks(withMediaType: .video).first {
                    insertSpeedAdjusted(
                        sourceTrack: sourceVideo,
                        into: compositionVideoTrack,
                        sourceStart: sourceStart,
                        sourceDuration: sourceDuration,
                        timelineDuration: segmentDuration,
                        timelineStart: cursor,
                        uniformSpeed: clip.speed,
                        ramp: clip.speedRamp
                    )
                    let transform = await reframeTransform(
                        for: sourceVideo,
                        clip: clip,
                        renderSize: renderSize
                    )
                    videoSegments.append(
                        videoSegment(
                            timeRange: segmentRange,
                            transform: transform,
                            clipIndex: clipIndex,
                            clips: clips,
                            openingTransitionKind: openingTransitionKind,
                            openingTransitionDuration: openingTransitionDuration,
                            closingTransitionKind: closingTransitionKind,
                            closingTransitionDuration: closingTransitionDuration
                        )
                    )
                }

                if let compositionAudioTrack,
                   let sourceAudio = try? await avAsset.loadTracks(withMediaType: .audio).first {
                    insertSpeedAdjusted(
                        sourceTrack: sourceAudio,
                        into: compositionAudioTrack,
                        sourceStart: sourceStart,
                        sourceDuration: sourceDuration,
                        timelineDuration: segmentDuration,
                        timelineStart: cursor,
                        uniformSpeed: clip.speed,
                        ramp: clip.speedRamp
                    )
                    audioVolumeSegments.append(
                        AudioVolumeSegment(
                            timeRange: segmentRange,
                            volume: clip.volume,
                            keyframes: clip.keyframes
                        )
                    )
                }
            } else if let photoURL = await photoVideoURL(for: clip.asset, duration: clip.duration) {
                let photoAsset = AVURLAsset(url: photoURL)
                if let sourceVideo = try? await photoAsset.loadTracks(withMediaType: .video).first {
                    let fullRange = CMTimeRange(start: .zero, duration: segmentDuration)
                    try? compositionVideoTrack.insertTimeRange(fullRange, of: sourceVideo, at: cursor)
                    let transform = await reframeTransform(
                        for: sourceVideo,
                        clip: clip,
                        renderSize: renderSize
                    )
                    videoSegments.append(
                        videoSegment(
                            timeRange: segmentRange,
                            transform: transform,
                            clipIndex: clipIndex,
                            clips: clips,
                            openingTransitionKind: openingTransitionKind,
                            openingTransitionDuration: openingTransitionDuration,
                            closingTransitionKind: closingTransitionKind,
                            closingTransitionDuration: closingTransitionDuration
                        )
                    )
                }
            }

            cursor = cursor + segmentDuration
        }

        guard cursor.seconds > 0 else { return nil }

        let videoDuration = cursor.seconds
        var timelineExtent = videoDuration
        for audioClip in audioClips {
            timelineExtent = max(timelineExtent, audioClip.timelineStart + audioClip.duration)
        }
        for overlay in textOverlays {
            timelineExtent = max(timelineExtent, overlay.endTime)
        }
        for overlay in overlayClips {
            timelineExtent = max(timelineExtent, overlay.timelineEnd)
        }

        var overlayVideoSegments: [OverlayVideoSegment] = []
        var overlayAudioTracks: [(track: AVMutableCompositionTrack, clip: EditorOverlayClip)] = []
        let orderedOverlayClips = overlayClips.sorted {
            if $0.zIndex == $1.zIndex { return $0.laneIndex < $1.laneIndex }
            return $0.zIndex < $1.zIndex
        }
        for overlay in orderedOverlayClips {
            guard overlay.duration > 0 else { continue }

            let asset: AVAsset
            if overlay.asset.mediaType == .video {
                guard let videoAsset = await loadVideoAsset(for: overlay.asset) else { continue }
                asset = videoAsset
            } else {
                // Reuse the same still-image conversion as primary photo clips so
                // photo overlays have identical preview/export behavior.
                guard let photoURL = await photoVideoURL(
                    for: overlay.asset,
                    duration: overlay.originalDuration
                ) else { continue }
                asset = AVURLAsset(url: photoURL)
            }

            let timelineStart = CMTime(seconds: overlay.timelineStart, preferredTimescale: timescale)
            let sourceStart = CMTime(seconds: overlay.trimStart, preferredTimescale: timescale)
            let sourceDuration = CMTime(
                seconds: overlay.trimEnd - overlay.trimStart,
                preferredTimescale: timescale
            )
            let timelineDuration = CMTime(seconds: overlay.duration, preferredTimescale: timescale)
            let sourceRange = CMTimeRange(start: sourceStart, duration: sourceDuration)
            let timelineRange = CMTimeRange(start: timelineStart, duration: timelineDuration)

            if let sourceVideo = try? await asset.loadTracks(withMediaType: .video).first,
               let overlayTrack = composition.addMutableTrack(
                    withMediaType: .video,
                    preferredTrackID: kCMPersistentTrackID_Invalid
               ) {
                do {
                    try overlayTrack.insertTimeRange(sourceRange, of: sourceVideo, at: timelineStart)
                    applySpeed(
                        overlay.speed,
                        sourceDuration: sourceDuration,
                        timelineDuration: timelineDuration,
                        on: overlayTrack,
                        at: timelineStart
                    )
                    let base = await reframeTransform(
                        for: sourceVideo,
                        clip: overlay.thumbnailClip,
                        renderSize: renderSize
                    )
                    overlayVideoSegments.append(
                        OverlayVideoSegment(
                            track: overlayTrack,
                            timeRange: timelineRange,
                            transform: overlayTransform(
                                base: base,
                                clip: overlay,
                                renderSize: renderSize
                            ),
                            opacity: Float(overlay.opacity),
                            colorAdjustment: overlay.colorAdjustment,
                            animation: renderAnimation(for: overlay)
                        )
                    )
                } catch {
                    composition.removeTrack(overlayTrack)
                }
            }

            if let sourceAudio = try? await asset.loadTracks(withMediaType: .audio).first,
               let overlayAudioTrack = composition.addMutableTrack(
                    withMediaType: .audio,
                    preferredTrackID: kCMPersistentTrackID_Invalid
               ) {
                do {
                    try overlayAudioTrack.insertTimeRange(sourceRange, of: sourceAudio, at: timelineStart)
                    applySpeed(
                        overlay.speed,
                        sourceDuration: sourceDuration,
                        timelineDuration: timelineDuration,
                        on: overlayAudioTrack,
                        at: timelineStart
                    )
                    overlayAudioTracks.append((overlayAudioTrack, overlay))
                } catch {
                    composition.removeTrack(overlayAudioTrack)
                }
            }
        }

        var segmentsSnapshot = videoSegments
        // Core Animation composition tools are valid for offline rendering only.
        // Assigning one to an AVPlayerItem raises an Objective-C exception on device.
        // Playback gets its opaque canvas from each video-composition instruction below.
        let animationTool: AVVideoCompositionCoreAnimationTool? = {
            guard isOfflineRender, !textOverlays.isEmpty else { return nil }

            let parentLayer = CALayer()
            parentLayer.frame = CGRect(origin: .zero, size: renderSize)
            parentLayer.backgroundColor = UIColor.black.cgColor
            parentLayer.isOpaque = true
            parentLayer.isGeometryFlipped = true

            let videoLayer = CALayer()
            videoLayer.frame = parentLayer.bounds
            parentLayer.addSublayer(videoLayer)

            let totalDuration = timelineExtent
            for overlay in textOverlays {
                if let image = EditorTextOverlayRenderer.render(overlay: overlay, renderSize: renderSize) {
                    let textLayer = CALayer()
                    textLayer.contents = image.cgImage
                    textLayer.contentsScale = 1
                    textLayer.frame = CGRect(origin: .zero, size: renderSize)
                    textLayer.opacity = 0

                    addTextAnimations(
                        to: textLayer,
                        overlay: overlay,
                        totalDuration: totalDuration,
                        renderSize: renderSize
                    )
                    parentLayer.addSublayer(textLayer)
                }
            }

            return AVVideoCompositionCoreAnimationTool(
                postProcessingAsVideoLayer: videoLayer,
                in: parentLayer
            )
        }()

        // Background music clips (inserted before extending video track / instructions).
        var mixParams: [AVMutableAudioMixInputParameters] = []

        for overlayAudio in overlayAudioTracks {
            let params = AVMutableAudioMixInputParameters(track: overlayAudio.track)
            applyVolumeAutomation(
                to: params,
                timeRange: CMTimeRange(
                    start: CMTime(
                        seconds: overlayAudio.clip.timelineStart,
                        preferredTimescale: timescale
                    ),
                    duration: CMTime(
                        seconds: overlayAudio.clip.duration,
                        preferredTimescale: timescale
                    )
                ),
                baseVolume: overlayAudio.clip.volume,
                keyframes: overlayAudio.clip.keyframes
            )
            mixParams.append(params)
        }

        // Per-clip volume
        if let clipAudioTrack = compositionAudioTrack, !audioVolumeSegments.isEmpty {
            let needsClipMix = audioVolumeSegments.contains {
                abs($0.volume - 1.0) > 0.001
                    || !$0.keyframes.track(for: .volume).isEmpty
            }
            if needsClipMix {
                let params = AVMutableAudioMixInputParameters(track: clipAudioTrack)
                for seg in audioVolumeSegments {
                    applyVolumeAutomation(
                        to: params,
                        timeRange: seg.timeRange,
                        baseVolume: seg.volume,
                        keyframes: seg.keyframes
                    )
                }
                mixParams.append(params)
            }
        }

        // Background music clips
        for audioClip in audioClips where FileManager.default.fileExists(atPath: audioClip.fileURL.path) {
            let bgAsset = AVURLAsset(url: audioClip.fileURL)
            guard let bgSourceTrack = try? await bgAsset.loadTracks(withMediaType: .audio).first,
                  let bgCompTrack = composition.addMutableTrack(
                    withMediaType: .audio,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                  ) else { continue }

            let timelineStart = CMTime(seconds: audioClip.timelineStart, preferredTimescale: timescale)
            let sourceStart = CMTime(seconds: audioClip.trimStart, preferredTimescale: timescale)
            let sourceDuration = CMTime(seconds: audioClip.duration, preferredTimescale: timescale)
            guard sourceDuration.seconds > 0 else { continue }

            let sourceRange = CMTimeRange(start: sourceStart, duration: sourceDuration)

            try? bgCompTrack.insertTimeRange(sourceRange, of: bgSourceTrack, at: timelineStart)

            timelineExtent = max(timelineExtent, audioClip.timelineStart + audioClip.duration)

            let bgParams = AVMutableAudioMixInputParameters(track: bgCompTrack)
            let fadeIn = min(max(0, audioClip.fadeInDuration), audioClip.duration)
            let fadeOut = min(
                max(0, audioClip.fadeOutDuration),
                max(0, audioClip.duration - fadeIn)
            )

            applyVolumeAutomation(
                to: bgParams,
                timeRange: CMTimeRange(start: timelineStart, duration: sourceDuration),
                baseVolume: audioClip.volume,
                keyframes: audioClip.keyframes,
                fadeIn: fadeIn,
                fadeOut: fadeOut
            )
            mixParams.append(bgParams)
        }

        // Keep the video track and composition instructions aligned with the full timeline
        // (long background audio extends composition duration past the last video frame).
        if timelineExtent > videoDuration {
            let emptyStart = CMTime(seconds: videoDuration, preferredTimescale: timescale)
            let emptyDuration = CMTime(seconds: timelineExtent - videoDuration, preferredTimescale: timescale)
            compositionVideoTrack.insertEmptyTimeRange(
                CMTimeRange(start: emptyStart, duration: emptyDuration)
            )
        }
        segmentsSnapshot = segmentsCoveringTimelineExtent(
            segmentsSnapshot,
            extent: timelineExtent
        )

        // AVVideoCompositionInstruction.backgroundColor is not consistently materialized
        // by AVAssetReaderVideoCompositionOutput. On device, uncovered YUV planes can then
        // encode as green. Real black/white video tracks guarantee initialized pixels under
        // letterboxed clips and every opacity/transform transition.
        let backgroundTracks = await makeBackgroundVideoTracks(
            in: composition,
            duration: CMTime(seconds: timelineExtent, preferredTimescale: timescale),
            renderSize: renderSize,
            canvasSettings: canvasSettings,
            needsWhite: segmentsSnapshot.contains {
                usesWhiteCanvas($0.transitionIn) || usesWhiteCanvas($0.transitionOut)
            }
        )

        let videoComposition: AVVideoComposition? = {
            guard !segmentsSnapshot.isEmpty else { return nil }
            return makeVideoComposition(
                compositionTrack: compositionVideoTrack,
                backgroundTracks: backgroundTracks,
                segments: segmentsSnapshot,
                overlaySegments: overlayVideoSegments,
                frameRate: frameRate,
                renderSize: renderSize,
                canvasSettings: canvasSettings,
                animationTool: animationTool
            )
        }()

        let audioMix: AVAudioMix?
        if mixParams.isEmpty {
            audioMix = nil
        } else {
            let mix = AVMutableAudioMix()
            mix.inputParameters = mixParams
            audioMix = mix
        }

        return EditorCompositionBuildResult(
            composition: composition,
            videoComposition: videoComposition,
            audioMix: audioMix,
            duration: CMTime(seconds: timelineExtent, preferredTimescale: timescale)
        )
    }

    private static func applyVolumeAutomation(
        to parameters: AVMutableAudioMixInputParameters,
        timeRange: CMTimeRange,
        baseVolume: Float,
        keyframes: EditorKeyframeTracks,
        fadeIn: TimeInterval = 0,
        fadeOut: TimeInterval = 0
    ) {
        let duration = max(0, timeRange.duration.seconds)
        guard duration > 0 else { return }
        let volumeTrack = keyframes.track(for: .volume)
        let hasAutomation = !volumeTrack.isEmpty || fadeIn > 0 || fadeOut > 0
        guard hasAutomation else {
            parameters.setVolume(baseVolume, at: timeRange.start)
            return
        }

        let sampleCount = min(600, max(1, Int(ceil(duration * 12))))
        func value(at localTime: TimeInterval) -> Float {
            let automated = volumeTrack.value(
                at: localTime,
                default: Double(baseVolume)
            )
            let fadeInGain = fadeIn > 0 ? min(max(localTime / fadeIn, 0), 1) : 1
            let remaining = duration - localTime
            let fadeOutGain = fadeOut > 0 ? min(max(remaining / fadeOut, 0), 1) : 1
            return Float(min(max(automated * fadeInGain * fadeOutGain, 0), 1))
        }

        for index in 0..<sampleCount {
            let startLocal = duration * Double(index) / Double(sampleCount)
            let endLocal = duration * Double(index + 1) / Double(sampleCount)
            let range = CMTimeRange(
                start: timeRange.start + CMTime(seconds: startLocal, preferredTimescale: timescale),
                duration: CMTime(seconds: endLocal - startLocal, preferredTimescale: timescale)
            )
            parameters.setVolumeRamp(
                fromStartVolume: value(at: startLocal),
                toEndVolume: value(at: endLocal),
                timeRange: range
            )
        }
    }

    private static func addTextAnimations(
        to layer: CALayer,
        overlay: EditorTextOverlay,
        totalDuration: TimeInterval,
        renderSize: CGSize
    ) {
        guard totalDuration > 0 else { return }
        let sampleCount = min(1_800, max(2, Int(ceil(totalDuration * 30))))
        var keyTimes: [NSNumber] = []
        var opacities: [NSNumber] = []
        var transforms: [NSValue] = []
        let screenScale = renderSize.width / max(UIScreen.main.bounds.width, 1)

        for index in 0...sampleCount {
            let globalTime = totalDuration * Double(index) / Double(sampleCount)
            let localTime = min(max(0, globalTime - overlay.startTime), overlay.duration)
            let visible = globalTime >= overlay.startTime && globalTime < overlay.endTime
            let opacity = visible
                ? overlay.keyframes.value(
                    for: .opacity,
                    at: localTime,
                    default: overlay.opacity
                )
                : 0
            let x = overlay.keyframes.value(
                for: .textPositionX,
                at: localTime,
                default: Double(overlay.xOffset)
            )
            let y = overlay.keyframes.value(
                for: .textPositionY,
                at: localTime,
                default: Double(overlay.yOffset)
            )
            let scale = overlay.keyframes.value(
                for: .textScale,
                at: localTime,
                default: 1
            )
            let rotation = overlay.keyframes.value(
                for: .textRotation,
                at: localTime,
                default: 0
            )
            var transform = CATransform3DMakeTranslation(
                CGFloat(x - Double(overlay.xOffset)) * screenScale,
                CGFloat(y - Double(overlay.yOffset)) * screenScale,
                0
            )
            transform = CATransform3DScale(transform, CGFloat(scale), CGFloat(scale), 1)
            transform = CATransform3DRotate(
                transform,
                CGFloat(rotation * .pi / 180),
                0,
                0,
                1
            )

            keyTimes.append(NSNumber(value: Double(index) / Double(sampleCount)))
            opacities.append(NSNumber(value: opacity))
            transforms.append(NSValue(caTransform3D: transform))
        }

        let opacityAnimation = CAKeyframeAnimation(keyPath: "opacity")
        opacityAnimation.values = opacities
        opacityAnimation.keyTimes = keyTimes
        opacityAnimation.calculationMode = .linear
        configureTextAnimation(opacityAnimation, duration: totalDuration)
        layer.add(opacityAnimation, forKey: "keyframedOpacity")

        let transformAnimation = CAKeyframeAnimation(keyPath: "transform")
        transformAnimation.values = transforms
        transformAnimation.keyTimes = keyTimes
        transformAnimation.calculationMode = .linear
        configureTextAnimation(transformAnimation, duration: totalDuration)
        layer.add(transformAnimation, forKey: "keyframedTransform")
    }

    private static func configureTextAnimation(
        _ animation: CAPropertyAnimation,
        duration: TimeInterval
    ) {
        animation.duration = duration
        animation.beginTime = AVCoreAnimationBeginTimeAtZero
        animation.isRemovedOnCompletion = false
        animation.fillMode = .forwards
    }

    /// Builds one continuous composition for the whole timeline (CapCut-style seamless preview).
    static func makePlayerItem(
        from clips: [EditorClip],
        audioClips: [EditorAudioClip] = [],
        overlayClips: [EditorOverlayClip] = [],
        openingTransitionKind: EditorTransitionKind = .none,
        openingTransitionDuration: TimeInterval = 0,
        closingTransitionKind: EditorTransitionKind = .none,
        closingTransitionDuration: TimeInterval = 0,
        canvasSettings: EditorCanvasSettings = .default
    ) async -> AVPlayerItem? {
        guard let built = await build(
            from: clips,
            audioClips: audioClips,
            overlayClips: overlayClips,
            openingTransitionKind: openingTransitionKind,
            openingTransitionDuration: openingTransitionDuration,
            closingTransitionKind: closingTransitionKind,
            closingTransitionDuration: closingTransitionDuration,
            canvasSettings: canvasSettings,
            canvasSize: canvasSettings.renderSize(longEdge: 1920)
        ) else { return nil }

        let item = await AVPlayerItem(asset: built.composition)
        await MainActor.run {
            item.audioTimePitchAlgorithm = .spectral
            item.videoComposition = built.videoComposition
            item.audioMix = built.audioMix
        }
        return item
    }

    private static func applySpeed(
        _ speed: Float,
        sourceDuration: CMTime,
        timelineDuration: CMTime,
        on track: AVMutableCompositionTrack,
        at cursor: CMTime
    ) {
        guard abs(speed - 1.0) > 0.001, sourceDuration.seconds > 0 else { return }
        let insertedRange = CMTimeRange(start: cursor, duration: sourceDuration)
        track.scaleTimeRange(insertedRange, toDuration: timelineDuration)
    }

    /// Inserts a clip as contiguous constant-rate slices sampled from the shared
    /// speed-ramp render plan. AVMutableComposition cannot express a continuous
    /// rate curve directly, so bounded slices provide deterministic smooth ramps
    /// without changing the video-composition instruction topology.
    private static func insertSpeedAdjusted(
        sourceTrack: AVAssetTrack,
        into compositionTrack: AVMutableCompositionTrack,
        sourceStart: CMTime,
        sourceDuration: CMTime,
        timelineDuration: CMTime,
        timelineStart: CMTime,
        uniformSpeed: Float,
        ramp: EditorSpeedRamp?
    ) {
        guard let ramp, ramp.isUsable else {
            let sourceRange = CMTimeRange(start: sourceStart, duration: sourceDuration)
            try? compositionTrack.insertTimeRange(sourceRange, of: sourceTrack, at: timelineStart)
            applySpeed(
                uniformSpeed,
                sourceDuration: sourceDuration,
                timelineDuration: timelineDuration,
                on: compositionTrack,
                at: timelineStart
            )
            return
        }

        let plan = ramp.renderSegments(sourceDuration: sourceDuration.seconds)
        for segment in plan {
            let segmentSourceStart = sourceStart + CMTime(
                seconds: segment.sourceStart,
                preferredTimescale: timescale
            )
            let segmentSourceDuration = CMTime(
                seconds: segment.sourceDuration,
                preferredTimescale: timescale
            )
            let segmentTimelineStart = timelineStart + CMTime(
                seconds: segment.timelineStart,
                preferredTimescale: timescale
            )
            let segmentTimelineDuration = CMTime(
                seconds: segment.timelineDuration,
                preferredTimescale: timescale
            )
            let sourceRange = CMTimeRange(
                start: segmentSourceStart,
                duration: segmentSourceDuration
            )
            try? compositionTrack.insertTimeRange(
                sourceRange,
                of: sourceTrack,
                at: segmentTimelineStart
            )
            compositionTrack.scaleTimeRange(
                CMTimeRange(start: segmentTimelineStart, duration: segmentSourceDuration),
                toDuration: segmentTimelineDuration
            )
        }
    }

    /// Extends the last video segment so instructions span the full composition (audio/text tail).
    private static func segmentsCoveringTimelineExtent(
        _ segments: [VideoSegment],
        extent: TimeInterval
    ) -> [VideoSegment] {
        guard !segments.isEmpty, extent > 0 else { return segments }
        let extentTime = CMTime(seconds: extent, preferredTimescale: timescale)
        guard let last = segments.last else { return segments }
        let lastEnd = last.timeRange.end
        guard lastEnd < extentTime else { return segments }

        let holdRange = CMTimeRange(start: lastEnd, duration: extentTime - lastEnd)
        var extended = segments
        extended.append(
            VideoSegment(
                timeRange: holdRange,
                transform: last.transform,
                colorAdjustment: last.colorAdjustment,
                animation: nil,
                transitionIn: .none,
                transitionOut: .none,
                fadeInDuration: 0,
                fadeOutDuration: 0
            )
        )
        return extended
    }

    private static func videoSegment(
        timeRange: CMTimeRange,
        transform: CGAffineTransform,
        clipIndex: Int,
        clips: [EditorClip],
        openingTransitionKind: EditorTransitionKind,
        openingTransitionDuration: TimeInterval,
        closingTransitionKind: EditorTransitionKind,
        closingTransitionDuration: TimeInterval
    ) -> VideoSegment {
        let duration = max(0, timeRange.duration.seconds)
        let isLastClip = clipIndex == clips.count - 1
        let requestedFadeIn = clipIndex > 0
            ? clips[clipIndex - 1].transitionDuration
            : openingTransitionDuration
        let requestedFadeOut = isLastClip
            ? closingTransitionDuration
            : clips[clipIndex].transitionDuration
        let transitionIn = clipIndex > 0
            ? clips[clipIndex - 1].transitionKind
            : openingTransitionKind
        let transitionOut = isLastClip
            ? closingTransitionKind
            : clips[clipIndex].transitionKind
        return VideoSegment(
            timeRange: timeRange,
            transform: transform,
            colorAdjustment: clips[clipIndex].colorAdjustment,
            animation: renderAnimation(for: clips[clipIndex]),
            transitionIn: transitionIn,
            transitionOut: transitionOut,
            fadeInDuration: clipIndex == 0
                ? min(max(0, requestedFadeIn), duration)
                : min(max(0, requestedFadeIn / 2), duration / 2),
            fadeOutDuration: isLastClip
                ? min(max(0, requestedFadeOut), duration)
                : min(max(0, requestedFadeOut / 2), duration / 2)
        )
    }

    // MARK: - Video composition (orientation + aspect fit)

    private static func makeVideoComposition(
        compositionTrack: AVMutableCompositionTrack,
        backgroundTracks: BackgroundVideoTracks,
        segments: [VideoSegment],
        overlaySegments: [OverlayVideoSegment],
        frameRate: Int32,
        renderSize: CGSize,
        canvasSettings: EditorCanvasSettings,
        animationTool: AVVideoCompositionCoreAnimationTool? = nil
    ) -> AVVideoComposition {
        let frameDuration = CMTime(value: 1, timescale: frameRate)

        let composition = AVMutableVideoComposition()
        composition.renderSize = renderSize
        composition.frameDuration = frameDuration
        composition.animationTool = animationTool

        let needsGPUCompositor = segments.contains {
            !$0.colorAdjustment.isNeutral
                || $0.transitionIn.usesGPUCompositor
                || $0.transitionOut.usesGPUCompositor
                || $0.animation?.hasVisualAnimation == true
        } || overlaySegments.contains {
            !$0.colorAdjustment.isNeutral || $0.animation?.hasVisualAnimation == true
        } || canvasSettings.backgroundKind == .blur
        if needsGPUCompositor {
            composition.customVideoCompositorClass = EditorTransitionCompositor.self
            composition.instructions = segments.map { segment in
                let usesWhiteBackground = usesWhiteCanvas(segment.transitionIn)
                    || usesWhiteCanvas(segment.transitionOut)
                let backgroundTrack = usesWhiteBackground
                    ? (backgroundTracks.white ?? backgroundTracks.black)
                    : backgroundTracks.black

                return EditorTransitionRenderInstruction(
                    timeRange: segment.timeRange,
                    foregroundTrackID: compositionTrack.trackID,
                    backgroundTrackID: backgroundTrack?.trackID,
                    overlayLayers: overlaySegments.map {
                        EditorOverlayRenderLayer(
                            trackID: $0.track.trackID,
                            timeRange: $0.timeRange,
                            transform: $0.transform,
                            opacity: $0.opacity,
                            colorAdjustment: $0.colorAdjustment,
                            animation: $0.animation
                        )
                    },
                    baseTransform: segment.transform,
                    animation: segment.animation,
                    colorAdjustment: segment.colorAdjustment,
                    incomingKind: segment.transitionIn,
                    outgoingKind: segment.transitionOut,
                    incomingDuration: segment.fadeInDuration,
                    outgoingDuration: segment.fadeOutDuration,
                    incomingMotion: transitionMotionCurve(
                        for: segment.transitionIn,
                        base: segment.transform,
                        renderSize: renderSize,
                        entering: true
                    ),
                    outgoingMotion: transitionMotionCurve(
                        for: segment.transitionOut,
                        base: segment.transform,
                        renderSize: renderSize,
                        entering: false
                    ),
                    renderSize: renderSize,
                    canvasBackgroundKind: canvasSettings.backgroundKind,
                    enablePostProcessing: animationTool != nil
                )
            }
            return composition
        }

        composition.instructions = segments.map { segment in
            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = segment.timeRange
            let usesWhiteBackground = usesWhiteCanvas(segment.transitionIn)
                || usesWhiteCanvas(segment.transitionOut)
            instruction.backgroundColor = (usesWhiteBackground ? UIColor.white : UIColor.black).cgColor
            instruction.enablePostProcessing = (animationTool != nil)

            let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionTrack)
            layer.setTransform(segment.transform, at: segment.timeRange.start)

            if segment.fadeInDuration > 0 {
                applyTransition(
                    segment.transitionIn,
                    to: layer,
                    base: segment.transform,
                    renderSize: renderSize,
                    timeRange: CMTimeRange(
                        start: segment.timeRange.start,
                        duration: CMTime(
                            seconds: segment.fadeInDuration,
                            preferredTimescale: timescale
                        )
                    ),
                    entering: true
                )
            }
            if segment.fadeOutDuration > 0 {
                let fadeStart = segment.timeRange.end
                    - CMTime(seconds: segment.fadeOutDuration, preferredTimescale: timescale)
                applyTransition(
                    segment.transitionOut,
                    to: layer,
                    base: segment.transform,
                    renderSize: renderSize,
                    timeRange: CMTimeRange(
                        start: fadeStart,
                        duration: CMTime(
                            seconds: segment.fadeOutDuration,
                            preferredTimescale: timescale
                        )
                    ),
                    entering: false
                )
            }

            var layerInstructions: [AVVideoCompositionLayerInstruction] = overlaySegments
                .reversed()
                .filter {
                    CMTimeRangeGetIntersection(
                        $0.timeRange,
                        otherRange: segment.timeRange
                    ).duration > .zero
                }
                .map { overlay in
                    let overlayLayer = AVMutableVideoCompositionLayerInstruction(
                        assetTrack: overlay.track
                    )
                    let activeStart = max(overlay.timeRange.start, segment.timeRange.start)
                    overlayLayer.setTransform(overlay.transform, at: activeStart)
                    overlayLayer.setOpacity(overlay.opacity, at: activeStart)
                    return overlayLayer
                }
            layerInstructions.append(layer)
            let backgroundTrack = usesWhiteBackground
                ? (backgroundTracks.white ?? backgroundTracks.black)
                : backgroundTracks.black
            if let backgroundTrack {
                let backgroundLayer = AVMutableVideoCompositionLayerInstruction(
                    assetTrack: backgroundTrack
                )
                backgroundLayer.setTransform(.identity, at: segment.timeRange.start)
                layerInstructions.append(backgroundLayer)
            }
            instruction.layerInstructions = layerInstructions
            return instruction
        }

        return composition
    }

    private static func overlayTransform(
        base: CGAffineTransform,
        clip: EditorOverlayClip,
        renderSize: CGSize
    ) -> CGAffineTransform {
        let scale = min(max(clip.scale, 0.15), 1.5)
        let destinationTransform = CGAffineTransform(
            a: scale,
            b: 0,
            c: 0,
            d: scale,
            tx: (1 - scale) * renderSize.width / 2 + clip.xOffset * renderSize.width,
            ty: (1 - scale) * renderSize.height / 2 + clip.yOffset * renderSize.height
        )
        return base.concatenating(destinationTransform)
    }

    private static func renderAnimation(for clip: EditorClip) -> EditorRenderKeyframeAnimation? {
        guard !clip.keyframes.isEmpty else { return nil }
        return EditorRenderKeyframeAnimation(
            tracks: clip.keyframes,
            basePositionX: Double(clip.reframeXOffset),
            basePositionY: Double(clip.reframeYOffset),
            baseScale: Double(clip.reframeScale),
            baseRotation: clip.straightenDegrees,
            baseOpacity: 1,
            baseFilterIntensity: clip.colorAdjustment.presetIntensity,
            baseCropX: Double(clip.reframeXOffset),
            baseCropY: Double(clip.reframeYOffset),
            baseCropScale: Double(clip.reframeScale)
        )
    }

    private static func renderAnimation(
        for clip: EditorOverlayClip
    ) -> EditorRenderKeyframeAnimation? {
        guard !clip.keyframes.isEmpty else { return nil }
        return EditorRenderKeyframeAnimation(
            tracks: clip.keyframes,
            basePositionX: Double(clip.xOffset),
            basePositionY: Double(clip.yOffset),
            baseScale: Double(clip.scale),
            baseRotation: clip.straightenDegrees,
            baseOpacity: clip.opacity,
            baseFilterIntensity: clip.colorAdjustment.presetIntensity,
            baseCropX: Double(clip.reframeXOffset),
            baseCropY: Double(clip.reframeYOffset),
            baseCropScale: Double(clip.reframeScale)
        )
    }

    private static func transitionMotionCurve(
        for kind: EditorTransitionKind,
        base: CGAffineTransform,
        renderSize: CGSize,
        entering: Bool
    ) -> EditorTransitionMotionCurve? {
        let effect = transitionTransform(
            for: kind,
            base: base,
            renderSize: renderSize,
            entering: entering
        )
        let start = entering ? effect : base
        let end = entering ? base : effect
        let overshoot = transitionOvershootTransform(
            for: kind,
            base: base,
            renderSize: renderSize,
            entering: entering
        )
        guard start != end || overshoot != nil else { return nil }
        return EditorTransitionMotionCurve(start: start, overshoot: overshoot, end: end)
    }

    private static func applyTransition(
        _ kind: EditorTransitionKind,
        to layer: AVMutableVideoCompositionLayerInstruction,
        base: CGAffineTransform,
        renderSize: CGSize,
        timeRange: CMTimeRange,
        entering: Bool
    ) {
        let effectTransform = transitionTransform(
            for: kind,
            base: base,
            renderSize: renderSize,
            entering: entering
        )
        let firstTransform = entering ? effectTransform : base
        let lastTransform = entering ? base : effectTransform

        if let middleTransform = transitionOvershootTransform(
            for: kind,
            base: base,
            renderSize: renderSize,
            entering: entering
        ) {
            let firstDuration = CMTimeMultiplyByFloat64(
                timeRange.duration,
                multiplier: 0.68
            )
            let secondRange = CMTimeRange(
                start: timeRange.start + firstDuration,
                duration: timeRange.duration - firstDuration
            )
            layer.setTransformRamp(
                fromStart: firstTransform,
                toEnd: middleTransform,
                timeRange: CMTimeRange(start: timeRange.start, duration: firstDuration)
            )
            layer.setTransformRamp(
                fromStart: middleTransform,
                toEnd: lastTransform,
                timeRange: secondRange
            )
        } else if firstTransform != lastTransform {
            layer.setTransformRamp(
                fromStart: firstTransform,
                toEnd: lastTransform,
                timeRange: timeRange
            )
        }

        applyTransitionOpacity(kind, to: layer, timeRange: timeRange, entering: entering)
    }

    private static func applyTransitionOpacity(
        _ kind: EditorTransitionKind,
        to layer: AVMutableVideoCompositionLayerInstruction,
        timeRange: CMTimeRange,
        entering: Bool
    ) {
        switch kind {
        case .pushLeft, .pushRight, .pushUp, .pushDown:
            layer.setOpacity(1, at: timeRange.start)
        case .strobe:
            let firstDuration = CMTimeMultiplyByFloat64(timeRange.duration, multiplier: 0.34)
            let secondDuration = CMTimeMultiplyByFloat64(timeRange.duration, multiplier: 0.28)
            let firstEnd = timeRange.start + firstDuration
            let secondEnd = firstEnd + secondDuration
            if entering {
                layer.setOpacityRamp(
                    fromStartOpacity: 0,
                    toEndOpacity: 1,
                    timeRange: CMTimeRange(start: timeRange.start, duration: firstDuration)
                )
                layer.setOpacityRamp(
                    fromStartOpacity: 1,
                    toEndOpacity: 0.18,
                    timeRange: CMTimeRange(start: firstEnd, duration: secondDuration)
                )
                layer.setOpacityRamp(
                    fromStartOpacity: 0.18,
                    toEndOpacity: 1,
                    timeRange: CMTimeRange(
                        start: secondEnd,
                        duration: timeRange.end - secondEnd
                    )
                )
            } else {
                layer.setOpacityRamp(
                    fromStartOpacity: 1,
                    toEndOpacity: 0.18,
                    timeRange: CMTimeRange(start: timeRange.start, duration: firstDuration)
                )
                layer.setOpacityRamp(
                    fromStartOpacity: 0.18,
                    toEndOpacity: 1,
                    timeRange: CMTimeRange(start: firstEnd, duration: secondDuration)
                )
                layer.setOpacityRamp(
                    fromStartOpacity: 1,
                    toEndOpacity: 0,
                    timeRange: CMTimeRange(
                        start: secondEnd,
                        duration: timeRange.end - secondEnd
                    )
                )
            }
        default:
            layer.setOpacityRamp(
                fromStartOpacity: entering ? 0 : 1,
                toEndOpacity: entering ? 1 : 0,
                timeRange: timeRange
            )
        }
    }

    private static func transitionOvershootTransform(
        for kind: EditorTransitionKind,
        base: CGAffineTransform,
        renderSize: CGSize,
        entering: Bool
    ) -> CGAffineTransform? {
        let direction: CGFloat = entering ? -1 : 1
        switch kind {
        case .snapBack:
            return base.concatenating(CGAffineTransform(scaleX: 1.12, y: 1.12))
        case .diveAndBounce:
            return base
                .concatenating(CGAffineTransform(scaleX: 1.08, y: 1.08))
                .concatenating(
                    CGAffineTransform(
                        translationX: 0,
                        y: direction * renderSize.height * 0.08
                    )
                )
        case .dofWiggle, .cameraShake:
            return base
                .concatenating(CGAffineTransform(scaleX: 1.06, y: 1.06))
                .concatenating(CGAffineTransform(rotationAngle: -direction * 0.055))
                .concatenating(
                    CGAffineTransform(
                        translationX: -direction * renderSize.width * 0.06,
                        y: direction * renderSize.height * 0.025
                    )
                )
        case .elasticLeft, .elasticRight:
            return base.concatenating(CGAffineTransform(scaleX: 0.88, y: 1.08))
        case .swingLeft, .swingRight:
            let angle: CGFloat = kind == .swingLeft ? -0.08 : 0.08
            return base
                .concatenating(CGAffineTransform(scaleX: 1.04, y: 1.04))
                .concatenating(CGAffineTransform(rotationAngle: angle * direction))
        case .bounceIn, .bounceOut:
            return base.concatenating(CGAffineTransform(scaleX: 1.10, y: 1.10))
        case .compressLeft, .compressRight:
            return base.concatenating(CGAffineTransform(scaleX: 1.12, y: 0.96))
        default:
            return nil
        }
    }

    private static func usesWhiteCanvas(_ kind: EditorTransitionKind) -> Bool {
        switch kind {
        case .dipToWhite, .blink, .flash, .flashZoom, .glare, .strobe, .lightSweep:
            return true
        default:
            return false
        }
    }

    private static func makeBackgroundVideoTracks(
        in composition: AVMutableComposition,
        duration: CMTime,
        renderSize: CGSize,
        canvasSettings: EditorCanvasSettings,
        needsWhite: Bool
    ) async -> BackgroundVideoTracks {
        guard duration.seconds > 0 else {
            return BackgroundVideoTracks(black: nil, white: nil)
        }

        let primaryColor = UIColor(
            red: CGFloat((canvasSettings.backgroundColorRGB >> 16) & 0xff) / 255,
            green: CGFloat((canvasSettings.backgroundColorRGB >> 8) & 0xff) / 255,
            blue: CGFloat(canvasSettings.backgroundColorRGB & 0xff) / 255,
            alpha: 1
        )
        let primary: AVMutableCompositionTrack?
        if canvasSettings.backgroundKind == .image,
           let path = canvasSettings.backgroundImagePath {
            primary = await insertCanvasImageTrack(
                path: path, in: composition, duration: duration, renderSize: renderSize
            )
        } else {
            primary = await insertSolidVideoTrack(
                color: primaryColor,
                colorKey: String(format: "canvas-%06x", canvasSettings.backgroundColorRGB),
                in: composition,
                duration: duration,
                renderSize: renderSize
            )
        }
        let white: AVMutableCompositionTrack?
        if needsWhite {
            white = await insertSolidVideoTrack(
                color: .white,
                colorKey: "white",
                in: composition,
                duration: duration,
                renderSize: renderSize
            )
        } else {
            white = nil
        }
        return BackgroundVideoTracks(black: primary, white: white)
    }

    private static func insertSolidVideoTrack(
        color: UIColor,
        colorKey: String,
        in composition: AVMutableComposition,
        duration: CMTime,
        renderSize: CGSize
    ) async -> AVMutableCompositionTrack? {
        guard
            let url = await solidVideoURL(color: color, colorKey: colorKey, renderSize: renderSize),
            let track = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
        else { return nil }

        let asset = AVURLAsset(url: url)
        guard
            let sourceTrack = try? await asset.loadTracks(withMediaType: .video).first,
            let sourceDuration = try? await asset.load(.duration),
            sourceDuration.seconds > 0
        else { return nil }

        let sourceRange = CMTimeRange(start: .zero, duration: sourceDuration)
        do {
            try track.insertTimeRange(sourceRange, of: sourceTrack, at: .zero)
            track.scaleTimeRange(sourceRange, toDuration: duration)
            return track
        } catch {
            composition.removeTrack(track)
            return nil
        }
    }

    private static func insertCanvasImageTrack(
        path: String,
        in composition: AVMutableComposition,
        duration: CMTime,
        renderSize: CGSize
    ) async -> AVMutableCompositionTrack? {
        guard let image = UIImage(contentsOfFile: path),
              let url = await canvasImageVideoURL(image: image, path: path, renderSize: renderSize),
              let track = composition.addMutableTrack(
                withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid
              ) else { return nil }
        let asset = AVURLAsset(url: url)
        guard let source = try? await asset.loadTracks(withMediaType: .video).first,
              let sourceDuration = try? await asset.load(.duration) else { return nil }
        let range = CMTimeRange(start: .zero, duration: sourceDuration)
        do {
            try track.insertTimeRange(range, of: source, at: .zero)
            track.scaleTimeRange(range, toDuration: duration)
            return track
        } catch {
            composition.removeTrack(track)
            return nil
        }
    }

    private static func transitionTransform(
        for kind: EditorTransitionKind,
        base: CGAffineTransform,
        renderSize: CGSize,
        entering: Bool
    ) -> CGAffineTransform {
        switch kind {
        case .zoomIn:
            let scale: CGFloat = entering ? 1.35 : 0.72
            return base.concatenating(CGAffineTransform(scaleX: scale, y: scale))
        case .zoomOut:
            let scale: CGFloat = entering ? 0.68 : 1.42
            return base.concatenating(CGAffineTransform(scaleX: scale, y: scale))
        case .shrink:
            return base.concatenating(CGAffineTransform(scaleX: 0.35, y: 0.35))
        case .expand:
            return base.concatenating(CGAffineTransform(scaleX: 1.65, y: 1.65))
        case .flashZoom, .glare:
            let scale: CGFloat = entering ? 1.5 : 0.65
            return base.concatenating(CGAffineTransform(scaleX: scale, y: scale))
        case .snapBack:
            let scale: CGFloat = entering ? 0.48 : 1.55
            return base
                .concatenating(CGAffineTransform(scaleX: scale, y: scale))
                .concatenating(
                    CGAffineTransform(
                        translationX: entering ? -renderSize.width * 0.08 : renderSize.width * 0.08,
                        y: 0
                    )
                )
        case .clapAndPull:
            let horizontalScale: CGFloat = entering ? 0.15 : 1.8
            return base.concatenating(
                CGAffineTransform(scaleX: horizontalScale, y: 1.12)
            )
        case .diveAndBounce:
            return base
                .concatenating(CGAffineTransform(scaleX: 0.72, y: 0.72))
                .concatenating(
                    CGAffineTransform(
                        translationX: 0,
                        y: entering ? renderSize.height * 0.45 : -renderSize.height * 0.45
                    )
                )
        case .dofWiggle:
            let direction: CGFloat = entering ? -1 : 1
            return base
                .concatenating(CGAffineTransform(scaleX: 1.16, y: 1.16))
                .concatenating(CGAffineTransform(rotationAngle: direction * 0.12))
                .concatenating(
                    CGAffineTransform(
                        translationX: direction * renderSize.width * 0.14,
                        y: -direction * renderSize.height * 0.05
                    )
                )
        case .tiltLeft:
            return base
                .concatenating(CGAffineTransform(scaleX: 1.18, y: 1.18))
                .concatenating(CGAffineTransform(rotationAngle: entering ? 0.20 : -0.20))
        case .tiltRight:
            return base
                .concatenating(CGAffineTransform(scaleX: 1.18, y: 1.18))
                .concatenating(CGAffineTransform(rotationAngle: entering ? -0.20 : 0.20))
        case .swingLeft, .swingRight:
            let side: CGFloat = kind == .swingLeft ? -1 : 1
            let direction: CGFloat = entering ? -1 : 1
            return base
                .concatenating(CGAffineTransform(scaleX: 1.12, y: 1.12))
                .concatenating(CGAffineTransform(rotationAngle: side * direction * 0.32))
                .concatenating(
                    CGAffineTransform(
                        translationX: side * direction * renderSize.width * 0.35,
                        y: renderSize.height * 0.08
                    )
                )
        case .orbitLeft, .orbitRight:
            let side: CGFloat = kind == .orbitLeft ? -1 : 1
            let direction: CGFloat = entering ? -1 : 1
            return base
                .concatenating(CGAffineTransform(scaleX: 0.52, y: 0.52))
                .concatenating(CGAffineTransform(rotationAngle: side * direction * .pi * 0.85))
                .concatenating(
                    CGAffineTransform(
                        translationX: side * direction * renderSize.width * 0.52,
                        y: renderSize.height * 0.2
                    )
                )
        case .flipZoomIn:
            let scale: CGFloat = entering ? 0.38 : 1.5
            return base.concatenating(CGAffineTransform(scaleX: 0.05, y: scale))
        case .flipZoomOut:
            let scale: CGFloat = entering ? 1.5 : 0.38
            return base.concatenating(CGAffineTransform(scaleX: scale, y: 0.05))
        case .bounceIn:
            return base
                .concatenating(CGAffineTransform(scaleX: 0.42, y: 0.42))
                .concatenating(
                    CGAffineTransform(
                        translationX: 0,
                        y: entering ? renderSize.height * 0.5 : -renderSize.height * 0.5
                    )
                )
        case .bounceOut:
            return base
                .concatenating(CGAffineTransform(scaleX: 1.55, y: 1.55))
                .concatenating(
                    CGAffineTransform(
                        translationX: 0,
                        y: entering ? -renderSize.height * 0.34 : renderSize.height * 0.34
                    )
                )
        case .slideLeft:
            let x = entering ? renderSize.width : -renderSize.width
            return base.concatenating(CGAffineTransform(translationX: x, y: 0))
        case .slideRight:
            let x = entering ? -renderSize.width : renderSize.width
            return base.concatenating(CGAffineTransform(translationX: x, y: 0))
        case .slideUp:
            let y = entering ? renderSize.height : -renderSize.height
            return base.concatenating(CGAffineTransform(translationX: 0, y: y))
        case .slideDown:
            let y = entering ? -renderSize.height : renderSize.height
            return base.concatenating(CGAffineTransform(translationX: 0, y: y))
        case .pushLeft:
            let x = entering ? renderSize.width * 0.78 : -renderSize.width * 0.78
            return base.concatenating(CGAffineTransform(translationX: x, y: 0))
        case .pushRight:
            let x = entering ? -renderSize.width * 0.78 : renderSize.width * 0.78
            return base.concatenating(CGAffineTransform(translationX: x, y: 0))
        case .pushUp:
            let y = entering ? renderSize.height * 0.78 : -renderSize.height * 0.78
            return base.concatenating(CGAffineTransform(translationX: 0, y: y))
        case .pushDown:
            let y = entering ? -renderSize.height * 0.78 : renderSize.height * 0.78
            return base.concatenating(CGAffineTransform(translationX: 0, y: y))
        case .driftLeft:
            let x = entering ? renderSize.width * 0.32 : -renderSize.width * 0.32
            return base
                .concatenating(CGAffineTransform(scaleX: 1.08, y: 1.08))
                .concatenating(CGAffineTransform(translationX: x, y: 0))
        case .driftRight:
            let x = entering ? -renderSize.width * 0.32 : renderSize.width * 0.32
            return base
                .concatenating(CGAffineTransform(scaleX: 1.08, y: 1.08))
                .concatenating(CGAffineTransform(translationX: x, y: 0))
        case .diagonalUpLeft:
            let direction: CGFloat = entering ? 1 : -1
            return base.concatenating(
                CGAffineTransform(
                    translationX: direction * renderSize.width,
                    y: direction * renderSize.height
                )
            )
        case .diagonalUpRight:
            let direction: CGFloat = entering ? -1 : 1
            return base.concatenating(
                CGAffineTransform(
                    translationX: direction * renderSize.width,
                    y: -direction * renderSize.height
                )
            )
        case .diagonalDownLeft:
            let direction: CGFloat = entering ? 1 : -1
            return base.concatenating(
                CGAffineTransform(
                    translationX: direction * renderSize.width,
                    y: -direction * renderSize.height
                )
            )
        case .diagonalDownRight:
            let direction: CGFloat = entering ? -1 : 1
            return base.concatenating(
                CGAffineTransform(
                    translationX: direction * renderSize.width,
                    y: direction * renderSize.height
                )
            )
        case .whipLeft:
            let x = (entering ? 1.35 : -1.35) * renderSize.width
            return base
                .concatenating(CGAffineTransform(scaleX: 1.12, y: 0.92))
                .concatenating(CGAffineTransform(translationX: x, y: 0))
        case .whipRight:
            let x = (entering ? -1.35 : 1.35) * renderSize.width
            return base
                .concatenating(CGAffineTransform(scaleX: 1.12, y: 0.92))
                .concatenating(CGAffineTransform(translationX: x, y: 0))
        case .elasticLeft:
            let x = (entering ? 0.72 : -0.72) * renderSize.width
            return base
                .concatenating(CGAffineTransform(scaleX: 1.32, y: 0.88))
                .concatenating(CGAffineTransform(translationX: x, y: 0))
        case .elasticRight:
            let x = (entering ? -0.72 : 0.72) * renderSize.width
            return base
                .concatenating(CGAffineTransform(scaleX: 1.32, y: 0.88))
                .concatenating(CGAffineTransform(translationX: x, y: 0))
        case .compressLeft, .compressRight:
            let side: CGFloat = kind == .compressLeft ? -1 : 1
            let direction: CGFloat = entering ? -1 : 1
            return base
                .concatenating(CGAffineTransform(scaleX: 0.24, y: 1.08))
                .concatenating(
                    CGAffineTransform(
                        translationX: side * direction * renderSize.width * 0.62,
                        y: 0
                    )
                )
        case .stretchUp, .stretchDown:
            let side: CGFloat = kind == .stretchUp ? -1 : 1
            let direction: CGFloat = entering ? -1 : 1
            return base
                .concatenating(CGAffineTransform(scaleX: 0.82, y: 1.85))
                .concatenating(
                    CGAffineTransform(
                        translationX: 0,
                        y: side * direction * renderSize.height * 0.42
                    )
                )
        case .panLeftZoom, .panRightZoom:
            let side: CGFloat = kind == .panLeftZoom ? -1 : 1
            let direction: CGFloat = entering ? -1 : 1
            return base
                .concatenating(CGAffineTransform(scaleX: 1.48, y: 1.48))
                .concatenating(
                    CGAffineTransform(
                        translationX: side * direction * renderSize.width * 0.38,
                        y: renderSize.height * 0.06
                    )
                )
        case .skewLeft, .skewRight:
            let side: CGFloat = kind == .skewLeft ? -1 : 1
            let direction: CGFloat = entering ? -1 : 1
            return base
                .concatenating(
                    CGAffineTransform(
                        a: 1,
                        b: 0,
                        c: side * direction * 0.42,
                        d: 1,
                        tx: side * direction * renderSize.width * 0.34,
                        ty: 0
                    )
                )
        case .spinLeft:
            let angle: CGFloat = entering ? .pi / 2 : -.pi / 2
            return base.concatenating(CGAffineTransform(rotationAngle: angle))
        case .spinRight:
            let angle: CGFloat = entering ? -.pi / 2 : .pi / 2
            return base.concatenating(CGAffineTransform(rotationAngle: angle))
        case .spinZoom:
            let angle: CGFloat = entering ? -.pi * 0.75 : .pi * 0.75
            return base
                .concatenating(CGAffineTransform(scaleX: 0.45, y: 0.45))
                .concatenating(CGAffineTransform(rotationAngle: angle))
        case .rollLeft:
            let angle: CGFloat = entering ? .pi : -.pi
            return base
                .concatenating(CGAffineTransform(scaleX: 0.58, y: 0.58))
                .concatenating(CGAffineTransform(rotationAngle: angle))
        case .rollRight:
            let angle: CGFloat = entering ? -.pi : .pi
            return base
                .concatenating(CGAffineTransform(scaleX: 0.58, y: 0.58))
                .concatenating(CGAffineTransform(rotationAngle: angle))
        case .flipHorizontal:
            return base.concatenating(CGAffineTransform(scaleX: 0.04, y: 1))
        case .flipVertical:
            return base.concatenating(CGAffineTransform(scaleX: 1, y: 0.04))
        case .squeezeHorizontal:
            return base.concatenating(CGAffineTransform(scaleX: 0.12, y: 1.18))
        case .squeezeVertical:
            return base.concatenating(CGAffineTransform(scaleX: 1.18, y: 0.12))
        case .stretchLeft:
            return base
                .concatenating(CGAffineTransform(scaleX: 1.75, y: 0.72))
                .concatenating(
                    CGAffineTransform(
                        translationX: entering ? renderSize.width * 0.48 : -renderSize.width * 0.48,
                        y: 0
                    )
                )
        case .stretchRight:
            return base
                .concatenating(CGAffineTransform(scaleX: 1.75, y: 0.72))
                .concatenating(
                    CGAffineTransform(
                        translationX: entering ? -renderSize.width * 0.48 : renderSize.width * 0.48,
                        y: 0
                    )
                )
        case .dragSwitch:
            let direction: CGFloat = entering ? -1 : 1
            return base
                .concatenating(CGAffineTransform(scaleX: 0.72, y: 1.22))
                .concatenating(CGAffineTransform(rotationAngle: direction * 0.08))
                .concatenating(
                    CGAffineTransform(
                        translationX: direction * renderSize.width * 0.65,
                        y: renderSize.height * 0.08
                    )
                )
        case .cameraShake:
            let direction: CGFloat = entering ? -1 : 1
            return base
                .concatenating(CGAffineTransform(rotationAngle: direction * 0.08))
                .concatenating(
                    CGAffineTransform(
                        translationX: direction * renderSize.width * 0.12,
                        y: renderSize.height * 0.04
                    )
                )
        case .fadeLift:
            let y = entering ? renderSize.height * 0.22 : -renderSize.height * 0.22
            return base.concatenating(CGAffineTransform(translationX: 0, y: y))
        case .fadeDrop:
            let y = entering ? -renderSize.height * 0.22 : renderSize.height * 0.22
            return base.concatenating(CGAffineTransform(translationX: 0, y: y))
        case .lightSweep:
            let x = entering ? renderSize.width * 0.28 : -renderSize.width * 0.28
            return base
                .concatenating(CGAffineTransform(scaleX: 1.08, y: 1.08))
                .concatenating(CGAffineTransform(translationX: x, y: 0))
        case .none, .fade, .mix, .dipToBlack, .dipToWhite, .blink,
             .flash, .strobe, .motionBlurLeft, .motionBlurRight,
             .motionBlurUp, .motionBlurDown, .zoomBlur, .gaussianBlur,
             .radialBlur, .pixelDissolve, .crystallize, .rgbSplit, .glitch,
             .ripple, .fisheye, .kaleidoscope, .bumpPulse, .pinchPulse,
             .vortexLeft, .vortexRight, .glassWarp, .triangleMirror,
             .torusLens, .comicFlash, .bloom, .vignettePulse, .hueSpin,
             .colorInvert, .posterize, .noirFlash, .sepiaFlash, .chromeFlash,
             .processFlash, .falseColor, .edgeGlow, .circleReveal, .radialWipe:
            return base
        }
    }

    /// Applies `preferredTransform` and scales the track into `renderSize` without stretching.
    private static func aspectFitTransform(for track: AVAssetTrack, renderSize: CGSize) async -> CGAffineTransform {
        let naturalSize = (try? await track.load(.naturalSize)) ?? .zero
        let preferred = (try? await track.load(.preferredTransform)) ?? .identity

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

    /// Builds the persistent per-clip crop/reframe transform used by both preview and export.
    private static func reframeTransform(
        for track: AVAssetTrack,
        clip: EditorClip,
        renderSize: CGSize
    ) async -> CGAffineTransform {
        let naturalSize = (try? await track.load(.naturalSize)) ?? .zero
        let preferred = (try? await track.load(.preferredTransform)) ?? .identity
        let orientedRect = CGRect(origin: .zero, size: naturalSize).applying(preferred)
        let sourceWidth = abs(orientedRect.width)
        let sourceHeight = abs(orientedRect.height)
        guard sourceWidth > 0, sourceHeight > 0 else { return preferred }

        var framingWidth = sourceWidth
        var framingHeight = sourceHeight
        if let ratio = clip.cropAspect.ratio {
            let sourceRatio = sourceWidth / sourceHeight
            if sourceRatio > ratio {
                framingWidth = sourceHeight * ratio
            } else {
                framingHeight = sourceWidth / ratio
            }
        }

        let horizontalCrop = (sourceWidth - framingWidth) / 2
        let verticalCrop = (sourceHeight - framingHeight) / 2
        let widthScale = renderSize.width / framingWidth
        let heightScale = renderSize.height / framingHeight
        let framingScale = clip.reframeMode == .fill
            ? max(widthScale, heightScale)
            : min(widthScale, heightScale)

        let scaledWidth = framingWidth * framingScale
        let scaledHeight = framingHeight * framingScale
        let tx = (renderSize.width - scaledWidth) / 2
            - (orientedRect.origin.x + horizontalCrop) * framingScale
        let ty = (renderSize.height - scaledHeight) / 2
            - (orientedRect.origin.y + verticalCrop) * framingScale

        var base = preferred.concatenating(
            CGAffineTransform(scaleX: framingScale, y: framingScale)
        )
        base = base.concatenating(CGAffineTransform(translationX: tx, y: ty))

        let radians = (
            Double(clip.rotationQuarterTurns) * 90 + clip.straightenDegrees
        ) * .pi / 180
        let horizontalFlip: CGFloat = clip.isFlippedHorizontally ? -1 : 1
        let verticalFlip: CGFloat = clip.isFlippedVertically ? -1 : 1
        let scaleX = clip.reframeScale * horizontalFlip
        let scaleY = clip.reframeScale * verticalFlip
        let cosine = CGFloat(cos(radians))
        let sine = CGFloat(sin(radians))
        let a = cosine * scaleX
        let b = sine * scaleX
        let c = -sine * scaleY
        let d = cosine * scaleY
        let center = CGPoint(x: renderSize.width / 2, y: renderSize.height / 2)
        let destinationCenter = CGPoint(
            x: center.x + clip.reframeXOffset * renderSize.width,
            y: center.y + clip.reframeYOffset * renderSize.height
        )
        let adjustment = CGAffineTransform(
            a: a,
            b: b,
            c: c,
            d: d,
            tx: destinationCenter.x - a * center.x - c * center.y,
            ty: destinationCenter.y - b * center.x - d * center.y
        )
        return base.concatenating(adjustment)
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

    private static func solidVideoURL(
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

    private static func canvasImageVideoURL(
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
        solidVideoCache.removeAll()
        warmedPlayerItem = nil
        warmedFingerprint = nil
    }
}
