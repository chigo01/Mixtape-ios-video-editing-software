//
//  MediaLibraryPickerScreen.swift
//  Mixtape
//

import SwiftUI
import UIKit
import Photos

/// Photo-library grid with multi-select; used for new projects and adding clips in the editor.
struct MediaLibraryPickerScreen: View {
    let title: String
    let confirmButtonTitle: String
    var isConfirmLoading: Bool = false
    var allowedMediaType: PHAssetMediaType?
    var onCancel: () -> Void
    var onConfirm: ([MediaItem]) -> Void

    @State private var vm = PhotoLibraryViewModel()
    @State private var previewItem: MediaItem?

    var body: some View {
        AppGlobalBackgroundScaffold {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    headerBar
                    searchBar
                        .padding(.horizontal, horizontalPadding(for: geometry.size.width))
                        .padding(.top, 6)
                        .padding(.bottom, 10)
                    filterChips
                        .padding(.bottom, 10)

                    content(availableWidth: geometry.size.width)
                }
                .frame(maxWidth: 1280)
                .frame(maxWidth: .infinity)
                .safeAreaInset(edge: .bottom) {
                    if !vm.selectedIDs.isEmpty {
                        SelectionBottomBar(
                            vm: vm,
                            confirmTitle: confirmButtonTitle,
                            isLoading: isConfirmLoading,
                            onNext: confirmSelection
                        )
                        .frame(maxWidth: 920)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: vm.selectedIDs.count)
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { vm.requestAccessAndLoad() }
        .fullScreenCover(item: $previewItem) { item in
            MediaPreviewView(item: item, vm: vm)
        }
    }

    private func confirmSelection() {
        let picked = vm.selectedItems.filter(isAllowed)
        guard !picked.isEmpty, !isConfirmLoading else { return }
        onConfirm(picked)
    }

    private var headerBar: some View {
        HStack {
            Button(action: cancelAndReset) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.white.opacity(0.06)))
            }
            .buttonStyle(.plain)

            Spacer()

            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)

            Spacer()

            if vm.authorizationStatus == .limited {
                Button(action: { vm.openLimitedPicker() }) {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.white.opacity(0.06)))
                }
                .buttonStyle(.plain)
            } else {
                Color.clear.frame(width: 36, height: 36)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    private func cancelAndReset() {
        withAnimation(.easeInOut(duration: 0.2)) {
            vm.clearSelection()
        }
        onCancel()
    }

    private var searchBar: some View {
        @Bindable var vm = vm
        return HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Color.white.opacity(0.5))
            TextField("", text: $vm.searchText, prompt:
                Text("Search your library")
                    .foregroundColor(Color.white.opacity(0.45))
            )
            .font(.system(size: 14))
            .foregroundColor(.white)
            .textFieldStyle(.plain)
            .submitLabel(.search)
            if !vm.searchText.isEmpty {
                Button(action: { vm.searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(Color.white.opacity(0.4))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(MediaFilter.allCases) { filter in
                    FilterChip(
                        title: filter.rawValue,
                        isSelected: vm.filter == filter
                    ) {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            vm.filter = filter
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    @ViewBuilder
    private func content(availableWidth: CGFloat) -> some View {
        switch vm.authorizationStatus {
        case .denied, .restricted:
            permissionDeniedView
        case .notDetermined:
            ProgressView()
                .tint(Color.appColors.primaryColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .authorized, .limited:
            grid(availableWidth: availableWidth)
        @unknown default:
            grid(availableWidth: availableWidth)
        }
    }

    private var permissionDeniedView: some View {
        VStack(spacing: 14) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 42, weight: .light))
                .foregroundColor(Color.white.opacity(0.6))
            Text("Photo access needed")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
            Text("Grant access to your library to add media.")
                .font(.system(size: 13))
                .foregroundColor(Color.white.opacity(0.55))
                .multilineTextAlignment(.center)
            Button(action: { vm.openSettings() }) {
                Text("Open Settings")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.appColors.primaryColor))
            }
            .buttonStyle(.plain)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func grid(availableWidth: CGFloat) -> some View {
        let visible = vm.filteredItems.filter(isAllowed)
        let spacing: CGFloat = availableWidth >= 700 ? 10 : 6
        let minimumTileWidth: CGFloat = availableWidth >= 700 ? 142 : 108
        let columns = [GridItem(.adaptive(minimum: minimumTileWidth), spacing: spacing)]
        return ScrollView {
            if visible.isEmpty && !vm.isLoading {
                emptyState
                    .padding(.top, 60)
            } else {
                LazyVGrid(columns: columns, spacing: spacing) {
                    ForEach(visible) { item in
                        MediaGridItemView(
                            item: item,
                            isSelected: vm.isSelected(item),
                            imageManager: vm.imageManager
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                vm.toggleSelection(item)
                            }
                        }
                        .onLongPressGesture(minimumDuration: 0.35) {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            previewItem = item
                        }
                    }
                }
                .padding(.horizontal, horizontalPadding(for: availableWidth))
                .padding(.bottom, 24)
            }
        }
        .scrollIndicators(.hidden)
    }

    private func horizontalPadding(for availableWidth: CGFloat) -> CGFloat {
        availableWidth >= 700 ? 24 : 16
    }

    private func isAllowed(_ item: MediaItem) -> Bool {
        guard let allowedMediaType else { return true }
        return item.asset.mediaType == allowedMediaType
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 32, weight: .light))
                .foregroundColor(Color.white.opacity(0.4))
            Text("Nothing here yet")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
            Text("Try a different filter or clear your search.")
                .font(.system(size: 12))
                .foregroundColor(Color.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
    }
}
