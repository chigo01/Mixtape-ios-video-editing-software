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

private struct OverlayLanePlacement: Identifiable {
    let clip: EditorOverlayClip
    let lane: Int
    var id: UUID { clip.id }
}

private struct AudioLanePlacement: Identifiable {
    let clip: EditorAudioClip
    let lane: Int
    var id: UUID { clip.id }
}

private struct SequenceLanePlacement: Identifiable {
    let sequence: EditorSequence
    let range: ClosedRange<TimeInterval>
    let lane: Int
    var id: UUID { sequence.id }
}

struct EditorTimeline: View {
    let vm: EditorViewModel
    @Binding var isOverlayTracksExpanded: Bool
    var onInsertAfterClip: (Int) -> Void = { _ in }
    var onSelectOpeningTransition: () -> Void = {}
    var onSelectClosingTransition: () -> Void = {}
    var onSelectTransition: (Int) -> Void = { _ in }
    var onAddAudioTrack: () -> Void = {}
    var onInsertAudioAfterClip: (UUID) -> Void = { _ in }
    var onAddOverlayClip: () -> Void = {}

    private let pixelsPerSecond: CGFloat = 18
    private let rulerLabelHeight: CGFloat = 14
    /// Drag here (or on the ruler labels) to scrub; pinch-scroll is disabled while dragging.
    private let scrubRailHeight: CGFloat = 24
    private let clipsLaneHeight: CGFloat = 52
    private let audioLaneHeight: CGFloat = 28
    private let audioLaneSpacing: CGFloat = 5
    private let overlayLaneHeight: CGFloat = 40
    private let overlayLaneSpacing: CGFloat = 6
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
    @State private var isGraphicTrimming = false
    @State private var isGraphicMoving = false
    @State private var isOverlayTrimming = false
    @State private var isOverlayMoving = false
    @State private var playheadDragBaselineContentX: CGFloat?
    @State private var reorderState = ClipReorderState()
    fileprivate static let playheadScrollID = "timeline-playhead"

    private var textOverlayLaneHeight: CGFloat { vm.textOverlays.isEmpty ? 0 : 36 }
    private var graphicOverlayLaneHeight: CGFloat { vm.graphicOverlays.isEmpty ? 0 : 36 }
    private var adjustmentLaneHeight: CGFloat { vm.adjustmentLayers.isEmpty ? 0 : 32 }
    private let sequenceBandHeight: CGFloat = 26
    private let sequenceBandSpacing: CGFloat = 4
    private var sequenceLanePlacements: [SequenceLanePlacement] {
        let ranged = vm.visibleSequences.compactMap { sequence in
            vm.sequenceTimeRange(id: sequence.id).map { (sequence, $0) }
        }
        .sorted {
            if $0.1.lowerBound == $1.1.lowerBound { return $0.1.upperBound < $1.1.upperBound }
            return $0.1.lowerBound < $1.1.lowerBound
        }
        var laneEnds: [TimeInterval] = []
        return ranged.map { sequence, range in
            let lane = laneEnds.firstIndex(where: { $0 <= range.lowerBound }) ?? laneEnds.count
            if lane == laneEnds.count { laneEnds.append(range.upperBound) }
            else { laneEnds[lane] = range.upperBound }
            return SequenceLanePlacement(sequence: sequence, range: range, lane: lane)
        }
    }
    private var sequenceLaneCount: Int {
        (sequenceLanePlacements.map(\.lane).max() ?? -1) + 1
    }
    private var sequenceLaneHeight: CGFloat {
        guard sequenceLaneCount > 0 else { return 0 }
        return CGFloat(sequenceLaneCount) * sequenceBandHeight
            + CGFloat(max(0, sequenceLaneCount - 1)) * sequenceBandSpacing
    }
    private var overlayLanePlacements: [OverlayLanePlacement] {
        let logicalLanes = Array(Set(vm.overlayClips.map(\.laneIndex))).sorted()
        let displayLaneByLogicalLane = Dictionary(
            uniqueKeysWithValues: logicalLanes.enumerated().map { ($0.element, $0.offset) }
        )
        return vm.overlayClips
            .sorted {
                if $0.laneIndex == $1.laneIndex {
                    return $0.timelineStart < $1.timelineStart
                }
                return $0.laneIndex < $1.laneIndex
            }
            .map { clip in
                OverlayLanePlacement(
                    clip: clip,
                    lane: displayLaneByLogicalLane[clip.laneIndex] ?? 0
                )
        }
    }

    private var overlayLaneCount: Int {
        (overlayLanePlacements.map(\.lane).max() ?? -1) + 1
    }

