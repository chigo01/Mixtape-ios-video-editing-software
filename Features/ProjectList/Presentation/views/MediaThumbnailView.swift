//
//  MediaThumbnailView.swift
//  Mixtape
//
//  Created by Favour Baruch on 08/05/2026.
//

import SwiftUI
import UIKit
import Photos

struct MediaThumbnailView: View {
    let item: MediaItem
    let imageManager: PHCachingImageManager
    let targetSize: CGSize

    @State private var image: UIImage?
    @State private var requestID: PHImageRequestID?

    var body: some View {
        ZStack {
            Color.white.opacity(0.04)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(Color.white.opacity(0.5))
            }
        }
        .clipped()
        .onAppear { loadImage() }
        .onDisappear { cancelLoad() }
    }

    private func loadImage() {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        let scale = UIScreen.main.scale
        let pixelSize = CGSize(width: targetSize.width * scale, height: targetSize.height * scale)
        requestID = imageManager.requestImage(
            for: item.asset,
            targetSize: pixelSize,
            contentMode: .aspectFill,
            options: options
        ) { result, _ in
            if let result {
                Task { @MainActor in
                    self.image = result
                }
            }
        }
    }

    private func cancelLoad() {
        if let id = requestID {
            imageManager.cancelImageRequest(id)
            requestID = nil
        }
    }
}
