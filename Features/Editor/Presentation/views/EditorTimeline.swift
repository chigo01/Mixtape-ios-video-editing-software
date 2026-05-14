//
//  EditorTimeline.swift
//  Mixtape
//
//  Created by Favour Baruch on 14/05/2026.
//

import SwiftUI
import UIKit
import Photos

struct EditorTimeline: View {
    let vm: EditorViewModel

    private let pixelsPerSecond: CGFloat = 18
    private let rulerLabelHeight: CGFloat = 14
    /// Drag here (or on the ruler labels) to scrub; pinch-scroll is disabled while dragging.
    private let scrubRailHeight: CGFloat = 24
    private let clipsLaneHeight: CGFloat = 72
    private let audioLaneHeight: CGFloat = 36
    /// Require this much drag on filmstrips before scrubbing claims the gesture (keeps horizontal scroll natural).
    private let clipScrubMinimumDistance: CGFloat = 18
    private let audioScrubMinimumDistance: CGFloat = 18

    @State private var isScrubbing = false
    @State private var playheadDragBaseline: TimeInterval?

    private var textOverlayLaneHeight: CGFloat { vm.textOverlays.isEmpty ? 0 : 24 }
    private var audioLaneResolvedHeight: CGFloat { vm.audioTrack == nil ? 0 : audioLaneHeight }

    private var playheadStackHeight: CGFloat {
        4 + rulerLabelHeight + scrubRailHeight + 8 + textOverlayLaneHeight + 8 + clipsLaneHeight
            + 8 + audioLaneResolvedHeight
    }

    var body: some View {
        let totalWidth = max(CGFloat(vm.totalDuration) * pixelsPerSecond, 1)

        GeometryReader { geo in
            /// Inset for `ZStack` vertical padding (4pt top + bottom).
            let paddedMinHeight = max(1, geo.size.height - 8)

            ScrollView(.horizontal, showsIndicators: false) {
                ZStack(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 8) {
                        rulerAndScrubStrip(totalWidth: totalWidth)
                            .padding(.top, 4)

                        if !vm.textOverlays.isEmpty {
                            textOverlayRow(totalWidth: totalWidth)
                                .frame(height: 24, alignment: .leading)
                        }

                        clipsRow
                            .frame(height: clipsLaneHeight, alignment: .leading)

                        audioRow(totalWidth: totalWidth)
                            .frame(height: audioLaneResolvedHeight, alignment: .leading)

                        // Fills space below tracks (and future overlay lanes) so horizontal pan works
                        // on the whole timeline stack, not only on the thin overlay/clip rows.
                        Spacer(minLength: 0)
                            .contentShape(Rectangle())
                    }
                    .frame(width: totalWidth, height: paddedMinHeight, alignment: .top)

                    playheadLine()
                    playheadKnob()
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

    private func rulerAndScrubStrip(totalWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ruler(totalWidth: totalWidth)
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
                    let t = TimeInterval(x / pixelsPerSecond)
                    vm.setTimelinePositionForScrub(t)
                }
                .onEnded { _ in
                    isScrubbing = false
                    vm.commitTimelineAfterScrub()
                }
        )
    }

    private func ruler(totalWidth: CGFloat) -> some View {
        let everyFive = stride(from: 0, through: Int(vm.totalDuration), by: 5).map { $0 }
        return ZStack(alignment: .topLeading) {
            ForEach(everyFive, id: \.self) { sec in
                Text(formatRuler(sec))
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundColor(Color.white.opacity(0.55))
                    .offset(x: CGFloat(sec) * pixelsPerSecond - 14, y: 0)
            }
        }
        .frame(width: totalWidth, height: rulerLabelHeight, alignment: .leading)
    }

    private func formatRuler(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    // MARK: Text overlays

    private func textOverlayRow(totalWidth: CGFloat) -> some View {
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
                .offset(x: CGFloat(overlay.startTime) * pixelsPerSecond, y: 0)
            }
        }
        .frame(width: totalWidth, alignment: .leading)
    }

    private func truncated(_ s: String) -> String {
        s.count > 8 ? String(s.prefix(7)) + "…" : s
    }

    // MARK: Clips

