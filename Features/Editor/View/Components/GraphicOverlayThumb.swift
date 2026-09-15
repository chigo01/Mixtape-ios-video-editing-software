//
//  GraphicOverlayThumb.swift
//  Mixtape
//

import SwiftUI
import UIKit
import Photos
import AVFoundation

struct GraphicOverlayThumb: View {
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
    @State private var isHoldActive = false

    private var startX: CGFloat {
        if let trimBaseline {
            return trimBaseline.x + layout.contentX(forTime: graphic.startTime)
                - layout.contentX(forTime: trimBaseline.time)
        }
        return layout.contentX(forTime: graphic.startTime)
    }
    private var width: CGFloat {
        max(layout.minimumItemWidth, layout.contentX(forTime: graphic.endTime) - startX)
    }

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
        .scaleEffect(isHoldActive ? 1.04 : 1)
        .shadow(color: .black.opacity(isHoldActive ? 0.5 : 0), radius: 7, y: 3)
        .gesture(moveGesture)
        .offset(x: startX)
    }

    private var moveGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.28, maximumDistance: 16)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                guard !isTrimming else { return }
                switch value {
                case .first(true):
                    activateHoldMove()
                case let .second(true, drag):
                    guard let drag else { return }
                    activateHoldMove()
                    if moveBaseline == nil { moveBaseline = graphic.startTime }
                    let baseX = layout.contentX(forTime: moveBaseline ?? graphic.startTime)
                    onMove(layout.time(atContentX: max(0, baseX + drag.translation.width)))
                default:
                    break
                }
            }
            .onEnded { _ in
                let didMove = moveBaseline != nil
                isMoving = false
                isHoldActive = false
                moveBaseline = nil
                if didMove { onEditEnded() }
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