    private var overlayLaneResolvedHeight: CGFloat {
        guard overlayLaneCount > 0 else { return 0 }
        return CGFloat(overlayLaneCount) * overlayLaneHeight
            + CGFloat(max(0, overlayLaneCount - 1)) * overlayLaneSpacing
    }
    private var expandedOverlayViewportHeight: CGFloat {
        min(overlayLaneResolvedHeight, overlayLaneHeight * 2 + overlayLaneSpacing)
    }
    private var overlayDisplayHeight: CGFloat {
        guard !vm.overlayClips.isEmpty else { return 0 }
        return isOverlayTracksExpanded ? expandedOverlayViewportHeight : overlayLaneHeight
    }
    /// Groups audio clips into display lanes the same way `overlayLanePlacements` does for
    /// video overlays — each `laneIndex` becomes an independent track, so a second audio clip
    /// can sit at the same playhead as an existing one instead of colliding with it.
    private var audioLanePlacements: [AudioLanePlacement] {
        let logicalLanes = Array(Set(vm.audioClips.map(\.laneIndex))).sorted()
        let displayLaneByLogicalLane = Dictionary(
            uniqueKeysWithValues: logicalLanes.enumerated().map { ($0.element, $0.offset) }
        )
        return vm.audioClips
            .sorted {
                if $0.laneIndex == $1.laneIndex {
                    return $0.timelineStart < $1.timelineStart
                }
                return $0.laneIndex < $1.laneIndex
            }
            .map { clip in
                AudioLanePlacement(clip: clip, lane: displayLaneByLogicalLane[clip.laneIndex] ?? 0)
            }
    }

    private var audioLaneCount: Int {
        max(1, (audioLanePlacements.map(\.lane).max() ?? -1) + 1)
    }

    private var audioLaneResolvedHeight: CGFloat {
        CGFloat(audioLaneCount) * audioLaneHeight
            + CGFloat(max(0, audioLaneCount - 1)) * audioLaneSpacing
    }

    /// Caps on-screen height at ~2 tracks tall; additional tracks scroll vertically instead of
    /// pushing the rest of the timeline chrome down.
    private var audioViewportHeight: CGFloat {
        min(audioLaneResolvedHeight, audioLaneHeight * 2 + audioLaneSpacing)
    }

