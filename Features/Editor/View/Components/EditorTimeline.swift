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
    var onSelectOpeningTransition: () -> Void = {}
    var onSelectClosingTransition: () -> Void = {}
    var onSelectTransition: (Int) -> Void = { _ in }
    var onAddAudioClip: (Int?) -> Void = { _ in }

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
    @State private var isAudioTrimming = false
    @State private var isAudioMoving = false
    @State private var isTextTrimming = false
    @State private var isTextMoving = false
    @State private var playheadDragBaselineContentX: CGFloat?
    @State private var reorderState = ClipReorderState()

    private var textOverlayLaneHeight: CGFloat { vm.textOverlays.isEmpty ? 0 : 36 }
    private var audioLaneResolvedHeight: CGFloat { audioLaneHeight }

    private var playheadStackHeight: CGFloat {
        4 + rulerLabelHeight + scrubRailHeight + 8 + textOverlayLaneHeight + 8 + clipsLaneHeight
            + 8 + audioLaneResolvedHeight
    }

    private var layout: TimelineLayout {
        TimelineLayout(
            clips: vm.clips,
            videoDuration: vm.videoDuration,
            timelineExtent: vm.totalDuration,
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
                    .clipped()

                    TimelinePlayheadLine(vm: vm, layout: layout, stackHeight: playheadStackHeight)
                    TimelinePlayheadKnob(
                        vm: vm,
                        layout: layout,
                        stackHeight: playheadStackHeight,
                        isScrubbing: $isScrubbing,
                        baselineContentX: $playheadDragBaselineContentX
                    )
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
                .frame(width: totalWidth + 32, height: paddedMinHeight, alignment: .topLeading)
                .clipped()
            }
            .scrollDisabled(isScrubbing || isAudioTrimming || isAudioMoving || isTextTrimming || isTextMoving || reorderState.isDragging)
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
        let everyFive = stride(from: 0, through: Int(layout.timelineExtent), by: 5).map { $0 }
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
                TextOverlayThumb(
                    overlay: overlay,
                    layout: layout,
                    isSelected: vm.selectedTextOverlayID == overlay.id,
                    isTrimming: $isTextTrimming,
                    isMoving: $isTextMoving,
                    onSelect: { vm.selectTextOverlay(overlay.id) },
                    onTrimChanged: { start, end in
                        vm.updateTextOverlayTimeRange(id: overlay.id, start: start, end: end)
                    },
                    onTrimEnded: { vm.commitTextOverlayTimeRange() },
                    onMove: { start in
                        vm.moveTextOverlayOnTimeline(id: overlay.id, startTime: start)
                    },
                    onMoveEnded: { vm.commitTextOverlayMove() }
                )
            }
        }
        .frame(width: totalWidth, alignment: .leading)
    }

    // MARK: Clips

    private func clipsRow(layout: TimelineLayout) -> some View {
        let metrics = TimelineClipMetrics(
            clipWidths: vm.clips.map { layout.clipWidth(for: $0) },
            insertSlotWidth: insertSlotWidth
        )
        let isDragging = reorderState.isDragging
        let dragSource = reorderState.draggingSourceIndex
        let dragDest = reorderState.proposedDestinationIndex
        let dragTx = reorderState.dragTranslationX

        return HStack(spacing: 0) {
            OpeningTransitionControl(
                transitionKind: vm.openingTransitionKind
            ) {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onSelectOpeningTransition()
            }
            .frame(width: insertSlotWidth, height: clipsLaneHeight)
            .opacity(isDragging ? 0.15 : 1)
            .allowsHitTesting(!isDragging)

            ForEach(Array(vm.clips.enumerated()), id: \.element.id) { index, clip in
                let start = vm.timelineOffsetForClipIndex(index)
                let thumbWidth = layout.clipWidth(for: clip)
                let isSelected = vm.selectedClipID == clip.id
                let isBeingDragged = isDragging && dragSource == index

                // Calculate the shift for non-dragged clips to make room.
                let shiftOffset: CGFloat = {
                    guard isDragging,
                          let source = dragSource,
                          let dest = dragDest,
                          source != dest,
                          index != source else { return 0 }

                    let sourceWidth = metrics.clipWidths[source] + insertSlotWidth

                    if source < dest {
                        // Dragged right: clips between (source, dest] shift left.
                        if index > source && index <= dest {
                            return -sourceWidth
                        }
                    } else {
                        // Dragged left: clips between [dest, source) shift right.
                        if index >= dest && index < source {
                            return sourceWidth
                        }
                    }
                    return 0
                }()

                ClipThumb(
                    clip: clip,
                    width: thumbWidth,
                    clipTimelineStart: start,
                    isSelected: isSelected,
                    pixelsPerSecond: pixelsPerSecond,
                    scrubMinimumDistance: clipScrubMinimumDistance,
                    height: clipsLaneHeight,
                    clipIndex: index,
                    reorderMetrics: metrics,
                    reorderState: reorderState,
                    canReorder: isSelected && vm.clips.count > 1,
                    onScrub: { t in vm.setTimelinePositionForScrub(t) },
                    onScrubCommit: { vm.commitTimelineAfterScrub() },
                    onScrubbingChanged: { isScrubbing = $0 },
                    onSelectForEditing: { vm.selectClipForEditing(clip.id) },
                    onTrimChanged: { start, end in
                        vm.setTrim(clipID: clip.id, trimStart: start, trimEnd: end)
                    },
                    onTrimEnded: { vm.commitTrimEdit() },
                    onMoveClip: { from, to in vm.moveClip(from: from, to: to) }
                )
                .offset(x: isBeingDragged ? dragTx : shiftOffset)
                .scaleEffect(isBeingDragged ? 1.06 : 1.0)
                .shadow(
                    color: isBeingDragged ? Color.black.opacity(0.45) : Color.clear,
                    radius: isBeingDragged ? 8 : 0,
                    y: isBeingDragged ? 4 : 0
                )
                .opacity(isBeingDragged ? 0.92 : 1.0)
                .zIndex(isBeingDragged ? 100 : 0)
                .animation(.interactiveSpring(response: 0.28, dampingFraction: 0.78), value: shiftOffset)
                .animation(.interactiveSpring(response: 0.22, dampingFraction: 0.72), value: isBeingDragged)

                Group {
                    if index < vm.clips.count - 1 {
                        ClipBoundarySlot(
                            width: insertSlotWidth,
                            height: clipsLaneHeight,
                            transitionKind: clip.transitionKind,
                            onTransition: {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                onSelectTransition(index)
                            },
                            onInsert: {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                onInsertAfterClip(index)
                            }
                        )
                    } else {
                        ClipEndingSlot(
                            width: insertSlotWidth,
                            height: clipsLaneHeight,
                            transitionKind: vm.closingTransitionKind,
                            onTransition: {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                onSelectClosingTransition()
                            },
                            onInsert: {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                onInsertAfterClip(index)
                            }
                        )
                    }
                }
                .opacity(isDragging ? 0.15 : 1.0)
                .offset(x: isDragging ? shiftOffset : 0)
                .animation(.interactiveSpring(response: 0.28, dampingFraction: 0.78), value: shiftOffset)
                .animation(.easeInOut(duration: 0.15), value: isDragging)
                .allowsHitTesting(!isDragging)
            }
        }
    }

    // MARK: Audio

    private func audioRow(totalWidth: CGFloat, layout: TimelineLayout) -> some View {
        let sorted = vm.sortedAudioClips

        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .frame(width: totalWidth, height: audioLaneHeight)

            if sorted.isEmpty {
                Button {
                    onAddAudioClip(nil)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .bold))
                        Text("Add Audio")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(.white.opacity(0.8))
                    .padding(.horizontal, 12)
                    .frame(height: audioLaneHeight)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.white.opacity(0.1))
                    )
                }
                .buttonStyle(.plain)
            } else {
                // Insert buttons sit under clips so they don't cover trim handles.
                ForEach(Array(sorted.enumerated()), id: \.element.id) { index, clip in
                    let slotX = CGFloat(clip.timelineEnd) * pixelsPerSecond + insertSlotWidth / 2
                    if slotX < totalWidth - 20 {
                        audioInsertButton(insertAfterIndex: index)
                            .offset(x: slotX, y: (audioLaneHeight - 24) / 2)
                            .zIndex(0)
                    }
                }

                ForEach(sorted) { clip in
                    AudioClipThumb(
                        clip: clip,
                        pixelsPerSecond: pixelsPerSecond,
                        scrubMinimumDistance: audioScrubMinimumDistance,
                        laneHeight: audioLaneHeight,
                        isSelected: vm.selectedAudioClipID == clip.id,
                        isTrimming: $isAudioTrimming,
                        isMoving: $isAudioMoving,
                        onSelect: { vm.selectAudioClip(clip.id) },
                        onScrub: { vm.setTimelinePositionForScrub($0) },
                        onScrubCommit: { vm.commitTimelineAfterScrub() },
                        onTrimChanged: { start, end in
                            vm.setAudioTrim(clipID: clip.id, trimStart: start, trimEnd: end)
                        },
                        onTrimEnded: { vm.commitAudioTrim(clipID: clip.id) },
                        onMove: { start in
                            vm.setAudioTimelineStart(clipID: clip.id, timelineStart: start)
                        },
                        onMoveEnded: { vm.commitAudioMove() }
                    )
                    .zIndex(vm.selectedAudioClipID == clip.id ? 10 : 1)
                }
            }
        }
        .frame(width: totalWidth, height: audioLaneHeight, alignment: .leading)
        .clipped()
    }

    private func audioInsertButton(insertAfterIndex: Int) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onAddAudioClip(insertAfterIndex)
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.appColors.primaryColor))
                .overlay(Circle().stroke(Color.black.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add audio")
    }
}

