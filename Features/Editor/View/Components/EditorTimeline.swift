//
//  EditorTimeline.swift
//  Mixtape
//
//  Created by Favour Baruch on 14/05/2026.
//

import SwiftUI
import UIKit
import Photos
import AVFoundation

struct EditorTimeline: View {
    let vm: EditorViewModel
    var onInsertAfterClip: (Int) -> Void = { _ in }

    private let pixelsPerSecond: CGFloat = 18
    private let rulerLabelHeight: CGFloat = 14
    /// Drag here (or on the ruler labels) to scrub; pinch-scroll is disabled while dragging.
    private let scrubRailHeight: CGFloat = 24
    private let clipsLaneHeight: CGFloat = 52
    private let audioLaneHeight: CGFloat = 28
    /// Require this much drag on filmstrips before scrubbing claims the gesture (keeps horizontal scroll natural).
    private let clipScrubMinimumDistance: CGFloat = 18
    private let audioScrubMinimumDistance: CGFloat = 18
    /// Fixed column between clips so + never overlaps thumbnails.
    private let insertSlotWidth: CGFloat = 28

    @State private var isScrubbing = false
    @State private var playheadDragBaselineContentX: CGFloat?

    private var textOverlayLaneHeight: CGFloat { vm.textOverlays.isEmpty ? 0 : 20 }
    private var audioLaneResolvedHeight: CGFloat { vm.audioTrack == nil ? 0 : audioLaneHeight }

    private var playheadStackHeight: CGFloat {
        4 + rulerLabelHeight + scrubRailHeight + 8 + textOverlayLaneHeight + 8 + clipsLaneHeight
            + 8 + audioLaneResolvedHeight
    }

    private var layout: TimelineLayout {
        TimelineLayout(
            clips: vm.clips,
            totalDuration: vm.totalDuration,
            pixelsPerSecond: pixelsPerSecond,
            insertSlotWidth: insertSlotWidth
        )
    }

