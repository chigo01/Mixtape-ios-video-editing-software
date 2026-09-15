//
//  TimelinePlaybackControls.swift
//  Mixtape
//

import SwiftUI
import UIKit
import Photos
import AVFoundation

/// Keep playback scrolling isolated from the expensive clip and waveform view builders.
struct PlaybackFollowingTimelineScrollView<Content: View>: View {
    let vm: EditorViewModel
    let layout: TimelineLayout
    let viewportWidth: CGFloat
    let isEditing: Bool
    let content: Content

    @State private var position = ScrollPosition(edge: .leading)
    @State private var isUserScrolling = false

    init(
        vm: EditorViewModel,
        layout: TimelineLayout,
        viewportWidth: CGFloat,
        isEditing: Bool,
        @ViewBuilder content: () -> Content
    ) {
        self.vm = vm
        self.layout = layout
        self.viewportWidth = viewportWidth
        self.isEditing = isEditing
        self.content = content()
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            content
        }
        .scrollPosition($position)
        .onScrollPhaseChange { _, phase in
            isUserScrolling = phase == .tracking || phase == .interacting || phase == .decelerating
            if phase == .idle { followPlayhead() }
        }
        .onChange(of: vm.timelinePosition) { _, _ in followPlayhead() }
        .onChange(of: vm.isPlaying) { _, playing in
            if playing { followPlayhead() }
        }
        .onChange(of: isEditing) { _, editing in
            if !editing { followPlayhead() }
        }
        .onChange(of: viewportWidth) { _, _ in followPlayhead() }
        .onChange(of: layout.contentWidth) { _, _ in followPlayhead() }
        .onAppear { followPlayhead() }
    }

    private func followPlayhead() {
        guard vm.isPlaying, !isEditing, !isUserScrolling else { return }
        // Match the timeline's 16pt content padding. Clamp at either end while
        // keeping the moving playhead centered throughout the scrollable range.
        let maximumOffset = max(0, layout.contentWidth + 32 - viewportWidth)
        let target = min(maximumOffset, max(0,
            layout.contentX(forTime: vm.timelinePosition) + 16 - viewportWidth / 2
        ))
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            position.scrollTo(x: target)
        }
    }
}

// MARK: - Playhead (isolated — only these views observe `timelinePosition` during playback)

struct TimelinePlayheadLine: View {
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

struct TimelinePlayheadKnob: View {
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