// MARK: - Audio clip thumb (mirrors ClipThumb trim / scrub behaviour)

private struct AudioClipThumb: View {
    let clip: EditorAudioClip
    let pixelsPerSecond: CGFloat
    let scrubMinimumDistance: CGFloat
    let laneHeight: CGFloat
    let isSelected: Bool
    @Binding var isTrimming: Bool
    @Binding var isMoving: Bool
    let onSelect: () -> Void
    let onScrub: (TimeInterval) -> Void
    let onScrubCommit: () -> Void
    let onTrimChanged: (TimeInterval, TimeInterval) -> Void
    let onTrimEnded: () -> Void
    let onMove: (TimeInterval) -> Void
    let onMoveEnded: () -> Void

    @State private var trimBaseline: (timelineStart: TimeInterval, trimStart: TimeInterval)?
    @State private var moveBaselineTimelineStart: TimeInterval?

    private var width: CGFloat {
        max(44, CGFloat(clip.duration) * pixelsPerSecond)
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
                if isSelected {
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
            .offset(x: CGFloat(displayTimelineStart) * pixelsPerSecond, y: 0)

        if isSelected {
            content.gesture(moveGesture)
        } else {
            content.gesture(scrubGesture)
        }
    }

    private var clipVisual: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.appColors.primaryColor.opacity(isSelected ? 0.28 : 0.18))

