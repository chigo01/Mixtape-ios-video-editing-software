//
//  EditorScreen.swift
//  Mixtape
//
//  Created by Favour Baruch on 14/05/2026.
//

import AVFoundation
import Photos
import SwiftUI
import UIKit

struct EditorScreen: View {
    @State private var vm: EditorViewModel
    @State private var isFullscreenPreview = false
    @State private var isMediaPickerPresented = false
    @State private var isAudioPickerPresented = false
    @State private var isAudioSourceChooserPresented = false
    @State private var isAudioLibraryPickerPresented = false
    @State private var isVoiceoverRecorderPresented = false
    @State private var isOverlayPickerPresented = false
    @State private var isOverlayTracksExpanded = false
    @State private var showExportScreen = false
    @State private var insertAfterClipIndex = 0
    @State private var insertAfterAudioClipID: UUID?
    @State private var isReplacingClip = false
    @State private var isReplacingOverlayClip = false
    @State private var transitionTarget: EditorTransitionTarget?
    @State private var isSequenceManagerPresented = false
    @Environment(\.dismiss) private var dismiss

    private let editorChromeMinHeight: CGFloat = 248
    private let previewHorizontalInset: CGFloat = 16

    init(project: EditorProject) {
        _vm = State(initialValue: EditorViewModel(project: project))
        _isOverlayTracksExpanded = State(initialValue: project.selectedOverlayClipID != nil)
    }

    var body: some View {
        editorLifecycleView
    }

