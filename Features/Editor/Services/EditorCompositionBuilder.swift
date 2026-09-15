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

    static let timescale: CMTimeScale = 600
    /// Portrait canvas matching `EditorPreviewLayout` (9:16).
    static let previewCanvasSize = CGSize(width: 1080, height: 1920)
    static var assetCache: [String: AVAsset] = [:]
    static var photoVideoCache: [String: URL] = [:]
    static var freezeVideoCache: [String: URL] = [:]
    static var solidVideoCache: [String: URL] = [:]
    static var canvasImageVideoCache: [String: URL] = [:]
    static var warmedPlayerItem: AVPlayerItem?
    static var warmedFingerprint: String?

    /// Stable key for matching a warmed composition to a freshly built clip list (IDs differ per init).
    static func timelineFingerprint(for clips: [EditorClip]) -> String {
        clips.map { clip in
            "\(clip.asset.localIdentifier)|\(clip.trimStart)|\(clip.trimEnd)|\(clip.speed)|\(String(describing: clip.speedRamp))|\(clip.playback)|\(clip.audioTrimStart ?? -1)|\(clip.audioTrimEnd ?? -1)|\(clip.isAudioLinked)|\(clip.cropAspect.rawValue)|\(clip.reframeMode.rawValue)|\(clip.rotationQuarterTurns)|\(clip.straightenDegrees)|\(clip.isFlippedHorizontally)|\(clip.isFlippedVertically)|\(clip.reframeScale)|\(clip.reframeXOffset)|\(clip.reframeYOffset)|\(clip.colorAdjustment)|\(clip.effects)|\(clip.compositing)|\(clip.keyframes)|\(clip.motionTracks)|\(clip.stabilization)|\(clip.transitionKind.rawValue)|\(clip.transitionDuration)|\(clip.duration)"
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
        let keyframeTimeOffset: TimeInterval
    }

    struct VideoSegment {
        let timeRange: CMTimeRange
        let transform: CGAffineTransform
        let colorAdjustment: EditorColorAdjustment
        let effects: [EditorVisualEffect]
        let compositing: EditorOverlayCompositing
        let animation: EditorRenderKeyframeAnimation?
        let stabilization: EditorRenderStabilization?
        let transitionIn: EditorTransitionKind
        let transitionOut: EditorTransitionKind
        let fadeInDuration: TimeInterval
        let fadeOutDuration: TimeInterval
    }

    struct OverlayVideoSegment {
        let track: AVMutableCompositionTrack
        let timeRange: CMTimeRange
        let transform: CGAffineTransform
        let opacity: Float
        let colorAdjustment: EditorColorAdjustment
        let effects: [EditorVisualEffect]
        let compositing: EditorOverlayCompositing
        let animation: EditorRenderKeyframeAnimation?
        let trackedMotion: EditorRenderTrackedMotion?
    }

    struct BackgroundVideoTracks {
        let black: AVMutableCompositionTrack?
        let white: AVMutableCompositionTrack?
    }

    /// Shared composition pipeline for preview and export.
    /// `frameRate` drives the video composition's `frameDuration` (export passes the user's setting).
    @MainActor
    static func build(
        from clips: [EditorClip],
        textOverlays: [EditorTextOverlay] = [],
        graphicOverlays: [EditorGraphicOverlay] = [],
        audioClips: [EditorAudioClip] = [],
        overlayClips: [EditorOverlayClip] = [],
        adjustmentLayers: [EditorAdjustmentLayer] = [],
        openingTransitionKind: EditorTransitionKind = .none,
        openingTransitionDuration: TimeInterval = 0,
        closingTransitionKind: EditorTransitionKind = .none,
        closingTransitionDuration: TimeInterval = 0,
        canvasSettings: EditorCanvasSettings = .default,
        frameRate: Int32 = 30,
        canvasSize: CGSize? = nil,
        isOfflineRender: Bool = false,
        proxySettings: EditorProxySettings = .default,
        audioTrackSettings: [Int: EditorAudioTrackSettings] = [:],
        masterVolume: Float = 1.0
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

        var cursor = CMTime.zero
        var videoSegments: [VideoSegment] = []
        var embeddedAudioSegments: [(track: AVMutableCompositionTrack, segment: AudioVolumeSegment)] = []
        var pendingFreezeAudioAdvance: (
            assetIdentifier: String,
            sourceTime: TimeInterval,
            duration: TimeInterval
        )?

        for (clipIndex, clip) in clips.enumerated() {
            let segmentDuration = CMTime(seconds: clip.duration, preferredTimescale: timescale)
            guard segmentDuration.seconds > 0 else { continue }

            let segmentRange = CMTimeRange(start: cursor, duration: segmentDuration)

            if clip.isVideo {
                guard let originalAsset = await loadVideoAsset(
                    for: clip.asset,
                    proxySettings: proxySettings,
                    allowProxy: !isOfflineRender && clip.playback == .forward
                ) else {
                    cursor = cursor + segmentDuration
                    continue
                }

                let mediaAsset: AVAsset
                let sourceStart: CMTime
                let sourceDuration: CMTime
                switch clip.playback {
                case .forward:
                    mediaAsset = originalAsset
                    sourceStart = CMTime(seconds: clip.trimStart, preferredTimescale: timescale)
                    sourceDuration = CMTime(
                        seconds: max(0, clip.trimEnd - clip.trimStart),
                        preferredTimescale: timescale
                    )
                case let .reverse(audioPolicy):
                    guard let url = try? await EditorReverseMediaService.cachedURL(
                        for: clip.asset,
                        sourceStart: clip.trimStart,
                        sourceEnd: clip.trimEnd,
                        audioPolicy: audioPolicy
                    ) else {
                        cursor = cursor + segmentDuration
                        continue
                    }
                    mediaAsset = AVURLAsset(url: url)
                    sourceStart = .zero
                    sourceDuration = CMTime(
                        seconds: max(0, clip.trimEnd - clip.trimStart),
                        preferredTimescale: timescale
                    )
                case let .freeze(sourceTime, _):
                    guard let url = await freezeVideoURL(
                        for: originalAsset,
                        assetIdentifier: clip.asset.localIdentifier,
                        sourceTime: sourceTime,
                        duration: clip.duration
                    ) else {
                        cursor = cursor + segmentDuration
                        continue
                    }
                    mediaAsset = AVURLAsset(url: url)
                    sourceStart = .zero
                    sourceDuration = segmentDuration
                }

                if let sourceVideo = try? await mediaAsset.loadTracks(withMediaType: .video).first {
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

                let audioSource: (
                    asset: AVAsset,
                    start: TimeInterval,
                    end: TimeInterval,
                    anchorsAtClipStart: Bool
                )? = {
                    switch clip.playback {
                    case .forward:
                        if let pending = pendingFreezeAudioAdvance,
                           pending.assetIdentifier == clip.asset.localIdentifier,
                           abs(pending.sourceTime - clip.trimStart) <= 1.0 / 60.0 {
                            pendingFreezeAudioAdvance = nil
                            return (
                                originalAsset,
                                min(clip.effectiveAudioTrimEnd,
                                    max(clip.effectiveAudioTrimStart,
                                        pending.sourceTime + pending.duration)),
                                clip.effectiveAudioTrimEnd,
                                true
                            )
                        }
                        pendingFreezeAudioAdvance = nil
                        return (
                            originalAsset,
                            clip.effectiveAudioTrimStart,
                            clip.effectiveAudioTrimEnd,
                            false
                        )
                    case let .reverse(audioPolicy):
                        pendingFreezeAudioAdvance = nil
                        guard audioPolicy == .reverse else { return nil }
                        return (mediaAsset, 0, max(0, clip.trimEnd - clip.trimStart), true)
                    case let .freeze(sourceTime, audioPolicy):
                        guard audioPolicy == .continueSource else { return nil }
                        return (
                            originalAsset,
                            sourceTime,
                            min(clip.asset.duration, sourceTime + clip.duration),
                            true
                        )
                    }
                }()

                if let audioSource,
                   let sourceAudio = try? await audioSource.asset.loadTracks(withMediaType: .audio).first,
                   let clipAudioTrack = composition.addMutableTrack(
                       withMediaType: .audio,
                       preferredTrackID: kCMPersistentTrackID_Invalid
                   ) {
                    let rate = TimeInterval(max(clip.averageSpeed, 0.001))
                    var audioSourceStart = audioSource.start
                    let audioSourceEnd = audioSource.end
                    var audioTimelineStart = cursor.seconds
                    if case .forward = clip.playback, !audioSource.anchorsAtClipStart {
                        audioTimelineStart += (audioSourceStart - clip.trimStart) / rate
                    }
                    if audioTimelineStart < 0 {
                        audioSourceStart = min(audioSourceEnd, audioSourceStart - audioTimelineStart * rate)
                        audioTimelineStart = 0
                    }
                    let audioSourceSpan = max(0, audioSourceEnd - audioSourceStart)
                    let audioTimelineDuration = audioSourceSpan / rate
                    let audioTimeRange = CMTimeRange(
                        start: CMTime(seconds: audioTimelineStart, preferredTimescale: timescale),
                        duration: CMTime(seconds: audioTimelineDuration, preferredTimescale: timescale)
                    )
                    insertSpeedAdjusted(
                        sourceTrack: sourceAudio,
                        into: clipAudioTrack,
                        sourceStart: CMTime(seconds: audioSourceStart, preferredTimescale: timescale),
                        sourceDuration: CMTime(seconds: audioSourceSpan, preferredTimescale: timescale),
                        timelineDuration: audioTimeRange.duration,
                        timelineStart: audioTimeRange.start,
                        uniformSpeed: clip.speed,
                        ramp: clip.isAudioLinked ? clip.speedRamp : nil
                    )
                    embeddedAudioSegments.append((
                        clipAudioTrack,
                        AudioVolumeSegment(
                            timeRange: audioTimeRange,
                            volume: clip.volume,
                            keyframes: clip.keyframes,
                            keyframeTimeOffset: max(0, audioTimelineStart - cursor.seconds)
                        )
                    ))
                }
                if case let .freeze(sourceTime, audioPolicy) = clip.playback,
                   audioPolicy == .continueSource {
                    pendingFreezeAudioAdvance = (
                        clip.asset.localIdentifier,
                        sourceTime,
                        clip.duration
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
        for overlay in graphicOverlays {
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

            let originalAsset: AVAsset
            if overlay.asset.mediaType == .video {
                guard let videoAsset = await loadVideoAsset(
                    for: overlay.asset,
                    proxySettings: proxySettings,
                    allowProxy: !isOfflineRender && overlay.playback == .forward
                ) else { continue }
                originalAsset = videoAsset
            } else {
                // Reuse the same still-image conversion as primary photo clips so
                // photo overlays have identical preview/export behavior.
                guard let photoURL = await photoVideoURL(
                    for: overlay.asset,
                    duration: overlay.originalDuration
                ) else { continue }
                originalAsset = AVURLAsset(url: photoURL)
            }

            let timelineStart = CMTime(seconds: overlay.timelineStart, preferredTimescale: timescale)
            let timelineDuration = CMTime(seconds: overlay.duration, preferredTimescale: timescale)
            let mediaAsset: AVAsset
            let sourceStart: CMTime
            let sourceDuration: CMTime
            switch overlay.playback {
            case .forward:
                mediaAsset = originalAsset
                sourceStart = CMTime(seconds: overlay.trimStart, preferredTimescale: timescale)
                sourceDuration = CMTime(
                    seconds: overlay.trimEnd - overlay.trimStart,
                    preferredTimescale: timescale
                )
            case let .reverse(audioPolicy):
                guard let url = try? await EditorReverseMediaService.cachedURL(
                    for: overlay.asset,
                    sourceStart: overlay.trimStart,
                    sourceEnd: overlay.trimEnd,
                    audioPolicy: audioPolicy
                ) else { continue }
                mediaAsset = AVURLAsset(url: url)
                sourceStart = .zero
                sourceDuration = CMTime(
                    seconds: overlay.trimEnd - overlay.trimStart,
                    preferredTimescale: timescale
                )
            case let .freeze(sourceTime, _):
                guard let url = await freezeVideoURL(
                    for: originalAsset,
                    assetIdentifier: overlay.asset.localIdentifier,
                    sourceTime: sourceTime,
                    duration: overlay.duration
                ) else { continue }
                mediaAsset = AVURLAsset(url: url)
                sourceStart = .zero
                sourceDuration = timelineDuration
            }
            let sourceRange = CMTimeRange(start: sourceStart, duration: sourceDuration)
            let timelineRange = CMTimeRange(start: timelineStart, duration: timelineDuration)

            if let sourceVideo = try? await mediaAsset.loadTracks(withMediaType: .video).first,
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
                            effects: overlay.effects,
                            compositing: overlay.compositing,
                            animation: renderAnimation(for: overlay),
                            trackedMotion: trackedMotion(
                                for: overlay,
                                clips: clips,
                                overlayClips: overlayClips
                            )
                        )
                    )
                } catch {
                    composition.removeTrack(overlayTrack)
                }
            }

            let audioSource: (asset: AVAsset, range: CMTimeRange, timelineDuration: CMTime)? = {
                switch overlay.playback {
                case .forward:
                    return (originalAsset, sourceRange, timelineDuration)
                case let .reverse(audioPolicy):
                    guard audioPolicy == .reverse else { return nil }
                    return (mediaAsset, sourceRange, timelineDuration)
                case let .freeze(sourceTime, audioPolicy):
                    guard audioPolicy == .continueSource else { return nil }
                    let available = max(0, overlay.asset.duration - sourceTime)
                    let audioDuration = min(overlay.duration, available)
                    guard audioDuration > 0 else { return nil }
                    return (
                        originalAsset,
                        CMTimeRange(
                            start: CMTime(seconds: sourceTime, preferredTimescale: timescale),
                            duration: CMTime(seconds: audioDuration, preferredTimescale: timescale)
                        ),
                        CMTime(seconds: audioDuration, preferredTimescale: timescale)
                    )
                }
            }()

            if let audioSource,
               let sourceAudio = try? await audioSource.asset.loadTracks(withMediaType: .audio).first,
               let overlayAudioTrack = composition.addMutableTrack(
                    withMediaType: .audio,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                ) {
                do {
                    try overlayAudioTrack.insertTimeRange(audioSource.range, of: sourceAudio, at: timelineStart)
                    applySpeed(
                        overlay.speed,
                        sourceDuration: audioSource.range.duration,
                        timelineDuration: audioSource.timelineDuration,
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
            guard isOfflineRender, !textOverlays.isEmpty || !graphicOverlays.isEmpty else { return nil }

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
                let renderStates: [(EditorTextOverlay, UUID?)]
                if overlay.isCaption, overlay.animation.inPreset == .typewriter {
                    let delay = max(overlay.animation.characterDelay, 0.015)
                    var breakpoints = [overlay.startTime, overlay.endTime]
                    breakpoints.append(contentsOf: overlay.captionWords.map(\.startTime))
                    breakpoints.append(contentsOf: overlay.captionWords.indices.map {
                        overlay.startTime + Double($0 + 1) * delay
                    })
                    let orderedBreakpoints = Array(Set(breakpoints.map {
                        min(max($0, overlay.startTime), overlay.endTime)
                    })).sorted()
                    renderStates = zip(orderedBreakpoints, orderedBreakpoints.dropFirst()).compactMap {
                        stateStart, stateEnd in
                        guard stateEnd > stateStart else { return nil }
                        let progress = overlay.animation.revealProgress(
                            localTime: stateStart - overlay.startTime + 0.000_1,
                            itemCount: overlay.captionWords.count
                        )
                        let count = min(
                            overlay.captionWords.count,
                            max(0, Int(floor(Double(overlay.captionWords.count) * progress)))
                        )
                        guard count > 0 else { return nil }
                        var timedOverlay = overlay
                        timedOverlay.captionWords = Array(overlay.captionWords.prefix(count))
                        timedOverlay.text = timedOverlay.captionWords.map(\.text).joined(separator: " ")
                        timedOverlay.startTime = stateStart
                        timedOverlay.endTime = stateEnd
                        let highlightedID = overlay.activeCaptionWordID(at: stateStart + 0.000_1)
                        return (timedOverlay, highlightedID)
                    }
                } else if overlay.isCaption {
                    renderStates = overlay.captionWords.enumerated().map { index, word in
                        var timedOverlay = overlay
                        timedOverlay.startTime = index == 0 ? overlay.startTime : word.startTime
                        timedOverlay.endTime = index + 1 < overlay.captionWords.count
                            ? overlay.captionWords[index + 1].startTime
                            : overlay.endTime
                        return (timedOverlay, word.id)
                    }
                } else if overlay.animation.inPreset == .typewriter, !overlay.text.isEmpty {
                    let characters = Array(overlay.text)
                    let delay = max(overlay.animation.characterDelay, 0.015)
                    renderStates = characters.indices.compactMap { index in
                        let stateStart = overlay.startTime + Double(index + 1) * delay
                        guard stateStart < overlay.endTime else { return nil }
                        var timedOverlay = overlay
                        timedOverlay.text = String(characters.prefix(index + 1))
                        timedOverlay.startTime = stateStart
                        timedOverlay.endTime = index + 1 < characters.count
                            ? min(overlay.endTime, stateStart + delay)
                            : overlay.endTime
                        return (timedOverlay, nil)
                    }
                } else {
                    renderStates = [(overlay, nil)]
                }

                for (renderOverlay, highlightedWordID) in renderStates {
                    let usesBlur = [
                        overlay.animation.inPreset,
                        overlay.animation.outPreset,
                        overlay.animation.loopPreset
                    ].contains(.blur)
                    let usesPhaseBlur = overlay.animation.inPreset == .blur
                        || overlay.animation.outPreset == .blur
                    let maximumBlurRadius = max(
                        1,
                        (usesPhaseBlur ? 14 : 2.5) * overlay.animation.intensity
                    )
                    let layerVariants: [(isBlurred: Bool, radius: CGFloat)] = usesBlur
                        ? [(false, 0), (true, CGFloat(maximumBlurRadius))]
                        : [(false, 0)]

                    for variant in layerVariants {
                        guard let image = EditorTextOverlayRenderer.render(
                            overlay: renderOverlay,
                            renderSize: renderSize,
                            highlightedCaptionWordID: highlightedWordID,
                            blurRadius: variant.radius
                        ) else { continue }
                        let textLayer = CALayer()
                        textLayer.contents = image.cgImage
                        textLayer.contentsScale = 1
                        textLayer.frame = CGRect(origin: .zero, size: renderSize)
                        textLayer.opacity = 0

                        addTextAnimations(
                            to: textLayer,
                            overlay: renderOverlay,
                            animationSource: overlay,
                            clips: clips,
                            overlayClips: overlayClips,
                            totalDuration: totalDuration,
                            renderSize: renderSize,
                            blurLayer: variant.isBlurred,
                            maximumBlurRadius: maximumBlurRadius
                        )
                        parentLayer.addSublayer(textLayer)
                    }
                }
            }

            for graphic in graphicOverlays {
                guard let image = EditorGraphicOverlayRenderer.render(
                    graphic: graphic,
                    renderSize: renderSize
                ) else { continue }
                let layer = CALayer()
                layer.contents = image.cgImage
                layer.contentsScale = 1
                layer.frame = CGRect(origin: .zero, size: renderSize)
                layer.opacity = 0
                layer.compositingFilter = graphic.blendMode.coreAnimationFilterName
                addGraphicAnimations(
                    to: layer,
                    graphic: graphic,
                    totalDuration: totalDuration,
                    renderSize: renderSize
                )
                parentLayer.addSublayer(layer)
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
                keyframes: overlayAudio.clip.keyframes,
                extraGain: masterVolume
            )
            mixParams.append(params)
        }

        // Per-clip volume
        for embedded in embeddedAudioSegments {
            let params = AVMutableAudioMixInputParameters(track: embedded.track)
            applyVolumeAutomation(
                to: params,
                timeRange: embedded.segment.timeRange,
                baseVolume: embedded.segment.volume,
                keyframes: embedded.segment.keyframes,
                keyframeTimeOffset: embedded.segment.keyframeTimeOffset,
                extraGain: masterVolume
            )
            mixParams.append(params)
        }

        // Background music clips
        let anyLaneSoloed = audioTrackSettings.values.contains { $0.isSoloed }
        for audioClip in audioClips where FileManager.default.fileExists(atPath: audioClip.fileURL.path) {
            // `playbackFileURL` swaps in the Priority 15 effect-processed render when one exists
            // and falls back to the dry file otherwise — trim/timeline math below is unaffected
            // either way since effect rendering always preserves the source's exact duration.
            let bgAsset = AVURLAsset(url: audioClip.playbackFileURL)
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

            // A lane with no entry yet is still subject to solo — only the *default* (no entry
            // at all) skips it, not "no entry for this specific lane" — so this must default to
            // a plain `EditorAudioTrackSettings()` and go through `effectiveGain`, not fall back
            // straight to `1.0`, or an untouched lane would keep playing under an active solo.
            let laneSettings = audioTrackSettings[audioClip.laneIndex] ?? EditorAudioTrackSettings()
            let trackGain = laneSettings.effectiveGain(anySoloed: anyLaneSoloed)
            applyVolumeAutomation(
                to: bgParams,
                timeRange: CMTimeRange(start: timelineStart, duration: sourceDuration),
                baseVolume: audioClip.volume,
                keyframes: audioClip.keyframes,
                fadeIn: fadeIn,
                fadeOut: fadeOut,
                extraGain: trackGain * masterVolume
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
                adjustmentLayers: adjustmentLayers,
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
}
