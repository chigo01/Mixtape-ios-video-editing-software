//
//  CreateProjectScreen.swift
//  Mixtape
//
//  Created by Favour Baruch on 08/05/2026.
//

import SwiftUI
import UIKit
import Photos

struct CreateProjectScreen: View {
    @State private var vm = PhotoLibraryViewModel()
    @State private var previewItem: MediaItem?
    @State private var goToEditor: Bool = false
    @Environment(\.dismiss) private var dismiss

    private let columns: [GridItem] = Array(
        repeating: GridItem(.flexible(), spacing: 6),
        count: 3
    )

    var body: some View {
        AppGlobalBackgroundScaffold {
            VStack(spacing: 0) {
                headerBar
                searchBar
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                    .padding(.bottom, 10)
                filterChips
                    .padding(.bottom, 10)

                content
            }
            .safeAreaInset(edge: .bottom) {
                if !vm.selectedIDs.isEmpty {
                    SelectionBottomBar(vm: vm) {
                        goToEditor = true
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
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
        .navigationDestination(isPresented: $goToEditor) {
            EditorScreen(media: vm.selectedItems)
        }
    }

    // MARK: Actions

    private func closeAndReset() {
        withAnimation(.easeInOut(duration: 0.2)) {
            vm.clearSelection()
        }
        dismiss()
    }

    // MARK: Sub-views

    private var headerBar: some View {
        HStack {
            Button(action: closeAndReset) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.white.opacity(0.06)))
            }
            .buttonStyle(.plain)

            Spacer()

            Text("New Project")
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
    private var content: some View {
        switch vm.authorizationStatus {
        case .denied, .restricted:
            permissionDeniedView
        case .notDetermined:
            ProgressView()
                .tint(Color.appColors.primaryColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .authorized, .limited:
            grid
        @unknown default:
            grid
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
            Text("Grant access to your library to start a project.")
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

    private var grid: some View {
        let visible = vm.filteredItems
        return ScrollView {
            if visible.isEmpty && !vm.isLoading {
                emptyState
                    .padding(.top, 60)
            } else {
                LazyVGrid(columns: columns, spacing: 6) {
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
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(.isButton)
                        .accessibilityLabel(
                            item.isVideo
                            ? "Video, \(item.formattedDuration)"
                            : "Photo"
                        )
                        .accessibilityHint(
                            vm.isSelected(item)
                            ? "Tap to deselect. Long press to preview."
                            : "Tap to select. Long press to preview."
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        .scrollIndicators(.hidden)
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

#Preview {
    NavigationStack {
        CreateProjectScreen()
    }
}
