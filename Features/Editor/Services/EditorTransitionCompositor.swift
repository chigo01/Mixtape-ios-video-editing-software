//
//  EditorTransitionCompositor.swift
//  Mixtape
//
//  GPU-backed transition rendering shared by preview and export.
//

import AVFoundation
import CoreImage
import Metal

/// A compact transform curve prepared by the composition builder.
/// Keeping timeline math out of the compositor makes each render request deterministic.
struct EditorTransitionMotionCurve {
    let start: CGAffineTransform
    let overshoot: CGAffineTransform?
    let end: CGAffineTransform

    func transform(at progress: CGFloat) -> CGAffineTransform {
        let progress = min(max(progress, 0), 1)
        guard let overshoot else {
            return Self.interpolate(start, end, progress: progress)
        }

        let split: CGFloat = 0.68
        if progress <= split {
            return Self.interpolate(start, overshoot, progress: progress / split)
        }
        return Self.interpolate(
            overshoot,
            end,
            progress: (progress - split) / (1 - split)
        )
    }

    private static func interpolate(
        _ from: CGAffineTransform,
        _ to: CGAffineTransform,
        progress: CGFloat
    ) -> CGAffineTransform {
        CGAffineTransform(
            a: from.a + (to.a - from.a) * progress,
            b: from.b + (to.b - from.b) * progress,
            c: from.c + (to.c - from.c) * progress,
            d: from.d + (to.d - from.d) * progress,
            tx: from.tx + (to.tx - from.tx) * progress,
            ty: from.ty + (to.ty - from.ty) * progress
        )
    }
}

struct EditorOverlayRenderLayer {
    let trackID: CMPersistentTrackID
    let timeRange: CMTimeRange
    let transform: CGAffineTransform
    let opacity: Float
    let colorAdjustment: EditorColorAdjustment
    let effects: [EditorVisualEffect]
    let compositing: EditorOverlayCompositing
    let animation: EditorRenderKeyframeAnimation?
    let trackedMotion: EditorRenderTrackedMotion?
}

struct EditorAdjustmentRenderLayer {
    let timeRange: CMTimeRange
    let colorAdjustment: EditorColorAdjustment
    let effects: [EditorVisualEffect]
    let zIndex: Int
}

/// Immutable adapter between reusable editor tracks and frame rendering.
struct EditorRenderKeyframeAnimation {
    let tracks: EditorKeyframeTracks
    let basePositionX: Double
    let basePositionY: Double
    let baseScale: Double
    let baseRotation: Double
    let baseOpacity: Double
    let baseFilterIntensity: Double
    let baseCropX: Double
    let baseCropY: Double
    let baseCropScale: Double

    var hasVisualAnimation: Bool {
        let visual: Set<EditorKeyframeProperty> = [
            .positionX, .positionY, .scale, .rotation, .opacity,
            .cropX, .cropY, .cropScale, .filterIntensity, .effectAmount
        ]
        return tracks.tracks.contains { visual.contains($0.property) && !$0.isEmpty }
    }

    func transform(
        base: CGAffineTransform,
        at localTime: TimeInterval,
        renderSize: CGSize
    ) -> CGAffineTransform {
        let x = tracks.value(for: .positionX, at: localTime, default: basePositionX)
        let y = tracks.value(for: .positionY, at: localTime, default: basePositionY)
        let scale = tracks.value(for: .scale, at: localTime, default: baseScale)
        let rotation = tracks.value(for: .rotation, at: localTime, default: baseRotation)
        let cropX = tracks.value(for: .cropX, at: localTime, default: baseCropX)
        let cropY = tracks.value(for: .cropY, at: localTime, default: baseCropY)
        let cropScale = tracks.value(for: .cropScale, at: localTime, default: baseCropScale)

        let scaleRatio = CGFloat(
            (scale / max(baseScale, 0.000_001))
                * (cropScale / max(baseCropScale, 0.000_001))
        )
        let rotationDelta = CGFloat((rotation - baseRotation) * .pi / 180)
        let xDelta = CGFloat((x - basePositionX) + (cropX - baseCropX)) * renderSize.width
        let yDelta = CGFloat((y - basePositionY) + (cropY - baseCropY)) * renderSize.height
        let center = CGPoint(x: renderSize.width / 2, y: renderSize.height / 2)

        let destination = CGAffineTransform(translationX: center.x + xDelta, y: center.y + yDelta)
            .rotated(by: rotationDelta)
            .scaledBy(x: scaleRatio, y: scaleRatio)
            .translatedBy(x: -center.x, y: -center.y)
        return base.concatenating(destination)
    }

    func opacity(at localTime: TimeInterval) -> CGFloat {
        CGFloat(tracks.value(for: .opacity, at: localTime, default: baseOpacity))
    }