    private var editorBaseView: some View {
        AppGlobalBackgroundScaffold {
            GeometryReader { geo in
                VStack(spacing: 0) {
                    EditorTopBar(
                        onBack: { close() },
                        onExport: { showExportScreen = true }
                    )

                    if usesWideIPadLayout(in: geo) {
                        wideIPadWorkspace(in: geo)
                    } else {
                        compactWorkspace(in: geo)
                    }
                }
            }
        }
        .overlay {
            if let progress = vm.reverseGenerationProgress {
                ReverseGenerationOverlay(
                    progress: progress,
                    onCancel: { vm.cancelReverseGeneration() }
                )
                .transition(.opacity)
            }
        }
        .background(EditorNavigationPopGestureLock())
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $showExportScreen) {
            EditorExportScreen(vm: vm)
        }
        .animation(.easeInOut(duration: 0.2), value: vm.selectedTool)
    }

    private var mediaPresentationView: some View {
        editorBaseView
        .fullScreenCover(isPresented: $isFullscreenPreview) {
            EditorFullscreenPreviewSheet(vm: vm, onClose: { isFullscreenPreview = false })
        }
        .fullScreenCover(isPresented: $isMediaPickerPresented) {
            MediaLibraryPickerScreen(
                title: "Add Media",
                confirmButtonTitle: "Add",
                onCancel: { isMediaPickerPresented = false },
                onConfirm: { items in
                    if isReplacingClip, let item = items.first {
                        vm.replaceSelectedClip(with: item)
                    } else {
                        vm.insertClips(from: items, afterIndex: insertAfterClipIndex)
                    }
                    isReplacingClip = false
                    isMediaPickerPresented = false
                }
            )
        }
        .fullScreenCover(isPresented: $isOverlayPickerPresented) {
            MediaLibraryPickerScreen(
                title: isReplacingOverlayClip ? "Replace Overlay" : "Add Overlay",
                confirmButtonTitle: isReplacingOverlayClip ? "Replace" : "Add Overlay",
                onCancel: {
                    isReplacingOverlayClip = false
                    isOverlayPickerPresented = false
                },
                onConfirm: { items in
                    if isReplacingOverlayClip, let item = items.first {
                        vm.replaceSelectedOverlayClip(with: item)
                    } else {
                        vm.addOverlayClips(from: items)
                    }
                    isReplacingOverlayClip = false
                    isOverlayPickerPresented = false
                    isOverlayTracksExpanded = true
                }
            )
        }
        .modifier(
            AudioSourceSheets(
                vm: vm,
                isAudioSourceChooserPresented: $isAudioSourceChooserPresented,
                isAudioLibraryPickerPresented: $isAudioLibraryPickerPresented,
                isAudioPickerPresented: $isAudioPickerPresented,
                isVoiceoverRecorderPresented: $isVoiceoverRecorderPresented,
                insertAfterAudioClipID: $insertAfterAudioClipID
            )
        )
    }

    private var primaryToolSheetsView: some View {
        mediaPresentationView
        .editorSheet(
            isPresented: $isSequenceManagerPresented,
            iPadHeight: .fraction(0.72)
        ) {
            SequenceStructurePanel(
                vm: vm,
                onDone: { isSequenceManagerPresented = false }
            )
            .presentationDetents([.fraction(0.72), .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(Color.appColors.backgroundColor)
            .presentationBackgroundInteraction(.enabled)
        }
        .editorSheet(
            isPresented: Binding(
                get: { vm.selectedTool == .keyframe },
                set: { if !$0 && vm.selectedTool == .keyframe { vm.selectedTool = nil } }
            ),
            iPadHeight: .fraction(0.72)
        ) {
            KeyframeToolPanel(vm: vm, isEmbedded: UIDevice.current.userInterfaceIdiom == .pad)
                .presentationDetents([.fraction(0.72), .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Color.appColors.backgroundColor)
                .presentationBackgroundInteraction(.enabled)
        }
        .editorSheet(
            isPresented: Binding(
                get: { vm.selectedTool == .precision },
                set: { if !$0 && vm.selectedTool == .precision { vm.selectedTool = nil } }
            ),
            iPadHeight: .fixed(430)
        ) {
            PrecisionEditToolPanel(vm: vm)
            .presentationDetents([.height(430), .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(Color.appColors.backgroundColor)
            .presentationBackgroundInteraction(.enabled)
        }
        .editorSheet(
            isPresented: Binding(
                get: { vm.selectedTool == .freeze },
                set: { if !$0 && vm.selectedTool == .freeze { vm.selectedTool = nil } }
            ),
            iPadHeight: .fixed(410),
            allowsBackdropDismiss: false
        ) {
            FreezeFrameToolPanel(vm: vm, onDone: { vm.selectedTool = nil })
                .presentationDetents([.height(410)])
                .presentationDragIndicator(.visible)
                .presentationBackground(Color.appColors.backgroundColor)
        }
        .editorSheet(
            isPresented: Binding(
                get: { vm.selectedTool == .reverse },
                set: { if !$0 && vm.selectedTool == .reverse { vm.selectedTool = nil } }
            ),
            iPadHeight: .fixed(300),
            allowsBackdropDismiss: false
        ) {
            ReverseClipToolPanel(vm: vm, onStart: { vm.selectedTool = nil })
                .presentationDetents([.height(300)])
                .presentationDragIndicator(.visible)
                .presentationBackground(Color.appColors.backgroundColor)
        }
        .editorSheet(
            isPresented: Binding(
                get: { vm.selectedTool == .canvas },
                set: { if !$0 && vm.selectedTool == .canvas { vm.selectedTool = nil } }
            ),
            iPadHeight: .fixed(410)
        ) {
            CanvasToolPanel(vm: vm, isEmbedded: UIDevice.current.userInterfaceIdiom == .pad)
                .presentationDetents([.height(410), .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Color.appColors.backgroundColor)
        }
        .editorSheet(
            isPresented: Binding(
                get: { transitionTarget != nil },
                set: { if !$0 { transitionTarget = nil } }
            ),
            iPadHeight: .fraction(0.58),
            allowsBackdropDismiss: false
        ) {
            if let transitionTarget {
                EditorTransitionSheet(
                    vm: vm,
                    target: transitionTarget,
                    isEmbedded: UIDevice.current.userInterfaceIdiom == .pad,
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
    }

    private var textAndAudioToolSheetsView: some View {
        primaryToolSheetsView
        .editorSheet(
            isPresented: Binding(
                get: { vm.isTextEditorPresented },
                set: { newValue in
                    if !newValue { vm.dismissTextEditor() }
                }
            ),
            iPadHeight: .fraction(0.68)
        ) {
            if let overlay = vm.selectedTextOverlay {
                TextOverlayEditorSheet(
                    vm: vm,
                    overlay: overlay,
                    isEmbedded: UIDevice.current.userInterfaceIdiom == .pad
                )
                    .presentationBackgroundInteraction(.enabled)
            }
        }
        .editorSheet(
            isPresented: Binding(
                get: { vm.selectedTool == .captions },
                set: { if !$0 && vm.selectedTool == .captions { vm.selectedTool = nil } }
            ),
            iPadHeight: .fraction(0.82)
        ) {
            CaptionTranscriptEditorSheet(
                vm: vm,
                isEmbedded: UIDevice.current.userInterfaceIdiom == .pad
            )
            .presentationDetents([.fraction(0.82), .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(Color.appColors.backgroundColor)
            .presentationBackgroundInteraction(.enabled)
        }
        .editorSheet(
            isPresented: Binding(
                get: { vm.selectedTool == .volume },
                set: { newValue in
                    if !newValue && vm.selectedTool == .volume {
                        vm.selectedTool = nil
                    }
                }
            ),
            iPadHeight: .fixed(vm.selectedAudioClip == nil ? 180 : 300)
        ) {
            VolumeToolPanel(vm: vm)
                .presentationDetents([.height(vm.selectedAudioClip == nil ? 180 : 300)])
                .presentationDragIndicator(.visible)
                .presentationBackground(Color.appColors.backgroundColor)
                .presentationBackgroundInteraction(.enabled)
        }
        .modifier(MixToolSheet(vm: vm))
        .modifier(AudioEffectToolSheet(vm: vm))
        .editorSheet(
            isPresented: Binding(
                get: { vm.selectedTool == .speed },
                set: { newValue in
                    guard !newValue, vm.selectedTool == .speed else { return }
                    // Route dismissal through the tool lifecycle so a drag-to-close
                    // commits the current speed edit as one undoable operation.
                    vm.selectTool(.speed)
                }
            ),
            iPadHeight: .fraction(0.62)
        ) {
            ScrollView {
                SpeedToolPanel(vm: vm)
                    // A bounded canvas keeps controls comfortably reachable on
                    // wide iPads instead of stretching the curve edge to edge.
                    .frame(maxWidth: 920)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .presentationDetents([.fraction(0.62), .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(Color.appColors.backgroundColor)
            .presentationBackgroundInteraction(.enabled)
        }
    }

    private var visualToolSheetsView: some View {
        textAndAudioToolSheetsView
        .editorSheet(
            isPresented: Binding(
                get: {
                    vm.selectedTool == .crop
                        && (vm.selectedClipID != nil || vm.selectedOverlayClipID != nil)
                },
                set: { newValue in
                    if !newValue && vm.selectedTool == .crop {
                        vm.commitSelectedClipReframe()
                        vm.showsReframeSafeAreaGuides = false
                        vm.selectedTool = nil
                    }
                }
            ),
            iPadHeight: .fixed(430)
        ) {
            CropReframeToolPanel(vm: vm)
                .presentationDetents([.height(430), .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Color.appColors.backgroundColor)
                .presentationBackgroundInteraction(.enabled)
        }
        .editorSheet(
            isPresented: Binding(
                get: {
                    vm.selectedTool == .filter
                        && (vm.selectedClipID != nil
                            || vm.selectedOverlayClipID != nil
                            || vm.selectedAdjustmentLayerID != nil)
                },
                set: { newValue in
                    if !newValue && vm.selectedTool == .filter {
                        vm.commitColorAdjustmentEdit()
                        vm.selectedTool = nil
                    }
                }
            ),
            iPadHeight: .fraction(0.68)
        ) {
            ColorAdjustmentToolPanel(vm: vm)
                .presentationDetents([.fraction(0.68), .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Color.appColors.backgroundColor)
                .presentationBackgroundInteraction(.enabled)
        }
        .editorSheet(
            isPresented: Binding(
                get: { vm.selectedTool == .effects },
                set: { if !$0 && vm.selectedTool == .effects { vm.selectedTool = nil } }
            ),
            iPadHeight: .fraction(0.72)
        ) {
            VisualEffectsStackPanel(
                vm: vm,
                isEmbedded: UIDevice.current.userInterfaceIdiom == .pad
            )
            .presentationDetents([.fraction(0.72), .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(Color.appColors.backgroundColor)
            .presentationBackgroundInteraction(.enabled)
        }
        .editorSheet(
            isPresented: Binding(
                get: { vm.selectedTool == .opacity && vm.selectedOverlayClipID != nil },
                set: { newValue in
                    if !newValue && vm.selectedTool == .opacity {
                        vm.commitOverlayTransform()
                        vm.selectedTool = nil
                    }
                }
            ),
            iPadHeight: .fixed(180)
        ) {
            OverlayOpacityToolPanel(vm: vm)
                .presentationDetents([.height(180)])
                .presentationDragIndicator(.visible)
                .presentationBackground(Color.appColors.backgroundColor)
                .presentationBackgroundInteraction(.enabled)
        }
        .editorSheet(
            isPresented: Binding(
                get: {
                    vm.selectedTool == .compositing
                        && (vm.selectedOverlayClipID != nil || vm.selectedClipID != nil)
                },
                set: { newValue in
                    if !newValue && vm.selectedTool == .compositing {
                        vm.selectTool(.compositing)
                    }
                }
            ),
            iPadHeight: .fraction(0.68)
        ) {
            OverlayCompositingToolPanel(
                vm: vm,
                isEmbedded: UIDevice.current.userInterfaceIdiom == .pad,
                onDone: { vm.selectedTool = nil }
            )
            .presentationDetents([.fraction(0.68), .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(Color.appColors.backgroundColor)
            .presentationBackgroundInteraction(.enabled)
        }
        .editorSheet(
            isPresented: Binding(
                get: { vm.selectedTool == .track },
                set: { newValue in
                    if !newValue && vm.selectedTool == .track {
                        vm.selectTool(.track)
                    }
                }
            ),
            iPadHeight: .fixed(340)
        ) {
            MotionTrackingToolPanel(
                vm: vm,
                isEmbedded: UIDevice.current.userInterfaceIdiom == .pad,
                onDone: { vm.selectedTool = nil }
            )
            .presentationDetents([.height(340), .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(Color.appColors.backgroundColor)
            .presentationBackgroundInteraction(.enabled)
        }
        .editorSheet(
            isPresented: Binding(
                get: { vm.selectedTool == .stabilize },
                set: { newValue in
                    if !newValue && vm.selectedTool == .stabilize {
                        vm.selectTool(.stabilize)
                    }
                }
            ),
            iPadHeight: .fixed(520)
        ) {
            MotionTrackingToolPanel(
                vm: vm,
                isEmbedded: UIDevice.current.userInterfaceIdiom == .pad,
                lockedToStabilize: true,
                onDone: { vm.selectedTool = nil }
            )
            .presentationDetents([.height(520), .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(Color.appColors.backgroundColor)
            .presentationBackgroundInteraction(.enabled)
        }
    }

    private var editorLifecycleView: some View {
        visualToolSheetsView
        .alert(
            "Reverse Error",
            isPresented: Binding(
                get: { vm.reverseGenerationErrorMessage != nil },
                set: { if !$0 { vm.reverseGenerationErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { vm.reverseGenerationErrorMessage = nil }
        } message: {
            Text(vm.reverseGenerationErrorMessage ?? "Reverse generation failed.")
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

    private func usesWideIPadLayout(in geo: GeometryProxy) -> Bool {
        UIDevice.current.userInterfaceIdiom == .pad
            && geo.size.width >= 920
            && geo.size.width > geo.size.height
    }

    private func compactWorkspace(in geo: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            preview
                .frame(maxWidth: min(geo.size.width - (previewHorizontalInset * 2), 860))
                .frame(maxHeight: inlinePreviewHeight(in: geo))
                .frame(maxWidth: .infinity)
                .padding(.top, 2)

            activeInlineTool
            timelineControls
            timeline
            selectionActionBar
        }
    }

    private func wideIPadWorkspace(in geo: GeometryProxy) -> some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                preview
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(16)

                activeInlineTool
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
            .frame(width: max(390, geo.size.width * 0.43))

            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 1)

            VStack(spacing: 0) {
                timelineControls
                timeline
                selectionActionBar
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var preview: some View {
        EditorPreviewPlayer(vm: vm) {
            isFullscreenPreview = true
        }
    }

    @ViewBuilder
    private var activeInlineTool: some View {
        if vm.selectedTool == .duration {
            PhotoDurationToolPanel(vm: vm)
                .padding(.top, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var timelineControls: some View {
        EditorTimelineControls(
            onUndo: { vm.undo() },
            onRedo: { vm.redo() },
            canUndo: vm.canUndo,
            canRedo: vm.canRedo,
            isMultiSelectMode: vm.isMultiSelectMode,
            selectionCount: vm.selectionCount,
            activeSequenceName: vm.activeSequence?.title,
            onToggleMultiSelect: {
                vm.isMultiSelectMode ? vm.endMultiSelection() : vm.beginMultiSelection()
            },
            onAddMarker: { vm.addMarkerAtPlayhead() },
            onExitSequence: { vm.exitActiveSequence() }
        )
        .padding(.top, 4)
    }

    private var timeline: some View {
        EditorTimeline(
            vm: vm,
            isOverlayTracksExpanded: $isOverlayTracksExpanded,
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
            onAddAudioTrack: {
                insertAfterAudioClipID = nil
                isAudioSourceChooserPresented = true
            },
            onInsertAudioAfterClip: { clipID in
                insertAfterAudioClipID = clipID
                isAudioSourceChooserPresented = true
            },
            onAddOverlayClip: {
                isOverlayPickerPresented = true
            }
        )
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var selectionActionBar: some View {
        Group {
            if vm.isMultiSelectMode {
                SequenceSelectionActionBar(
                    vm: vm,
                    onStructure: { isSequenceManagerPresented = true }
                )
            } else if vm.selectedOverlayClipID != nil {
                EditorOverlayActionBar(
                    vm: vm,
                    onAddOverlay: { isOverlayPickerPresented = true },
                    onReplace: {
                        isReplacingOverlayClip = true
                        isOverlayPickerPresented = true
                    },
                    onBack: { isOverlayTracksExpanded = false }
                )
            } else if vm.selectedAudioClipID != nil {
                EditorAudioActionBar(
                    vm: vm,
                    onAddAudio: {
                        insertAfterAudioClipID = nil
                        isAudioSourceChooserPresented = true
                    }
                )
            } else if vm.selectedClipID != nil {
                EditorClipActionBar(vm: vm, onReplace: {
                    isReplacingClip = true
                    isMediaPickerPresented = true
                })
            } else if vm.selectedTextOverlayID != nil {
                EditorTextActionBar(vm: vm)
            } else {
                EditorBottomToolbar(
                    vm: vm,
                    isOverlayMode: isOverlayTracksExpanded,
                    onAddOverlay: {
                        if vm.overlayClips.isEmpty {
                            isOverlayPickerPresented = true
                        } else {
                            isOverlayTracksExpanded.toggle()
                        }
                    }
                )
            }
        }
        .animation(
            .easeInOut(duration: 0.2),
            value: vm.isMultiSelectMode || vm.selectedClipID != nil
                || vm.selectedTextOverlayID != nil
                || vm.selectedAudioClipID != nil
                || vm.selectedOverlayClipID != nil
        )
    }

    private func inlinePreviewHeight(in geo: GeometryProxy) -> CGFloat {
        let maxByChrome = geo.size.height - editorChromeMinHeight
        let maxByFraction = geo.size.height * 0.60
        return max(220, min(maxByChrome, maxByFraction))
    }
}

private struct ReverseGenerationOverlay: View {
    let progress: Double
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.72).ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "backward.end.alt.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(Color.appColors.primaryColor)
                Text("Generating Reverse Media")
                    .font(.headline)
                ProgressView(value: progress)
                    .tint(Color.appColors.primaryColor)
                Text("\(Int((progress * 100).rounded()))%")
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(.secondary)
                Button("Cancel", role: .cancel, action: onCancel)
                    .buttonStyle(.bordered)
            }
            .padding(24)
            .frame(maxWidth: 340)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
            .padding(28)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Generating reverse media")
        .accessibilityValue("\(Int((progress * 100).rounded())) percent")
    }
}

private struct EditorTransitionSheet: View {
    let vm: EditorViewModel
    let target: EditorTransitionTarget
    let isEmbedded: Bool
    let onCancel: () -> Void
    let onDone: () -> Void

    @State private var selectedCategory: EditorTransitionCategory = .all
    @State private var selectedKind: EditorTransitionKind
    @State private var duration: TimeInterval
    @State private var applyToAll = false

    init(
        vm: EditorViewModel,
        target: EditorTransitionTarget,
        isEmbedded: Bool = false,
        onCancel: @escaping () -> Void,
        onDone: @escaping () -> Void
    ) {
        self.vm = vm
        self.target = target
        self.isEmbedded = isEmbedded
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
        Group {
            if isEmbedded {
                VStack(spacing: 0) {
                    embeddedHeader
                    Divider().overlay(Color.white.opacity(0.1))
                    panelContent
                }
            } else {
                NavigationStack {
                    panelContent
                        .navigationTitle(target.navigationTitle)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar { nativeToolbar }
                }
            }
        }
    }

    private var panelContent: some View {
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
    }

    @ToolbarContentBuilder
    private var nativeToolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel", action: onCancel).foregroundColor(.white)
        }
        ToolbarItem(placement: .confirmationAction) {
            applyButton
        }
    }

    private var embeddedHeader: some View {
        ZStack {
            Text(target.navigationTitle)
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(.white)
            HStack {
                Button("Cancel", action: onCancel).foregroundColor(.white)
                Spacer()
                applyButton
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 48)
    }

    private var applyButton: some View {
        Button {
            previewSelection()
            onDone()
        } label: {
            Image(systemName: "checkmark").fontWeight(.bold)
        }
        .foregroundColor(Color.appColors.primaryColor)
        .accessibilityLabel("Apply transition")
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
        vm.player != nil
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Locked to the same aspect ratio and fit behavior as the inline
            // preview so overlay positions line up at every playhead position
            // instead of drifting when the canvas is cropped to fill the screen.
            canvasSurface
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .aspectRatio(vm.canvasSettings.aspectRatio, contentMode: .fit)

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

                fullscreenControls
                    .padding(.bottom, 28)
            }
        }
        .onAppear { loadPoster() }
        .onChange(of: vm.playbackClipID) { _, _ in loadPoster() }
        .onChange(of: vm.selectedClipID) { _, _ in
            if vm.playbackInfo == nil { loadPoster() }
        }
    }

    private var canvasSurface: some View {
        ZStack {
            if let posterImage, !showingVideoLayer {
                Image(uiImage: posterImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if showingVideoLayer, let player = vm.player {
                PlayerLayerView(player: player, videoGravity: .resizeAspect)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Text overlays rendered on top of video/poster
            EditorTextOverlayLayerView(vm: vm)

            EditorOverlaySelectionLayer(vm: vm)
        }
    }

    private var fullscreenControls: some View {
        VStack(spacing: 14) {
            VStack(spacing: 4) {
                Slider(
                    value: fullscreenScrubberBinding,
                    in: 0...max(vm.totalDuration, 0.01),
                    onEditingChanged: { isEditing in
                        if !isEditing {
                            vm.commitTimelineAfterScrub()
                        }
                    }
                )
                .tint(Color.appColors.primaryColor)
                .disabled(vm.totalDuration <= 0)
                .accessibilityLabel("Video position")
                .accessibilityValue(
                    "\(vm.currentTimeString) of \(vm.formatPlaybackTime(vm.totalDuration))"
                )

                HStack {
                    Text(vm.currentTimeString)
                    Spacer(minLength: 12)
                    Text(vm.formatPlaybackTime(vm.totalDuration))
                }
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundColor(.white.opacity(0.8))
            }
            .padding(.horizontal, 20)

            fullscreenHUD
        }
    }

    private var fullscreenHUD: some View {
        HStack(spacing: 14) {
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

    private var fullscreenScrubberBinding: Binding<Double> {
        Binding(
            get: { min(max(0, vm.timelinePosition), vm.totalDuration) },
            set: { vm.setTimelinePositionForScrub($0) }
        )
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

/// The MIX tool's sheet (master + per-track gain), pulled out as its own `ViewModifier` for the
/// same reason as `AudioSourceSheets` below — keeping inline modifiers off `EditorScreen.body`.
private struct MixToolSheet: ViewModifier {
    let vm: EditorViewModel

    func body(content: Content) -> some View {
        content.editorSheet(
            isPresented: Binding(
                get: { vm.selectedTool == .mix },
                set: { if !$0 && vm.selectedTool == .mix { vm.selectedTool = nil } }
            ),
            iPadHeight: .fixed(280)
        ) {
            MixToolPanel(vm: vm)
                .presentationDetents([.height(280), .medium])
                .presentationDragIndicator(.visible)
                .presentationBackground(Color.appColors.backgroundColor)
                .presentationBackgroundInteraction(.enabled)
        }
    }
}

/// The EFFECTS tool's sheet (Priority 15 voice/sound presets for the selected audio clip), same
/// pulled-out-`ViewModifier` reasoning as `MixToolSheet` above.
private struct AudioEffectToolSheet: ViewModifier {
    let vm: EditorViewModel

    func body(content: Content) -> some View {
        content.editorSheet(
            isPresented: Binding(
                get: { vm.selectedTool == .audioEffect },
                set: { if !$0 && vm.selectedTool == .audioEffect { vm.selectedTool = nil } }
            ),
            iPadHeight: .fixed(380)
        ) {
            EditorAudioEffectPanel(vm: vm)
                .presentationDetents([.height(380), .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Color.appColors.backgroundColor)
                .presentationBackgroundInteraction(.enabled)
        }
    }
}

/// Bundles the "Add Audio" source chooser and its two sheets (Files import, sound library) as
/// one `ViewModifier` rather than three chained modifiers directly on `EditorScreen.body` —
/// `body` is already a large single expression, and adding more inline modifiers there pushed
/// the type checker over its complexity budget ("unable to type-check ... in reasonable time").
private struct AudioSourceSheets: ViewModifier {
    let vm: EditorViewModel
    @Binding var isAudioSourceChooserPresented: Bool
    @Binding var isAudioLibraryPickerPresented: Bool
    @Binding var isAudioPickerPresented: Bool
    @Binding var isVoiceoverRecorderPresented: Bool
    @Binding var insertAfterAudioClipID: UUID?

    private var pendingInsertion: EditorViewModel.AudioInsertion {
        if let clipID = insertAfterAudioClipID { return .afterClip(clipID) }
        return .newTrackAtPlayhead
    }

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                "Add Audio",
                isPresented: $isAudioSourceChooserPresented,
                titleVisibility: .visible
            ) {
                Button("Record Voiceover") { isVoiceoverRecorderPresented = true }
                Button("Browse Sound Library") { isAudioLibraryPickerPresented = true }
                Button("Import from Files") { isAudioPickerPresented = true }
                Button("Cancel", role: .cancel) { insertAfterAudioClipID = nil }
            }
            .editorSheet(
                isPresented: $isAudioLibraryPickerPresented,
                iPadHeight: .fraction(0.82)
            ) {
                AudioLibraryPickerView(
                    vm: vm,
                    insertion: pendingInsertion,
                    onInsert: {
                        isAudioLibraryPickerPresented = false
                        insertAfterAudioClipID = nil
                    },
                    onCancel: {
                        isAudioLibraryPickerPresented = false
                        insertAfterAudioClipID = nil
                    }
                )
            }
            .editorSheet(
                isPresented: $isAudioPickerPresented,
                iPadHeight: .fraction(0.82)
            ) {
                AudioPickerView(
                    onPick: { url in
                        isAudioPickerPresented = false
                        vm.loadAudioClip(from: url, insertion: pendingInsertion)
                        insertAfterAudioClipID = nil
                    },
                    onCancel: {
                        isAudioPickerPresented = false
                        insertAfterAudioClipID = nil
                    }
                )
            }
            .editorSheet(
                isPresented: $isVoiceoverRecorderPresented,
                iPadHeight: .fraction(0.85)
            ) {
                VoiceoverRecorderView(
                    vm: vm,
                    mode: .insert(pendingInsertion),
                    onInsert: {
                        isVoiceoverRecorderPresented = false
                        insertAfterAudioClipID = nil
                    },
                    onCancel: {
                        isVoiceoverRecorderPresented = false
                        insertAfterAudioClipID = nil
                    }
                )
                .presentationDetents([.fraction(0.85), .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Color.black)
            }
            .editorSheet(
                isPresented: Binding(
                    get: { vm.punchInPendingRange != nil },
                    set: { if !$0 { vm.punchInPendingRange = nil } }
                ),
                iPadHeight: .fraction(0.85)
            ) {
                if let range = vm.punchInPendingRange {
                    VoiceoverRecorderView(
                        vm: vm,
                        mode: .punch(range),
                        onInsert: { vm.punchInPendingRange = nil },
                        onCancel: { vm.punchInPendingRange = nil }
                    )
                    .presentationDetents([.fraction(0.85), .large])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(Color.black)
                }
            }
    }
}