    private var playheadStackHeight: CGFloat {
        4 + rulerLabelHeight + scrubRailHeight
            + (sequenceLaneHeight > 0 ? 8 + sequenceLaneHeight : 0)
            + (adjustmentLaneHeight > 0 ? 8 + adjustmentLaneHeight : 0)
            + (isOverlayTracksExpanded || graphicOverlayLaneHeight == 0 ? 0 : 8 + graphicOverlayLaneHeight)
            + (isOverlayTracksExpanded ? 0 : 8 + textOverlayLaneHeight)
            + 8 + clipsLaneHeight + 8 + overlayDisplayHeight
            + (isOverlayTracksExpanded ? 0 : 8 + audioViewportHeight)
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

            ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                ZStack(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 8) {
                        rulerAndScrubStrip(totalWidth: totalWidth, layout: layout)
                            .padding(.top, 4)

                        if sequenceLaneHeight > 0 {
                            sequenceRow(totalWidth: totalWidth, layout: layout)
                                .frame(height: sequenceLaneHeight, alignment: .leading)
                        }

                        if adjustmentLaneHeight > 0 {
                            adjustmentLayerRow(totalWidth: totalWidth, layout: layout)
                                .frame(height: adjustmentLaneHeight, alignment: .leading)
                        }

                        if !isOverlayTracksExpanded, !vm.textOverlays.isEmpty {
                            textOverlayRow(totalWidth: totalWidth, layout: layout)
                                .frame(height: textOverlayLaneHeight, alignment: .leading)
                        }

                        if !isOverlayTracksExpanded, !vm.graphicOverlays.isEmpty {
                            graphicOverlayRow(totalWidth: totalWidth, layout: layout)
                                .frame(height: graphicOverlayLaneHeight, alignment: .leading)
                        }

                        clipsRow(layout: layout)
                            .frame(height: clipsLaneHeight, alignment: .leading)

                        if !vm.overlayClips.isEmpty {
                            overlayRow(totalWidth: totalWidth, layout: layout)
                                .frame(height: overlayDisplayHeight, alignment: .leading)
                        }

                        if !isOverlayTracksExpanded {
                            audioRow(totalWidth: totalWidth, layout: layout)
                                .frame(height: audioViewportHeight, alignment: .leading)
                        }

                        // Fills space below tracks (and future overlay lanes) so horizontal pan works
                        // on the whole timeline stack, not only on the thin overlay/clip rows.
                        Spacer(minLength: 0)
                            .contentShape(Rectangle())
                    }
                    .frame(width: totalWidth, height: paddedMinHeight, alignment: .top)
                    .clipped()

                    TimelinePlayheadLine(vm: vm, layout: layout, stackHeight: playheadStackHeight)
                    if let inPoint = vm.exportInPoint {
                        rangeMarker(time: inPoint, label: "IN", color: .green, layout: layout)
                    }
                    if let outPoint = vm.exportOutPoint {
                        rangeMarker(time: outPoint, label: "OUT", color: .orange, layout: layout)
                    }
                    ForEach(vm.markers) { marker in
                        rangeMarker(
                            time: marker.time,
                            label: marker.name,
                            color: .purple,
                            layout: layout
                        )
                    }
                    if let snapTime = vm.snapGuideTime {
                        Rectangle()
                            .fill(Color.appColors.primaryColor.opacity(0.9))
                            .frame(width: 1.5, height: playheadStackHeight)
                            .offset(x: layout.contentX(forTime: snapTime), y: 4)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
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
            .scrollDisabled(
                isScrubbing || isAudioTrimming || isAudioMoving || isTextTrimming
                    || isTextMoving || isOverlayTrimming || isOverlayMoving || reorderState.isDragging
            )
            .frame(width: geo.size.width, height: geo.size.height)
            .onAppear { revealPlayhead(using: proxy) }
            .onChange(of: vm.timelineRevealNonce) { _, _ in
                revealPlayhead(using: proxy)
            }
            }
        }
    }

    private func revealPlayhead(using proxy: ScrollViewProxy) {
        Task { @MainActor in
            await Task.yield()
            proxy.scrollTo(Self.playheadScrollID, anchor: .center)
            try? await Task.sleep(nanoseconds: 50_000_000)
            proxy.scrollTo(Self.playheadScrollID, anchor: .center)
        }
    }

    private func rangeMarker(
        time: TimeInterval,
        label: String,
        color: Color,
        layout: TimelineLayout
    ) -> some View {
        VStack(spacing: 0) {
            Text(label)
                .font(.system(size: 8, weight: .black))
                .lineLimit(1)
                .frame(maxWidth: 80)
                .foregroundStyle(.black)
                .padding(.horizontal, 4).padding(.vertical, 2)
                .background(Capsule().fill(color))
            Rectangle().fill(color.opacity(0.8)).frame(width: 1, height: playheadStackHeight - 14)
        }
        .offset(x: layout.contentX(forTime: time) - 8, y: 1)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: Media overlays

    private func sequenceRow(totalWidth: CGFloat, layout: TimelineLayout) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(sequenceLanePlacements) { placement in
                    let startX = layout.contentX(forTime: placement.range.lowerBound)
                    let endX = layout.contentX(forTime: placement.range.upperBound)
                    Button { vm.selectSequence(placement.sequence.id) } label: {
                        HStack(spacing: 5) {
                            Image(systemName: placement.sequence.kind == .compound
                                  ? "square.stack.3d.up.fill" : "rectangle.3.group")
                            Text(placement.sequence.title).lineLimit(1)
                        }
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .frame(width: max(48, endX - startX), height: sequenceBandHeight, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(placement.sequence.kind == .compound
                                      ? Color.purple.opacity(0.55) : Color.blue.opacity(0.48))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(
                                            vm.selectedSequenceID == placement.sequence.id
                                                ? Color.appColors.primaryColor : Color.white.opacity(0.25),
                                            lineWidth: vm.selectedSequenceID == placement.sequence.id ? 2 : 1
                                        )
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .offset(
                        x: startX,
                        y: CGFloat(placement.lane) * (sequenceBandHeight + sequenceBandSpacing)
                    )
                    .accessibilityLabel("\(placement.sequence.kind.rawValue) \(placement.sequence.title)")
            }
        }
        .frame(width: totalWidth, height: sequenceLaneHeight, alignment: .leading)
    }

    private func overlayRow(totalWidth: CGFloat, layout: TimelineLayout) -> some View {
        Group {
            if isOverlayTracksExpanded {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        expandedOverlayRows(totalWidth: totalWidth, layout: layout)
                    }
                    .onAppear {
                        revealSelectedOverlayRow(using: proxy, animated: false)
                    }
                    .onChange(of: overlayLaneCount) { _, _ in
                        revealSelectedOverlayRow(using: proxy, animated: true)
                    }
                    .onChange(of: vm.selectedOverlayClipID) { _, _ in
                        revealSelectedOverlayRow(using: proxy, animated: true)
                    }
                }
                .frame(
                    width: totalWidth,
                    height: expandedOverlayViewportHeight,
                    alignment: .topLeading
                )
                .contentShape(Rectangle())
                .clipped()
            } else {
                collapsedOverlaySummary(totalWidth: totalWidth, layout: layout)
            }
        }
        .frame(width: totalWidth, height: overlayDisplayHeight, alignment: .topLeading)
        .clipped()
    }

    private func revealSelectedOverlayRow(using proxy: ScrollViewProxy, animated: Bool) {
        guard let selectedID = vm.selectedOverlayClipID,
              let lane = overlayLanePlacements.first(where: { $0.clip.id == selectedID })?.lane
        else { return }

        if animated {
            withAnimation(.easeInOut(duration: 0.2)) {
                proxy.scrollTo(lane, anchor: .center)
            }
        } else {
            proxy.scrollTo(lane, anchor: .center)
        }
    }

    private func expandedOverlayRows(totalWidth: CGFloat, layout: TimelineLayout) -> some View {
        LazyVStack(alignment: .leading, spacing: overlayLaneSpacing) {
            ForEach(0..<overlayLaneCount, id: \.self) { lane in
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(0.04))

                    ForEach(overlayLanePlacements.filter { $0.lane == lane }) { placement in
                        OverlayClipThumb(
                            clip: placement.clip,
                            laneNumber: placement.lane + 1,
                            layout: layout,
                            laneHeight: overlayLaneHeight,
                            isSelected: vm.selectedOverlayClipID == placement.clip.id
                                || vm.isItemSelected(.overlay(placement.clip.id)),
                            allowsEditing: !vm.isMultiSelectMode,
                            isTrimming: $isOverlayTrimming,
                            isMoving: $isOverlayMoving,
                            onSelect: { vm.selectOverlayClip(placement.clip.id) },
                            onTrimChanged: { start, end in
                                vm.setOverlayTrim(
                                    clipID: placement.clip.id,
                                    trimStart: start,
                                    trimEnd: end
                                )
                            },
                            onTrimEnded: { vm.commitOverlayTrim(clipID: placement.clip.id) },
                            onMove: { start in
                                vm.setOverlayTimelineStart(
                                    clipID: placement.clip.id,
                                    timelineStart: start
                                )
                            },
                            onMoveEnded: { vm.commitOverlayMove() }
                        )
                        .opacity(vm.isItemInActiveSequence(.overlay(placement.clip.id)) ? 1 : 0.18)
                        .allowsHitTesting(vm.isItemInActiveSequence(.overlay(placement.clip.id)))
                        .zIndex(vm.selectedOverlayClipID == placement.clip.id ? 10 : 1)
                    }

                    if lane == 0 {
                        Button(action: onAddOverlayClip) {
                            Image(systemName: "plus")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.black)
                                .frame(width: 22, height: 22)
                                .background(Circle().fill(Color.appColors.primaryColor))
                        }
                        .buttonStyle(.plain)
                        .offset(x: max(0, totalWidth - 26), y: 9)
                        .zIndex(20)
                        .accessibilityLabel("Add media overlay")
                    }
                }
                .frame(width: totalWidth, height: overlayLaneHeight)
                .id(lane)
            }
        }
        .frame(width: totalWidth, height: overlayLaneResolvedHeight, alignment: .leading)
    }

    private func collapsedOverlaySummary(totalWidth: CGFloat, layout: TimelineLayout) -> some View {
        let start = vm.overlayClips.map(\.timelineStart).min() ?? 0
        let end = vm.overlayClips.map(\.timelineEnd).max() ?? start
        let startX = layout.contentX(forTime: start)
        let endX = layout.contentX(forTime: end)
        let width = max(64, endX - startX)

        return Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                isOverlayTracksExpanded = true
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "rectangle.3.group")
                    .font(.system(size: 11, weight: .bold))
                Text("\(vm.overlayClips.count) Overlay\(vm.overlayClips.count == 1 ? "" : "s")")
                    .font(.system(size: 10, weight: .semibold))
                Spacer(minLength: 2)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 9)
            .frame(width: width, height: overlayLaneHeight)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.appColors.primaryColor.opacity(0.26))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.appColors.primaryColor.opacity(0.75), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .offset(x: startX)
        .frame(width: totalWidth, height: overlayLaneHeight, alignment: .leading)
        .accessibilityLabel("Show \(vm.overlayClips.count) overlay tracks")
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

    private func adjustmentLayerRow(totalWidth: CGFloat, layout: TimelineLayout) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(vm.adjustmentLayers.sorted(by: { $0.zIndex < $1.zIndex })) { layer in
                let startX = layout.contentX(forTime: layer.startTime)
                let endX = layout.contentX(forTime: layer.endTime)
                Button {
                    vm.selectAdjustmentLayer(layer.id)
                    vm.selectTool(.effects)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: layer.isEnabled ? "wand.and.stars" : "eye.slash")
                        Text(layer.title).lineLimit(1)
                    }
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .frame(width: max(48, endX - startX), height: adjustmentLaneHeight, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.orange.opacity(layer.isEnabled ? 0.55 : 0.22))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6).stroke(
                                    vm.selectedAdjustmentLayerID == layer.id
                                        ? Color.appColors.primaryColor : Color.white.opacity(0.2),
                                    lineWidth: vm.selectedAdjustmentLayerID == layer.id ? 2 : 1
                                )
                            )
                    )
                }
                .buttonStyle(.plain)
                .offset(x: startX)
            }
        }
        .frame(width: totalWidth, height: adjustmentLaneHeight, alignment: .leading)
    }

    private func textOverlayRow(totalWidth: CGFloat, layout: TimelineLayout) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(vm.textOverlays) { overlay in
                TextOverlayThumb(
                    overlay: overlay,
                    layout: layout,
                    isSelected: vm.selectedTextOverlayID == overlay.id
                        || vm.isItemSelected(.text(overlay.id)),
                    allowsEditing: !vm.isMultiSelectMode,
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
                .opacity(vm.isItemInActiveSequence(.text(overlay.id)) ? 1 : 0.18)
                .allowsHitTesting(vm.isItemInActiveSequence(.text(overlay.id)))
            }
        }
        .frame(width: totalWidth, alignment: .leading)
    }

    private func graphicOverlayRow(totalWidth: CGFloat, layout: TimelineLayout) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(vm.graphicOverlays) { graphic in
                GraphicOverlayThumb(
                    graphic: graphic,
                    layout: layout,
                    isSelected: vm.selectedGraphicOverlayID == graphic.id,
                    isTrimming: $isGraphicTrimming,
                    isMoving: $isGraphicMoving,
                    onSelect: { vm.selectGraphicOverlay(graphic.id) },
                    onTrimChanged: { start, end in
                        vm.updateGraphicTimeRange(id: graphic.id, start: start, end: end)
                    },
                    onEditEnded: { vm.commitGraphicEdit() },
                    onMove: { vm.moveGraphicOnTimeline(id: graphic.id, startTime: $0) }
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
                let isSelected = vm.selectedClipID == clip.id || vm.isItemSelected(.primary(clip.id))
                let isInActiveSequence = vm.isItemInActiveSequence(.primary(clip.id))
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
                    canReorder: isSelected && !vm.isMultiSelectMode && vm.clips.count > 1,
                    allowsEditing: !vm.isMultiSelectMode,
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
                .opacity(isInActiveSequence ? 1 : 0.18)
                .zIndex(isBeingDragged ? 100 : 0)
                .animation(.interactiveSpring(response: 0.28, dampingFraction: 0.78), value: shiftOffset)
                .animation(.interactiveSpring(response: 0.22, dampingFraction: 0.72), value: isBeingDragged)
                .allowsHitTesting(isInActiveSequence)

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
        Group {
            if vm.audioClips.isEmpty {
                emptyAudioRow(totalWidth: totalWidth)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    audioLanes(totalWidth: totalWidth)
                }
                .frame(width: totalWidth, height: audioViewportHeight, alignment: .topLeading)
                .contentShape(Rectangle())
                .clipped()
            }
        }
        .frame(width: totalWidth, height: audioViewportHeight, alignment: .topLeading)
        .clipped()
    }

    private func emptyAudioRow(totalWidth: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .frame(width: totalWidth, height: audioLaneHeight)

            Button {
                onAddAudioTrack()
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
        }
        .frame(width: totalWidth, height: audioLaneHeight, alignment: .leading)
    }

    /// Each lane is an independent audio track. Lane 0 carries a pinned **+** that always adds
    /// a brand-new track at the current playhead, so a second (third, fourth, …) audio clip can
    /// land wherever the playhead is instead of being forced to the end of a single lane.
    private func audioLanes(totalWidth: CGFloat) -> some View {
        LazyVStack(alignment: .leading, spacing: audioLaneSpacing) {
            ForEach(0..<audioLaneCount, id: \.self) { lane in
                let laneClips = audioLanePlacements
                    .filter { $0.lane == lane }
                    .map(\.clip)
                    .sorted { $0.timelineStart < $1.timelineStart }

                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(0.04))

                    ForEach(laneClips) { clip in
                        let slotX = CGFloat(clip.timelineEnd) * pixelsPerSecond + insertSlotWidth / 2
                        if slotX < totalWidth - 20 {
                            audioInsertButton(afterClipID: clip.id)
                                .offset(x: slotX, y: (audioLaneHeight - 24) / 2)
                                .zIndex(0)
                        }
                    }

                    ForEach(laneClips) { clip in
                        AudioClipThumb(
                            clip: clip,
                            pixelsPerSecond: pixelsPerSecond,
                            scrubMinimumDistance: audioScrubMinimumDistance,
                            laneHeight: audioLaneHeight,
                            isSelected: vm.selectedAudioClipID == clip.id
                                || vm.isItemSelected(.audio(clip.id)),
                            allowsEditing: !vm.isMultiSelectMode,
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
                        .opacity(vm.isItemInActiveSequence(.audio(clip.id)) ? 1 : 0.18)
                        .allowsHitTesting(vm.isItemInActiveSequence(.audio(clip.id)))
                        .zIndex(vm.selectedAudioClipID == clip.id ? 10 : 1)
                    }

                    if lane == 0 {
                        Button(action: onAddAudioTrack) {
                            Image(systemName: "plus")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.black)
                                .frame(width: 22, height: 22)
                                .background(Circle().fill(Color.appColors.primaryColor))
                        }
                        .buttonStyle(.plain)
                        .offset(x: max(0, totalWidth - 26), y: (audioLaneHeight - 22) / 2)
                        .zIndex(20)
                        .accessibilityLabel("Add audio track")
                    }
                }
                .frame(width: totalWidth, height: audioLaneHeight)
                .id(lane)
            }
        }
        .frame(width: totalWidth, height: audioLaneResolvedHeight, alignment: .leading)
    }

    private func audioInsertButton(afterClipID: UUID) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onInsertAudioAfterClip(afterClipID)
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.appColors.primaryColor))
                .overlay(Circle().stroke(Color.black.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add audio after this clip")
    }
}