    func filterIntensity(at localTime: TimeInterval) -> Double {
        tracks.value(
            for: .filterIntensity,
            at: localTime,
            default: baseFilterIntensity
        )
    }
}

/// Instruction consumed by `EditorTransitionCompositor`.
/// It intentionally contains values only—no mutable composition or UI state.
final class EditorTransitionRenderInstruction:
    NSObject,
    AVVideoCompositionInstructionProtocol,
    @unchecked Sendable
{
    let timeRange: CMTimeRange
    let enablePostProcessing: Bool
    let containsTweening: Bool
    let requiredSourceTrackIDs: [NSValue]?
    let passthroughTrackID: CMPersistentTrackID = kCMPersistentTrackID_Invalid

    let foregroundTrackID: CMPersistentTrackID
    let backgroundTrackID: CMPersistentTrackID?
    let overlayLayers: [EditorOverlayRenderLayer]
    let adjustmentLayers: [EditorAdjustmentRenderLayer]
    let baseTransform: CGAffineTransform
    let animation: EditorRenderKeyframeAnimation?
    let stabilization: EditorRenderStabilization?
    let colorAdjustment: EditorColorAdjustment
    let effects: [EditorVisualEffect]
    let compositing: EditorOverlayCompositing
    let incomingKind: EditorTransitionKind
    let outgoingKind: EditorTransitionKind
    let incomingDuration: TimeInterval
    let outgoingDuration: TimeInterval
    let incomingMotion: EditorTransitionMotionCurve?
    let outgoingMotion: EditorTransitionMotionCurve?
    let renderSize: CGSize
    let canvasBackgroundKind: EditorCanvasBackgroundKind

    init(
        timeRange: CMTimeRange,
        foregroundTrackID: CMPersistentTrackID,
        backgroundTrackID: CMPersistentTrackID?,
        overlayLayers: [EditorOverlayRenderLayer],
        adjustmentLayers: [EditorAdjustmentRenderLayer],
        baseTransform: CGAffineTransform,
        animation: EditorRenderKeyframeAnimation?,
        stabilization: EditorRenderStabilization?,
        colorAdjustment: EditorColorAdjustment,
        effects: [EditorVisualEffect],
        compositing: EditorOverlayCompositing,
        incomingKind: EditorTransitionKind,
        outgoingKind: EditorTransitionKind,
        incomingDuration: TimeInterval,
        outgoingDuration: TimeInterval,
        incomingMotion: EditorTransitionMotionCurve?,
        outgoingMotion: EditorTransitionMotionCurve?,
        renderSize: CGSize,
        canvasBackgroundKind: EditorCanvasBackgroundKind,
        enablePostProcessing: Bool
    ) {
        self.timeRange = timeRange
        self.foregroundTrackID = foregroundTrackID
        self.backgroundTrackID = backgroundTrackID
        self.overlayLayers = overlayLayers
        self.adjustmentLayers = adjustmentLayers.sorted { $0.zIndex < $1.zIndex }
        self.baseTransform = baseTransform
        self.animation = animation
        self.stabilization = stabilization
        self.colorAdjustment = colorAdjustment
        self.effects = effects
        self.compositing = compositing
        self.incomingKind = incomingKind
        self.outgoingKind = outgoingKind
        self.incomingDuration = incomingDuration
        self.outgoingDuration = outgoingDuration
        self.incomingMotion = incomingMotion
        self.outgoingMotion = outgoingMotion
        self.renderSize = renderSize
        self.canvasBackgroundKind = canvasBackgroundKind
        self.enablePostProcessing = enablePostProcessing
        self.containsTweening = incomingDuration > 0
            || outgoingDuration > 0
            || animation?.hasVisualAnimation == true
            || stabilization?.isActive == true
            || overlayLayers.contains {
                $0.animation?.hasVisualAnimation == true || $0.trackedMotion?.isActive == true
            }

        var trackIDs = [NSNumber(value: foregroundTrackID)]
        if let backgroundTrackID {
            trackIDs.append(NSNumber(value: backgroundTrackID))
        }
        trackIDs.append(contentsOf: overlayLayers.map { NSNumber(value: $0.trackID) })
        self.requiredSourceTrackIDs = trackIDs
        super.init()
    }

    func state(at compositionTime: CMTime) -> EditorTransitionRenderState {
        let localTime = max(0, (compositionTime - timeRange.start).seconds)
        let duration = max(0, timeRange.duration.seconds)

        if incomingDuration > 0, localTime < incomingDuration {
            let progress = min(max(localTime / incomingDuration, 0), 1)
            return animatedState(EditorTransitionRenderState(
                kind: incomingKind,
                progress: progress,
                intensity: 1 - progress,
                visibility: incomingKind.usesShaderMask ? 1 : incomingOpacity(progress),
                transform: incomingMotion?.transform(at: progress) ?? baseTransform
            ), localTime: localTime)
        }

        let outgoingStart = duration - outgoingDuration
        if outgoingDuration > 0, localTime >= outgoingStart {
            let progress = min(max((localTime - outgoingStart) / outgoingDuration, 0), 1)
            return animatedState(EditorTransitionRenderState(
                kind: outgoingKind,
                progress: progress,
                intensity: progress,
                visibility: outgoingKind.usesShaderMask ? 1 : outgoingOpacity(progress),
                transform: outgoingMotion?.transform(at: progress) ?? baseTransform
            ), localTime: localTime)
        }

        return animatedState(EditorTransitionRenderState(
            kind: .none,
            progress: 1,
            intensity: 0,
            visibility: 1,
            transform: baseTransform
        ), localTime: localTime)
    }

    private func animatedState(
        _ state: EditorTransitionRenderState,
        localTime: TimeInterval
    ) -> EditorTransitionRenderState {
        let duration = max(timeRange.duration.seconds, 0.000_001)
        let progress = min(max(localTime / duration, 0), 1)
        var transform = state.transform
        if let stabilization, stabilization.isActive {
            transform = transform.concatenating(
                stabilization.transform(at: progress, renderSize: renderSize)
            )
        }
        guard let animation else {
            return EditorTransitionRenderState(
                kind: state.kind,
                progress: state.progress,
                intensity: state.intensity,
                visibility: state.visibility,
                transform: transform
            )
        }
        return EditorTransitionRenderState(
            kind: state.kind,
            progress: state.progress,
            intensity: state.intensity,
            visibility: state.visibility * animation.opacity(at: localTime),
            transform: animation.transform(
                base: transform,
                at: localTime,
                renderSize: renderSize
            )
        )
    }

    func clipProgress(at compositionTime: CMTime) -> Double {
        let duration = max(timeRange.duration.seconds, 0.000_001)
        return min(max((compositionTime - timeRange.start).seconds / duration, 0), 1)
    }

    private func incomingOpacity(_ progress: Double) -> CGFloat {
        switch incomingKind {
        case .pushLeft, .pushRight, .pushUp, .pushDown:
            return 1
        case .strobe:
            if progress < 0.34 { return CGFloat(progress / 0.34) }
            if progress < 0.62 {
                return CGFloat(1 - ((progress - 0.34) / 0.28) * 0.82)
            }
            return CGFloat(0.18 + ((progress - 0.62) / 0.38) * 0.82)
        default:
            return CGFloat(progress)
        }
    }

    private func outgoingOpacity(_ progress: Double) -> CGFloat {
        switch outgoingKind {
        case .pushLeft, .pushRight, .pushUp, .pushDown:
            return 1
        case .strobe:
            if progress < 0.34 { return CGFloat(1 - (progress / 0.34) * 0.82) }
            if progress < 0.62 {
                return CGFloat(0.18 + ((progress - 0.34) / 0.28) * 0.82)
            }
            return CGFloat(1 - ((progress - 0.62) / 0.38))
        default:
            return CGFloat(1 - progress)
        }
    }
}

