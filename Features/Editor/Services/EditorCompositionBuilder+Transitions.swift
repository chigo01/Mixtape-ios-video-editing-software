//
//  EditorCompositionBuilder+Transitions.swift
//  Mixtape
//

import AVFoundation
import Photos
import UIKit

extension EditorCompositionBuilder {
    static func transitionMotionCurve(
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

    static func applyTransition(
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

    static func usesWhiteCanvas(_ kind: EditorTransitionKind) -> Bool {
        switch kind {
        case .dipToWhite, .blink, .flash, .flashZoom, .glare, .strobe, .lightSweep:
            return true
        default:
            return false
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
}