// MARK: - Media overlay thumb

private struct OverlayClipThumb: View {
    let clip: EditorOverlayClip
    let laneNumber: Int
    let layout: TimelineLayout
    let laneHeight: CGFloat
    let isSelected: Bool
    let allowsEditing: Bool
    @Binding var isTrimming: Bool
    @Binding var isMoving: Bool
    let onSelect: () -> Void
    let onTrimChanged: (TimeInterval, TimeInterval) -> Void
    let onTrimEnded: () -> Void
    let onMove: (TimeInterval) -> Void
    let onMoveEnded: () -> Void

    @State private var trimBaseline: (
        timelineStart: TimeInterval,
        trimStart: TimeInterval,
        trimEnd: TimeInterval
    )?
    @State private var moveBaselineTimelineStart: TimeInterval?

    private var displayTimelineStart: TimeInterval {
        if let baseline = trimBaseline {
            let sourceDelta = clip.playback.isReverse
                ? baseline.trimEnd - clip.trimEnd
                : clip.trimStart - baseline.trimStart
            return max(
                0,
                baseline.timelineStart
                    + sourceDelta / TimeInterval(max(clip.speed, 0.001))
            )
        }
        return clip.timelineStart
    }

    private var startX: CGFloat { layout.contentX(forTime: displayTimelineStart) }
    private var endX: CGFloat { layout.contentX(forTime: displayTimelineStart + clip.duration) }
    private var width: CGFloat { max(44, endX - startX) }

