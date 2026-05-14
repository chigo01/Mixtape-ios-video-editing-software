//
//  MediaPreviewView.swift
//  Mixtape
//
//  Created by Favour Baruch on 08/05/2026.
//

import SwiftUI
import UIKit
import Photos
import AVKit

struct MediaPreviewView: View {
    let item: MediaItem
    let vm: PhotoLibraryViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var player: AVPlayer?
    @State private var imageRequestID: PHImageRequestID?
    @State private var videoRequestID: PHImageRequestID?
    @State private var isLoading: Bool = true

    private var isSelected: Bool { vm.isSelected(item) }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            mediaContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack {
                topBar
                Spacer()
                bottomBar
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .statusBarHidden()
        .onAppear { load() }
        .onDisappear { teardown() }
    }

    @ViewBuilder
    private var mediaContent: some View {
        if item.isVideo {
            if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea(edges: .horizontal)
            } else {
                loadingIndicator
            }
        } else {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                loadingIndicator
            }
        }
    }

    private var loadingIndicator: some View {
        ProgressView()
            .progressViewStyle(.circular)
            .tint(.white)
            .scaleEffect(1.2)
    }

    private var topBar: some View {
        HStack(alignment: .center) {
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.black.opacity(0.45)))
                    .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
            }
            .buttonStyle(.plain)

            Spacer()

            if let date = item.asset.creationDate {
                Text(date, format: .dateTime.month(.abbreviated).day().year())
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color.white.opacity(0.9))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.black.opacity(0.45)))
                    .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
            }

            Spacer()

            Color.clear.frame(width: 36, height: 36)
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 10) {
            if item.isVideo {
                HStack(spacing: 6) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 11, weight: .bold))
                    Text(item.formattedDuration)
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color.black.opacity(0.45)))
                .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
            }

            Spacer(minLength: 0)

            Button(action: toggleSelection) {
                HStack(spacing: 6) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "plus.circle")
                        .font(.system(size: 14, weight: .bold))
                    Text(isSelected ? "Selected" : "Select")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(isSelected ? .black : .white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    Capsule().fill(isSelected ? Color.appColors.primaryColor : Color.white.opacity(0.12))
                )
                .overlay(
                    Capsule().stroke(Color.white.opacity(isSelected ? 0 : 0.25), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func toggleSelection() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.easeInOut(duration: 0.15)) {
            vm.toggleSelection(item)
        }
    }

    // MARK: Loading

    private func load() {
        if item.isVideo {
            loadVideo()
        } else {
            loadImage()
        }
    }

    private func loadImage() {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .none
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false

        imageRequestID = vm.imageManager.requestImage(
            for: item.asset,
            targetSize: PHImageManagerMaximumSize,
            contentMode: .aspectFit,
            options: options
        ) { result, info in
            let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
            guard let result else { return }
            Task { @MainActor in
                self.image = result
                if !isDegraded { self.isLoading = false }
            }
        }
    }

    private func loadVideo() {
        let options = PHVideoRequestOptions()
        options.deliveryMode = .automatic
        options.isNetworkAccessAllowed = true

        videoRequestID = vm.imageManager.requestPlayerItem(
            forVideo: item.asset,
            options: options
        ) { playerItem, _ in
            guard let playerItem else { return }
            Task { @MainActor in
                let p = AVPlayer(playerItem: playerItem)
                self.player = p
                self.isLoading = false
                p.play()
            }
        }
    }

    private func teardown() {
        if let id = imageRequestID {
            vm.imageManager.cancelImageRequest(id)
            imageRequestID = nil
        }
        if let id = videoRequestID {
            vm.imageManager.cancelImageRequest(id)
            videoRequestID = nil
        }
        player?.pause()
        player = nil
    }
}