struct EditorTransitionRenderState {
    let kind: EditorTransitionKind
    let progress: Double
    let intensity: Double
    let visibility: CGFloat
    let transform: CGAffineTransform
}

/// Core Image uses Metal automatically when a Metal device is available.
/// AVFoundation instantiates this class for both AVPlayer preview and offline export.
final class EditorTransitionCompositor: NSObject, AVVideoCompositing {
    private let renderQueue = DispatchQueue(
        label: "com.mixtape.transition-compositor",
        qos: .userInitiated
    )
    private let stateQueue = DispatchQueue(label: "com.mixtape.transition-compositor.state")
    private var shouldCancelAllRequests = false

    private let colorSpace = CGColorSpaceCreateDeviceRGB()
    private let ciContext: CIContext = {
        if let device = MTLCreateSystemDefaultDevice() {
            return CIContext(
                mtlDevice: device,
                options: [
                    .cacheIntermediates: false,
                    .name: "Mixtape Transition Renderer"
                ]
            )
        }
        return CIContext(options: [.cacheIntermediates: false])
    }()

    // Advertising only 8-bit formats keeps this renderer in a stable SDR working
    // space. HDR support can be added later with a dedicated 10-bit render path.
    var sourcePixelBufferAttributes: [String: any Sendable]? {
        [
            kCVPixelBufferPixelFormatTypeKey as String: [
                kCVPixelFormatType_32BGRA,
                kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
            ],
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]
    }

