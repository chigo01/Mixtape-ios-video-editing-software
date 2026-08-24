//
//  ClipFilmstripView.swift
//  Mixtape
//

import SwiftUI

/// Tiled frames across a clip cell — multiple `AVAssetImageGenerator` samples.
struct ClipFilmstripView: View {
    let clip: EditorClip
    let width: CGFloat
    let height: CGFloat

    @State private var frames: [UIImage] = []

    var body: some View {
        Group {
            if frames.isEmpty {
                Color.white.opacity(0.06)
            } else {
                HStack(spacing: 0) {
                    ForEach(Array(frames.enumerated()), id: \.offset) { _, image in
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: tileWidth, height: height)
                            .clipped()
                    }
                }
            }
        }
        .frame(width: width, height: height)
        .task(id: taskKey) {
            frames = await ClipThumbnailService.shared.filmstrip(
                for: clip,
                width: width,
                height: height
            )
        }
    }

    private var tileWidth: CGFloat {
        guard !frames.isEmpty else { return width }
        return max(1, width / CGFloat(frames.count))
    }

    private var taskKey: String {
        "\(clip.id)|\(clip.trimStart)|\(clip.trimEnd)|\(clip.speed)|\(clip.playback)|\(Int(width))"
    }
}
