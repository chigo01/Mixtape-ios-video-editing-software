//
//  SelectionBottomBar.swift
//  Mixtape
//
//  Created by Favour Baruch on 08/05/2026.
//

import SwiftUI

struct SelectionBottomBar: View {
    let vm: PhotoLibraryViewModel
    var confirmTitle: String = "Next"
    var isLoading: Bool = false
    var onNext: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            avatarStack

            VStack(alignment: .leading, spacing: 2) {
                Text("\(vm.selectedIDs.count) Items Selected")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                Text("\(vm.totalSelectedDurationString) TOTAL DURATION")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.55))
                    .tracking(0.5)
            }

            Spacer(minLength: 8)

            Button(action: onNext) {
                HStack(spacing: 8) {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.black)
                            .scaleEffect(0.85)
                    }
                    Text(isLoading ? "Preparing…" : confirmTitle)
                        .font(.system(size: 14, weight: .semibold))
                    if !isLoading {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .bold))
                    }
                }
                .foregroundColor(.black)
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
                .background(Capsule().fill(Color.appColors.primaryColor))
            }
            .buttonStyle(.plain)
            .disabled(isLoading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private var avatarStack: some View {
        let visible = Array(vm.selectedItems.prefix(2))
        let extra = max(0, vm.selectedIDs.count - visible.count)

        return HStack(spacing: -10) {
            ForEach(Array(visible.enumerated()), id: \.element.id) { _, item in
                MediaThumbnailView(
                    item: item,
                    imageManager: vm.imageManager,
                    targetSize: CGSize(width: 32, height: 32)
                )
                .frame(width: 32, height: 32)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.black, lineWidth: 2))
            }
            if extra > 0 {
                Text("+\(extra)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle().fill(Color.appColors.primaryColor.opacity(0.85))
                    )
                    .overlay(Circle().stroke(Color.black, lineWidth: 2))
            }
        }
    }
}
