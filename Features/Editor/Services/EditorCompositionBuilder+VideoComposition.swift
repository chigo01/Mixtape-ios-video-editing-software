//
//  EditorCompositionBuilder+VideoComposition.swift
//  Mixtape
//

import AVFoundation
import Photos
import UIKit

extension EditorCompositionBuilder {
    // MARK: - Video composition (orientation + aspect fit)

    static func makeVideoComposition(
        compositionTrack: AVMutableCompositionTrack,
        backgroundTracks: BackgroundVideoTracks,
        segments: [VideoSegment],
        overlaySegments: [OverlayVideoSegment],
        adjustmentLayers: [EditorAdjustmentLayer],
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
                || $0.effects.contains(where: \.isEnabled)
                || $0.compositing.requiresGPUCompositor
                || $0.transitionIn.usesGPUCompositor
                || $0.transitionOut.usesGPUCompositor
                || $0.animation?.hasVisualAnimation == true
                || $0.stabilization?.isActive == true
        } || overlaySegments.contains {
            !$0.colorAdjustment.isNeutral
                || $0.effects.contains(where: \.isEnabled)
                || $0.compositing.requiresGPUCompositor
                || $0.animation?.hasVisualAnimation == true
                || $0.trackedMotion?.isActive == true
        } || adjustmentLayers.contains {
            $0.isEnabled
                && (!$0.colorAdjustment.isNeutral || $0.effects.contains(where: \.isEnabled))
        }
            || canvasSettings.backgroundKind == .blur
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
                            effects: $0.effects,
                            compositing: $0.compositing,
                            animation: $0.animation,
                            trackedMotion: $0.trackedMotion
                        )
                    },
                    adjustmentLayers: adjustmentLayers
                        .filter(\.isEnabled)
                        .map {
                            EditorAdjustmentRenderLayer(
                                timeRange: CMTimeRange(
                                    start: CMTime(
                                        seconds: max(0, $0.startTime),
                                        preferredTimescale: timescale
                                    ),
                                    duration: CMTime(
                                        seconds: max(0, $0.duration),
                                        preferredTimescale: timescale
                                    )
                                ),
                                colorAdjustment: $0.colorAdjustment,
                                effects: $0.effects,
                                zIndex: $0.zIndex
                            )
                        },
                    baseTransform: segment.transform,
                    animation: segment.animation,
                    stabilization: segment.stabilization,
                    colorAdjustment: segment.colorAdjustment,
                    effects: segment.effects,
                    compositing: segment.compositing,
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
                    canvasBackgroundBlurIntensity: canvasSettings.backgroundBlurIntensity,
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

    static func overlayTransform(
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

    static func renderAnimation(for clip: EditorClip) -> EditorRenderKeyframeAnimation? {
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

    static func renderAnimation(
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

    static func trackedMotion(
        for overlay: EditorOverlayClip,
        clips: [EditorClip],
        overlayClips: [EditorOverlayClip]
    ) -> EditorRenderTrackedMotion? {
        guard let clipID = overlay.attachedClipID,
              let trackID = overlay.attachedTrackID else { return nil }
        return renderTrackedMotion(
            clipID: clipID,
            trackID: trackID,
            attachRotation: overlay.attachRotation,
            attachScale: overlay.attachScale,
            clips: clips,
            overlayClips: overlayClips
        )
    }

    static func textAttachment(
        for overlay: EditorTextOverlay,
        clips: [EditorClip],
        overlayClips: [EditorOverlayClip]
    ) -> EditorRenderTrackedMotion? {
        guard let clipID = overlay.attachedClipID,
              let trackID = overlay.attachedTrackID else { return nil }
        return renderTrackedMotion(
            clipID: clipID,
            trackID: trackID,
            attachRotation: overlay.attachRotation,
            attachScale: overlay.attachScale,
            clips: clips,
            overlayClips: overlayClips
        )
    }

    private static func renderTrackedMotion(
        clipID: UUID,
        trackID: UUID,
        attachRotation: Bool,
        attachScale: Bool,
        clips: [EditorClip],
        overlayClips: [EditorOverlayClip]
    ) -> EditorRenderTrackedMotion? {
        var cursor: TimeInterval = 0
        var hostTimeRange: CMTimeRange?
        var track: EditorMotionTrack?
        for clip in clips {
            if clip.id == clipID, let found = clip.motionTracks.first(where: { $0.id == trackID }) {
                track = found
                hostTimeRange = CMTimeRange(
                    start: CMTime(seconds: cursor, preferredTimescale: timescale),
                    duration: CMTime(seconds: max(clip.duration, 0.001), preferredTimescale: timescale)
                )
                break
            }
            cursor += clip.duration
        }
        if track == nil {
            for overlay in overlayClips where overlay.id == clipID {
                guard let found = overlay.motionTracks.first(where: { $0.id == trackID }) else {
                    continue
                }
                track = found
                hostTimeRange = CMTimeRange(
                    start: CMTime(seconds: overlay.timelineStart, preferredTimescale: timescale),
                    duration: CMTime(seconds: max(overlay.duration, 0.001), preferredTimescale: timescale)
                )
                break
            }
        }
        guard let track, let hostTimeRange, track.isTracked else { return nil }
        return EditorRenderTrackedMotion(
            hostTimeRange: hostTimeRange,
            samples: track.samples,
            seedX: track.seedX,
            seedY: track.seedY,
            seedRotation: track.seedRotation,
            seedScale: 1,
            smoothing: track.smoothing,
            attachRotation: attachRotation,
            attachScale: attachScale
        )
    }

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
    static func reframeTransform(
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
}
