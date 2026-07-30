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
    @State private var transitionTarget: EditorTransitionTarget?
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
                        onSelectOpeningTransition: {
                            vm.beginTransitionEditing()
                            transitionTarget = .opening
                        },
                        onSelectClosingTransition: {
                            vm.beginTransitionEditing()
                            transitionTarget = .closing
                        },
                        onSelectTransition: { clipIndex in
                            vm.beginTransitionEditing()
                            transitionTarget = .cut(afterClipAt: clipIndex)
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
                get: { transitionTarget != nil },
                set: { if !$0 { transitionTarget = nil } }
            )
        ) {
            if let transitionTarget {
                EditorTransitionSheet(
                    vm: vm,
                    target: transitionTarget,
                    onCancel: {
                        vm.cancelTransitionEditing()
                        self.transitionTarget = nil
                    },
                    onDone: {
                        vm.commitTransitionEditing()
                        self.transitionTarget = nil
                    }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Color.appColors.backgroundColor)
                .interactiveDismissDisabled()
            }
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
                .presentationDetents([.height(vm.selectedAudioClip == nil ? 180 : 300)])
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

private struct EditorTransitionSheet: View {
    let vm: EditorViewModel
    let target: EditorTransitionTarget
    let onCancel: () -> Void
    let onDone: () -> Void

    @State private var selectedCategory: EditorTransitionCategory = .all
    @State private var selectedKind: EditorTransitionKind
    @State private var duration: TimeInterval
    @State private var applyToAll = false

    init(
        vm: EditorViewModel,
        target: EditorTransitionTarget,
        onCancel: @escaping () -> Void,
        onDone: @escaping () -> Void
    ) {
        self.vm = vm
        self.target = target
        self.onCancel = onCancel
        self.onDone = onDone
        let current = vm.transition(for: target) ?? (.none, 0)
        _selectedKind = State(initialValue: current.kind)
        _duration = State(
            initialValue: current.duration > 0
                ? current.duration
                : min(0.4, vm.maximumTransitionDuration(for: target))
        )
    }

    private var maximumDuration: TimeInterval {
        max(0.1, vm.maximumTransitionDuration(for: target))
    }

    private var visibleTransitions: [EditorTransitionKind] {
        EditorTransitionKind.allCases.filter {
            selectedCategory == .all || $0.category == selectedCategory
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                categoryPicker
                Divider().overlay(Color.white.opacity(0.12))

                if !target.isEndpoint {
                    HStack {
                        Toggle("Apply to all cuts", isOn: $applyToAll)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .tint(Color.appColors.primaryColor)
                            .onChange(of: applyToAll) {
                                previewSelection()
                            }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                }

                ScrollView {
                    LazyVGrid(
                        columns: Array(
                            repeating: GridItem(.flexible(), spacing: 12),
                            count: 3
                        ),
                        spacing: 16
                    ) {
                        ForEach(visibleTransitions) { transition in
                            transitionCard(transition)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }

                if selectedKind != .none {
                    durationControl
                }
            }
            .background(Color.appColors.backgroundColor)
            .navigationTitle(target.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                        .foregroundColor(.white)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        previewSelection()
                        onDone()
                    } label: {
                        Image(systemName: "checkmark")
                            .fontWeight(.bold)
                    }
                    .foregroundColor(Color.appColors.primaryColor)
                    .accessibilityLabel("Apply transition")
                }
            }
        }
    }

    private var categoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 22) {
                ForEach(EditorTransitionCategory.allCases) { category in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedCategory = category
                        }
                    } label: {
                        VStack(spacing: 8) {
                            Text(category.rawValue)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(
                                    selectedCategory == category
                                        ? .white
                                        : Color.white.opacity(0.5)
                                )
                            Capsule()
                                .fill(
                                    selectedCategory == category
                                        ? Color.appColors.primaryColor
                                        : Color.clear
                                )
                                .frame(height: 3)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
        }
        .frame(height: 48)
    }

    private func transitionCard(_ transition: EditorTransitionKind) -> some View {
        let isSelected = selectedKind == transition
        return Button {
            selectedKind = transition
            if transition != .none, duration <= 0 {
                duration = min(0.4, maximumDuration)
            }
            previewSelection()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            VStack(spacing: 7) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(cardGradient(for: transition))
                    Image(systemName: transition.systemImage)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(.white)
                    if transition.usesGPUCompositor {
                        VStack {
                            HStack {
                                Spacer()
                                Text("GPU")
                                    .font(.system(size: 7, weight: .black))
                                    .foregroundColor(.black)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 3)
                                    .background(
                                        Capsule().fill(Color.appColors.primaryColor)
                                    )
                            }
                            Spacer()
                        }
                        .padding(7)
                    }
                }
                .aspectRatio(1.15, contentMode: .fit)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(
                            isSelected ? Color.appColors.primaryColor : Color.white.opacity(0.12),
                            lineWidth: isSelected ? 3 : 1
                        )
                )

                Text(transition.title)
                    .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                    .foregroundColor(isSelected ? Color.appColors.primaryColor : .white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var durationControl: some View {
        VStack(spacing: 8) {
            Divider().overlay(Color.white.opacity(0.12))
            HStack {
                Text("Duration")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                Slider(
                    value: $duration,
                    in: 0.1...maximumDuration,
                    step: 0.05
                ) { Text("Transition duration") } onEditingChanged: { editing in
                    if !editing { previewSelection() }
                }
                .tint(Color.appColors.primaryColor)
                Text(String(format: "%.2fs", duration))
                    .font(.system(size: 12, weight: .bold).monospacedDigit())
                    .foregroundColor(Color.appColors.primaryColor)
                    .frame(width: 48, alignment: .trailing)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 12)
        }
    }

    private func previewSelection() {
        vm.previewTransition(
            kind: selectedKind,
            duration: duration,
            target: target,
            applyToAll: applyToAll
        )
    }

    private func cardGradient(for transition: EditorTransitionKind) -> LinearGradient {
        let colors: [Color]
        if transition == .none {
            colors = [.gray.opacity(0.55), .gray.opacity(0.25)]
        } else if transition == .dipToBlack {
            colors = [.white.opacity(0.35), .black]
        } else if transition == .dipToWhite {
            colors = [.black.opacity(0.7), .white]
        } else {
            switch transition.category {
            case .all, .basic:
                colors = [.gray.opacity(0.8), .black.opacity(0.7)]
            case .camera:
                colors = [.purple.opacity(0.9), .blue.opacity(0.55)]
            case .motion:
                colors = [.blue.opacity(0.85), .cyan.opacity(0.5)]
            case .light:
                colors = [.orange.opacity(0.95), .white.opacity(0.75)]
            case .blur:
                colors = [.indigo.opacity(0.9), .cyan.opacity(0.45)]
            case .glitch:
                colors = [.red.opacity(0.9), .blue.opacity(0.8)]
            case .mask:
                colors = [.mint.opacity(0.85), .black.opacity(0.75)]
            case .artistic:
                colors = [.yellow.opacity(0.85), .pink.opacity(0.7)]
            case .distortion:
                colors = [.pink.opacity(0.85), .purple.opacity(0.65)]
            }
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
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
