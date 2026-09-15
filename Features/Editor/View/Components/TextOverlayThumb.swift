//
//  TextOverlayThumb.swift
//  Mixtape
//

import SwiftUI
import UIKit
import Photos
import AVFoundation

// MARK: - Text overlay thumb

struct TextOverlayThumb: View {
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
    @State private var moveTranslationX: CGFloat = 0
    @State private var isHoldActive = false
    @GestureState private var isMoveGestureActive = false

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
        overlay.isCaption
            ? max(2, endX - displayStartX)
            : max(layout.minimumItemWidth, endX - displayStartX)
    }

    var body: some View {
        barContent
            .contentShape(Rectangle())
            .onTapGesture {
                guard !isTrimming, !isMoving else { return }
                onSelect()
            }
            // Keep body movement below the UIKit handles so it cannot steal a trim.
            .gesture(moveGesture, including: isSelected && allowsEditing ? .all : .none)
            .overlay {
                if isSelected && allowsEditing {
                    ClipTrimHandleRepresentable(
                        clipID: overlay.id,
                        trimStart: overlay.startTime,
                        trimEnd: overlay.endTime,
                        originalDuration: max(layout.timelineExtent, 1),
                        allowsDurationExtension: true,
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
            .scaleEffect(isHoldActive ? 1.04 : 1)
            .shadow(color: .black.opacity(isHoldActive ? 0.5 : 0), radius: 7, y: 3)
            // Keep the model stable while the finger moves. Updating startTime on
            // every frame rebuilds the lane layout and makes the bar stutter.
            .offset(x: displayStartX + moveTranslationX, y: 0)

        .onChange(of: isSelected) { _, selected in
            if !selected { finishInteraction() }
        }
        .onChange(of: isMoveGestureActive) { _, active in
            guard !active else { return }
            // GestureState resets beside onEnded. Defer cancellation cleanup so
            // a normal release can commit its final position first.
            Task { @MainActor in
                await Task.yield()
                if !isMoveGestureActive { finishMoveInteraction() }
            }
        }
        .onDisappear { finishInteraction() }
    }

    private func finishMoveInteraction() {
        if isHoldActive || moveBaselineStart != nil {
            isMoving = false
            isHoldActive = false
            moveTranslationX = 0
            moveBaselineStart = nil
        }
    }

    private func finishInteraction() {
        finishMoveInteraction()
        if trimBaseline != nil {
            isTrimming = false
            trimBaseline = nil
            onTrimEnded()
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
                    if moveBaselineStart == nil {
                        moveBaselineStart = overlay.startTime
                    }
                    let baseX = layout.contentX(forTime: moveBaselineStart ?? overlay.startTime)
                    moveTranslationX = max(-baseX, drag.translation.width)
                default:
                    break
                }
            }
            .onEnded { _ in
                let baseline = moveBaselineStart
                let finalTranslation = moveTranslationX
                isMoving = false
                isHoldActive = false
                moveTranslationX = 0
                moveBaselineStart = nil
                if let baseline {
                    let baseX = layout.contentX(forTime: baseline)
                    onMove(layout.time(atContentX: max(0, baseX + finalTranslation)))
                    onMoveEnded()
                }
            }
    }

    private func activateHoldMove() {
        guard !isHoldActive else { return }
        isHoldActive = true
        isMoving = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func truncated(_ s: String) -> String {
        s.count > 8 ? String(s.prefix(7)) + "…" : s
    }
}
