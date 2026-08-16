//
//  SpeedToolPanel.swift
//  Mixtape
//

import SwiftUI

struct SpeedToolPanel: View {
    let vm: EditorViewModel

    private let presets: [(label: String, value: Float)] = [
        ("0.5×", 0.5),
        ("0.75×", 0.75),
        ("1×", 1.0),
        ("1.5×", 1.5),
        ("2×", 2.0)
    ]

    private var activeSpeed: Float? {
        vm.selectedOverlayClip?.speed ?? vm.selectedClip?.speed
    }

    private var hasSelection: Bool {
        vm.selectedOverlayClipID != nil || vm.selectedClipID != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Speed")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                if let activeSpeed {
                    Text(String(format: "%.2g×", activeSpeed))
                        .font(.system(size: 13, weight: .bold).monospacedDigit())
                        .foregroundColor(Color.appColors.primaryColor)
                }
            }

            if !hasSelection {
                Text("Select a clip to change speed.")
                    .font(.system(size: 12))
                    .foregroundColor(Color.white.opacity(0.55))
            } else {
                HStack(spacing: 8) {
                    ForEach(presets, id: \.label) { preset in
                        speedChip(preset)
                    }
                }

                Slider(
                    value: Binding(
                        get: { Double(activeSpeed ?? 1) },
                        set: { setSpeed(Float($0), commit: false) }
                    ),
                    in: 0.25...3.0,
                    step: 0.05
                ) {
                    Text("Speed")
                } minimumValueLabel: {
                    Text("0.25×").font(.system(size: 10)).foregroundColor(.white.opacity(0.5))
                } maximumValueLabel: {
                    Text("3×").font(.system(size: 10)).foregroundColor(.white.opacity(0.5))
                }
                .tint(Color.appColors.primaryColor)
                .disabled(!hasSelection)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
        .padding(.horizontal, 12)
    }

    private func speedChip(_ preset: (label: String, value: Float)) -> some View {
        let isActive = abs((activeSpeed ?? 1) - preset.value) < 0.02
        return Button {
            setSpeed(preset.value, commit: true)
        } label: {
            Text(preset.label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(isActive ? .black : .white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule().fill(isActive ? Color.appColors.primaryColor : Color.white.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
        .disabled(!hasSelection)
    }

    private func setSpeed(_ speed: Float, commit: Bool) {
        if let id = vm.selectedOverlayClipID {
            if commit {
                vm.commitOverlaySpeed(clipID: id, speed: speed)
            } else {
                vm.setOverlaySpeed(clipID: id, speed: speed)
            }
        } else if let id = vm.selectedClipID {
            if commit {
                vm.commitSpeed(clipID: id, speed: speed)
            } else {
                vm.setSpeed(clipID: id, speed: speed)
            }
        }
    }
}

struct PhotoDurationToolPanel: View {
    let vm: EditorViewModel

    private let presets: [TimeInterval] = [1, 3, 5, 10]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Photo duration")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                if let clip = vm.selectedDurationClip, clip.isPhoto {
                    Text(formatted(clip.duration))
                        .font(.system(size: 13, weight: .bold).monospacedDigit())
                        .foregroundColor(Color.appColors.primaryColor)
                }
            }

            if vm.selectedDurationClip?.isPhoto == true {
                HStack(spacing: 8) {
                    ForEach(presets, id: \.self) { preset in
                        durationChip(preset)
                    }
                }

                durationSlider
            } else {
                Text("Select a photo clip to change its duration.")
                    .font(.system(size: 12))
                    .foregroundColor(Color.white.opacity(0.55))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
        .padding(.horizontal, 12)
    }

    private func durationChip(_ duration: TimeInterval) -> some View {
        let isActive = abs((vm.selectedDurationClip?.duration ?? 0) - duration) < 0.05
        return Button {
            guard let id = vm.selectedOverlayClipID ?? vm.selectedClipID else { return }
            vm.commitPhotoDuration(clipID: id, duration: duration)
        } label: {
            Text(formatted(duration))
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(isActive ? .black : .white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule().fill(isActive ? Color.appColors.primaryColor : Color.white.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Set photo duration to \(formatted(duration))")
    }

    private var durationSlider: some View {
        Slider(
            value: durationBinding,
            in: EditorClip.photoMinimumDuration...EditorClip.photoMaximumDuration,
            step: 0.5,
            label: { Text("Photo duration") },
            minimumValueLabel: {
                Text("0.5 s").font(.system(size: 10)).foregroundColor(.white.opacity(0.5))
            },
            maximumValueLabel: {
                Text("30 s").font(.system(size: 10)).foregroundColor(.white.opacity(0.5))
            },
            onEditingChanged: finishSliderEdit
        )
        .tint(Color.appColors.primaryColor)
    }

    private var durationBinding: Binding<Double> {
        Binding(
            get: { vm.selectedDurationClip?.duration ?? EditorClip.photoDefaultDuration },
            set: { duration in
                guard let id = vm.selectedOverlayClipID ?? vm.selectedClipID else { return }
                vm.setPhotoDuration(clipID: id, duration: duration)
            }
        )
    }

    private func finishSliderEdit(_ isEditing: Bool) {
        guard !isEditing,
              let id = vm.selectedOverlayClipID ?? vm.selectedClipID,
              let duration = vm.selectedDurationClip?.duration else { return }
        vm.commitPhotoDuration(clipID: id, duration: duration)
    }

    private func formatted(_ duration: TimeInterval) -> String {
        duration.rounded() == duration
            ? String(format: "%.0f s", duration)
            : String(format: "%.1f s", duration)
    }
}

struct CropReframeToolPanel: View {
    let vm: EditorViewModel

    private var clip: EditorClip? { vm.selectedReframeClip }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("Crop & Reframe")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                    Button("Reset") {
                        vm.resetSelectedClipReframe()
                        vm.commitSelectedClipReframe()
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color.appColors.primaryColor)
                }

                if let clip {
                    modePicker(clip)
                    aspectPicker(clip)
                    transformButtons(clip)
                    valueSlider(
                        title: "Straighten",
                        valueText: String(format: "%.1f°", clip.straightenDegrees),
                        value: Binding(
                            get: { clip.straightenDegrees },
                            set: { vm.setSelectedClipStraighten($0) }
                        ),
                        range: -45...45,
                        step: 0.5
                    )
                    valueSlider(
                        title: "Scale",
                        valueText: String(format: "%.0f%%", clip.reframeScale * 100),
                        value: Binding(
                            get: { Double(clip.reframeScale) },
                            set: { vm.setSelectedClipReframeScale(CGFloat($0)) }
                        ),
                        range: 0.5...4,
                        step: 0.01
                    )

                    Toggle("Safe-area and rule-of-thirds guides", isOn: Binding(
                        get: { vm.showsReframeSafeAreaGuides },
                        set: { vm.showsReframeSafeAreaGuides = $0 }
                    ))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .tint(Color.appColors.primaryColor)

                    Text("Drag the preview to reposition. Pinch the preview to zoom.")
                        .font(.system(size: 11))
                        .foregroundColor(Color.white.opacity(0.55))
                } else {
                    Text("Select a clip to crop or reframe it.")
                        .foregroundColor(Color.white.opacity(0.6))
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 20)
        }
    }

    private func modePicker(_ clip: EditorClip) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Background framing")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color.white.opacity(0.7))
            Picker("Background framing", selection: Binding(
                get: { clip.reframeMode },
                set: { mode in
                    vm.setSelectedClipReframeMode(mode)
                    vm.commitSelectedClipReframe()
                }
            )) {
                ForEach(EditorReframeMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private func aspectPicker(_ clip: EditorClip) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Crop aspect")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color.white.opacity(0.7))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(EditorCropAspect.allCases) { aspect in
                        Button {
                            vm.setSelectedClipCropAspect(aspect)
                            vm.commitSelectedClipReframe()
                        } label: {
                            Text(aspect.title)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(clip.cropAspect == aspect ? .black : .white)
                                .padding(.horizontal, 13)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule().fill(
                                        clip.cropAspect == aspect
                                            ? Color.appColors.primaryColor
                                            : Color.white.opacity(0.08)
                                    )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func transformButtons(_ clip: EditorClip) -> some View {
        HStack(spacing: 10) {
            transformButton(title: "Rotate", image: "rotate.right") {
                vm.rotateSelectedClipClockwise()
                vm.commitSelectedClipReframe()
            }
            transformButton(
                title: "Flip H",
                image: "arrow.left.and.right.righttriangle.left.righttriangle.right",
                selected: clip.isFlippedHorizontally
            ) {
                vm.toggleSelectedClipHorizontalFlip()
                vm.commitSelectedClipReframe()
            }
            transformButton(
                title: "Flip V",
                image: "arrow.up.and.down.righttriangle.up.righttriangle.down",
                selected: clip.isFlippedVertically
            ) {
                vm.toggleSelectedClipVerticalFlip()
                vm.commitSelectedClipReframe()
            }
            transformButton(title: "Center", image: "scope") {
                vm.centerSelectedClipReframe()
                vm.commitSelectedClipReframe()
            }
        }
    }

    private func transformButton(
        title: String,
        image: String,
        selected: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: image).font(.system(size: 16, weight: .semibold))
                Text(title).font(.system(size: 10, weight: .semibold))
            }
            .foregroundColor(selected ? Color.appColors.primaryColor : .white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.07)))
        }
        .buttonStyle(.plain)
    }

    private func valueSlider(
        title: String,
        valueText: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double
    ) -> some View {
        VStack(spacing: 6) {
            HStack {
                Text(title).font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(valueText).font(.system(size: 12, weight: .bold).monospacedDigit())
                    .foregroundColor(Color.appColors.primaryColor)
            }
            .foregroundColor(.white)
            Slider(value: value, in: range, step: step) { Text(title) } onEditingChanged: { editing in
                if !editing { vm.commitSelectedClipReframe() }
            }
            .tint(Color.appColors.primaryColor)
        }
    }
}