    var requiredPixelBufferAttributesForRenderContext: [String: any Sendable] {
        [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]
    }

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {
        ciContext.clearCaches()
    }

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        let cancelled = stateQueue.sync { shouldCancelAllRequests }
        guard !cancelled else {
            request.finishCancelledRequest()
            return
        }

        renderQueue.async { [weak self] in
            guard let self else {
                request.finishCancelledRequest()
                return
            }
            self.render(request)
        }
    }

    func cancelAllPendingVideoCompositionRequests() {
        stateQueue.sync { shouldCancelAllRequests = true }
        renderQueue.async { [weak self] in
            self?.stateQueue.sync { self?.shouldCancelAllRequests = false }
        }
    }

    private func render(_ request: AVAsynchronousVideoCompositionRequest) {
        do {
            guard
                let instruction = request.videoCompositionInstruction
                    as? EditorTransitionRenderInstruction,
                let output = request.renderContext.newPixelBuffer()
            else {
                throw EditorTransitionCompositorError.invalidInstruction
            }

            let extent = CGRect(origin: .zero, size: instruction.renderSize)
            let state = instruction.state(at: request.compositionTime)
            let instructionLocalTime = max(
                0,
                (request.compositionTime - instruction.timeRange.start).seconds
            )
            let background = backgroundImage(
                for: request,
                instruction: instruction,
                extent: extent
            )

            var composed = background
            if let foregroundBuffer = request.sourceFrame(
                byTrackID: instruction.foregroundTrackID
            ) {
                let sourceSize = CGSize(
                    width: CVPixelBufferGetWidth(foregroundBuffer),
                    height: CVPixelBufferGetHeight(foregroundBuffer)
                )
                let imageTransform = coreImageTransform(
                    from: state.transform,
                    sourceSize: sourceSize,
                    renderSize: instruction.renderSize
                )

                var animatedColor = instruction.colorAdjustment
                if let animation = instruction.animation {
                    animatedColor.presetIntensity = animation.filterIntensity(at: instructionLocalTime)
                }
                var foreground = EditorColorGradeRenderer.applyBase(
                    animatedColor,
                    to: CIImage(cvPixelBuffer: foregroundBuffer)
                )
                foreground = EditorVisualEffectRenderer.apply(
                    instruction.effects,
                    to: foreground,
                    localTime: instructionLocalTime
                )
                foreground = EditorOverlayCompositingRenderer.applyChromaKey(
                    instruction.compositing.chromaKey,
                    to: foreground
                )
                foreground = EditorOverlayCompositingRenderer.applyLumaKey(
                    instruction.compositing.lumaKey,
                    to: foreground
                )
                foreground = foreground.transformed(by: imageTransform)
                if instruction.stabilization?.settings.fillEdges == true {
                    foreground = foreground.clampedToExtent()
                }
                foreground = foreground.cropped(to: extent)

                if animatedColor.masks.contains(where: \.isEffective) {
                    foreground = EditorColorGradeRenderer.applyMasks(
                        animatedColor.masks,
                        to: foreground,
                        clipProgress: instruction.clipProgress(at: request.compositionTime)
                    )
                }

                foreground = EditorOverlayCompositingRenderer.applyMask(
                    instruction.compositing.mask,
                    to: foreground
                )

                foreground = EditorTransitionEffectRenderer.apply(
                    state: state,
                    to: foreground,
                    background: background,
                    extent: extent
                )
                foreground = foreground.applyingOpacity(state.visibility)
                let primaryBackground = EditorOverlayCompositingRenderer.backgroundWithShadow(
                    from: foreground,
                    over: background,
                    settings: instruction.compositing.shadow,
                    extent: extent
                )
                composed = EditorOverlayCompositingRenderer.composite(
                    foreground,
                    over: primaryBackground,
                    using: instruction.compositing.blendMode,
                    extent: extent
                )
            }

            for overlay in instruction.overlayLayers
            where CMTimeRangeContainsTime(overlay.timeRange, time: request.compositionTime) {
                guard let overlayBuffer = request.sourceFrame(byTrackID: overlay.trackID) else {
                    continue
                }
                let sourceSize = CGSize(
                    width: CVPixelBufferGetWidth(overlayBuffer),
                    height: CVPixelBufferGetHeight(overlayBuffer)
                )
                var overlayTransform = overlay.animation?.transform(
                    base: overlay.transform,
                    at: max(0, (request.compositionTime - overlay.timeRange.start).seconds),
                    renderSize: instruction.renderSize
                ) ?? overlay.transform
                if let trackedMotion = overlay.trackedMotion, trackedMotion.isActive {
                    overlayTransform = overlayTransform.concatenating(
                        trackedMotion.extraTransform(
                            at: request.compositionTime,
                            renderSize: instruction.renderSize
                        )
                    )
                }
                let imageTransform = coreImageTransform(
                    from: overlayTransform,
                    sourceSize: sourceSize,
                    renderSize: instruction.renderSize
                )
                let overlayLocalTime = max(
                    0,
                    (request.compositionTime - overlay.timeRange.start).seconds
                )
                var overlayColor = overlay.colorAdjustment
                if let animation = overlay.animation {
                    overlayColor.presetIntensity = animation.filterIntensity(at: overlayLocalTime)
                }
                var overlayImage = EditorColorGradeRenderer.applyBase(
                    overlayColor,
                    to: CIImage(cvPixelBuffer: overlayBuffer)
                )
                overlayImage = EditorVisualEffectRenderer.apply(
                    overlay.effects,
                    to: overlayImage,
                    localTime: overlayLocalTime
                )
                overlayImage = EditorOverlayCompositingRenderer.applyChromaKey(
                    overlay.compositing.chromaKey,
                    to: overlayImage
                )
                overlayImage = EditorOverlayCompositingRenderer.applyLumaKey(
                    overlay.compositing.lumaKey,
                    to: overlayImage
                )
                overlayImage = overlayImage
                    .transformed(by: imageTransform)
                    .cropped(to: extent)

                if overlayColor.masks.contains(where: \.isEffective) {
                    let progress = overlay.timeRange.duration.seconds > 0
                        ? overlayLocalTime / overlay.timeRange.duration.seconds
                        : 0
                    overlayImage = EditorColorGradeRenderer.applyMasks(
                        overlayColor.masks,
                        to: overlayImage,
                        clipProgress: progress
                    )
                }

                overlayImage = EditorOverlayCompositingRenderer.applyMask(
                    overlay.compositing.mask,
                    to: overlayImage
                )

                overlayImage = overlayImage.applyingOpacity(
                    overlay.animation?.opacity(at: overlayLocalTime) ?? CGFloat(overlay.opacity)
                )
                let overlayBackground = EditorOverlayCompositingRenderer.backgroundWithShadow(
                    from: overlayImage,
                    over: composed,
                    settings: overlay.compositing.shadow,
                    extent: extent
                )
                composed = EditorOverlayCompositingRenderer.composite(
                    overlayImage,
                    over: overlayBackground,
                    using: overlay.compositing.blendMode,
                    extent: extent
                )
            }

            for layer in instruction.adjustmentLayers
            where CMTimeRangeContainsTime(layer.timeRange, time: request.compositionTime) {
                let localTime = max(0, (request.compositionTime - layer.timeRange.start).seconds)
                composed = EditorColorGradeRenderer.apply(layer.colorAdjustment, to: composed)
                composed = EditorVisualEffectRenderer.apply(
                    layer.effects,
                    to: composed,
                    localTime: localTime
                )
            }

            ciContext.render(
                composed,
                to: output,
                bounds: extent,
                colorSpace: colorSpace
            )
            request.finish(withComposedVideoFrame: output)
        } catch {
            request.finish(with: error)
        }
    }

    private func backgroundImage(
        for request: AVAsynchronousVideoCompositionRequest,
        instruction: EditorTransitionRenderInstruction,
        extent: CGRect
    ) -> CIImage {
        if instruction.canvasBackgroundKind == .blur,
           let foreground = request.sourceFrame(byTrackID: instruction.foregroundTrackID) {
            let source = CIImage(cvPixelBuffer: foreground)
            let sx = extent.width / max(source.extent.width, 1)
            let sy = extent.height / max(source.extent.height, 1)
            let scale = max(sx, sy)
            let scaled = source.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            let centered = scaled.transformed(by: CGAffineTransform(
                translationX: extent.midX - scaled.extent.midX,
                y: extent.midY - scaled.extent.midY
            ))
            return centered
                .clampedToExtent()
                .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 36])
                .cropped(to: extent)
        }
        if let trackID = instruction.backgroundTrackID,
           let buffer = request.sourceFrame(byTrackID: trackID) {
            return CIImage(cvPixelBuffer: buffer).cropped(to: extent)
        }
        return CIImage(color: .black).cropped(to: extent)
    }

    /// Layer-instruction transforms are authored in AVFoundation's video geometry,
    /// while Core Image evaluates pixel-buffer coordinates from the lower-left.
    /// Conjugating the full (possibly animated) transform with source/output Y flips
    /// preserves identity clips and corrects portrait rotations in every GPU effect.
    private func coreImageTransform(
        from videoTransform: CGAffineTransform,
        sourceSize: CGSize,
        renderSize: CGSize
    ) -> CGAffineTransform {
        let sourceFlip = CGAffineTransform(
            a: 1,
            b: 0,
            c: 0,
            d: -1,
            tx: 0,
            ty: sourceSize.height
        )
        let renderFlip = CGAffineTransform(
            a: 1,
            b: 0,
            c: 0,
            d: -1,
            tx: 0,
            ty: renderSize.height
        )
        return sourceFlip
            .concatenating(videoTransform)
            .concatenating(renderFlip)
    }
}

