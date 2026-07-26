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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Speed")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                if let clip = vm.selectedClip {
                    Text(String(format: "%.2g×", clip.speed))
                        .font(.system(size: 13, weight: .bold).monospacedDigit())
                        .foregroundColor(Color.appColors.primaryColor)
                }
            }

            if vm.selectedClip == nil {
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
                        get: { Double(vm.selectedClip?.speed ?? 1) },
                        set: { vm.setSpeed(clipID: vm.selectedClipID!, speed: Float($0)) }
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
                .disabled(vm.selectedClipID == nil)
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
        let isActive = abs((vm.selectedClip?.speed ?? 1) - preset.value) < 0.02
        return Button {
            guard let id = vm.selectedClipID else { return }
            vm.commitSpeed(clipID: id, speed: preset.value)
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
        .disabled(vm.selectedClipID == nil)
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
                if let clip = vm.selectedClip, clip.isPhoto {
                    Text(formatted(clip.duration))
                        .font(.system(size: 13, weight: .bold).monospacedDigit())
                        .foregroundColor(Color.appColors.primaryColor)
                }
            }

            if vm.selectedClip?.isPhoto == true {
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
        let isActive = abs((vm.selectedClip?.duration ?? 0) - duration) < 0.05
        return Button {
            guard let id = vm.selectedClipID else { return }
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
            get: { vm.selectedClip?.duration ?? EditorClip.photoDefaultDuration },
            set: { duration in
                guard let id = vm.selectedClipID else { return }
                vm.setPhotoDuration(clipID: id, duration: duration)
            }
        )
    }

    private func finishSliderEdit(_ isEditing: Bool) {
        guard !isEditing,
              let id = vm.selectedClipID,
              let duration = vm.selectedClip?.duration else { return }
        vm.commitPhotoDuration(clipID: id, duration: duration)
    }

    private func formatted(_ duration: TimeInterval) -> String {
        duration.rounded() == duration
            ? String(format: "%.0f s", duration)
            : String(format: "%.1f s", duration)
    }
}
