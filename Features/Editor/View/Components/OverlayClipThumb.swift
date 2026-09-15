//
//  OverlayClipThumb.swift
//  Mixtape
//

import SwiftUI
import UIKit
import Photos
import AVFoundation

// MARK: - Media overlay thumb

struct OverlayClipThumb: View {
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
    let onMoveToLane: (Int) -> Void
    let onMoveEnded: () -> Void

    @State private var trimBaseline: (
        timelineStart: TimeInterval,
        trimStart: TimeInterval,
        trimEnd: TimeInterval
    )?
    @State private var moveBaselineTimelineStart: TimeInterval?
    @State private var moveTranslation: CGSize = .zero
    @State private var isHoldActive = false
    @GestureState private var isMoveGestureActive = false

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
    private var width: CGFloat { max(layout.minimumItemWidth, endX - startX) }

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
            .scaleEffect(isHoldActive ? 1.04 : 1)
            .shadow(color: .black.opacity(isHoldActive ? 0.5 : 0), radius: 7, y: 3)
            .offset(x: startX + moveTranslation.width, y: moveTranslation.height)
            .simultaneousGesture(
                moveGesture,
                including: isSelected && allowsEditing ? .all : .none
            )
            .onChange(of: isSelected) { _, selected in
                if !selected { cancelInteraction() }
            }
            .onChange(of: isMoveGestureActive) { _, active in
                guard !active else { return }
                Task { @MainActor in
                    await Task.yield()
                    if !isMoveGestureActive,
                       isHoldActive || isMoving || moveBaselineTimelineStart != nil {
                        cancelMove()
                    }
                }
            }
            .onDisappear { cancelInteraction() }
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
        LongPressGesture(minimumDuration: 0.28, maximumDistance: 16)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
            .updating($isMoveGestureActive) { _, active, _ in active = true }
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
                default:
                    break
                }
            }
            .onEnded { value in
                if case let .second(true, drag) = value, let drag {
                    let laneStep = laneHeight + 6
                    onMoveToLane(Int((drag.translation.height / laneStep).rounded()))
                }
                let baseline = moveBaselineTimelineStart
                let finalTranslation = moveTranslation
                isMoving = false
                isHoldActive = false
                moveTranslation = .zero
                moveBaselineTimelineStart = nil
                if let baseline {
                    let baselineX = layout.contentX(forTime: baseline)
                    onMove(layout.time(atContentX: max(0, baselineX + finalTranslation.width)))
                    onMoveEnded()
                }
            }
    }

    private func activateHoldMove() {
        guard !isHoldActive else { return }
        isHoldActive = true
        isMoving = true
        onSelect()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func cancelMove() {
        isMoving = false
        isHoldActive = false
        moveTranslation = .zero
        moveBaselineTimelineStart = nil
    }

    private func cancelInteraction() {
        cancelMove()
        if trimBaseline != nil {
            isTrimming = false
            trimBaseline = nil
            onTrimEnded()
        }
    }
}