private enum EditorTransitionCompositorError: LocalizedError {
    case invalidInstruction

    var errorDescription: String? {
        "The transition compositor received an invalid render instruction."
    }
}

private enum EditorTransitionEffectRenderer {
    static func apply(
        state: EditorTransitionRenderState,
        to image: CIImage,
        background: CIImage,
        extent: CGRect
    ) -> CIImage {
        let intensity = CGFloat(min(max(state.intensity, 0), 1))
        guard intensity > 0.001 else { return image }
        let center = CIVector(x: extent.midX, y: extent.midY)

        switch state.kind {
        case .motionBlurLeft:
            return image.applyingFilter(
                "CIMotionBlur",
                parameters: [kCIInputRadiusKey: 42 * intensity, kCIInputAngleKey: 0]
            )
        case .motionBlurRight:
            return image.applyingFilter(
                "CIMotionBlur",
                parameters: [kCIInputRadiusKey: 42 * intensity, kCIInputAngleKey: .pi]
            )
        case .motionBlurUp:
            return image.applyingFilter(
                "CIMotionBlur",
                parameters: [
                    kCIInputRadiusKey: 42 * intensity,
                    kCIInputAngleKey: CGFloat.pi / 2
                ]
            )
        case .motionBlurDown:
            return image.applyingFilter(
                "CIMotionBlur",
                parameters: [
                    kCIInputRadiusKey: 42 * intensity,
                    kCIInputAngleKey: -CGFloat.pi / 2
                ]
            )
        case .zoomBlur:
            return image.applyingFilter(
                "CIZoomBlur",
                parameters: [kCIInputCenterKey: center, kCIInputAmountKey: 48 * intensity]
            )
        case .gaussianBlur:
            return image.applyingFilter(
                "CIGaussianBlur",
                parameters: [kCIInputRadiusKey: 34 * intensity]
            )
        case .radialBlur:
            let orbitingCenter = CIVector(
                x: extent.midX + cos(intensity * .pi * 2) * extent.width * 0.12,
                y: extent.midY + sin(intensity * .pi * 2) * extent.height * 0.12
            )
            return image.applyingFilter(
                "CIZoomBlur",
                parameters: [
                    kCIInputCenterKey: orbitingCenter,
                    kCIInputAmountKey: 64 * intensity
                ]
            )
        case .pixelDissolve:
            return image.applyingFilter(
                "CIPixellate",
                parameters: [
                    kCIInputCenterKey: center,
                    kCIInputScaleKey: 1 + 68 * intensity
                ]
            )
        case .crystallize:
            return image.applyingFilter(
                "CICrystallize",
                parameters: [
                    kCIInputCenterKey: center,
                    kCIInputRadiusKey: 1 + 46 * intensity
                ]
            )
        case .rgbSplit:
            return rgbSplit(image, amount: 30 * intensity)
        case .glitch:
            let jitter = sin(CGFloat(state.progress) * .pi * 14) * 24 * intensity
            let shifted = image.transformed(
                by: CGAffineTransform(translationX: jitter, y: -jitter * 0.25)
            )
            let pixelated = shifted.applyingFilter(
                "CIPixellate",
                parameters: [kCIInputScaleKey: 1 + 16 * intensity]
            )
            return rgbSplit(pixelated, amount: 38 * intensity)
        case .ripple:
            return image.applyingFilter(
                "CITwirlDistortion",
                parameters: [
                    kCIInputCenterKey: center,
                    kCIInputRadiusKey: min(extent.width, extent.height) * 0.62,
                    kCIInputAngleKey: intensity * .pi * 1.7
                ]
            )
        case .fisheye:
            return image.applyingFilter(
                "CIBumpDistortion",
                parameters: [
                    kCIInputCenterKey: center,
                    kCIInputRadiusKey: min(extent.width, extent.height) * 0.72,
                    kCIInputScaleKey: 0.72 * intensity
                ]
            )
        case .kaleidoscope:
            return image.applyingFilter(
                "CIKaleidoscope",
                parameters: [
                    kCIInputCenterKey: center,
                    "inputCount": 4 + Int(8 * intensity),
                    kCIInputAngleKey: intensity * .pi
                ]
            )
        case .bumpPulse:
            return image.applyingFilter(
                "CIBumpDistortion",
                parameters: [
                    kCIInputCenterKey: center,
                    kCIInputRadiusKey: min(extent.width, extent.height) * 0.68,
                    kCIInputScaleKey: -0.78 * intensity
                ]
            )
        case .pinchPulse:
            return image.applyingFilter(
                "CIPinchDistortion",
                parameters: [
                    kCIInputCenterKey: center,
                    kCIInputRadiusKey: min(extent.width, extent.height) * 0.72,
                    kCIInputScaleKey: 0.82 * intensity
                ]
            )
        case .vortexLeft, .vortexRight:
            let direction: CGFloat = state.kind == .vortexLeft ? -1 : 1
            return image.applyingFilter(
                "CITwirlDistortion",
                parameters: [
                    kCIInputCenterKey: center,
                    kCIInputRadiusKey: hypot(extent.width, extent.height) * 0.52,
                    kCIInputAngleKey: direction * intensity * .pi * 2.4
                ]
            )
        case .glassWarp:
            return glassWarp(
                image,
                extent: extent,
                center: center,
                intensity: intensity
            )
        case .triangleMirror:
            return image.applyingFilter(
                "CITriangleKaleidoscope",
                parameters: [
                    "inputPoint": center,
                    "inputSize": min(extent.width, extent.height) * (0.25 + 0.55 * intensity),
                    "inputRotation": intensity * .pi,
                    "inputDecay": 0.85
                ]
            )
        case .torusLens:
            return image.applyingFilter(
                "CITorusLensDistortion",
                parameters: [
                    kCIInputCenterKey: center,
                    kCIInputRadiusKey: min(extent.width, extent.height) * 0.48,
                    "inputWidth": 28 + 110 * intensity,
                    "inputRefraction": 1 + 0.9 * intensity
                ]
            )
        case .comicFlash:
            let comic = image.applyingFilter("CIComicEffect")
            return image.applyingFilter(
                "CIDissolveTransition",
                parameters: [
                    kCIInputTargetImageKey: comic,
                    kCIInputTimeKey: intensity
                ]
            )
        case .bloom:
            return image.applyingFilter(
                "CIBloom",
                parameters: [
                    kCIInputRadiusKey: 8 + 34 * intensity,
                    kCIInputIntensityKey: 0.2 + 1.4 * intensity
                ]
            )
        case .vignettePulse:
            return image.applyingFilter(
                "CIVignetteEffect",
                parameters: [
                    kCIInputCenterKey: center,
                    kCIInputRadiusKey: min(extent.width, extent.height) * (0.9 - 0.45 * intensity),
                    kCIInputIntensityKey: 1.8 * intensity,
                    "inputFalloff": 0.35
                ]
            )
        case .hueSpin:
            return image.applyingFilter(
                "CIHueAdjust",
                parameters: [kCIInputAngleKey: intensity * .pi * 2]
            )
        case .colorInvert:
            return blend(
                image.applyingFilter("CIColorInvert"),
                over: image,
                amount: intensity
            )
        case .posterize:
            return image.applyingFilter(
                "CIColorPosterize",
                parameters: ["inputLevels": max(3, 16 - 12 * intensity)]
            )
        case .noirFlash:
            return blend(
                image.applyingFilter("CIPhotoEffectNoir"),
                over: image,
                amount: intensity
            )
        case .sepiaFlash:
            return image.applyingFilter(
                "CISepiaTone",
                parameters: [kCIInputIntensityKey: intensity]
            )
        case .chromeFlash:
            return blend(
                image.applyingFilter("CIPhotoEffectChrome"),
                over: image,
                amount: intensity
            )
        case .processFlash:
            return blend(
                image.applyingFilter("CIPhotoEffectProcess"),
                over: image,
                amount: intensity
            )
        case .falseColor:
            return image.applyingFilter(
                "CIFalseColor",
                parameters: [
                    "inputColor0": CIColor(
                        red: 0.08,
                        green: 0.02 + 0.2 * intensity,
                        blue: 0.35 + 0.5 * intensity
                    ),
                    "inputColor1": CIColor(
                        red: 1,
                        green: 0.9 - 0.45 * intensity,
                        blue: 0.1
                    )
                ]
            )
        case .edgeGlow:
            let edges = image
                .applyingFilter(
                    "CIEdges",
                    parameters: [kCIInputIntensityKey: 1 + 8 * intensity]
                )
                .applyingFilter(
                    "CIBloom",
                    parameters: [
                        kCIInputRadiusKey: 4 + 18 * intensity,
                        kCIInputIntensityKey: 0.8 + intensity
                    ]
                )
            return blend(edges, over: image, amount: intensity)
        case .circleReveal:
            return maskedReveal(
                image: image,
                background: background,
                extent: extent,
                visibility: state.kind.maskVisibility(for: state)
            )
        case .radialWipe:
            let angle = CGFloat(state.progress) * .pi * 2
            let rotated = image.transformed(
                by: CGAffineTransform(rotationAngle: angle * intensity * 0.18)
            )
            return maskedReveal(
                image: rotated,
                background: background,
                extent: extent,
                visibility: state.kind.maskVisibility(for: state)
            )
        default:
            return image
        }
    }

