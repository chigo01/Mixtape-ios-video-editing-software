//
//  MotionTrackingToolPanel.swift
//  Mixtape
//
//  Stabilize (camera-shake removal) and Track (CapCut-style subject
//  tracking for text and graphic overlays) controls.
//

import SwiftUI

struct MotionTrackingToolPanel: View {
    let vm: EditorViewModel
    let isEmbedded: Bool
    /// When true, the panel opens locked to Stabilize and never auto-switches
    /// to Track — used by the dedicated Stabilize entry point so it stays on
    /// topic even when a graphic/text overlay happens to be selected.
    var lockedToStabilize: Bool = false
    let onDone: () -> Void

    private enum Section: String, CaseIterable, Identifiable {
        case stabilize = "Stabilize"
        case track = "Track"
        var id: String { rawValue }
    }

    @State private var section: Section = .stabilize

    var body: some View {
        Group {
            if isEmbedded {
                VStack(spacing: 0) {
                    embeddedHeader
                    Divider().overlay(Color.white.opacity(0.10))
                    panelContent
                }
            } else {
                NavigationStack {
                    panelContent
                        .navigationTitle("Motion")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done", action: finish)
                                    .fontWeight(.bold)
                                    .foregroundColor(Color.appColors.primaryColor)
                            }
                        }
                }
            }
        }
        .background(Color.appColors.backgroundColor)
        .onAppear { syncSection() }
        .onChange(of: vm.isGraphicFollowTracking) { _, _ in syncSection() }
    }

    private func syncSection() {
        guard !lockedToStabilize else {
            section = .stabilize
            return
        }
        if vm.isGraphicFollowTracking {
            section = .track
            vm.prepareSubjectTrackingIfNeeded()
        } else {
            section = .stabilize
        }
    }

    private var embeddedHeader: some View {
        ZStack {
            Text("Motion")
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(.white)
            HStack {
                Spacer()
                Button("Done", action: finish)
                    .fontWeight(.bold)
                    .foregroundColor(Color.appColors.primaryColor)
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 48)
    }

    private var panelContent: some View {
        VStack(spacing: 0) {
            if visibleSections.count > 1 {
                Picker("Motion section", selection: $section) {
                    ForEach(visibleSections) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)

                Divider().overlay(Color.white.opacity(0.10))
            }

            ScrollView {
                Group {
                    switch section {
                    case .stabilize: stabilizeControls
                    case .track: trackControls
                    }
                }
                .frame(maxWidth: 920)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
            }
        }
    }

    private var visibleSections: [Section] {
        guard !lockedToStabilize else { return [.stabilize] }
        return vm.isGraphicFollowTracking ? [.track] : [.stabilize]
    }

    // MARK: - Track (CapCut-style: box on preview → Track → auto-attaches)

    private var trackControls: some View {
        let track = vm.currentTrackingBox
        let tracked = track?.isTracked == true
        return VStack(alignment: .leading, spacing: 16) {
            sectionTitle(
                "Tracking",
                detail: "Drag the circle onto an object to track, then tap Start tracking. The selected text or sticker will follow it."
            )

            if vm.subjectTrackingHostClip?.isVideo != true {
                Text("Park the playhead on a video clip, then start tracking.")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.55))
            } else {
                if tracked {
                    Label("Tracking subject", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color.appColors.primaryColor)
                    Text("If the track drifts, scrub to that frame and drag the tracking circle back onto the object, then tap Track again.")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.55))
                }

                if vm.isMotionTracking {
                    actionChip("Cancel", systemImage: "xmark.circle", role: .red) {
                        vm.cancelMotionTracking()
                    }
                    if let progress = vm.stabilizationAnalysisProgress {
                        ProgressView(value: progress)
                            .tint(Color.appColors.primaryColor)
                    }
                } else {
                    Button(action: { vm.startSubjectTracking() }) {
                        Text(tracked ? "Track again" : "Start tracking")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.appColors.primaryColor)
                            )
                    }
                    .buttonStyle(.plain)
                }

                Toggle(isOn: Binding(
                    get: { vm.selectedTextOverlay?.attachRotation ?? vm.selectedOverlayClip?.attachRotation ?? false },
                    set: { vm.setSelectedAttachmentFollowsRotation($0) }
                )) {
                    Text("Follow rotation")
                        .foregroundColor(.white)
                }
                .tint(Color.appColors.primaryColor)

                Toggle(isOn: Binding(
                    get: { vm.selectedTextOverlay?.attachScale ?? vm.selectedOverlayClip?.attachScale ?? false },
                    set: { vm.setSelectedAttachmentFollowsScale($0) }
                )) {
                    Text("Follow scale")
                        .foregroundColor(.white)
                }
                .tint(Color.appColors.primaryColor)

                if track != nil {
                    actionChip("Clear tracking", systemImage: "arrow.uturn.backward", role: .red) {
                        vm.clearSubjectTracking()
                    }
                }
            }

            statusMessage
        }
    }

    // MARK: - Stabilize

    private var stabilizeControls: some View {
        let settings = vm.selectedStabilization
        return VStack(alignment: .leading, spacing: 16) {
            sectionTitle(
                "Stabilization",
                detail: "Analyze the clip, then choose Smooth (keep pans) or Lock (tripod). Auto crop punches in just enough to hide the warp."
            )

            if !vm.canStabilizeSelectedClip {
                Text("Select a primary video clip to analyze camera motion. Still images have no camera path.")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.55))
            } else {
                Toggle(isOn: Binding(
                    get: { settings.isEnabled },
                    set: { enabled in
                        vm.updateSelectedStabilization { $0.isEnabled = enabled }
                    }
                )) {
                    Text("Enable stabilization")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                }
                .tint(Color.appColors.primaryColor)

                Picker("Mode", selection: Binding(
                    get: { settings.mode },
                    set: { mode in
                        vm.updateSelectedStabilization { $0.mode = mode }
                    }
                )) {
                    ForEach(EditorStabilizationMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Text(settings.mode.detail)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.45))

                sliderRow(
                    settings.mode == .lock ? "Lock strength" : "Smoothness",
                    value: settings.smoothness,
                    range: 0...1,
                    format: { "\(Int($0 * 100))%" }
                ) { value in
                    vm.updateSelectedStabilization { $0.smoothness = value }
                }

                Toggle(isOn: Binding(
                    get: { settings.autoCrop },
                    set: { enabled in
                        vm.updateSelectedStabilization { $0.autoCrop = enabled }
                    }
                )) {
                    Text(
                        settings.autoCrop
                            ? "Auto crop  \(Int((settings.fittedCrop * 100).rounded()))%"
                            : "Auto crop"
                    )
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                }
                .tint(Color.appColors.primaryColor)

                sliderRow(
                    settings.autoCrop ? "Extra crop" : "Crop",
                    value: settings.crop,
                    range: 0...0.5,
                    format: { "\(Int($0 * 100))%" }
                ) { value in
                    vm.updateSelectedStabilization { $0.crop = value }
                }

                Toggle(isOn: Binding(
                    get: { settings.fillEdges },
                    set: { enabled in
                        vm.updateSelectedStabilization { $0.fillEdges = enabled }
                    }
                )) {
                    Text("Fill edges")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                }
                .tint(Color.appColors.primaryColor)

                HStack(spacing: 8) {
                    actionChip(
                        settings.isAnalyzed ? "Re-analyze" : "Analyze motion",
                        systemImage: "waveform.path.ecg",
                        disabled: vm.isMotionTracking
                    ) {
                        vm.analyzeSelectedStabilization()
                    }
                    if vm.isMotionTracking {
                        actionChip("Cancel", systemImage: "xmark.circle", role: .red) {
                            vm.cancelMotionTracking()
                        }
                    } else if settings.isAnalyzed {
                        actionChip("Clear", systemImage: "arrow.uturn.backward", role: .red) {
                            vm.clearSelectedStabilization()
                        }
                    }
                }

                if let progress = vm.stabilizationAnalysisProgress {
                    ProgressView(value: progress)
                        .tint(Color.appColors.primaryColor)
                }
            }

            statusMessage
        }
    }

    @ViewBuilder
    private var statusMessage: some View {
        if let message = vm.motionTrackingMessage {
            Text(message)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.6))
        }
    }

    private func finish() {
        vm.commitMotionTrackingEdit()
        onDone()
    }

    private func sectionTitle(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.white)
            Text(detail)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func sliderRow(
        _ title: String,
        value: Double,
        range: ClosedRange<Double>,
        format: (Double) -> String,
        onChange: @escaping (Double) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                Text(format(value))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.55))
            }
            Slider(
                value: Binding(
                    get: { value },
                    set: onChange
                ),
                in: range
            )
            .tint(Color.appColors.primaryColor)
        }
    }

    private func actionChip(
        _ title: String,
        systemImage: String,
        role: Color = .white,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(disabled ? .white.opacity(0.3) : role)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.07))
                )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}