            WaveformShape(samples: clip.waveform)
                .stroke(Color.appColors.primaryColor.opacity(0.95), lineWidth: 1)
                .padding(.vertical, 6)

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
        DragGesture(minimumDistance: 6, coordinateSpace: .local)
            .onChanged { value in
                guard !isTrimming else { return }
                if moveBaselineTimelineStart == nil {
                    moveBaselineTimelineStart = clip.timelineStart
                }
                isMoving = true
                let delta = TimeInterval(value.translation.width / pixelsPerSecond)
                let base = moveBaselineTimelineStart ?? clip.timelineStart
                onMove(max(0, base + delta))
            }
            .onEnded { _ in
                isMoving = false
                moveBaselineTimelineStart = nil
                onMoveEnded()
            }
    }
}

// MARK: - Text overlay thumb

private struct TextOverlayThumb: View {
    let overlay: EditorTextOverlay
    let layout: TimelineLayout
    let isSelected: Bool
    @Binding var isTrimming: Bool
    @Binding var isMoving: Bool
    let onSelect: () -> Void
    let onTrimChanged: (TimeInterval, TimeInterval) -> Void
    let onTrimEnded: () -> Void
    let onMove: (TimeInterval) -> Void
    let onMoveEnded: () -> Void

    @State private var trimBaseline: (startTime: TimeInterval, startX: CGFloat)?
    @State private var moveBaselineStart: TimeInterval?

