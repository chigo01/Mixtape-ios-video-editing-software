//
//  EditorScreen.swift
//  Mixtape
//
//  Created by Favour Baruch on 14/05/2026.
//

import AVFoundation
import Photos
import SwiftUI

struct EditorScreen: View {
    @State private var vm: EditorViewModel
    @State private var isFullscreenPreview = false
    @Environment(\.dismiss) private var dismiss

    /// Fraction of available screen height for the preview stage (~CapCut balance: preview ≈ lower editor stack).
    private let previewMaxHeightFraction: CGFloat = 0.45

    init(media: [MediaItem]) {
        _vm = State(initialValue: EditorViewModel(media: media))
    }

    var body: some View {
        AppGlobalBackgroundScaffold {
            GeometryReader { geo in
                VStack(spacing: 0) {
                    EditorTopBar(onBack: { close() })

                    EditorPreviewPlayer(vm: vm) {
                        isFullscreenPreview = true
                    }
                    .frame(maxWidth: .infinity, maxHeight: geo.size.height * previewMaxHeightFraction)
                    .padding(.horizontal, 4)
                    .padding(.top, 2)

                    EditorTimeline(vm: vm)
                        .padding(.top, 8)
                        .frame(maxHeight: .infinity, alignment: .top)

                    EditorBottomToolbar(vm: vm)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(isPresented: $isFullscreenPreview) {
            EditorFullscreenPreviewSheet(vm: vm, onClose: { isFullscreenPreview = false })
        }
        .task {
            await vm.setupPlayer()
        }
        .onDisappear {
            vm.teardownPlayer()
        }
    }

    private func close() {
        vm.teardownPlayer()
        dismiss()
    }
}

// MARK: - Fullscreen preview

private struct EditorFullscreenPreviewSheet: View {
    @Bindable var vm: EditorViewModel
    let onClose: () -> Void

    @State private var posterImage: UIImage?

    private var previewClip: EditorClip? {
        vm.playbackInfo?.clip ?? vm.selectedClip
    }

    private var showingVideoLayer: Bool {
        guard let clip = previewClip, clip.isVideo else { return false }
        return vm.player != nil
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            Group {
                if let posterImage {
                    Image(uiImage: posterImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if showingVideoLayer, let player = vm.player {
                    PlayerLayerView(player: player, videoGravity: .resizeAspectFill)
                        .ignoresSafeArea()
                }
            }

            VStack(spacing: 0) {
                HStack {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(Color.white.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 8)
                    .padding(.top, 8)
                    Spacer(minLength: 0)
                }
                Spacer(minLength: 0)
                fullscreenHUD
                    .padding(.bottom, 28)
            }
        }
        .onAppear { loadPoster() }
        .onChange(of: vm.playbackClipID) { _, _ in loadPoster() }
        .onChange(of: vm.selectedClipID) { _, _ in
            if vm.playbackInfo == nil { loadPoster() }
        }
    }

    private var fullscreenHUD: some View {
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
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 10)
        .background(Capsule().fill(Color.black.opacity(0.55)))
        .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
    }

    private func loadPoster() {
        posterImage = nil
        guard let clip = previewClip else { return }
        let manager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true
        let target = CGSize(width: 1600, height: 1600)
        manager.requestImage(
            for: clip.asset,
            targetSize: target,
            contentMode: .aspectFit,
            options: options
        ) { image, _ in
            guard let image else { return }
            Task { @MainActor in posterImage = image }
        }
    }
}
