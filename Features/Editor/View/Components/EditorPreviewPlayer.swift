//
//  EditorPreviewPlayer.swift
//  Mixtape
//
//  Created by Favour Baruch on 14/05/2026.
//

import SwiftUI
import AVFoundation
import UIKit
import Photos

struct EditorPreviewPlayer: View {
    let vm: EditorViewModel
    /// When true, the preview stretches to fill a non–9:16 parent frame (fullscreen sheet only).
    var fillsBounds: Bool = false
    var onFullscreen: () -> Void = {}

    @State private var posterImage: UIImage?

    private var previewClip: EditorClip? {
        vm.playbackInfo?.clip ?? vm.selectedClip
    }

    private var showingVideoLayer: Bool {
        guard let clip = previewClip, clip.isVideo else { return false }
        return vm.player != nil
    }

    var body: some View {
        Group {
            if fillsBounds {
                previewSurface
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            } else {
                previewSurface
                    .frame(maxWidth: .infinity)
                    .aspectRatio(EditorPreviewLayout.aspectWidthOverHeight, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
        .task { loadPoster() }
        .onChange(of: vm.playbackClipID) { _, _ in loadPoster() }
        .onChange(of: vm.selectedClipID) { _, _ in
            if vm.playbackInfo == nil { loadPoster() }
        }
    }

    private var previewSurface: some View {
        ZStack {
            background

            if let posterImage, !showingVideoLayer {
                Image(uiImage: posterImage)
                    .resizable()
                    .modifier(PreviewMediaScaling(fillsBounds: fillsBounds))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if showingVideoLayer, let player = vm.player {
                PlayerLayerView(
                    player: player,
                    videoGravity: fillsBounds ? .resizeAspectFill : .resizeAspect
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Text overlays rendered on top of video/poster
            textOverlayLayer

            if shouldShowLoading {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
            }

            VStack {
                Spacer(minLength: 0)
                    .allowsHitTesting(false)
                controlsHUD
            }
        }
    }

    private var textOverlayLayer: some View {
        EditorTextOverlayLayerView(vm: vm)
    }

    private var shouldShowLoading: Bool {
        guard let clip = previewClip else { return false }
        if clip.isVideo { return vm.player == nil && posterImage == nil }
        return posterImage == nil
    }

    private var background: some View {
        Color.black
    }

    private var controlsHUD: some View {
        HStack(spacing: 14) {
            Text(vm.currentTimeString)
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundColor(.white)

            Button(action: { vm.togglePlay() }) {
                Image(systemName: vm.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundColor(.white)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .disabled(vm.totalDuration <= 0)
            .accessibilityLabel(vm.isPlaying ? "Pause" : "Play")

            Button(action: onFullscreen) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Fullscreen")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
        .background(Capsule().fill(Color.black.opacity(0.55)))
        .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
        .padding(.bottom, 14)
    }

    private func loadPoster() {
        posterImage = nil
        guard let clip = previewClip else { return }
        let manager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true
        let target = CGSize(width: 1200, height: 1200)
        manager.requestImage(
            for: clip.asset,
            targetSize: target,
            contentMode: .aspectFit,
            options: options
        ) { image, _ in
            guard let image else { return }
            Task { @MainActor in self.posterImage = image }
        }
    }
}

private struct PreviewMediaScaling: ViewModifier {
    let fillsBounds: Bool

    func body(content: Content) -> some View {
        if fillsBounds {
            content.scaledToFill()
        } else {
            content.scaledToFit()
        }
    }
}

// MARK: - AVPlayerLayer wrapper

struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer
    var videoGravity: AVLayerVideoGravity = .resizeAspect

    func makeUIView(context: Context) -> PlayerHostView {
        let v = PlayerHostView()
        v.playerLayer.player = player
        v.playerLayer.videoGravity = videoGravity
        v.backgroundColor = .black
        return v
    }

    func updateUIView(_ uiView: PlayerHostView, context: Context) {
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
        }
        uiView.playerLayer.videoGravity = videoGravity
        uiView.setNeedsLayout()
    }
}

final class PlayerHostView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
    }
}
