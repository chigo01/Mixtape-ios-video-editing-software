//
//  EditorCompositionBuilder+Speed.swift
//  Mixtape
//

import AVFoundation
import Photos
import UIKit

extension EditorCompositionBuilder {
    static func applySpeed(
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
    static func insertSpeedAdjusted(
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
            // Quantize shared boundaries, not each duration independently. Otherwise
            // rounding can leave gaps or overlap adjacent video/audio slices.
            let segmentSourceEnd = sourceStart + CMTime(
                seconds: segment.sourceStart + segment.sourceDuration,
                preferredTimescale: timescale
            )
            let segmentSourceDuration = segmentSourceEnd - segmentSourceStart
            let segmentTimelineStart = timelineStart + CMTime(
                seconds: segment.timelineStart,
                preferredTimescale: timescale
            )
            let segmentTimelineEnd = timelineStart + CMTime(
                seconds: segment.timelineStart + segment.timelineDuration,
                preferredTimescale: timescale
            )
            let segmentTimelineDuration = segmentTimelineEnd - segmentTimelineStart
            guard segmentSourceDuration > .zero, segmentTimelineDuration > .zero else { continue }
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
    static func segmentsCoveringTimelineExtent(
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
                effects: last.effects,
                compositing: last.compositing,
                animation: nil,
                stabilization: last.stabilization,
                transitionIn: .none,
                transitionOut: .none,
                fadeInDuration: 0,
                fadeOutDuration: 0
            )
        )
        return extended
    }

    static func videoSegment(
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
            effects: clips[clipIndex].effects,
            compositing: clips[clipIndex].compositing,
            animation: renderAnimation(for: clips[clipIndex]),
            stabilization: clips[clipIndex].stabilization.isActive
                ? EditorRenderStabilization(settings: clips[clipIndex].stabilization)
                : nil,
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
}