    private static func blend(
        _ effect: CIImage,
        over image: CIImage,
        amount: CGFloat
    ) -> CIImage {
        image.applyingFilter(
            "CIDissolveTransition",
            parameters: [
                kCIInputTargetImageKey: effect,
                kCIInputTimeKey: min(max(amount, 0), 1)
            ]
        )
    }

    private static func glassWarp(
        _ image: CIImage,
        extent: CGRect,
        center: CIVector,
        intensity: CGFloat
    ) -> CIImage {
        guard let generator = CIFilter(name: "CICheckerboardGenerator") else {
            return image
        }
        generator.setValue(center, forKey: kCIInputCenterKey)
        generator.setValue(CIColor(red: 0.18, green: 0.72, blue: 0.92), forKey: "inputColor0")
        generator.setValue(CIColor(red: 0.82, green: 0.22, blue: 0.62), forKey: "inputColor1")
        generator.setValue(50 + 90 * intensity, forKey: "inputWidth")
        generator.setValue(0.75, forKey: "inputSharpness")
        guard let texture = generator.outputImage?
            .applyingFilter(
                "CIGaussianBlur",
                parameters: [kCIInputRadiusKey: 18 + 16 * intensity]
            )
            .cropped(to: extent)
        else { return image }

        return image.applyingFilter(
            "CIGlassDistortion",
            parameters: [
                "inputTexture": texture,
                kCIInputCenterKey: center,
                kCIInputScaleKey: 120 * intensity
            ]
        )
    }

