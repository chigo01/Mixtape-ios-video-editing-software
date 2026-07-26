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
    @State private var isMediaPickerPresented = false
    @State private var isAudioPickerPresented = false
    @State private var showExportScreen = false
    @State private var insertAfterClipIndex = 0
    @State private var insertAfterAudioIndex: Int?
    @Environment(\.dismiss) private var dismiss

    private let editorChromeMinHeight: CGFloat = 268
    private let previewHorizontalInset: CGFloat = 16

    init(project: EditorProject) {
        _vm = State(initialValue: EditorViewModel(project: project))
    }

    var body: some View {
        AppGlobalBackgroundScaffold {
            GeometryReader { geo in
                VStack(spacing: 0) {
                    EditorTopBar(
                        onBack: { close() },
                        onExport: { showExportScreen = true }
                    )

                    EditorPreviewPlayer(vm: vm) {
                        isFullscreenPreview = true
                    }
                    .frame(maxWidth: geo.size.width - (previewHorizontalInset * 2))
                    .frame(maxHeight: inlinePreviewHeight(in: geo))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 2)

                    if vm.selectedTool == .speed {
                        SpeedToolPanel(vm: vm)
                            .padding(.top, 8)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    if vm.selectedTool == .duration {
                        PhotoDurationToolPanel(vm: vm)
                            .padding(.top, 8)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    EditorTimelineControls(
                        onUndo: { vm.undo() },
                        onRedo: { vm.redo() },
                        canUndo: vm.canUndo,
                        canRedo: vm.canRedo
                    )
                    .padding(.top, 4)

                    EditorTimeline(
                        vm: vm,
                        onInsertAfterClip: { clipIndex in
                            insertAfterClipIndex = clipIndex
                            isMediaPickerPresented = true
                        },
                        onAddAudioClip: { audioIndex in
                            insertAfterAudioIndex = audioIndex
                            isAudioPickerPresented = true
                        }
                    )
                    .frame(maxHeight: .infinity, alignment: .top)

                    Group {
                        if vm.selectedAudioClipID != nil {
                            EditorAudioActionBar(vm: vm)
                        } else if vm.selectedClipID != nil {
                            EditorClipActionBar(vm: vm)
                        } else if vm.selectedTextOverlayID != nil {
                            EditorTextActionBar(vm: vm)
                        } else {
                            EditorBottomToolbar(vm: vm)
                        }
                    }
                    .animation(
                        .easeInOut(duration: 0.2),
                        value: vm.selectedClipID != nil
                            || vm.selectedTextOverlayID != nil
                            || vm.selectedAudioClipID != nil
                    )
                }
            }

        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $showExportScreen) {
            EditorExportScreen(vm: vm)
        }
        .animation(.easeInOut(duration: 0.2), value: vm.selectedTool)
        .fullScreenCover(isPresented: $isFullscreenPreview) {
            EditorFullscreenPreviewSheet(vm: vm, onClose: { isFullscreenPreview = false })
        }
        .fullScreenCover(isPresented: $isMediaPickerPresented) {
            MediaLibraryPickerScreen(
                title: "Add Media",
                confirmButtonTitle: "Add",
                onCancel: { isMediaPickerPresented = false },
                onConfirm: { items in
                    vm.insertClips(from: items, afterIndex: insertAfterClipIndex)
                    isMediaPickerPresented = false
                }
            )
        }
        .sheet(isPresented: $isAudioPickerPresented) {
            AudioPickerView(
                onPick: { url in
                    isAudioPickerPresented = false
                    vm.loadAudioClip(from: url, insertAfterIndex: insertAfterAudioIndex)
                    insertAfterAudioIndex = nil
                },
                onCancel: {
                    isAudioPickerPresented = false
                }
            )
        }
        .sheet(
            isPresented: Binding(
                get: { vm.isTextEditorPresented },
                set: { newValue in
                    if !newValue { vm.dismissTextEditor() }
                }
            )
        ) {
            if let overlay = vm.selectedTextOverlay {
                TextOverlayEditorSheet(vm: vm, overlay: overlay)
                    .presentationBackgroundInteraction(.enabled)
            }
        }
        .sheet(
            isPresented: Binding(
                get: { vm.selectedTool == .volume },
                set: { newValue in
                    if !newValue && vm.selectedTool == .volume {
                        vm.selectedTool = nil
                    }
                }
            )
        ) {
            VolumeToolPanel(vm: vm)
                .presentationDetents([.height(180)])
                .presentationDragIndicator(.visible)
                .presentationBackground(Color.appColors.backgroundColor)
                .presentationBackgroundInteraction(.enabled)
        }
        .task {
            await Task.yield()
            guard !Task.isCancelled else { return }
            await vm.setupPlayer()
        }
        .onDisappear {
            vm.saveNow()
            vm.teardownPlayer()
        }
    }

    private func close() {
        vm.saveNow()
        vm.teardownPlayer()
        dismiss()
    }

    private func inlinePreviewHeight(in geo: GeometryProxy) -> CGFloat {
        let maxByChrome = geo.size.height - editorChromeMinHeight
        let maxByFraction = geo.size.height * 0.54
        return max(220, min(maxByChrome, maxByFraction))
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
                if let posterImage, !showingVideoLayer {
                    Image(uiImage: posterImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if showingVideoLayer, let player = vm.player {
                    PlayerLayerView(player: player, videoGravity: .resizeAspectFill)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .ignoresSafeArea()
                }
            }

            // Text overlays rendered on top of video/poster
            EditorTextOverlayLayerView(vm: vm)

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
                    .allowsHitTesting(false)

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
