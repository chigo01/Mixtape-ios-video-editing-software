//
//  VolumeToolPanel.swift
//  Mixtape
//

import SwiftUI

struct VolumeToolPanel: View {
    let vm: EditorViewModel

    private let presets: [(label: String, value: Float)] = [
        ("0%", 0.0),
        ("25%", 0.25),
        ("50%", 0.5),
        ("75%", 0.75),
        ("100%", 1.0)
    ]

    private var activeVolume: Float? {
        if let audio = vm.selectedAudioClip { return audio.volume }
        if let clip = vm.selectedClip { return clip.volume }
        return nil
    }

    private var hasSelection: Bool {
        vm.selectedAudioClip != nil || vm.selectedClip != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Volume")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                if let volume = activeVolume {
                    Text("\(Int(volume * 100))%")
                        .font(.system(size: 13, weight: .bold).monospacedDigit())
                        .foregroundColor(Color.appColors.primaryColor)
                }
            }

            if !hasSelection {
                Text("Select a clip or audio track to change volume.")
                    .font(.system(size: 12))
                    .foregroundColor(Color.white.opacity(0.55))
            } else {
                HStack(spacing: 8) {
                    ForEach(presets, id: \.label) { preset in
                        volumeChip(preset)
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        guard let volume = activeVolume else { return }
                        applyVolume(volume > 0 ? 0 : 1.0, commit: true)
                    } label: {
                        Image(systemName: (activeVolume ?? 1) > 0
                              ? "speaker.wave.2.fill"
                              : "speaker.slash.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor((activeVolume ?? 1) > 0
                                            ? .white
                                            : Color.appColors.primaryColor)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 28)

                    Slider(
                        value: Binding(
                            get: { Double(activeVolume ?? 1) },
                            set: { applyVolume(Float($0), commit: false) }
                        ),
                        in: 0.0...1.0,
                        step: 0.01
                    ) {
                        Text("Volume")
                    } minimumValueLabel: {
                        Text("0").font(.system(size: 10)).foregroundColor(.white.opacity(0.5))
                    } maximumValueLabel: {
                        Text("100").font(.system(size: 10)).foregroundColor(.white.opacity(0.5))
                    } onEditingChanged: { isEditing in
                        guard !isEditing, let volume = activeVolume else { return }
                        applyVolume(volume, commit: true)
                    }
                    .tint(Color.appColors.primaryColor)
                    .disabled(!hasSelection)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 16)
    }

    private func volumeChip(_ preset: (label: String, value: Float)) -> some View {
        let isActive = abs((activeVolume ?? 1) - preset.value) < 0.02
        return Button {
            applyVolume(preset.value, commit: true)
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

    private func applyVolume(_ volume: Float, commit: Bool) {
        if let id = vm.selectedAudioClipID {
            if commit {
                vm.commitAudioVolume(clipID: id, volume: volume)
            } else {
                vm.setAudioVolume(clipID: id, volume: volume)
            }
        } else if let id = vm.selectedClipID {
            if commit {
                vm.commitVolume(clipID: id, volume: volume)
            } else {
                vm.setVolume(clipID: id, volume: volume)
            }
        }
    }
}