    private static func rgbSplit(_ image: CIImage, amount: CGFloat) -> CIImage {
        let red = image
            .applyingFilter(
                "CIColorMatrix",
                parameters: [
                    "inputRVector": CIVector(x: 1, y: 0, z: 0, w: 0),
                    "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                    "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0)
                ]
            )
            .transformed(by: CGAffineTransform(translationX: amount, y: 0))
        let green = image.applyingFilter(
            "CIColorMatrix",
            parameters: [
                "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 1, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0)
            ]
        )
        let blue = image
            .applyingFilter(
                "CIColorMatrix",
                parameters: [
                    "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                    "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                    "inputBVector": CIVector(x: 0, y: 0, z: 1, w: 0)
                ]
            )
            .transformed(by: CGAffineTransform(translationX: -amount, y: 0))

        return red
            .applyingFilter(
                "CIAdditionCompositing",
                parameters: [kCIInputBackgroundImageKey: green]
            )
            .applyingFilter(
                "CIAdditionCompositing",
                parameters: [kCIInputBackgroundImageKey: blue]
            )
            .cropped(to: image.extent)
    }

    private static func maskedReveal(
        image: CIImage,
        background: CIImage,
        extent: CGRect,
        visibility: CGFloat
    ) -> CIImage {
        let maximumRadius = hypot(extent.width, extent.height) * 0.55
        let radius = maximumRadius * min(max(visibility, 0), 1)
        guard let radialGradient = CIFilter(name: "CIRadialGradient") else {
            return image
        }
        radialGradient.setValue(
            CIVector(x: extent.midX, y: extent.midY),
            forKey: kCIInputCenterKey
        )
        radialGradient.setValue(max(0, radius - 3), forKey: "inputRadius0")
        radialGradient.setValue(radius + 3, forKey: "inputRadius1")
        radialGradient.setValue(CIColor.white, forKey: "inputColor0")
        radialGradient.setValue(CIColor.clear, forKey: "inputColor1")
        guard let mask = radialGradient.outputImage?.cropped(to: extent) else {
            return image
        }

        return image.applyingFilter(
            "CIBlendWithAlphaMask",
            parameters: [
                kCIInputBackgroundImageKey: background,
                kCIInputMaskImageKey: mask
            ]
        )
    }
}

private extension CIImage {
    func applyingOpacity(_ opacity: CGFloat) -> CIImage {
        let opacity = min(max(opacity, 0), 1)
        guard opacity < 0.999 else { return self }
        return applyingFilter(
            "CIColorMatrix",
            parameters: [
                "inputRVector": CIVector(x: opacity, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: opacity, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: opacity, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: opacity)
            ]
        )
    }
}

private extension EditorTransitionKind {
    func maskVisibility(for state: EditorTransitionRenderState) -> CGFloat {
        CGFloat(1 - state.intensity)
    }
}