    private var displayedTrimStart: TimeInterval {
        clip.playback.isReverse
            ? clip.originalDuration - clip.trimEnd
            : clip.trimStart
    }

    private var displayedTrimEnd: TimeInterval {
        clip.playback.isReverse
            ? clip.originalDuration - clip.trimStart
            : clip.trimEnd
    }

    var body: some View {
        thumbnailContent
            .contentShape(Rectangle())
            .onTapGesture {
                guard !isTrimming, !isMoving else { return }
                onSelect()
            }
            .offset(x: startX)
            .simultaneousGesture(
                moveGesture,
                including: isSelected && allowsEditing ? .all : .none
            )
    }

    private var thumbnailContent: some View {
        ZStack(alignment: .bottomLeading) {
            ClipFilmstripView(clip: clip.thumbnailClip, width: width, height: laneHeight)
            overlayLabel
        }
        .frame(width: width, height: laneHeight)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(
                    isSelected ? Color.appColors.primaryColor : Color.white.opacity(0.32),
                    lineWidth: isSelected ? 2 : 1
                )
        )
        .overlay {
            trimHandles
        }
    }

    private var overlayLabel: some View {
        HStack(spacing: 4) {
            Image(systemName: "rectangle.on.rectangle")
            if clip.playback.isReverse {
                Image(systemName: "backward.end.alt.fill")
            } else if clip.playback.isFreezeFrame {
                Image(systemName: "snowflake")
            }
            Text("Overlay \(laneNumber) · Layer \(clip.zIndex + 1)")
        }
        .font(.system(size: 9, weight: .semibold))
        .foregroundColor(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.black.opacity(0.6)))
        .padding(4)
    }

    @ViewBuilder
    private var trimHandles: some View {
        if isSelected && allowsEditing {
            ClipTrimHandleRepresentable(
                clipID: clip.id,
                trimStart: displayedTrimStart,
                trimEnd: displayedTrimEnd,
                originalDuration: clip.originalDuration,
                allowsDurationExtension: clip.isPhoto,
                speed: clip.speed,
                pixelsPerSecond: layout.pixelsPerSecond,
                onTrimChanged: handleTrimChanged,
                onTrimEnded: handleTrimEnded
            )
            .allowsHitTesting(true)
        }
    }

    private func handleTrimChanged(
        _: UUID,
        _ start: TimeInterval,
        _ end: TimeInterval
    ) {
        if trimBaseline == nil {
            trimBaseline = (clip.timelineStart, clip.trimStart, clip.trimEnd)
        }
        isTrimming = true
        onTrimChanged(start, end)
    }

    private func handleTrimEnded() {
        isTrimming = false
        trimBaseline = nil
        onTrimEnded()
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .local)
            .onChanged { value in
                guard !isTrimming else { return }
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                if moveBaselineTimelineStart == nil {
                    moveBaselineTimelineStart = clip.timelineStart
                }
                isMoving = true
                let baseX = layout.contentX(forTime: moveBaselineTimelineStart ?? clip.timelineStart)
                onMove(layout.time(atContentX: max(0, baseX + value.translation.width)))
            }
            .onEnded { _ in
                guard moveBaselineTimelineStart != nil else { return }
                isMoving = false
                moveBaselineTimelineStart = nil
                onMoveEnded()
            }
    }
}

