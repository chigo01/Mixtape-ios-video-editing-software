//
//  MediaGridItemView.swift
//  Mixtape
//
//  Created by Favour Baruch on 08/05/2026.
//

import SwiftUI
import Photos

struct MediaGridItemView: View {
    let item: MediaItem
    let isSelected: Bool
    let imageManager: PHCachingImageManager

    var body: some View {
        GeometryReader { proxy in
            let side = proxy.size.width
            ZStack(alignment: .topTrailing) {
                MediaThumbnailView(
                    item: item,
                    imageManager: imageManager,
                    targetSize: CGSize(width: side, height: side)
                )
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(
                            isSelected ? Color.appColors.primaryColor : Color.clear,
                            lineWidth: 2
                        )
                )

                if item.isVideo {
                    HStack(spacing: 0) {
                        Spacer()
                        VStack(spacing: 0) {
                            Spacer()
                            Text(item.formattedDuration)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule().fill(Color.black.opacity(0.55))
                                )
                                .padding(6)
                        }
                    }
                    .frame(width: side, height: side, alignment: .bottomLeading)
                }

                SelectionBadge(isSelected: isSelected)
                    .padding(6)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

struct SelectionBadge: View {
    let isSelected: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(isSelected ? Color.appColors.primaryColor : Color.black.opacity(0.35))
            Circle()
                .stroke(Color.white.opacity(isSelected ? 0 : 0.85), lineWidth: 1.4)
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
            }
        }
        .frame(width: 22, height: 22)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}