    private var endX: CGFloat { layout.contentX(forTime: overlay.endTime) }

    private var displayStartX: CGFloat {
        if let base = trimBaseline {
            return base.startX + (layout.contentX(forTime: overlay.startTime) - layout.contentX(forTime: base.startTime))
        }
        return layout.contentX(forTime: overlay.startTime)
    }

    private var barWidth: CGFloat {
        max(44, endX - displayStartX)
    }

    var body: some View {
        let content = barContent
            .overlay {
                if isSelected {
                    ClipTrimHandleRepresentable(
                        clipID: overlay.id,
                        trimStart: overlay.startTime,
                        trimEnd: overlay.endTime,
                        originalDuration: max(layout.timelineExtent, 1),
                        allowsDurationExtension: false,
                        speed: 1.0,
                        pixelsPerSecond: layout.pixelsPerSecond,
                        onTrimChanged: { _, start, end in
                            if trimBaseline == nil {
                                let x = layout.contentX(forTime: overlay.startTime)
                                trimBaseline = (overlay.startTime, x)
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
                    .frame(width: barWidth, height: 32)
                    .allowsHitTesting(true)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                guard !isTrimming, !isMoving else { return }
                onSelect()
            }
            .offset(x: displayStartX, y: 0)

        if isSelected {
            content.gesture(moveGesture)
        } else {
            content
        }
    }

    private var barContent: some View {
        HStack(spacing: 4) {
            Image(systemName: "textformat")
                .font(.system(size: 9, weight: .bold))
            Text(truncated(overlay.text))
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundColor(.white)
        .frame(width: barWidth, alignment: .leading)
        .padding(.horizontal, 8)
        .frame(height: 32)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.appColors.primaryColor.opacity(isSelected ? 0.35 : 0.2))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(
                    isSelected ? Color.appColors.primaryColor : Color.appColors.primaryColor.opacity(0.45),
                    lineWidth: isSelected ? 2 : 1
                )
        )
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .local)
            .onChanged { value in
                guard !isTrimming else { return }
                if moveBaselineStart == nil {
                    moveBaselineStart = overlay.startTime
                }
                isMoving = true
                let baseX = layout.contentX(forTime: moveBaselineStart ?? overlay.startTime)
                let newX = max(0, baseX + value.translation.width)
                let newStart = layout.time(atContentX: newX)
                onMove(newStart)
            }
            .onEnded { _ in
                isMoving = false
                moveBaselineStart = nil
                onMoveEnded()
            }
    }

    private func truncated(_ s: String) -> String {
        s.count > 8 ? String(s.prefix(7)) + "…" : s
    }
}

// MARK: - Timeline layout (clip widths + insert gaps)

private struct TimelineLayout {
    let clips: [EditorClip]
    let videoDuration: TimeInterval
    let timelineExtent: TimeInterval
    let pixelsPerSecond: CGFloat
    let insertSlotWidth: CGFloat

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
        max(44, CGFloat(clip.duration) * pixelsPerSecond)
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

private struct ClipBoundarySlot: View {
    let width: CGFloat
    let height: CGFloat
    let transitionKind: EditorTransitionKind
    let onTransition: () -> Void
    let onInsert: () -> Void

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.white.opacity(0.04))
            Rectangle()
                .fill(Color.white.opacity(0.16))
                .frame(width: 1)

            Button(action: onTransition) {
                Image(systemName: transitionKind == .none
                      ? "rectangle.split.2x1"
                      : transitionKind.systemImage)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(transitionKind == .none ? .white : .black)
                    .frame(width: 26, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(
                                transitionKind == .none
                                    ? Color.white.opacity(0.16)
                                    : Color.appColors.primaryColor
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(Color.white.opacity(0.35), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .offset(y: -9)
            .accessibilityLabel("Edit transition at cut")

            Button(action: onInsert) {
                Image(systemName: "plus")
                    .font(.system(size: 8, weight: .black))
                    .foregroundColor(.black)
                    .frame(width: 17, height: 17)
                    .background(Circle().fill(Color.white))
            }
            .buttonStyle(.plain)
            .offset(y: 16)
            .accessibilityLabel("Add media at this cut")
        }
        .frame(width: width, height: height)
    }
}

private struct ClipEndingSlot: View {
    let width: CGFloat
    let height: CGFloat
    let transitionKind: EditorTransitionKind
    let onTransition: () -> Void
    let onInsert: () -> Void

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.white.opacity(0.04))
            Rectangle()
                .fill(Color.white.opacity(0.16))
                .frame(width: 1)

            Button(action: onTransition) {
                Image(
                    systemName: transitionKind == .none
                        ? "rectangle.portrait.and.arrow.forward"
                        : transitionKind.systemImage
                )
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(transitionKind == .none ? .white : .black)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(
                            transitionKind == .none
                                ? Color.white.opacity(0.16)
                                : Color.appColors.primaryColor
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(Color.white.opacity(0.35), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .offset(y: -9)
            .accessibilityLabel("Edit closing transition")
            .accessibilityHint("Applies an exit effect to the final clip")

            Button(action: onInsert) {
                Image(systemName: "plus")
                    .font(.system(size: 8, weight: .black))
                    .foregroundColor(.black)
                    .frame(width: 17, height: 17)
                    .background(Circle().fill(Color.white))
            }
            .buttonStyle(.plain)
            .offset(y: 16)
            .accessibilityLabel("Add media after this clip")
        }
        .frame(width: width, height: height)
    }
}

private struct OpeningTransitionControl: View {
    let transitionKind: EditorTransitionKind
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(
                systemName: transitionKind == .none
                    ? "rectangle.portrait.and.arrow.forward"
                    : transitionKind.systemImage
            )
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(transitionKind == .none ? .white : .black)
            .frame(width: 26, height: 30)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        transitionKind == .none
                            ? Color.white.opacity(0.18)
                            : Color.appColors.primaryColor
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(0.4), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Edit opening transition")
        .accessibilityHint("Applies an entrance effect to the first clip")
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
    let clipIndex: Int
    let reorderMetrics: TimelineClipMetrics
    let reorderState: ClipReorderState
    let canReorder: Bool
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
            if isSelected {
                ClipTrimHandleRepresentable(
                    clipID: clip.id,
                    trimStart: clip.trimStart,
                    trimEnd: clip.trimEnd,
                    originalDuration: clip.originalDuration,
                    allowsDurationExtension: clip.isPhoto,
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

// MARK: - Playhead (isolated — only these views observe `timelinePosition` during playback)

private struct TimelinePlayheadLine: View {
    let vm: EditorViewModel
    let layout: TimelineLayout
    let stackHeight: CGFloat

    var body: some View {
        let x = layout.contentX(forTime: vm.timelinePosition)
        PlayheadShape()
            .stroke(Color.white.opacity(0.95), lineWidth: 1)
            .frame(width: 18, height: stackHeight)
            .offset(x: x - 9, y: 0)
            .allowsHitTesting(false)
    }
}

private struct TimelinePlayheadKnob: View {
    let vm: EditorViewModel
    let layout: TimelineLayout
    let stackHeight: CGFloat
    @Binding var isScrubbing: Bool
    @Binding var baselineContentX: CGFloat?

    var body: some View {
        let x = layout.contentX(forTime: vm.timelinePosition)
        let knobY = -stackHeight / 2 + 4
        let knobSize: CGFloat = 44

        ZStack {
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
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { v in
                    isScrubbing = true
                    if baselineContentX == nil {
                        baselineContentX = layout.contentX(forTime: vm.timelinePosition)
                    }
                    let contentX = (baselineContentX ?? 0) + v.translation.width
                    vm.setTimelinePositionForScrub(layout.time(atContentX: contentX))
                }
                .onEnded { _ in
                    baselineContentX = nil
                    isScrubbing = false
                    vm.commitTimelineAfterScrub()
                }
        )
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
