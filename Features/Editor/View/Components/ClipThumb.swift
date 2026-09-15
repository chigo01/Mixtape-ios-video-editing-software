//
//  ClipThumb.swift
//  Mixtape
//

import SwiftUI
import UIKit
import Photos
import AVFoundation

// MARK: - Clip thumbnail

struct ClipThumb: View {
    let clip: EditorClip
    let width: CGFloat
    let clipTimelineStart: TimeInterval
    let isSelected: Bool
    let pixelsPerSecond: CGFloat
    let scrubMinimumDistance: CGFloat
    let height: CGFloat
    let clipIndex: Int
    let reorderMetrics: TimelineClipMetrics
    let reorderState: ClipReorderState
    let canReorder: Bool
    let allowsEditing: Bool
    let onScrub: (TimeInterval) -> Void
    let onScrubCommit: () -> Void
    let onScrubbingChanged: (Bool) -> Void
    let onSelectForEditing: () -> Void
    let onTrimChanged: (TimeInterval, TimeInterval) -> Void
    let onTrimEnded: () -> Void
    let onMoveClip: (Int, Int) -> Void

    @State private var isTrimming = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            ClipFilmstripView(clip: clip, width: width, height: height)

            HStack(spacing: 4) {
                Text(format(duration: clip.duration))
                    .font(.system(size: 8, weight: .semibold).monospacedDigit())
                    .foregroundColor(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.black.opacity(0.55)))
                if clip.playback.isReverse {
                    Label("REV", systemImage: "backward.end.alt.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.cyan))
                } else if clip.playback.isFreezeFrame {
                    Label("HOLD", systemImage: "snowflake")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.blue.opacity(0.9)))
                }
                if clip.speedRamp != nil {
                    Label("Curve", systemImage: "waveform.path.ecg")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.appColors.primaryColor))
                } else if abs(clip.speed - 1.0) > 0.02 {
                    Text(String(format: "%.2g×", clip.speed))
                        .font(.system(size: 8, weight: .bold).monospacedDigit())
                        .foregroundColor(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.appColors.primaryColor.opacity(0.85)))
                }
                if clip.isVideo && !clip.isAudioLinked {
                    Label("J/L", systemImage: "link.slash")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.orange))
                }
            }
            .padding(4)
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(isSelected ? Color.appColors.primaryColor : Color.clear, lineWidth: 2)
        )
        .overlay {
            if canReorder {
                ClipReorderGestureRepresentable(
                    clipIndex: clipIndex,
                    metrics: reorderMetrics,
                    reorderState: reorderState,
                    onMove: onMoveClip
                )
            }
        }
        .overlay {
            if isSelected && allowsEditing {
                ClipTrimHandleRepresentable(
                    clipID: clip.id,
                    trimStart: clip.trimStart,
                    trimEnd: clip.trimEnd,
                    originalDuration: clip.originalDuration,
                    allowsDurationExtension: clip.isPhoto,
                    speed: clip.averageSpeed,
                    pixelsPerSecond: pixelsPerSecond,
                    onTrimChanged: { _, start, end in
                        isTrimming = true
                        onTrimChanged(start, end)
                    },
                    onTrimEnded: {
                        isTrimming = false
                        onTrimEnded()
                    }
                )
                .allowsHitTesting(true)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isTrimming else { return }
            onSelectForEditing()
        }
        .gesture(thumbScrubGesture())
    }

    private func thumbScrubGesture() -> some Gesture {
        DragGesture(minimumDistance: scrubMinimumDistance, coordinateSpace: .local)
            .onChanged { v in
                guard allowsEditing else { return }
                guard !isTrimming else { return }
                onScrubbingChanged(true)
                let frac = width > 0 ? max(0, min(1, v.location.x / width)) : 0
                let t = clipTimelineStart + frac * clip.duration
                onScrub(t)
            }
            .onEnded { _ in
                onScrubbingChanged(false)
                onScrubCommit()
            }
    }

    private func format(duration: TimeInterval) -> String {
        let t = Int(duration.rounded())
        return String(format: "%d:%02d", t / 60, t % 60)
    }

}

