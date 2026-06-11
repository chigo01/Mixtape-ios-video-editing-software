//
//  ProjectCardView.swift
//  Mixtape
//
//  Created by Favour Baruch on 07/05/2026.
//

import SwiftUI
import Photos

struct ProjectCardView: View {
    let project: EditorProject

    @State private var coverImage: UIImage?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            thumbnail

            durationBadge
                .padding(12)

            bottomInfo
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        // Clipped/scaled images don't register taps across the full card without an
        // explicit content shape — required so the whole card is tappable.
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .task(id: project.id) { loadCover() }
    }

    private var thumbnail: some View {
        Group {
            if let coverImage {
                Image(uiImage: coverImage)
                    .resizable()
                    .scaledToFill()
            } else {
                Image("DemoPhoto")
                    .resizable()
                    .scaledToFill()
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 180)
        .clipped()
    }

    private var durationBadge: some View {
        Text(project.formattedDuration)
            .font(.system(size: 12, weight: .semibold).monospacedDigit())
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.black.opacity(0.72)))
            .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1))
    }

    private var bottomInfo: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(project.title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(2)
                .shadow(color: .black.opacity(0.8), radius: 4, y: 1)

            Text("\(project.clips.count) clips · \(relativeDate(project.modifiedAt))")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.88))
                .shadow(color: .black.opacity(0.8), radius: 4, y: 1)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func loadCover() {
        guard let first = project.clips.first else { return }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [first.assetLocalIdentifier], options: nil)
        guard let asset = assets.firstObject else { return }

        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true

        PHImageManager.default().requestImage(
            for: asset,
            targetSize: CGSize(width: 400, height: 400),
            contentMode: .aspectFill,
            options: options
        ) { result, _ in
            guard let result else { return }
            Task { @MainActor in coverImage = result }
        }
    }
}