// MARK: - Audio clip thumb (mirrors ClipThumb trim / scrub behaviour)

private struct AudioClipThumb: View {
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
    let onMoveEnded: () -> Void

    @State private var trimBaseline: (timelineStart: TimeInterval, trimStart: TimeInterval)?
    @State private var moveBaselineTimelineStart: TimeInterval?
    /// Real peak-amplitude samples loaded async from `AudioWaveformGenerator` (Priority 13) —
    /// starts flat/placeholder-shaped and fills in once the file's been analyzed (cached after
    /// the first time, so this is usually instant on subsequent renders).
    @State private var waveformSamples: [CGFloat] = []

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
            .offset(x: CGFloat(displayTimelineStart) * pixelsPerSecond, y: 0)

        if isSelected && allowsEditing {
            content.gesture(moveGesture)
        } else {
            content.gesture(scrubGesture)
        }
    }

    private var clipVisual: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.appColors.primaryColor.opacity(isSelected ? 0.28 : 0.18))

            WaveformShape(samples: waveformSamples)
                .stroke(Color.appColors.primaryColor.opacity(0.95), lineWidth: 1)
                .padding(.vertical, 6)
                .task(id: clip.fileURL) {
                    waveformSamples = await AudioWaveformGenerator.shared.waveform(for: clip.fileURL)
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
    let allowsEditing: Bool
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
        // Caption segments are often well under a second. Giving every one a
        // 44pt minimum made neighboring captions overlap into an unreadable
        // stack. Their bars must remain faithful to timeline time.
        overlay.isCaption ? max(2, endX - displayStartX) : max(44, endX - displayStartX)
    }

    var body: some View {
        let content = barContent
            .overlay {
                if isSelected && allowsEditing {
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

        if isSelected && allowsEditing {
            content.gesture(moveGesture)
        } else {
            content
        }
    }

    private var barContent: some View {
        Group {
            if overlay.isCaption {
                HStack(spacing: 0) {
                    if barWidth >= 24 {
                        Text(overlay.text)
                            .font(.system(size: 10, weight: .semibold))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .padding(.horizontal, 5)
                    }
                }
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "textformat")
                        .font(.system(size: 9, weight: .bold))
                    if overlay.animation.isAnimated {
                        Image(systemName: "sparkles")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Color.appColors.primaryColor)
                    }
                    Text(truncated(overlay.text))
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(1)
                }
                .padding(.horizontal, 8)
            }
        }
        .foregroundColor(.white)
        .frame(width: barWidth, alignment: .leading)
        .frame(height: 32)
        .background(
            RoundedRectangle(cornerRadius: overlay.isCaption ? 3 : 6, style: .continuous)
                .fill(Color.appColors.primaryColor.opacity(
                    isSelected ? 0.7 : (overlay.isCaption ? 0.46 : 0.2)
                ))
                .padding(.horizontal, overlay.isCaption && barWidth > 4 ? 1 : 0)
        )
        .overlay(
            RoundedRectangle(cornerRadius: overlay.isCaption ? 3 : 6, style: .continuous)
                .stroke(
                    isSelected
                        ? Color.appColors.primaryColor
                        : (overlay.isCaption ? .clear : Color.appColors.primaryColor.opacity(0.45)),
                    lineWidth: isSelected ? 2 : 1
                )
                .padding(.horizontal, overlay.isCaption && barWidth > 4 ? 1 : 0)
        )
        .clipped()
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

