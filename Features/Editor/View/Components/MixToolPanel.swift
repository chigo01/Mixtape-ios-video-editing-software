//
//  MixToolPanel.swift
//  Mixtape
//
//  Priority 13 gain staging (master volume + one gain/mute row per audio track) plus Priority
//  15's mixer follow-up items that were cheap to add on top of it — solo and track-header
//  naming, both pure reuses of the existing `EditorAudioTrackSettings` plumbing. Still
//  deliberately not a full mixer strip: pan, routing/buses, and write/read/bypass automation are
//  out of scope — see the Priority 15 writeup in the README for why. Applies on composition/
//  export via `EditorCompositionBuilder`'s `audioTrackSettings` + `masterVolume` parameters.
//

import SwiftUI

struct MixToolPanel: View {
    let vm: EditorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Mix")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)

            masterRow

            if vm.audioLaneIndices.isEmpty {
                Text("Add background audio to get a per-track gain control here.")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.55))
            } else {
                Divider().overlay(Color.white.opacity(0.08))
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(Array(vm.audioLaneIndices.enumerated()), id: \.element) { index, laneIndex in
                            MixTrackRow(vm: vm, laneIndex: laneIndex, displayNumber: index + 1)
                        }
                    }
                }
                .frame(maxHeight: 180)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 20)
    }

    private var masterRow: some View {
        MixGainRow(
            title: "Master",
            systemImage: "speaker.wave.3.fill",
            gain: vm.masterVolume,
            isMuted: false,
            isSoloed: false,
            showsMuteAndSolo: false,
            onMuteToggle: {},
            onSoloToggle: {},
            onChange: { vm.setMasterVolume($0) },
            onCommit: { vm.commitMixChange() }
        )
    }
}

/// One track row: rename-on-tap title, mute, solo, gain slider. A real `View` (not a function
/// returning `some View`) so its rename `@State` has stable per-row identity across `ForEach`
/// updates.
private struct MixTrackRow: View {
    let vm: EditorViewModel
    let laneIndex: Int
    let displayNumber: Int

    @State private var isRenaming = false
    @State private var draftName = ""
    @FocusState private var isNameFieldFocused: Bool

    private var settings: EditorAudioTrackSettings {
        vm.audioTrackSettings(forLane: laneIndex)
    }

    private var displayName: String {
        settings.name ?? "Track \(displayNumber)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            nameRow
            MixGainRow(
                title: displayName,
                systemImage: "music.note",
                gain: settings.gain,
                isMuted: settings.isMuted,
                isSoloed: settings.isSoloed,
                showsMuteAndSolo: true,
                showsTitleText: false,
                onMuteToggle: { vm.toggleAudioTrackMute(laneIndex: laneIndex) },
                onSoloToggle: { vm.toggleAudioTrackSolo(laneIndex: laneIndex) },
                onChange: { vm.setAudioTrackGain(laneIndex: laneIndex, gain: $0) },
                onCommit: { vm.commitMixChange() }
            )
        }
    }

    private var nameRow: some View {
        HStack(spacing: 6) {
            if isRenaming {
                TextField("Track name", text: $draftName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .focused($isNameFieldFocused)
                    .submitLabel(.done)
                    .onSubmit { commitRename() }
                    .onAppear {
                        draftName = settings.name ?? ""
                        isNameFieldFocused = true
                    }
                Button("Done") { commitRename() }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color.appColors.primaryColor)
            } else {
                Button {
                    isRenaming = true
                } label: {
                    HStack(spacing: 4) {
                        Text(displayName)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                        Image(systemName: "pencil")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.white.opacity(0.4))
                    }
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
            }
        }
    }

    private func commitRename() {
        vm.setAudioTrackName(laneIndex: laneIndex, name: draftName)
        isRenaming = false
    }
}

/// Shared row layout for the master fader and every track fader — icon/mute, optional solo,
/// gain slider, percentage readout.
private struct MixGainRow: View {
    let title: String
    let systemImage: String
    let gain: Float
    let isMuted: Bool
    let isSoloed: Bool
    let showsMuteAndSolo: Bool
    var showsTitleText: Bool = true
    let onMuteToggle: () -> Void
    let onSoloToggle: () -> Void
    let onChange: (Float) -> Void
    let onCommit: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if showsMuteAndSolo {
                Button(action: onMuteToggle) {
                    Image(systemName: isMuted ? "speaker.slash.fill" : systemImage)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(isMuted ? Color.appColors.primaryColor : .white.opacity(0.8))
                        .frame(width: 20)
                }
                .buttonStyle(.plain)

                Button(action: onSoloToggle) {
                    Text("S")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(isSoloed ? .black : .white.opacity(0.6))
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(isSoloed ? Color.appColors.primaryColor : Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Solo \(title)")
            } else {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.8))
                    .frame(width: 20)
            }

            if showsTitleText {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                    .frame(width: 56, alignment: .leading)
            }

            Slider(
                value: Binding(
                    get: { Double(gain) },
                    set: { onChange(Float($0)) }
                ),
                in: 0...1,
                step: 0.01
            ) {
                Text(title)
            } onEditingChanged: { isEditing in
                guard !isEditing else { return }
                onCommit()
            }
            .tint(Color.appColors.primaryColor)
            .disabled(isMuted)
            .opacity(isMuted ? 0.4 : 1)

            Text("\(Int(gain * 100))%")
                .font(.system(size: 12, weight: .bold).monospacedDigit())
                .foregroundColor(Color.appColors.primaryColor)
                .frame(width: 36, alignment: .trailing)
        }
    }
}
