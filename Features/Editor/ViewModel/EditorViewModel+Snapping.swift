//
//  EditorViewModel+Snapping.swift
//  Mixtape
//

import SwiftUI
import UIKit
import AVFoundation
import Photos

extension EditorViewModel {
    func snappedTime(
        _ proposed: TimeInterval,
        excluding excludedID: UUID? = nil,
        pixelsPerSecond: CGFloat = 18,
        thresholdPoints: CGFloat = 8
    ) -> TimeInterval {
        let clamped = min(max(0, proposed), totalDuration)
        var candidates: [TimeInterval] = [0, videoDuration, totalDuration]
        var cursor: TimeInterval = 0
        for clip in clips {
            cursor += clip.duration
            if clip.id != excludedID { candidates.append(cursor) }
        }
        for clip in audioClips where clip.id != excludedID {
            candidates.append(contentsOf: [clip.timelineStart, clip.timelineEnd])
        }
        for overlay in textOverlays where overlay.id != excludedID {
            candidates.append(contentsOf: [overlay.startTime, overlay.endTime])
        }
        for overlay in graphicOverlays where overlay.id != excludedID {
            candidates.append(contentsOf: [overlay.startTime, overlay.endTime])
        }
        for clip in overlayClips where clip.id != excludedID {
            candidates.append(contentsOf: [clip.timelineStart, clip.timelineEnd])
        }
        if let exportInPoint { candidates.append(exportInPoint) }
        if let exportOutPoint { candidates.append(exportOutPoint) }
        candidates.append(contentsOf: markers.map(\.time))

        let threshold = TimeInterval(thresholdPoints / max(pixelsPerSecond, 1))
        guard let nearest = candidates.min(by: { abs($0 - clamped) < abs($1 - clamped) }),
              abs(nearest - clamped) <= threshold else {
            snapGuideTime = nil
            lastHapticSnapTime = nil
            return clamped
        }
        snapGuideTime = nearest
        if lastHapticSnapTime != nearest {
            UISelectionFeedbackGenerator().selectionChanged()
            lastHapticSnapTime = nearest
        }
        return nearest
    }

    func clearSnapGuide() {
        snapGuideTime = nil
        lastHapticSnapTime = nil
    }
}
