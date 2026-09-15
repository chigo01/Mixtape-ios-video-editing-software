//
//  EditorCompositionBuilder+AudioAndOverlays.swift
//  Mixtape
//

import AVFoundation
import Photos
import UIKit

extension EditorCompositionBuilder {
    static func applyVolumeAutomation(
        to parameters: AVMutableAudioMixInputParameters,
        timeRange: CMTimeRange,
        baseVolume: Float,
        keyframes: EditorKeyframeTracks,
        keyframeTimeOffset: TimeInterval = 0,
        fadeIn: TimeInterval = 0,
        fadeOut: TimeInterval = 0,
        extraGain: Float = 1.0
    ) {
        let duration = max(0, timeRange.duration.seconds)
        guard duration > 0 else { return }
        let volumeTrack = keyframes.track(for: .volume)
        let hasAutomation = !volumeTrack.isEmpty || fadeIn > 0 || fadeOut > 0
        guard hasAutomation else {
            parameters.setVolume(baseVolume * extraGain, at: timeRange.start)
            return
        }

        let sampleCount = min(600, max(1, Int(ceil(duration * 12))))
        func value(at localTime: TimeInterval) -> Float {
            let automated = volumeTrack.value(
                at: localTime + keyframeTimeOffset,
                default: Double(baseVolume)
            )
            let fadeInGain = fadeIn > 0 ? min(max(localTime / fadeIn, 0), 1) : 1
            let remaining = duration - localTime
            let fadeOutGain = fadeOut > 0 ? min(max(remaining / fadeOut, 0), 1) : 1
            // extraGain (track/master gain) is applied after the existing 0...1 clamp, not
            // baked into `automated` — it's always 0...1 itself (see
            // EditorAudioTrackSettings.effectiveGain), so the product stays in range without
            // needing to touch the keyframe/fade math above.
            return Float(min(max(automated * fadeInGain * fadeOutGain, 0), 1)) * extraGain
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

    static func addTextAnimations(
        to layer: CALayer,
        overlay: EditorTextOverlay,
        animationSource: EditorTextOverlay,
        clips: [EditorClip],
        overlayClips: [EditorOverlayClip],
        totalDuration: TimeInterval,
        renderSize: CGSize,
        blurLayer: Bool,
        maximumBlurRadius: Double
    ) {
        guard totalDuration > 0 else { return }
        let sampleCount = min(1_800, max(2, Int(ceil(totalDuration * 30))))
        var keyTimes: [NSNumber] = []
        var opacities: [NSNumber] = []
        var transforms: [NSValue] = []
        let screenScale = renderSize.width / EditorTextOverlayLayout.referenceWidth
        let previewCanvas = EditorTextOverlayLayout.referenceCanvasSize(
            matching: renderSize
        )
        let attachment = textAttachment(
            for: animationSource,
            clips: clips,
            overlayClips: overlayClips
        )

        for index in 0...sampleCount {
            let globalTime = totalDuration * Double(index) / Double(sampleCount)
            let localTime = min(
                max(0, globalTime - animationSource.startTime),
                animationSource.duration
            )
            let visible = globalTime >= overlay.startTime && globalTime < overlay.endTime
            let textAnimation = animationSource.animation.sample(
                localTime: localTime,
                duration: animationSource.duration
            )
            let blurMix = min(max(textAnimation.blurRadius / max(maximumBlurRadius, 0.001), 0), 1)
            let blurOpacity = blurLayer ? blurMix : 1 - blurMix
            let opacity = visible
                ? animationSource.keyframes.value(
                    for: .opacity,
                    at: localTime,
                    default: animationSource.opacity
                ) * textAnimation.opacity * blurOpacity
                : 0
            var x = animationSource.keyframes.value(
                for: .textPositionX,
                at: localTime,
                default: Double(animationSource.xOffset)
            )
            var y = animationSource.keyframes.value(
                for: .textPositionY,
                at: localTime,
                default: Double(animationSource.yOffset)
            )
            var scale = animationSource.keyframes.value(
                for: .textScale,
                at: localTime,
                default: 1
            )
            var rotation = animationSource.keyframes.value(
                for: .textRotation,
                at: localTime,
                default: 0
            )
            x += textAnimation.xOffset
            y += textAnimation.yOffset
            scale *= textAnimation.scale
            rotation += textAnimation.rotationDegrees
            if let attachment {
                let compositionTime = CMTime(seconds: globalTime, preferredTimescale: timescale)
                let sample = attachment.resolved(at: compositionTime)
                x += (sample.x - attachment.seedX) * Double(previewCanvas.width)
                y += (sample.y - attachment.seedY) * Double(previewCanvas.height)
                if animationSource.attachScale {
                    scale *= sample.scale / max(attachment.seedScale, 0.000_001)
                }
                if animationSource.attachRotation {
                    rotation += (sample.rotation - attachment.seedRotation) * 180 / .pi
                }
            }
            var transform = CATransform3DMakeTranslation(
                CGFloat(x - Double(animationSource.xOffset)) * screenScale,
                CGFloat(y - Double(animationSource.yOffset)) * screenScale,
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

    static func addGraphicAnimations(
        to layer: CALayer,
        graphic: EditorGraphicOverlay,
        totalDuration: TimeInterval,
        renderSize: CGSize
    ) {
        guard totalDuration > 0 else { return }
        let sampleCount = min(1_800, max(2, Int(ceil(totalDuration * 30))))
        var keyTimes: [NSNumber] = []
        var opacities: [NSNumber] = []
        var transforms: [NSValue] = []
        let renderScale = renderSize.width / EditorTextOverlayLayout.referenceWidth

        for index in 0...sampleCount {
            let globalTime = totalDuration * Double(index) / Double(sampleCount)
            let local = min(max(0, globalTime - graphic.startTime), graphic.duration)
            let visible = globalTime >= graphic.startTime && globalTime < graphic.endTime
            let sample = graphic.animation.sample(localTime: local, duration: graphic.duration)
            var transform = CATransform3DMakeTranslation(0, CGFloat(sample.y) * renderScale, 0)
            transform = CATransform3DScale(transform, CGFloat(sample.scale), CGFloat(sample.scale), 1)
            transform = CATransform3DRotate(transform, CGFloat(sample.rotation * .pi / 180), 0, 0, 1)
            keyTimes.append(NSNumber(value: Double(index) / Double(sampleCount)))
            opacities.append(NSNumber(value: visible ? sample.opacity : 0))
            transforms.append(NSValue(caTransform3D: transform))
        }

        let opacity = CAKeyframeAnimation(keyPath: "opacity")
        opacity.values = opacities
        opacity.keyTimes = keyTimes
        opacity.calculationMode = .linear
        configureTextAnimation(opacity, duration: totalDuration)
        layer.add(opacity, forKey: "graphicOpacity")

        let transform = CAKeyframeAnimation(keyPath: "transform")
        transform.values = transforms
        transform.keyTimes = keyTimes
        transform.calculationMode = .linear
        configureTextAnimation(transform, duration: totalDuration)
        layer.add(transform, forKey: "graphicTransform")
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
}