    var body: some View {
        let totalWidth = layout.contentWidth

        GeometryReader { geo in
            /// Inset for `ZStack` vertical padding (4pt top + bottom).
            let paddedMinHeight = max(1, geo.size.height - 8)

            ScrollView(.horizontal, showsIndicators: false) {
                ZStack(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 8) {
                        rulerAndScrubStrip(totalWidth: totalWidth, layout: layout)
                            .padding(.top, 4)

                        if !vm.textOverlays.isEmpty {
                            textOverlayRow(totalWidth: totalWidth, layout: layout)
                                .frame(height: textOverlayLaneHeight, alignment: .leading)
                        }

                        clipsRow(layout: layout)
                            .frame(height: clipsLaneHeight, alignment: .leading)

                        audioRow(totalWidth: totalWidth, layout: layout)
                            .frame(height: audioLaneResolvedHeight, alignment: .leading)

                        // Fills space below tracks (and future overlay lanes) so horizontal pan works
                        // on the whole timeline stack, not only on the thin overlay/clip rows.
                        Spacer(minLength: 0)
                            .contentShape(Rectangle())
                    }
                    .frame(width: totalWidth, height: paddedMinHeight, alignment: .top)

                    playheadLine(layout: layout)
                    playheadKnob(layout: layout)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
                .frame(height: paddedMinHeight)
            }
            .scrollDisabled(isScrubbing)
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    // MARK: Ruler + scrub

    private func rulerAndScrubStrip(totalWidth: CGFloat, layout: TimelineLayout) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ruler(totalWidth: totalWidth, layout: layout)
            Color.clear
                .frame(width: totalWidth, height: scrubRailHeight)
                .contentShape(Rectangle())
        }
        .frame(width: totalWidth, height: rulerLabelHeight + scrubRailHeight, alignment: .leading)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { v in
                    isScrubbing = true
                    let x = max(0, min(v.location.x, totalWidth))
                    vm.setTimelinePositionForScrub(layout.time(atContentX: x))
                }
                .onEnded { _ in
                    isScrubbing = false
                    vm.commitTimelineAfterScrub()
                }
        )
    }

    private func ruler(totalWidth: CGFloat, layout: TimelineLayout) -> some View {
        let everyFive = stride(from: 0, through: Int(vm.totalDuration), by: 5).map { $0 }
        return ZStack(alignment: .topLeading) {
            ForEach(everyFive, id: \.self) { sec in
                Text(formatRuler(sec))
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundColor(Color.white.opacity(0.55))
                    .offset(x: layout.contentX(forTime: TimeInterval(sec)) - 14, y: 0)
            }
        }
        .frame(width: totalWidth, height: rulerLabelHeight, alignment: .leading)
    }

    private func formatRuler(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    // MARK: Text overlays

    private func textOverlayRow(totalWidth: CGFloat, layout: TimelineLayout) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(vm.textOverlays) { overlay in
                HStack(spacing: 4) {
                    Image(systemName: "textformat")
                        .font(.system(size: 9, weight: .bold))
                    Text(truncated(overlay.text))
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.black.opacity(0.55))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                )
                .offset(x: layout.contentX(forTime: overlay.startTime), y: 0)
            }
        }
        .frame(width: totalWidth, alignment: .leading)
    }

    private func truncated(_ s: String) -> String {
        s.count > 8 ? String(s.prefix(7)) + "…" : s
    }

    // MARK: Clips

    private func clipsRow(layout: TimelineLayout) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(vm.clips.enumerated()), id: \.element.id) { index, clip in
                let start = vm.timelineOffsetForClipIndex(index)
                let thumbWidth = layout.clipWidth(for: clip)

                ClipThumb(
                    clip: clip,
                    width: thumbWidth,
                    clipTimelineStart: start,
                    isSelected: vm.selectedClipID == clip.id,
                    pixelsPerSecond: pixelsPerSecond,
                    scrubMinimumDistance: clipScrubMinimumDistance,
                    height: clipsLaneHeight,
                    onScrub: { t in vm.setTimelinePositionForScrub(t) },
                    onScrubCommit: { vm.commitTimelineAfterScrub() },
                    onScrubbingChanged: { isScrubbing = $0 },
                    onSelectForEditing: { vm.selectClipForEditing(clip.id) },
                    onTrimChanged: { start, end in
                        vm.setTrim(clipID: clip.id, trimStart: start, trimEnd: end)
                    },
                    onTrimEnded: { vm.commitTrimEdit() }
                )

                ClipInsertSlot(width: insertSlotWidth, height: clipsLaneHeight) {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onInsertAfterClip(index)
                }
            }
        }
    }

    // MARK: Audio

    private func audioRow(totalWidth: CGFloat, layout: TimelineLayout) -> some View {
        Group {
            if let audio = vm.audioTrack {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.appColors.primaryColor.opacity(0.18))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color.appColors.primaryColor.opacity(0.55), lineWidth: 1)
                        )

                    WaveformShape(samples: audio.waveform)
                        .stroke(Color.appColors.primaryColor.opacity(0.95), lineWidth: 1)
                        .padding(.vertical, 6)

                    HStack(spacing: 5) {
                        Image(systemName: "music.note")
                            .font(.system(size: 9, weight: .bold))
                        Text(audio.title)
                            .font(.system(size: 10, weight: .semibold))
                            .lineLimit(1)
                    }
                    .foregroundColor(Color.white.opacity(0.85))
                    .padding(.horizontal, 8)
                }
                .frame(
                    width: max(CGFloat(audio.duration) * pixelsPerSecond, totalWidth),
                    height: audioLaneHeight,
                    alignment: .leading
                )
                .contentShape(Rectangle())
                .gesture(
                    audioScrubGesture(
                        trackWidth: max(CGFloat(audio.duration) * pixelsPerSecond, totalWidth),
                        layout: layout
                    )
                )
            }
        }
    }

    private func audioScrubGesture(trackWidth: CGFloat, layout: TimelineLayout) -> some Gesture {
        DragGesture(minimumDistance: audioScrubMinimumDistance, coordinateSpace: .local)
            .onChanged { v in
                isScrubbing = true
                let w = max(1, trackWidth)
                let x = max(0, min(v.location.x, w))
                vm.setTimelinePositionForScrub(layout.time(atContentX: x))
            }
            .onEnded { _ in
                isScrubbing = false
                vm.commitTimelineAfterScrub()
            }
    }

    // MARK: Playhead (line is visual-only; only the knob captures drags so ScrollView can pan elsewhere.)

    private func playheadLine(layout: TimelineLayout) -> some View {
        let x = layout.contentX(forTime: vm.timelinePosition)
        return PlayheadShape()
            .stroke(Color.white.opacity(0.95), lineWidth: 1)
            .frame(width: 18, height: playheadStackHeight)
            .offset(x: x - 9, y: 0)
            .allowsHitTesting(false)
    }

    private func playheadKnob(layout: TimelineLayout) -> some View {
        let x = layout.contentX(forTime: vm.timelinePosition)
        let knobY = -playheadStackHeight / 2 + 4
        let knobSize: CGFloat = 44

        return ZStack {
            Circle()
                .fill(Color.white.opacity(0.001))
                .frame(width: knobSize, height: knobSize)
                .contentShape(Circle())
            Circle()
                .fill(Color.white)
                .frame(width: 10, height: 10)
                .allowsHitTesting(false)
        }
        .frame(width: knobSize, height: knobSize)
        .offset(x: x - knobSize / 2, y: knobY)
        .gesture(playheadDragGesture(layout: layout))
    }

    private func playheadDragGesture(layout: TimelineLayout) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { v in
                isScrubbing = true
                if playheadDragBaselineContentX == nil {
                    playheadDragBaselineContentX = layout.contentX(forTime: vm.timelinePosition)
                }
                let x = (playheadDragBaselineContentX ?? 0) + v.translation.width
                vm.setTimelinePositionForScrub(layout.time(atContentX: x))
            }
            .onEnded { _ in
                playheadDragBaselineContentX = nil
                isScrubbing = false
                vm.commitTimelineAfterScrub()
            }
    }
}