    private var clipsRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(vm.clips.enumerated()), id: \.element.id) { index, clip in
                let start = vm.timelineOffsetForClipIndex(index)
                ClipThumb(
                    clip: clip,
                    clipTimelineStart: start,
                    isSelected: vm.selectedClipID == clip.id,
                    pixelsPerSecond: pixelsPerSecond,
                    scrubMinimumDistance: clipScrubMinimumDistance,
                    height: clipsLaneHeight,
                    onScrub: { t in vm.setTimelinePositionForScrub(t) },
                    onScrubCommit: { vm.commitTimelineAfterScrub() },
                    onScrubbingChanged: { isScrubbing = $0 },
                    onSelectForEditing: { vm.selectClipForEditing(clip.id) }
                )
            }
        }
    }

    // MARK: Audio

    private func audioRow(totalWidth: CGFloat) -> some View {
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
                        trackWidth: max(CGFloat(audio.duration) * pixelsPerSecond, totalWidth)
                    )
                )
            }
        }
    }

    private func audioScrubGesture(trackWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: audioScrubMinimumDistance, coordinateSpace: .local)
            .onChanged { v in
                isScrubbing = true
                let w = max(1, trackWidth)
                let x = max(0, min(v.location.x, w))
                let t = TimeInterval(x / pixelsPerSecond)
                vm.setTimelinePositionForScrub(t)
            }
            .onEnded { _ in
                isScrubbing = false
                vm.commitTimelineAfterScrub()
            }
    }

    // MARK: Playhead (line is visual-only; only the knob captures drags so ScrollView can pan elsewhere.)

    private func playheadLine() -> some View {
        let x = CGFloat(vm.timelinePosition) * pixelsPerSecond
        return PlayheadShape()
            .stroke(Color.white.opacity(0.95), lineWidth: 1)
            .frame(width: 18, height: playheadStackHeight)
            .offset(x: x - 9, y: 0)
            .allowsHitTesting(false)
    }

    private func playheadKnob() -> some View {
        let x = CGFloat(vm.timelinePosition) * pixelsPerSecond
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
        .gesture(playheadDragGesture())
    }

    private func playheadDragGesture() -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { v in
                isScrubbing = true
                if playheadDragBaseline == nil {
                    playheadDragBaseline = vm.timelinePosition
                }
                let delta = TimeInterval(v.translation.width / pixelsPerSecond)
                let t = (playheadDragBaseline ?? 0) + delta
                vm.setTimelinePositionForScrub(t)
            }
            .onEnded { _ in
                playheadDragBaseline = nil
                isScrubbing = false
                vm.commitTimelineAfterScrub()
            }
    }
}

// MARK: - Clip thumbnail

private struct ClipThumb: View {
    let clip: EditorClip
    let clipTimelineStart: TimeInterval
    let isSelected: Bool
    let pixelsPerSecond: CGFloat
    let scrubMinimumDistance: CGFloat
    let height: CGFloat
    let onScrub: (TimeInterval) -> Void
    let onScrubCommit: () -> Void
    let onScrubbingChanged: (Bool) -> Void
    let onSelectForEditing: () -> Void

    @State private var image: UIImage?

    private var width: CGFloat {
        max(44, CGFloat(clip.duration) * pixelsPerSecond)
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.white.opacity(0.06)
            }

            if clip.isVideo {
                Text(format(duration: clip.duration))
                    .font(.system(size: 8, weight: .semibold).monospacedDigit())
                    .foregroundColor(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.black.opacity(0.55)))
                    .padding(4)
            }
        }
        .frame(width: width, height: height)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(isSelected ? Color.appColors.primaryColor : Color.clear, lineWidth: 2)
        )
        .animation(.easeInOut(duration: 0.15), value: isSelected)
        .contentShape(Rectangle())
        .gesture(thumbScrubGesture())
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.45)
                .onEnded { _ in onSelectForEditing() }
        )
        .onAppear(perform: load)
    }

    private func thumbScrubGesture() -> some Gesture {
        DragGesture(minimumDistance: scrubMinimumDistance, coordinateSpace: .local)
            .onChanged { v in
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

    private func load() {
        guard image == nil else { return }
        let manager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        let scale = UIScreen.main.scale
        let target = CGSize(width: width * scale, height: height * scale)
        manager.requestImage(
            for: clip.asset,
            targetSize: target,
            contentMode: .aspectFill,
            options: options
        ) { result, _ in
            guard let result else { return }
            Task { @MainActor in self.image = result }
        }
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
