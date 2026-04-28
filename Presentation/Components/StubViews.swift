//  StubViews.swift
//  Mixtape  —  Presentation/Components
//  Placeholder views — replace with real implementations

import SwiftUI
import AVFoundation

struct VideoPreviewView: UIViewRepresentable {
    let project: VideoProject
    let currentTime: TimeInterval
    let isPlaying: Bool

    func makeUIView(context: Context) -> PlayerUIView {
        PlayerUIView(frame: .zero)
    }

    func updateUIView(_ uiView: PlayerUIView, context: Context) {
        uiView.update(with: project, currentTime: currentTime, isPlaying: isPlaying)
    }
}

class PlayerUIView: UIView {
    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }

    override static var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        playerLayer.videoGravity = .resizeAspect
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(with project: VideoProject, currentTime: TimeInterval, isPlaying: Bool) {
        if player == nil {
            if let firstClip = project.timeline.videoTracks.first?.clips.first {
                player = AVPlayer(url: firstClip.assetURL)
                playerLayer.player = player
            }
        }

        if isPlaying {
            player?.play()
        } else {
            player?.pause()
            let targetTime = CMTime(seconds: currentTime, preferredTimescale: 600)
            player?.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero)
        }
    }
}

struct PlaybackControlsView: View {
    @Binding var isPlaying: Bool
    @Binding var currentTime: TimeInterval
    let duration: TimeInterval

    var body: some View {
        HStack(spacing: 24) {
            Button { currentTime = max(0, currentTime - 5) } label: {
                Image(systemName: "gobackward.5")
            }
            Button { isPlaying.toggle() } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.title2)
            }
            Button { currentTime = min(duration, currentTime + 5) } label: {
                Image(systemName: "goforward.5")
            }
        }
        .padding()
    }
}

struct VideoTrackRowView: View {
    let track: VideoTrack
    let pixelsPerSecond: CGFloat
    let selectedClipId: UUID?
    let onSelectClip: (UUID) -> Void
    let onDeleteClip: (UUID) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(track.clips) { clip in
                RoundedRectangle(cornerRadius: 4)
                    .fill(selectedClipId == clip.id ? Color.blue : Color.gray)
                    .frame(width: CGFloat(clip.duration) * pixelsPerSecond, height: 60)
                    .onTapGesture { onSelectClip(clip.id) }
                    .contextMenu {
                        Button(role: .destructive) {
                            onDeleteClip(clip.id)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
        }
    }
}

struct ClipToolsView: View {
    let clip: VideoClip
    let onUpdateEffect: (Effect) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(EffectType.allCases, id: \.self) { effectType in
                    Button(effectType.rawValue.capitalized) {
                        onUpdateEffect(Effect(type: effectType, intensity: 0.5))
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
        }
    }
}

struct NewProjectView: View {
    @Environment(\.dismiss) var dismiss
    @State private var name: String = ""
    @State private var aspectRatio: AspectRatio = .widescreen
    
    private let saveUseCase: SaveProjectUseCaseProtocol = DIContainer.shared.saveProjectUseCase

    var body: some View {
        NavigationStack {
            Form {
                Section("Project Name") {
                    TextField("My Video", text: $name)
                }
                Section("Aspect Ratio") {
                    Picker("Ratio", selection: $aspectRatio) {
                        ForEach(AspectRatio.allCases, id: \.self) {
                            Text($0.rawValue).tag($0)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("New Project")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let newProject = VideoProject(name: name, aspectRatio: aspectRatio)
                        _ = saveUseCase.execute(input: newProject)
                        dismiss()
                    }
                    .disabled(name.isEmpty)
                }
            }
            .preferredColorScheme(.dark)
            .tint(.orange)
        }
    }
}

struct ProjectThumbnailView: View {
    let project: VideoProject
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .aspectRatio(16/9, contentMode: .fit)
                .cornerRadius(8)
                .overlay(
                    Image(systemName: "film")
                        .foregroundStyle(.secondary)
                )
            Text(project.name)
                .font(.caption.bold())
                .lineLimit(1)
            Text(project.aspectRatio.rawValue)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
