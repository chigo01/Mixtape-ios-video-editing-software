//  TimelineView.swift
//  Mixtape  —  Presentation/Features/Editor/Components

import SwiftUI

struct TimelineView: View {
    let timeline: Timeline
    let currentTime: TimeInterval
    let selectedClipId: UUID?
    let onSelectClip: (UUID) -> Void
    let onDeleteClip: (UUID) -> Void

    private let pixelsPerSecond: CGFloat = 60

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            ZStack(alignment: .topLeading) {
                VStack(spacing: 2) {
                    ForEach(timeline.videoTracks) { track in
                        VideoTrackRowView(
                            track: track,
                            pixelsPerSecond: pixelsPerSecond,
                            selectedClipId: selectedClipId,
                            onSelectClip: onSelectClip,
                            onDeleteClip: onDeleteClip
                        )
                    }
                }
                // Playhead
                Rectangle()
                    .fill(.red)
                    .frame(width: 2)
                    .offset(x: CGFloat(currentTime) * pixelsPerSecond)
            }
            .padding(.horizontal)
        }
        .background(Color(uiColor: .systemGray6))
    }
}