private struct GraphicOverlayThumb: View {
    let graphic: EditorGraphicOverlay
    let layout: TimelineLayout
    let isSelected: Bool
    @Binding var isTrimming: Bool
    @Binding var isMoving: Bool
    let onSelect: () -> Void
    let onTrimChanged: (TimeInterval, TimeInterval) -> Void
    let onEditEnded: () -> Void
    let onMove: (TimeInterval) -> Void

    @State private var trimBaseline: (time: TimeInterval, x: CGFloat)?
    @State private var moveBaseline: TimeInterval?

    private var startX: CGFloat {
        if let trimBaseline {
            return trimBaseline.x + layout.contentX(forTime: graphic.startTime)
                - layout.contentX(forTime: trimBaseline.time)
        }
        return layout.contentX(forTime: graphic.startTime)
    }
    private var width: CGFloat { max(44, layout.contentX(forTime: graphic.endTime) - startX) }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "face.smiling.inverse")
            Text(graphic.title).lineLimit(1)
            if graphic.animation != .none { Image(systemName: "waveform.path") }
        }
        .font(.system(size: 9, weight: .bold))
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .frame(width: width, height: 32, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.purple.opacity(isSelected ? 0.72 : 0.38))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(
                    isSelected ? Color.appColors.primaryColor : Color.purple.opacity(0.75),
                    lineWidth: isSelected ? 2 : 1
                ))
        )
        .overlay {
            if isSelected {
                ClipTrimHandleRepresentable(
                    clipID: graphic.id,
                    trimStart: graphic.startTime,
                    trimEnd: graphic.endTime,
                    originalDuration: max(layout.timelineExtent, 1),
                    allowsDurationExtension: false,
                    speed: 1,
                    pixelsPerSecond: layout.pixelsPerSecond,
                    onTrimChanged: { _, start, end in
                        if trimBaseline == nil { trimBaseline = (graphic.startTime, layout.contentX(forTime: graphic.startTime)) }
                        isTrimming = true
                        onTrimChanged(start, end)
                    },
                    onTrimEnded: {
                        isTrimming = false
                        trimBaseline = nil
                        onEditEnded()
                    }
                )
                .frame(width: width, height: 32)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { if !isTrimming && !isMoving { onSelect() } }
        .gesture(moveGesture)
        .offset(x: startX)
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                guard !isTrimming else { return }
                if moveBaseline == nil { moveBaseline = graphic.startTime }
                isMoving = true
                let baseX = layout.contentX(forTime: moveBaseline ?? graphic.startTime)
                onMove(layout.time(atContentX: max(0, baseX + value.translation.width)))
            }
            .onEnded { _ in
                isMoving = false
                moveBaseline = nil
                onEditEnded()
            }
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

// MARK: - Playhead (isolated — only these views observe `timelinePosition` during playback)

private struct TimelinePlayheadLine: View {
    let vm: EditorViewModel
    let layout: TimelineLayout
    let stackHeight: CGFloat

    var body: some View {
        let x = layout.contentX(forTime: vm.timelinePosition)
        ZStack(alignment: .topLeading) {
            HStack(spacing: 0) {
                Color.clear.frame(width: max(0, x), height: 1)
                Color.clear
                    .frame(width: 1, height: 1)
                    .id(EditorTimeline.playheadScrollID)
                Spacer(minLength: 0)
            }
            .frame(height: 1)
            .allowsHitTesting(false)
            .accessibilityHidden(true)

            PlayheadShape()
                .stroke(Color.white.opacity(0.95), lineWidth: 1)
                .frame(width: 18, height: stackHeight)
                .offset(x: x - 9, y: 0)
        }
        .frame(width: layout.contentWidth, height: stackHeight, alignment: .leading)
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
