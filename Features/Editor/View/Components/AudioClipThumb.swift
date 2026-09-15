//
//  AudioClipThumb.swift
//  Mixtape
//

import SwiftUI
import UIKit
import Photos
import AVFoundation

// MARK: - Audio clip thumb (mirrors ClipThumb trim / scrub behaviour)

struct AudioClipThumb: View {
    let clip: EditorAudioClip
    let pixelsPerSecond: CGFloat
    let scrubMinimumDistance: CGFloat
    let laneHeight: CGFloat
    let isSelected: Bool
    let allowsEditing: Bool
    @Binding var isTrimming: Bool
    @Binding var isMoving: Bool
    let onSelect: () -> Void
    let onScrub: (TimeInterval) -> Void
    let onScrubCommit: () -> Void
    let onTrimChanged: (TimeInterval, TimeInterval) -> Void
    let onTrimEnded: () -> Void
    let onMove: (TimeInterval) -> Void
    let onMoveToLane: (Int) -> Void
    let onMoveEnded: () -> Void

    @State private var trimBaseline: (timelineStart: TimeInterval, trimStart: TimeInterval)?
    @State private var moveBaselineTimelineStart: TimeInterval?
    @State private var moveTranslation: CGSize = .zero
    @State private var isHoldActive = false
    /// Full-file peak envelope from `AudioWaveformGenerator`. The visible bars are sliced to
    /// this clip's trim window so the waveform matches the audio you actually hear.
    @State private var waveform: AudioWaveform?

    private var width: CGFloat {
        max(
            TimelineLayout.minimumItemWidth(for: pixelsPerSecond),
            CGFloat(clip.duration) * pixelsPerSecond
        )
    }

    /// During a leading-edge trim the clip must shift on the timeline without
    /// updating `clip.timelineStart` in the model (that re-layout breaks the UIKit handle drag).
    private var displayTimelineStart: TimeInterval {
        if let base = trimBaseline {
            return max(0, base.timelineStart + (clip.trimStart - base.trimStart))
        }
        return clip.timelineStart
    }

    var body: some View {
        let content = clipVisual
            .overlay {
                if isSelected && allowsEditing {
                    ClipTrimHandleRepresentable(
                        clipID: clip.id,
                        trimStart: clip.trimStart,
                        trimEnd: clip.trimEnd,
                        originalDuration: clip.originalDuration,
                        allowsDurationExtension: false,
                        speed: 1.0,
                        pixelsPerSecond: pixelsPerSecond,
                        onTrimChanged: { _, start, end in
                            if trimBaseline == nil {
                                trimBaseline = (clip.timelineStart, clip.trimStart)
                            }
                            isTrimming = true
                            onTrimChanged(start, end)
                        },
                        onTrimEnded: {
                            isTrimming = false
                            trimBaseline = nil
                            onTrimEnded()
                        }
                    )
                    .frame(width: width, height: laneHeight)
                    .allowsHitTesting(true)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                guard !isTrimming, !isMoving else { return }
                onSelect()
            }
            .scaleEffect(isHoldActive ? 1.04 : 1)
            .shadow(color: .black.opacity(isHoldActive ? 0.5 : 0), radius: 7, y: 3)
            .offset(
                x: CGFloat(displayTimelineStart) * pixelsPerSecond,
                y: moveTranslation.height
            )

        if isSelected && allowsEditing {
            content.gesture(moveGesture)
        } else {
            content.gesture(scrubGesture)
        }
    }

    private var displayedWaveformSamples: [CGFloat] {
        guard let waveform else { return [] }
        let barCount = max(8, Int(width / 1.6))
        return waveform.buckets(start: clip.trimStart, end: clip.trimEnd, count: barCount)
    }

    private var clipVisual: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.appColors.primaryColor.opacity(isSelected ? 0.28 : 0.18))

            WaveformShape(samples: displayedWaveformSamples)
                .fill(Color.appColors.primaryColor.opacity(isSelected ? 0.95 : 0.82))
                .padding(.vertical, 3)
                .task(id: clip.playbackFileURL) {
                    waveform = await AudioWaveformGenerator.shared.waveform(for: clip.playbackFileURL)
                }

            HStack(spacing: 5) {
                Image(systemName: "music.note")
                    .font(.system(size: 9, weight: .bold))
                Text(clip.title)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundColor(Color.white.opacity(0.85))
            .padding(.horizontal, 8)
        }
        .frame(width: width, height: laneHeight, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(isSelected ? Color.appColors.primaryColor : Color.appColors.primaryColor.opacity(0.55),
                        lineWidth: isSelected ? 2 : 1)
        )
    }

    private var scrubGesture: some Gesture {
        DragGesture(minimumDistance: scrubMinimumDistance, coordinateSpace: .local)
            .onChanged { value in
                guard !isTrimming else { return }
                let frac = width > 0 ? max(0, min(1, value.location.x / width)) : 0
                let t = clip.timelineStart + frac * clip.duration
                onScrub(t)
            }
            .onEnded { _ in
                guard !isTrimming else { return }
                onScrubCommit()
            }
    }

    private var moveGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.28, maximumDistance: 16)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
            .onChanged { value in
                guard !isTrimming else { return }
                switch value {
                case .first(true):
                    activateHoldMove()
                case let .second(true, drag):
                    guard let drag else { return }
                    activateHoldMove()
                    moveTranslation = drag.translation
                    if moveBaselineTimelineStart == nil {
                        moveBaselineTimelineStart = clip.timelineStart
                    }
                    let delta = TimeInterval(drag.translation.width / pixelsPerSecond)
                    let base = moveBaselineTimelineStart ?? clip.timelineStart
                    onMove(max(0, base + delta))
                default:
                    break
                }
            }
            .onEnded { value in
                if case let .second(true, drag) = value, let drag {
                    let laneStep = laneHeight + 5
                    onMoveToLane(Int((drag.translation.height / laneStep).rounded()))
                }
                let didMove = moveBaselineTimelineStart != nil
                isMoving = false
                isHoldActive = false
                moveTranslation = .zero
                moveBaselineTimelineStart = nil
                if didMove { onMoveEnded() }
            }
    }

    private func activateHoldMove() {
        guard !isHoldActive else { return }
        isHoldActive = true
        isMoving = true
        onSelect()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
}

