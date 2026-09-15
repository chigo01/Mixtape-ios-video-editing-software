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
    @Binding var isAudioTracksExpanded: Bool
    @Binding var isTextTracksExpanded: Bool
    var onInsertAfterClip: (Int) -> Void = { _ in }
    var onSelectOpeningTransition: () -> Void = {}
    var onSelectClosingTransition: () -> Void = {}
    var onSelectTransition: (Int) -> Void = { _ in }
    var onAddAudioTrack: () -> Void = {}
    var onInsertAudioAfterClip: (UUID) -> Void = { _ in }
    var onAddOverlayClip: () -> Void = {}

    private let minimumPixelsPerSecond: CGFloat = 1.5
    private let maximumPixelsPerSecond: CGFloat = 72
    private let trackHeaderWidth: CGFloat = 38
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
    /// Transition gaps compress with the timeline when zoomed far out. Keeping
    /// these fixed at 28pt prevented projects with many cuts from ever fitting.
    private var insertSlotWidth: CGFloat {
        max(3, 28 * min(1, pixelsPerSecond / 18))
    }

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
    @State private var committedPixelsPerSecond: CGFloat = 18
    @GestureState private var activeTimelineMagnification: CGFloat = 1
    static let playheadScrollID = "timeline-playhead"

    private var pixelsPerSecond: CGFloat {
        min(
            maximumPixelsPerSecond,
            max(minimumPixelsPerSecond, committedPixelsPerSecond * activeTimelineMagnification)
        )
    }

    private let textLaneHeight: CGFloat = 36
    private let textLaneSpacing: CGFloat = 5
    @State private var textLaneByID: [UUID: Int] = [:]
    private var textIntervals: [EditorTextLaneInterval] {
        vm.textOverlays.map { .init(id: $0.id, start: $0.startTime, end: $0.endTime) }
    }
    private var textLaneCount: Int { max(1, (textLaneByID.values.max() ?? -1) + 1) }

    private func refreshTextLanes() {
        // Keep lane positions and the viewport fixed for the entire gesture.
        guard !isTextMoving, !isTextTrimming else { return }
        textLaneByID = EditorTextLaneLayout.assign(textIntervals, preserving: textLaneByID)
    }

    private var textOverlayLaneHeight: CGFloat {
        guard isTextTracksExpanded else { return textLaneHeight }
        return CGFloat(min(2, textLaneCount)) * textLaneHeight
            + CGFloat(min(2, textLaneCount) - 1) * textLaneSpacing
    }
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

    private var audioDisplayHeight: CGFloat {
        if vm.audioClips.isEmpty || isAudioTracksExpanded {
            return audioViewportHeight
        }
        return audioLaneHeight
    }

    private var playheadStackHeight: CGFloat {
        4 + rulerLabelHeight + scrubRailHeight
            + (sequenceLaneHeight > 0 ? 8 + sequenceLaneHeight : 0)
            + (adjustmentLaneHeight > 0 ? 8 + adjustmentLaneHeight : 0)
            + (isOverlayTracksExpanded || graphicOverlayLaneHeight == 0 ? 0 : 8 + graphicOverlayLaneHeight)
            + 8 + textOverlayLaneHeight
            + 8 + clipsLaneHeight + 8 + overlayDisplayHeight
            + (isOverlayTracksExpanded ? 0 : 8 + audioDisplayHeight)
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

            HStack(spacing: 0) {
                trackHeaderRail(height: geo.size.height)

                ScrollViewReader { proxy in
                PlaybackFollowingTimelineScrollView(
                    vm: vm,
                    layout: layout,
                    viewportWidth: max(1, geo.size.width - trackHeaderWidth),
                    isEditing: isScrubbing || isAudioTrimming || isAudioMoving || isTextTrimming
                        || isTextMoving || isGraphicTrimming || isGraphicMoving
                        || isOverlayTrimming || isOverlayMoving || reorderState.isDragging
                        || activeTimelineMagnification != 1
                ) {
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

                        textTracks(totalWidth: totalWidth, layout: layout)
                            .frame(height: textOverlayLaneHeight, alignment: .leading)

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
                                .frame(height: audioDisplayHeight, alignment: .leading)
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
                    || isTextMoving || isGraphicTrimming || isGraphicMoving
                    || isOverlayTrimming || isOverlayMoving || reorderState.isDragging
            )
            .simultaneousGesture(
                timelineZoomGesture(
                    onChanged: { proxy.scrollTo(Self.playheadScrollID, anchor: .center) },
                    onEnded: { revealPlayhead(using: proxy) }
                )
            )
            .frame(
                width: max(1, geo.size.width - trackHeaderWidth),
                height: geo.size.height
            )
            .onAppear {
                refreshTextLanes()
                revealPlayhead(using: proxy)
            }
            .onChange(of: textIntervals) { _, _ in refreshTextLanes() }
            .onChange(of: isTextMoving) { _, moving in
                if !moving { refreshTextLanes() }
            }
            .onChange(of: isTextTrimming) { _, trimming in
                if !trimming { refreshTextLanes() }
            }
            .onChange(of: vm.timelineRevealNonce) { _, _ in
                revealPlayhead(using: proxy)
            }
            .onDisappear {
                // A disappearing timeline must never carry a gesture lock into
                // the next presentation of the editor.
                isScrubbing = false
                isAudioTrimming = false
                isAudioMoving = false
                isTextTrimming = false
                isTextMoving = false
                isGraphicTrimming = false
                isGraphicMoving = false
                isOverlayTrimming = false
                isOverlayMoving = false
            }
                }
            }
        }
    }

    private func timelineZoomGesture(
        onChanged: @escaping () -> Void,
        onEnded: @escaping () -> Void
    ) -> some Gesture {
        MagnificationGesture()
            .updating($activeTimelineMagnification) { value, state, _ in
                state = value
            }
            .onChanged { _ in onChanged() }
            .onEnded { value in
                committedPixelsPerSecond = min(
                    maximumPixelsPerSecond,
                    max(minimumPixelsPerSecond, committedPixelsPerSecond * value)
                )
                UISelectionFeedbackGenerator().selectionChanged()
                onEnded()
            }
    }

    private func trackHeaderRail(height: CGFloat) -> some View {
        VStack(spacing: 8) {
            Color.clear
                .frame(height: rulerLabelHeight + scrubRailHeight)
                .padding(.top, 4)

            if sequenceLaneHeight > 0 {
                trackHeaderIcon("square.stack.3d.up.fill", label: "Sequence track")
                    .frame(height: sequenceLaneHeight)
            }

            if adjustmentLaneHeight > 0 {
                trackHeaderIcon("wand.and.stars", label: "Adjustment track")
                    .frame(height: adjustmentLaneHeight)
            }

            Button {
                vm.addTextOverlay()
            } label: {
                trackHeaderIcon("text.badge.plus", label: "Add text overlay")
                    .frame(height: textOverlayLaneHeight)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add text overlay")
            .disabled(vm.totalDuration <= 0.1)

            if !isOverlayTracksExpanded, !vm.graphicOverlays.isEmpty {
                trackHeaderIcon("face.smiling", label: "Graphic track")
                    .frame(height: graphicOverlayLaneHeight)
            }

            trackHeaderIcon("film.stack", label: "Main video track")
                .frame(height: clipsLaneHeight)

            if !vm.overlayClips.isEmpty {
                trackHeaderLaneIcons(
                    "rectangle.on.rectangle",
                    label: "Overlay track",
                    visibleLaneCount: isOverlayTracksExpanded ? min(2, overlayLaneCount) : 1,
                    laneHeight: overlayLaneHeight,
                    laneSpacing: overlayLaneSpacing,
                    totalHeight: overlayDisplayHeight
                )
            }

            if !isOverlayTracksExpanded {
                trackHeaderLaneIcons(
                    "music.note",
                    label: "Audio track",
                    visibleLaneCount: isAudioTracksExpanded ? min(2, audioLaneCount) : 1,
                    laneHeight: audioLaneHeight,
                    laneSpacing: audioLaneSpacing,
                    totalHeight: audioDisplayHeight
                )
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .frame(width: trackHeaderWidth, height: height, alignment: .top)
        .background(Color.black.opacity(0.96))
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(width: 1)
        }
    }

    private func trackHeaderLaneIcons(
        _ systemName: String,
        label: String,
        visibleLaneCount: Int,
        laneHeight: CGFloat,
        laneSpacing: CGFloat,
        totalHeight: CGFloat
    ) -> some View {
        VStack(spacing: laneSpacing) {
            ForEach(0..<max(1, visibleLaneCount), id: \.self) { lane in
                trackHeaderIcon(systemName, label: "\(label) \(lane + 1)")
                    .frame(height: laneHeight)
            }
        }
        .frame(width: trackHeaderWidth, height: totalHeight, alignment: .top)
        .clipped()
    }

    private func trackHeaderIcon(_ systemName: String, label: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.white.opacity(0.78))
            .frame(width: 30, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white.opacity(0.09))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
            .accessibilityLabel(label)
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
        revealTimelineLane(lane, using: proxy, animated: animated)
    }

    private func revealSelectedAudioRow(using proxy: ScrollViewProxy, animated: Bool) {
        guard let selectedID = vm.selectedAudioClipID,
              let lane = audioLanePlacements.first(where: { $0.clip.id == selectedID })?.lane
        else { return }
        revealTimelineLane(lane, using: proxy, animated: animated)
    }

    private func revealTimelineLane(_ lane: Int, using proxy: ScrollViewProxy, animated: Bool) {
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
                            onMoveToLane: { laneDelta in
                                vm.setOverlayLaneIndex(
                                    clipID: placement.clip.id,
                                    laneIndex: max(0, placement.clip.laneIndex + laneDelta)
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
                vm.selectPreferredOverlayClip()
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
        let tickInterval: Int = {
            if pixelsPerSecond >= 12 { return 5 }
            if pixelsPerSecond >= 6 { return 10 }
            if pixelsPerSecond >= 3 { return 20 }
            return 30
        }()
        let ticks = stride(from: 0, through: Int(layout.timelineExtent), by: tickInterval).map { $0 }
        return ZStack(alignment: .topLeading) {
            ForEach(ticks, id: \.self) { sec in
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

    private func textTracks(totalWidth: CGFloat, layout: TimelineLayout) -> some View {
        Group {
            if vm.textOverlays.isEmpty {
                Button { vm.addTextOverlay() } label: {
                    Label("Add Text", systemImage: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.75))
                        .padding(.horizontal, 12)
                        .frame(height: textLaneHeight)
                        .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .disabled(vm.totalDuration <= 0.1)
                .frame(width: totalWidth, alignment: .leading)
            } else if !isTextTracksExpanded {
                collapsedTextSummary(totalWidth: totalWidth, layout: layout)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: textLaneCount > 2) {
                        ZStack(alignment: .topLeading) {
                            VStack(spacing: textLaneSpacing) {
                                ForEach(0..<textLaneCount, id: \.self) { lane in
                                    Color.white.opacity(0.025)
                                        .frame(height: textLaneHeight)
                                        .id(lane)
                                }
                            }
                            .allowsHitTesting(false)

                            // One stable ForEach owns every clip. Changing a lane
                            // changes only its offset, never its gesture identity.
                            textOverlayRow(totalWidth: totalWidth, layout: layout)
                        }
                        .frame(width: totalWidth,
                               height: CGFloat(textLaneCount) * (textLaneHeight + textLaneSpacing) - textLaneSpacing,
                               alignment: .topLeading)
                    }
                    .frame(width: totalWidth, height: textOverlayLaneHeight, alignment: .topLeading)
                    .clipped()
                    .onChange(of: textLaneByID) { _, _ in
                        revealSelectedTextLane(using: proxy)
                    }
                    .onChange(of: vm.selectedTextOverlayID) { _, _ in
                        revealSelectedTextLane(using: proxy)
                    }
                    .onAppear { revealSelectedTextLane(using: proxy) }
                }
            }
        }
    }

    private func collapsedTextSummary(totalWidth: CGFloat, layout: TimelineLayout) -> some View {
        let start = vm.textOverlays.map(\.startTime).min() ?? 0
        let end = vm.textOverlays.map(\.endTime).max() ?? start
        let startX = layout.contentX(forTime: start)
        let width = max(96, layout.contentX(forTime: end) - startX)
        return Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                isTextTracksExpanded = true
                if vm.selectedTextOverlayID == nil,
                   let preferred = vm.textOverlays.first(where: { $0.isVisible(at: vm.timelinePosition) })
                    ?? vm.textOverlays.first {
                    vm.selectTextOverlay(preferred.id)
                }
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "textformat")
                Text("\(vm.textOverlays.count) Text & Captions")
                    .lineLimit(1)
                Spacer(minLength: 2)
                Image(systemName: "chevron.up.chevron.down")
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .frame(width: width, height: textLaneHeight)
            .background(Color.appColors.primaryColor.opacity(0.26), in: RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.appColors.primaryColor.opacity(0.75), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .offset(x: startX)
        .frame(width: totalWidth, height: textLaneHeight, alignment: .leading)
        .accessibilityLabel("Expand text and caption tracks")
    }

    private func revealSelectedTextLane(using proxy: ScrollViewProxy) {
        guard !isTextMoving, !isTextTrimming,
              let id = vm.selectedTextOverlayID, let lane = textLaneByID[id] else { return }
        proxy.scrollTo(lane, anchor: .center)
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
                .offset(y: CGFloat(textLaneByID[overlay.id] ?? 0) * (textLaneHeight + textLaneSpacing))
                .zIndex(vm.selectedTextOverlayID == overlay.id ? 1 : 0)
                .opacity(vm.isItemInActiveSequence(.text(overlay.id)) ? 1 : 0.18)
                .allowsHitTesting(vm.isItemInActiveSequence(.text(overlay.id)))
            }
        }
        .frame(width: totalWidth,
               height: CGFloat(textLaneCount) * (textLaneHeight + textLaneSpacing) - textLaneSpacing,
               alignment: .topLeading)
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
            } else if isAudioTracksExpanded {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        audioLanes(totalWidth: totalWidth)
                    }
                    .onAppear {
                        revealSelectedAudioRow(using: proxy, animated: false)
                    }
                    .onChange(of: audioLaneCount) { _, _ in
                        revealSelectedAudioRow(using: proxy, animated: true)
                    }
                    .onChange(of: vm.selectedAudioClipID) { _, _ in
                        revealSelectedAudioRow(using: proxy, animated: true)
                    }
                }
                .frame(width: totalWidth, height: audioViewportHeight, alignment: .topLeading)
                .contentShape(Rectangle())
                .clipped()
            } else {
                collapsedAudioSummary(totalWidth: totalWidth, layout: layout)
            }
        }
        .frame(width: totalWidth, height: audioDisplayHeight, alignment: .topLeading)
        .clipped()
    }

    private func collapsedAudioSummary(totalWidth: CGFloat, layout: TimelineLayout) -> some View {
        let start = vm.audioClips.map(\.timelineStart).min() ?? 0
        let end = vm.audioClips.map(\.timelineEnd).max() ?? start
        let startX = layout.contentX(forTime: start)
        let endX = layout.contentX(forTime: end)
        let width = max(64, endX - startX)

        return Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                isAudioTracksExpanded = true
                vm.selectPreferredAudioClip()
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "music.note.list")
                    .font(.system(size: 11, weight: .bold))
                Text("\(vm.audioClips.count) Audio Track\(vm.audioClips.count == 1 ? "" : "s")")
                    .font(.system(size: 10, weight: .semibold))
                Spacer(minLength: 2)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 9)
            .frame(width: width, height: audioLaneHeight)
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
        .frame(width: totalWidth, height: audioLaneHeight, alignment: .leading)
        .accessibilityLabel("Show \(vm.audioClips.count) audio tracks")
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

                    // One append control per lane is enough. Keeping controls after clips that
                    // already have a successor puts buttons on top of the next waveform and its
                    // trim handles, making a continuous audio track look broken and cluttered.
                    if let lastClip = laneClips.last {
                        // Leave room for the selected clip's trailing trim handle.
                        let slotX = layout.contentX(forTime: lastClip.timelineEnd) + 26
                        if slotX < totalWidth - 20 {
                            audioInsertButton(afterClipID: lastClip.id)
                                .offset(x: slotX, y: (audioLaneHeight - 24) / 2)
                                .zIndex(0)
                        }
                    }

                    ForEach(laneClips) { clip in
                        AudioClipThumb(
                            clip: clip,
                            layout: layout,
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
                            onMoveToLane: { laneDelta in
                                vm.setAudioLaneIndex(
                                    clipID: clip.id,
                                    laneIndex: max(0, clip.laneIndex + laneDelta)
                                )
                            },
                            onMoveEnded: { vm.commitAudioMove() },
                            onResolvedSourceDuration: { duration in
                                vm.reconcileAudioSourceDuration(clipID: clip.id, duration: duration)
                            }
                        )
                        .opacity(vm.isItemInActiveSequence(.audio(clip.id)) ? 1 : 0.18)
                        .allowsHitTesting(vm.isItemInActiveSequence(.audio(clip.id)))
                        .zIndex(vm.selectedAudioClipID == clip.id ? 10 : 1)
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
