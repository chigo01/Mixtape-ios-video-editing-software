//
//  EditorColorMaskTracker.swift
//  Mixtape
//
//  Bidirectional Vision tracking for color power windows.
//

import AVFoundation
import Vision

enum EditorColorMaskTrackingDirection {
    case backward
    case forward
}

enum EditorColorMaskTrackingError: LocalizedError {
    case unavailableFrame
    case lostSubject

    var errorDescription: String? {
        switch self {
        case .unavailableFrame: return "A video frame could not be read for tracking."
        case .lostSubject: return "The tracker lost the subject. Try a tighter mask on a clearer frame."
        }
    }
}

enum EditorColorMaskTracker {
    static func track(
        mask: EditorColorMask,
        asset: AVAsset,
        videoComposition: AVVideoComposition?,
        clipStart: TimeInterval,
        clipDuration: TimeInterval,
        startProgress: Double,
        direction: EditorColorMaskTrackingDirection
    ) async throws -> [EditorColorMaskTrackingKeyframe] {
        let duration = max(clipDuration, 0.001)
        let start = min(max(startProgress, 0), 1)
        let distance = direction == .forward ? 1 - start : start
        guard distance > 0.0001 else { return [sample(for: mask, progress: start, confidence: 1)] }

        // Ten samples/second is responsive for typical clips; long clips taper
        // toward one sample/second and never exceed the persisted 720-sample cap.
        let sampleRate = min(10.0, max(1.0, 720.0 / max(duration * distance, 1)))
        let sampleCount = max(1, Int(ceil(duration * distance * sampleRate)))
        let step = distance / Double(sampleCount)
        let progresses = (1...sampleCount).map { index in
            direction == .forward
                ? min(1, start + Double(index) * step)
                : max(0, start - Double(index) * step)
        }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.videoComposition = videoComposition
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 960, height: 960)
        let tolerance = CMTime(seconds: 1 / max(sampleRate * 2, 1), preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance

        let sequence = VNSequenceRequestHandler()
        var observation = VNDetectedObjectObservation(boundingBox: visionRect(for: mask))
        var samples = [sample(for: mask, progress: start, confidence: 1)]

        for progress in progresses {
            try Task.checkCancellation()
            let timelineTime = clipStart + progress * duration
            let result = try await generator.image(
                at: CMTime(seconds: timelineTime, preferredTimescale: 600)
            )
            let request = VNTrackObjectRequest(detectedObjectObservation: observation)
            request.trackingLevel = .accurate
            try sequence.perform([request], on: result.image, orientation: .up)
            guard let tracked = request.results?.first as? VNDetectedObjectObservation,
                  tracked.confidence >= 0.2 else { break }
            observation = tracked
            samples.append(sample(from: tracked, progress: progress))
        }

        guard samples.count > 1 else { throw EditorColorMaskTrackingError.lostSubject }
        return samples
    }

    private static func visionRect(for mask: EditorColorMask) -> CGRect {
        let box: CGRect
        if mask.shape == .polygon, !mask.points.isEmpty {
            let xs = mask.points.map(\.x)
            let ys = mask.points.map(\.y)
            let minX = xs.min() ?? 0
            let maxX = xs.max() ?? 1
            let minY = ys.min() ?? 0
            let maxY = ys.max() ?? 1
            box = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        } else {
            box = CGRect(
                x: mask.centerX - mask.width / 2,
                y: mask.centerY - mask.height / 2,
                width: mask.width,
                height: mask.height
            )
        }
        return CGRect(
            x: min(max(box.minX, 0), 1),
            y: min(max(1 - box.maxY, 0), 1),
            width: min(max(box.width, 0.02), 1),
            height: min(max(box.height, 0.02), 1)
        )
    }

    private static func sample(
        from observation: VNDetectedObjectObservation,
        progress: Double
    ) -> EditorColorMaskTrackingKeyframe {
        let box = observation.boundingBox
        return EditorColorMaskTrackingKeyframe(
            progress: progress,
            centerX: box.midX,
            centerY: 1 - box.midY,
            width: box.width,
            height: box.height,
            confidence: Double(observation.confidence)
        )
    }

    private static func sample(
        for mask: EditorColorMask,
        progress: Double,
        confidence: Double
    ) -> EditorColorMaskTrackingKeyframe {
        let box = visionRect(for: mask)
        return EditorColorMaskTrackingKeyframe(
            progress: progress,
            centerX: box.midX,
            centerY: 1 - box.midY,
            width: box.width,
            height: box.height,
            confidence: confidence
        )
    }
}
