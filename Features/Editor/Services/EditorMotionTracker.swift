//
//  EditorMotionTracker.swift
//  Mixtape
//
//  Vision-backed CapCut-style box tracking and camera-path analysis. Work
//  happens off the main actor on downsampled source frames so preview stays
//  interactive.
//

import AVFoundation
import CoreGraphics
import CoreVideo
import Photos
import UIKit
import Vision

enum EditorMotionTracker {
    private static let analysisLongEdge: CGFloat = 960
    private static let maxSamples = 720
    /// Below this, Vision's own match is too weak to trust for this frame's
    /// exact position. Real hand/skin tracking legitimately dips into the
    /// 0.2–0.3 range under normal motion blur and lighting, so this stays
    /// forgiving — the low-confidence streak tolerance above handles the
    /// rest by holding position through brief weak stretches.
    private static let minTrackingConfidence: Float = 0.22

    /// PhotoKit source video. Analysis never reads the live player composition
    /// because `AVAssetImageGenerator` cannot open a custom GPU compositor.
    static func loadSourceAsset(for asset: PHAsset) async -> AVAsset? {
        guard asset.mediaType == .video else { return nil }
        let options = PHVideoRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.version = .current
        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestAVAsset(
                forVideo: asset,
                options: options
            ) { avAsset, _, _ in
                continuation.resume(returning: avAsset)
            }
        }
    }

    static func track(
        _ track: EditorMotionTrack,
        asset: AVAsset,
        sourceTime: @escaping (Double) -> TimeInterval,
        startProgress: Double,
        boundProgress: Double,
        clipDuration: TimeInterval,
        canvasAspect: CGFloat,
        fillCanvas: Bool,
        referenceScale: Double = 1,
        progressHandler: (@Sendable (Double) -> Void)? = nil
    ) async throws -> [EditorMotionTrackSample] {
        try await prepare(asset)
        let duration = max(clipDuration, 0.001)
        let start = min(max(startProgress, 0), 1)
        let bound = min(max(boundProgress, 0), 1)
        let goingForward = bound >= start
        let distance = abs(bound - start)
        let seed = EditorMotionTrackSample.seed(
            progress: start,
            x: track.seedX,
            y: track.seedY,
            rotation: track.seedRotation,
            scale: referenceScale
        )
        guard distance > 0.0001 else { return [seed] }

        // Sample close to the source's own frame rate. A fixed low cap here
        // (this used to be 10 fps) makes correlation tracking lose fast,
        // non-rigid subjects like a swinging hand almost immediately — the
        // per-step displacement between sampled frames outgrows the small
        // motion VNTrackObjectRequest can correlate, so it locks onto
        // whatever static background is left under the box instead. The
        // `maxSamples` budget below still bounds the total for long spans.
        let frameRateCeiling = min(max(await nominalFrameRate(for: asset), 12), 60)
        let sampleRate = min(frameRateCeiling, max(1.0, Double(maxSamples) / max(duration * distance, 1)))
        let sampleCount = max(1, Int(ceil(duration * distance * sampleRate)))
        let step = distance / Double(sampleCount)
        let progresses = (1...sampleCount).map { index in
            goingForward
                ? min(bound, start + Double(index) * step)
                : max(bound, start - Double(index) * step)
        }

        let generator = makeGenerator(asset: asset, sampleRate: sampleRate)
        let firstImage = try await presentationImage(
            from: generator,
            at: sourceTime(start),
            canvasAspect: canvasAspect,
            fillCanvas: fillCanvas
        )

        // A hand's own landmark points (wrist, knuckles) give a stateless,
        // per-frame position/rotation/scale with no drift accumulation —
        // far more reliable for a moving palm than correlating a generic
        // bounding box, which loses lock the moment the hand's silhouette
        // deforms (fingers spreading, rotating, motion blur). Only take
        // this path when the seed box was actually drawn on a hand;
        // everything else (objects, faces, logos, stickers) keeps using
        // the box tracker below unchanged.
        if let handSeed = closestHand(to: visionRect(for: track), in: detectHands(in: firstImage)) {
            let samples = try await trackHand(
                seed: seed,
                handSeed: handSeed,
                track: track,
                progresses: progresses,
                generator: generator,
                sourceTime: sourceTime,
                canvasAspect: canvasAspect,
                fillCanvas: fillCanvas,
                referenceScale: referenceScale,
                progressHandler: progressHandler
            )
            guard samples.count > 1 else { throw EditorMotionTrackingError.lostSubject }
            return samples
        }

        let sequence = VNSequenceRequestHandler()
        var observation = VNDetectedObjectObservation(boundingBox: visionRect(for: track))
        var samples = [seed]
        var previousImage: CGImage? = firstImage
        var previousRotation = track.seedRotation

        for (index, progress) in progresses.enumerated() {
            try Task.checkCancellation()
            progressHandler?(Double(index + 1) / Double(progresses.count))
            let cgImage = try await presentationImage(
                from: generator,
                at: sourceTime(progress),
                canvasAspect: canvasAspect,
                fillCanvas: fillCanvas
            )
            let previousBox = observation.boundingBox
            let request = VNTrackObjectRequest(detectedObjectObservation: observation)
            request.trackingLevel = .accurate
            try sequence.perform([request], on: cgImage, orientation: .up)
            let tracked = request.results?.first as? VNDetectedObjectObservation
            let confidence = tracked?.confidence ?? 0

            let box: CGRect
            if let tracked, confidence >= minTrackingConfidence {
                observation = tracked
                box = tracked.boundingBox
            } else {
                // Hold the last known box rather than abandoning the rest of
                // the clip — a single weak frame (motion blur, brief
                // occlusion, a pose Vision's correlator briefly dislikes)
                // used to cut sampling short here, freezing the graphic in
                // place for everything after it even though later frames
                // often regain a confident match. Re-seed the tracker from
                // the held box every frame so it can recover as soon as the
                // subject is trackable again, all the way to the end of the
                // requested span.
                box = previousBox
                observation = VNDetectedObjectObservation(boundingBox: previousBox)
            }

            // Geometric mean of the width/height ratios: an unchanged box
            // must resolve to scale 1. (Euclidean norm of two ~1 ratios
            // would read ~1.41 and inflate every attached graphic.)
            let widthRatio = box.width / max(track.seedWidth, 0.02)
            let heightRatio = box.height / max(track.seedHeight, 0.02)
            let scale = max((widthRatio * heightRatio).squareRoot() * referenceScale, 0.05)
            // Estimate rotation from crops around the tracked box only — a
            // full-frame homography mostly measures the (mostly static)
            // background, not the subject's own spin.
            var rotation = previousRotation
            if let previousImage,
               let previousPatch = croppedPatch(previousImage, boundingBox: previousBox, padding: 0.4),
               let currentPatch = croppedPatch(cgImage, boundingBox: box, padding: 0.4),
               let delta = homographyDelta(from: previousPatch, to: currentPatch) {
                rotation = wrapAngle(previousRotation + delta.rotation)
            }

            var sample = EditorMotionTrackSample(
                progress: progress,
                x: box.midX,
                y: 1 - box.midY,
                rotation: rotation,
                scale: scale,
                confidence: Double(confidence)
            )
            sample.sanitize()
            samples.append(sample)
            previousImage = cgImage
            previousRotation = rotation
        }

        guard samples.count > 1 else { throw EditorMotionTrackingError.lostSubject }
        return samples
    }

    private struct HandLandmarks {
        let center: CGPoint
        let rotation: Double
        let span: Double
        let confidence: Double
    }

    /// Walks the requested progresses using per-frame hand-pose detection
    /// instead of sequential correlation. Each frame is an independent
    /// detection, so — unlike the box tracker — a missed frame can never
    /// compound into permanent drift; the very next confident detection
    /// snaps straight back onto the real hand.
    private static func trackHand(
        seed: EditorMotionTrackSample,
        handSeed: HandLandmarks,
        track: EditorMotionTrack,
        progresses: [Double],
        generator: AVAssetImageGenerator,
        sourceTime: @escaping (Double) -> TimeInterval,
        canvasAspect: CGFloat,
        fillCanvas: Bool,
        referenceScale: Double,
        progressHandler: (@Sendable (Double) -> Void)?
    ) async throws -> [EditorMotionTrackSample] {
        var samples = [seed]
        var previousCenter = handSeed.center
        let seedRotation = handSeed.rotation
        let seedSpan = max(handSeed.span, 0.01)
        // How far the hand may plausibly move between two sampled frames
        // before a detection in the new frame counts as a different hand
        // rather than the one being tracked. Generous because sampling now
        // runs near native frame rate, so real inter-frame motion is small.
        let associationGate = 0.3

        for (index, progress) in progresses.enumerated() {
            try Task.checkCancellation()
            progressHandler?(Double(index + 1) / Double(progresses.count))
            let cgImage = try await presentationImage(
                from: generator,
                at: sourceTime(progress),
                canvasAspect: canvasAspect,
                fillCanvas: fillCanvas
            )
            let matched = detectHands(in: cgImage)
                .filter {
                    hypot($0.center.x - previousCenter.x, $0.center.y - previousCenter.y) <= associationGate
                }
                .min {
                    hypot($0.center.x - previousCenter.x, $0.center.y - previousCenter.y)
                        < hypot($1.center.x - previousCenter.x, $1.center.y - previousCenter.y)
                }

            let center: CGPoint
            let rotation: Double
            let span: Double
            let confidence: Double
            if let matched {
                center = matched.center
                rotation = matched.rotation
                span = matched.span
                confidence = matched.confidence
                previousCenter = center
            } else {
                // Hold position — no template to drift, so this is a true
                // pause, not a slow slide onto the wrong thing.
                center = previousCenter
                rotation = seedRotation
                span = seedSpan
                confidence = 0
            }

            var sample = EditorMotionTrackSample(
                progress: progress,
                x: center.x,
                y: 1 - center.y,
                rotation: track.seedRotation + wrapAngle(rotation - seedRotation),
                scale: max((span / seedSpan) * referenceScale, 0.05),
                confidence: confidence
            )
            sample.sanitize()
            samples.append(sample)
        }
        return samples
    }

    /// Detects up to two hands and derives a similarity transform (center,
    /// rotation, scale proxy) from named landmarks rather than a bounding
    /// box, so it tracks the hand's actual pose instead of a drifting crop.
    private static func detectHands(in image: CGImage) -> [HandLandmarks] {
        let request = VNDetectHumanHandPoseRequest()
        request.maximumHandCount = 2
        let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
        guard (try? handler.perform([request])) != nil,
              let observations = request.results else {
            return []
        }
        let minConfidence: Float = 0.3
        return observations.compactMap { observation -> HandLandmarks? in
            guard let wrist = try? observation.recognizedPoint(.wrist),
                  let middleMCP = try? observation.recognizedPoint(.middleMCP),
                  let indexMCP = try? observation.recognizedPoint(.indexMCP),
                  let littleMCP = try? observation.recognizedPoint(.littleMCP),
                  wrist.confidence >= minConfidence,
                  middleMCP.confidence >= minConfidence,
                  indexMCP.confidence >= minConfidence,
                  littleMCP.confidence >= minConfidence
            else { return nil }
            let center = CGPoint(
                x: (wrist.location.x + middleMCP.location.x) / 2,
                y: (wrist.location.y + middleMCP.location.y) / 2
            )
            let axis = CGVector(
                dx: middleMCP.location.x - wrist.location.x,
                dy: middleMCP.location.y - wrist.location.y
            )
            let rotation = atan2(Double(axis.dy), Double(axis.dx)) - .pi / 2
            let span = hypot(
                indexMCP.location.x - littleMCP.location.x,
                indexMCP.location.y - littleMCP.location.y
            )
            let confidence = Double(
                min(min(wrist.confidence, middleMCP.confidence), min(indexMCP.confidence, littleMCP.confidence))
            )
            return HandLandmarks(center: center, rotation: rotation, span: max(span, 0.01), confidence: confidence)
        }
    }

    /// Picks the detected hand nearest the seed box's center, gated to
    /// roughly the box's own footprint so an unrelated hand elsewhere in
    /// frame is never mistaken for the one the user boxed.
    private static func closestHand(to rect: CGRect, in hands: [HandLandmarks]) -> HandLandmarks? {
        guard !hands.isEmpty else { return nil }
        let target = CGPoint(x: rect.midX, y: rect.midY)
        let gate = max(hypot(rect.width, rect.height), 0.12) * 2
        guard let closest = hands.min(by: {
            hypot($0.center.x - target.x, $0.center.y - target.y)
                < hypot($1.center.x - target.x, $1.center.y - target.y)
        }) else { return nil }
        guard hypot(closest.center.x - target.x, closest.center.y - target.y) <= gate else { return nil }
        return closest
    }

    static func analyzeStabilization(
        asset: AVAsset,
        sourceTime: @escaping (Double) -> TimeInterval,
        clipDuration: TimeInterval,
        progressHandler: (@Sendable (Double) -> Void)? = nil
    ) async throws -> [EditorMotionTrackSample] {
        try await prepare(asset)
        let duration = max(clipDuration, 0.001)
        let frameRateCeiling = min(max(await nominalFrameRate(for: asset), 18), 30)
        let sampleRate = min(frameRateCeiling, max(16.0, Double(maxSamples) / max(duration, 1)))
        let sampleCount = max(2, Int(ceil(duration * sampleRate)))
        let generator = makeGenerator(asset: asset, sampleRate: sampleRate)

        var samples: [EditorMotionTrackSample] = [
            .seed(progress: 0, x: 0.5, y: 0.5)
        ]
        var previousImage = try await image(from: generator, at: sourceTime(0))
        var cumulativeX = 0.0
        var cumulativeY = 0.0
        var cumulativeRotation = 0.0
        let referenceSize = CGSize(
            width: previousImage.width,
            height: previousImage.height
        )
        let maxStepTranslation = 0.08
        let maxJump = 0.18
        let maxStepRotation = 3.0 * .pi / 180

        for index in 1..<sampleCount {
            try Task.checkCancellation()
            let progress = Double(index) / Double(sampleCount - 1)
            progressHandler?(progress)
            let current = try await image(from: generator, at: sourceTime(progress))
            let motion = opticalFlowDelta(from: previousImage, to: current, imageSize: referenceSize)
                ?? registration(from: previousImage, to: current, imageSize: referenceSize)
            if let motion {
                let jump = hypot(motion.x, motion.y)
                if jump < maxJump {
                    cumulativeX += min(max(motion.x, -maxStepTranslation), maxStepTranslation)
                    cumulativeY += min(max(motion.y, -maxStepTranslation), maxStepTranslation)
                }
                if abs(motion.rotation) <= maxStepRotation {
                    cumulativeRotation += motion.rotation
                }
            }
            samples.append(
                EditorMotionTrackSample(
                    progress: progress,
                    x: min(max(0.5 + cumulativeX, -0.25), 1.25),
                    y: min(max(0.5 + cumulativeY, -0.25), 1.25),
                    rotation: cumulativeRotation,
                    scale: 1,
                    confidence: 1
                )
            )
            previousImage = current
        }

        guard samples.count > 1 else { throw EditorMotionTrackingError.lostSubject }
        return samples
    }

    private static func prepare(_ asset: AVAsset) async throws {
        do {
            _ = try await asset.load(.tracks)
        } catch {
            throw EditorMotionTrackingError.unavailableFrame
        }
    }

    private static func nominalFrameRate(for asset: AVAsset) async -> Double {
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let rate = try? await track.load(.nominalFrameRate),
              rate > 0 else {
            return 30
        }
        return Double(rate)
    }

    private static func makeGenerator(
        asset: AVAsset,
        sampleRate: Double
    ) -> AVAssetImageGenerator {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: analysisLongEdge, height: analysisLongEdge)
        let tolerance = CMTime(seconds: 1 / max(sampleRate * 2, 1), preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance
        return generator
    }

    private static func image(
        from generator: AVAssetImageGenerator,
        at seconds: TimeInterval
    ) async throws -> CGImage {
        do {
            let result = try await generator.image(
                at: CMTime(seconds: max(0, seconds), preferredTimescale: 600)
            )
            return result.image
        } catch {
            throw EditorMotionTrackingError.unavailableFrame
        }
    }

    private static func presentationImage(
        from generator: AVAssetImageGenerator,
        at seconds: TimeInterval,
        canvasAspect: CGFloat,
        fillCanvas: Bool
    ) async throws -> CGImage {
        let source = try await image(from: generator, at: seconds)
        return fit(source, toCanvasAspect: canvasAspect, fill: fillCanvas)
    }

    /// Letterbox or fill the source into the project canvas so tracker
    /// coordinates match the preview the user placed the box on.
    private static func fit(
        _ source: CGImage,
        toCanvasAspect canvasAspect: CGFloat,
        fill: Bool
    ) -> CGImage {
        let aspect = max(canvasAspect, 0.05)
        let raw = aspect >= 1
            ? CGSize(width: analysisLongEdge, height: analysisLongEdge / aspect)
            : CGSize(width: analysisLongEdge * aspect, height: analysisLongEdge)
        let width = max(2, (Int(raw.width.rounded()) / 2) * 2)
        let height = max(2, (Int(raw.height.rounded()) / 2) * 2)
        let canvas = CGSize(width: width, height: height)
        let sourceSize = CGSize(width: source.width, height: source.height)
        guard sourceSize.width > 0, sourceSize.height > 0 else { return source }
        let scale = fill
            ? max(canvas.width / sourceSize.width, canvas.height / sourceSize.height)
            : min(canvas.width / sourceSize.width, canvas.height / sourceSize.height)
        let draw = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
        let origin = CGPoint(
            x: (canvas.width - draw.width) / 2,
            y: (canvas.height - draw.height) / 2
        )

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return source }
        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(origin: .zero, size: canvas))
        context.interpolationQuality = .high
        context.draw(source, in: CGRect(origin: origin, size: draw))
        return context.makeImage() ?? source
    }

    /// Crops an analysis frame to a padded region around a Vision bounding box
    /// (normalized, bottom-left origin) so registration only sees the tracked
    /// subject, not unrelated background content.
    private static func croppedPatch(
        _ image: CGImage,
        boundingBox: CGRect,
        padding: CGFloat
    ) -> CGImage? {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        guard width > 0, height > 0 else { return nil }
        let expandedWidth = min(boundingBox.width * (1 + padding * 2), 1)
        let expandedHeight = min(boundingBox.height * (1 + padding * 2), 1)
        let originX = min(max(boundingBox.midX - expandedWidth / 2, 0), 1 - expandedWidth)
        // Vision's origin is bottom-left; CGImage cropping is top-left.
        let originYTopLeft = min(
            max((1 - boundingBox.midY) - expandedHeight / 2, 0),
            1 - expandedHeight
        )
        let pixelRect = CGRect(
            x: (originX * width).rounded(),
            y: (originYTopLeft * height).rounded(),
            width: max((expandedWidth * width).rounded(), 8),
            height: max((expandedHeight * height).rounded(), 8)
        )
        return image.cropping(to: pixelRect)
    }

    private static func visionRect(for track: EditorMotionTrack) -> CGRect {
        CGRect(
            x: min(max(track.seedX - track.seedWidth / 2, 0), 1),
            y: min(max(1 - (track.seedY + track.seedHeight / 2), 0), 1),
            width: min(max(track.seedWidth, 0.02), 1),
            height: min(max(track.seedHeight, 0.02), 1)
        )
    }

    private static func homographyDelta(
        from previous: CGImage,
        to current: CGImage
    ) -> (rotation: Double, scale: Double)? {
        let request = VNHomographicImageRegistrationRequest(targetedCGImage: current)
        let handler = VNImageRequestHandler(cgImage: previous, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        guard let observation = request.results?.first as? VNImageHomographicAlignmentObservation else {
            return nil
        }
        let matrix = observation.warpTransform
        let rotation = atan2(Double(matrix.columns.0.y), Double(matrix.columns.0.x))
        let scale = hypot(Double(matrix.columns.0.x), Double(matrix.columns.0.y))
        guard scale.isFinite, rotation.isFinite else { return nil }
        return (wrapAngle(rotation), min(max(scale, 0.05), 8))
    }

    private static func registration(
        from previous: CGImage,
        to current: CGImage,
        imageSize: CGSize
    ) -> (x: Double, y: Double, rotation: Double)? {
        let width = max(Double(imageSize.width), 1)
        let height = max(Double(imageSize.height), 1)

        let translationRequest = VNTranslationalImageRegistrationRequest(targetedCGImage: current)
        let handler = VNImageRequestHandler(cgImage: previous, options: [:])
        do {
            try handler.perform([translationRequest])
        } catch {
            return nil
        }
        guard let translation = translationRequest.results?.first as? VNImageTranslationAlignmentObservation else {
            return nil
        }
        // Inverse of "align current onto previous" is the content motion of current.
        let inverse = translation.alignmentTransform.inverted()
        var rotation = 0.0
        // Full-frame homography on repeating texture or moving subjects
        // reports garbage spin and the inverse warp deforms the clip.
        // Only keep a tiny rigid rotation when the scale is near 1.
        if let homography = homographyDelta(from: previous, to: current),
           abs(homography.scale - 1) < 0.04,
           abs(homography.rotation) < 2.0 * .pi / 180 {
            rotation = homography.rotation
        }
        return (
            Double(inverse.tx) / width,
            Double(inverse.ty) / height,
            rotation
        )
    }

    /// Median optical-flow translation plus a least-squares rigid rotation.
    /// Much more stable than a single full-frame homography on repeating texture.
    private static func opticalFlowDelta(
        from previous: CGImage,
        to current: CGImage,
        imageSize: CGSize
    ) -> (x: Double, y: Double, rotation: Double)? {
        let width = max(Double(imageSize.width), 1)
        let height = max(Double(imageSize.height), 1)
        let request = VNGenerateOpticalFlowRequest(targetedCGImage: current)
        request.computationAccuracy = .low
        let handler = VNImageRequestHandler(cgImage: previous, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        guard let observation = request.results?.first as? VNPixelBufferObservation else {
            return nil
        }
        let buffer = observation.pixelBuffer
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let flowWidth = CVPixelBufferGetWidth(buffer)
        let flowHeight = CVPixelBufferGetHeight(buffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let format = CVPixelBufferGetPixelFormatType(buffer)
        guard flowWidth > 8, flowHeight > 8 else { return nil }

        let stepX = max(flowWidth / 20, 1)
        let stepY = max(flowHeight / 20, 1)
        var xs: [Double] = []
        var ys: [Double] = []
        var points: [(x: Double, y: Double, vx: Double, vy: Double)] = []
        xs.reserveCapacity(400)
        ys.reserveCapacity(400)

        for py in stride(from: stepY, to: flowHeight - stepY, by: stepY) {
            for px in stride(from: stepX, to: flowWidth - stepX, by: stepX) {
                let vx: Double
                let vy: Double
                guard format == kCVPixelFormatType_TwoComponent32Float else { return nil }
                let row = base.advanced(by: py * bytesPerRow).assumingMemoryBound(to: Float.self)
                vx = Double(row[px * 2])
                vy = Double(row[px * 2 + 1])
                guard vx.isFinite, vy.isFinite else { continue }
                let mag = hypot(vx, vy)
                guard mag < 0.28 * width else { continue }
                let nx = Double(px) / Double(flowWidth) - 0.5
                let ny = Double(py) / Double(flowHeight) - 0.5
                xs.append(vx / width)
                ys.append(vy / height)
                points.append((nx, ny, vx / width, vy / height))
            }
        }
        guard xs.count >= 24 else { return nil }
        let tx = median(xs)
        let ty = median(ys)
        var numer = 0.0
        var denom = 0.0
        for point in points {
            let dvx = point.vx - tx
            let dvy = point.vy - ty
            if hypot(dvx, dvy) > 0.08 { continue }
            numer += dvy * point.x - dvx * point.y
            denom += point.x * point.x + point.y * point.y
        }
        let rotation = denom > 0.000_1 ? numer / denom : 0
        guard rotation.isFinite, tx.isFinite, ty.isFinite else { return nil }
        return (tx, ty, wrapAngle(rotation))
    }

    private static func median(_ values: [Double]) -> Double {
        let ordered = values.sorted()
        let mid = ordered.count / 2
        if ordered.count.isMultiple(of: 2), mid > 0 {
            return (ordered[mid - 1] + ordered[mid]) / 2
        }
        return ordered[mid]
    }

    private static func wrapAngle(_ value: Double) -> Double {
        var angle = value
        while angle > .pi { angle -= 2 * .pi }
        while angle < -.pi { angle += 2 * .pi }
        return angle
    }
}