// MARK: - Timeline layout (clip widths + insert gaps)

private struct TimelineLayout {
    let clips: [EditorClip]
    let totalDuration: TimeInterval
    let pixelsPerSecond: CGFloat
    let insertSlotWidth: CGFloat

    func clipWidth(for clip: EditorClip) -> CGFloat {
        max(44, CGFloat(clip.duration) * pixelsPerSecond)
    }

    var contentWidth: CGFloat {
        guard !clips.isEmpty else { return 1 }
        let clipsW = clips.reduce(CGFloat(0)) { $0 + clipWidth(for: $1) }
        return max(clipsW + CGFloat(clips.count) * insertSlotWidth, 1)
    }

    func contentX(forTime time: TimeInterval) -> CGFloat {
        guard !clips.isEmpty else { return 0 }
        let clamped = min(max(0, time), totalDuration)
        var acc: TimeInterval = 0
        var x: CGFloat = 0

        for (index, clip) in clips.enumerated() {
            let duration = clip.duration
            if duration <= 0 { continue }

            if clamped < acc + duration - 1e-9 || index == clips.count - 1 {
                let local = min(max(0, clamped - acc), duration)
                return x + CGFloat(local) * pixelsPerSecond
            }

            x += clipWidth(for: clip) + insertSlotWidth
            acc += duration
        }

        return x
    }

    func time(atContentX rawX: CGFloat) -> TimeInterval {
        guard !clips.isEmpty else { return 0 }
        var x = max(0, rawX)
        var acc: TimeInterval = 0

        for clip in clips {
            let cw = clipWidth(for: clip)
            if x <= cw {
                return acc + TimeInterval(x / pixelsPerSecond)
            }
            x -= cw

            if x <= insertSlotWidth {
                return x < insertSlotWidth / 2 ? acc : min(acc + clip.duration, totalDuration)
            }
            x -= insertSlotWidth
            acc += clip.duration
        }

        return totalDuration
    }
}

// MARK: - Insert slot (dedicated gap between clips)

private struct ClipInsertSlot: View {
    let width: CGFloat
    let height: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Rectangle()
                    .fill(Color.white.opacity(0.04))
                Rectangle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 1)
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.appColors.primaryColor))
                    .overlay(Circle().stroke(Color.black.opacity(0.35), lineWidth: 1))
            }
            .frame(width: width, height: height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add media after this clip")
    }
}

// MARK: - Clip thumbnail

private struct ClipThumb: View {
    let clip: EditorClip
    let width: CGFloat
    let clipTimelineStart: TimeInterval
    let isSelected: Bool
    let pixelsPerSecond: CGFloat
    let scrubMinimumDistance: CGFloat
    let height: CGFloat
    let onScrub: (TimeInterval) -> Void
    let onScrubCommit: () -> Void
    let onScrubbingChanged: (Bool) -> Void
    let onSelectForEditing: () -> Void
    let onTrimChanged: (TimeInterval, TimeInterval) -> Void
    let onTrimEnded: () -> Void

    @State private var isTrimming = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            ClipFilmstripView(clip: clip, width: width, height: height)

            HStack(spacing: 4) {
                if clip.isVideo {
                    Text(format(duration: clip.duration))
                        .font(.system(size: 8, weight: .semibold).monospacedDigit())
                        .foregroundColor(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.black.opacity(0.55)))
                }
                if abs(clip.speed - 1.0) > 0.02 {
                    Text(String(format: "%.2g×", clip.speed))
                        .font(.system(size: 8, weight: .bold).monospacedDigit())
                        .foregroundColor(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.appColors.primaryColor.opacity(0.85)))
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
            if isSelected {
                ClipTrimHandleRepresentable(
                    clipID: clip.id,
                    trimStart: clip.trimStart,
                    trimEnd: clip.trimEnd,
                    originalDuration: clip.originalDuration,
                    speed: clip.speed,
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
        .animation(.easeInOut(duration: 0.15), value: isSelected)
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

// MARK: - Shapes

private struct PlayheadShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let mid = rect.midX
        p.move(to: CGPoint(x: mid, y: rect.minY + 4))
        p.addLine(to: CGPoint(x: mid, y: rect.maxY))
        return p
    }
}

private struct WaveformShape: Shape {
    let samples: [CGFloat]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard !samples.isEmpty else { return path }
        let barCount = samples.count
        let spacing = rect.width / CGFloat(barCount)
        let midY = rect.midY

        for (index, sample) in samples.enumerated() {
            let x = CGFloat(index) * spacing + spacing / 2
            let h = max(2, sample * (rect.height - 4))
            path.move(to: CGPoint(x: x, y: midY - h / 2))
            path.addLine(to: CGPoint(x: x, y: midY + h / 2))
        }
        return path
    }
}
