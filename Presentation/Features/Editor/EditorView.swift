//  EditorView.swift
//  Mixtape  —  Presentation/Features/Editor

import SwiftUI

struct EditorView: View {
    @StateObject private var viewModel: EditorViewModel
    @State private var showingExport = false

    init(project: VideoProject) {
        _viewModel = StateObject(wrappedValue: EditorViewModel(project: project))
    }

    var body: some View {
        VStack(spacing: 0) {
            VideoPreviewView(
                project: viewModel.project,
                currentTime: viewModel.currentTime,
                isPlaying: viewModel.isPlaying
            )
            .frame(maxHeight: 300)

            PlaybackControlsView(
                isPlaying: $viewModel.isPlaying,
                currentTime: $viewModel.currentTime,
                duration: viewModel.project.timeline.duration
            )

            Divider()

            TimelineView(
                timeline: viewModel.project.timeline,
                currentTime: viewModel.currentTime,
                selectedClipId: viewModel.selectedClipId,
                onSelectClip: { viewModel.selectClip(id: $0) },
                onDeleteClip: { viewModel.removeClip(id: $0) }
            )
            .frame(height: 120)

            if let clip = viewModel.selectedClip {
                ClipToolsView(clip: clip, onUpdateEffect: { _ in })
            }
        }
        .navigationTitle(viewModel.project.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { viewModel.exportProject() } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
    }
}