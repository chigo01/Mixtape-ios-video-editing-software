//
//  TimelineLayout.swift
//  Mixtape
//

import SwiftUI
import UIKit
import Photos
import AVFoundation

// MARK: - Timeline layout (clip widths + insert gaps)

struct TimelineLayout {
    let clips: [EditorClip]
    let videoDuration: TimeInterval
    let timelineExtent: TimeInterval
    let pixelsPerSecond: CGFloat
    let insertSlotWidth: CGFloat

    var minimumItemWidth: CGFloat {
        Self.minimumItemWidth(for: pixelsPerSecond)
    }

    static func minimumItemWidth(for pixelsPerSecond: CGFloat) -> CGFloat {
        max(4, min(44, 44 * pixelsPerSecond / 18))
    }

    init(
        clips: [EditorClip],
        videoDuration: TimeInterval,
        timelineExtent: TimeInterval,
        pixelsPerSecond: CGFloat,
        insertSlotWidth: CGFloat
    ) {
        self.clips = clips
        self.videoDuration = videoDuration
        self.timelineExtent = max(timelineExtent, videoDuration)
        self.pixelsPerSecond = pixelsPerSecond
        self.insertSlotWidth = insertSlotWidth
    }

    func clipWidth(for clip: EditorClip) -> CGFloat {
        max(minimumItemWidth, CGFloat(clip.duration) * pixelsPerSecond)
    }

    func clipStartContentX(forIndex index: Int) -> CGFloat {
        guard index > 0 else { return insertSlotWidth }
        var x = insertSlotWidth
        for i in 0..<index {
            x += clipWidth(for: clips[i]) + insertSlotWidth
        }
        return x
    }

    var contentWidth: CGFloat {
        guard !clips.isEmpty else { return max(1, CGFloat(timelineExtent) * pixelsPerSecond) }
        let clipsW = clips.reduce(CGFloat(0)) { $0 + clipWidth(for: $1) }
        let base = clipsW + CGFloat(clips.count + 1) * insertSlotWidth
        let extra = max(0, timelineExtent - videoDuration)
        return max(base + CGFloat(extra) * pixelsPerSecond, 1)
    }

    func contentX(forTime time: TimeInterval) -> CGFloat {
        guard !clips.isEmpty else { return CGFloat(max(0, time)) * pixelsPerSecond }
        let clamped = max(0, time)
        if clamped > videoDuration + 1e-9 {
            return contentX(forTime: videoDuration) + CGFloat(clamped - videoDuration) * pixelsPerSecond
        }
        let clampedToVideo = min(clamped, videoDuration)
        var acc: TimeInterval = 0
        var x = insertSlotWidth

        for (index, clip) in clips.enumerated() {
            let duration = clip.duration
            if duration <= 0 { continue }

            if clampedToVideo < acc + duration - 1e-9 || index == clips.count - 1 {
                let local = min(max(0, clampedToVideo - acc), duration)
                return x + CGFloat(local) * pixelsPerSecond
            }

            x += clipWidth(for: clip) + insertSlotWidth
            acc += duration
        }

        return x
    }

    func time(atContentX rawX: CGFloat) -> TimeInterval {
        guard !clips.isEmpty else { return max(0, TimeInterval(rawX / pixelsPerSecond)) }
        let videoEndX = contentX(forTime: videoDuration)
        if rawX > videoEndX + 1 {
            let extra = TimeInterval((rawX - videoEndX) / pixelsPerSecond)
            return videoDuration + extra
        }
        var x = max(0, rawX)
        if x <= insertSlotWidth {
            return 0
        }
        x -= insertSlotWidth
        var acc: TimeInterval = 0

        for clip in clips {
            let cw = clipWidth(for: clip)
            if x <= cw {
                return acc + TimeInterval(x / pixelsPerSecond)
            }
            x -= cw

            if x <= insertSlotWidth {
                return x < insertSlotWidth / 2 ? acc : min(acc + clip.duration, videoDuration)
            }
            x -= insertSlotWidth
            acc += clip.duration
        }

        return videoDuration
    }
}

