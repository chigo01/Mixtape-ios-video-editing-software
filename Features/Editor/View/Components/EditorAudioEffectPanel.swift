//
//  EditorAudioEffectPanel.swift
//  Mixtape
//
//  Priority 15 audio effects — CapCut-style voice/sound presets for the selected audio clip,
//  split into Filters / Characters tabs the same way CapCut's own "Voice filters" / "Voice
//  characters" tabs are. "Original" (`.none`) is pinned as the first cell in both tabs rather
//  than living behind a separate Reset button, matching CapCut's layout. Tapping a preset renders
//  it once (offline, cached — see `EditorAudioEffectRenderer`) and the effect becomes audible on
//  the next composition rebuild, so this panel doubles as its own live audition.
//

import SwiftUI

struct EditorAudioEffectPanel: View {
    let vm: EditorViewModel

    @State private var selectedCategory: EditorAudioEffect.Category = .filters

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Effects")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)

            if let clip = vm.selectedAudioClip {
                categoryTabs
                ScrollView {
                    grid(for: clip)
                        .padding(.top, 2)
                }
            } else {
                Text("Select an audio clip to apply an effect.")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.55))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 20)
        .alert(
            "Couldn't apply effect",
            isPresented: Binding(
                get: { vm.audioEffectErrorMessage != nil },
                set: { if !$0 { vm.audioEffectErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(vm.audioEffectErrorMessage ?? "")
        }
    }

    private var categoryTabs: some View {
        HStack(spacing: 8) {
            ForEach(EditorAudioEffect.Category.allCases) { category in
                Button {
                    selectedCategory = category
                } label: {
                    Text(category.rawValue)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(selectedCategory == category ? .black : .white.opacity(0.7))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(
                                selectedCategory == category
                                    ? Color.appColors.primaryColor
                                    : Color.white.opacity(0.08)
                            )
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    private func grid(for clip: EditorAudioClip) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 12)], spacing: 14) {
            cell(.none, clip: clip)
            ForEach(EditorAudioEffect.allCases.filter { $0 != .none && $0.category == selectedCategory }) { effect in
                cell(effect, clip: clip)
            }
        }
    }

    private func cell(_ effect: EditorAudioEffect, clip: EditorAudioClip) -> some View {
        let isSelected = clip.effect == effect
        let isRendering = vm.renderingAudioEffectClipID == clip.id && vm.renderingAudioEffect == effect
        let isBusy = vm.renderingAudioEffectClipID != nil

        return Button {
            vm.setAudioClipEffect(clipID: clip.id, effect: effect)
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.appColors.primaryColor : Color.white.opacity(0.08))
                        .frame(width: 52, height: 52)
                    if isRendering {
                        ProgressView()
                            .tint(isSelected ? .black : .white)
                    } else {
                        Image(systemName: effect.systemImage)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(isSelected ? .black : .white.opacity(0.85))
                    }
                }
                Text(effect.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isSelected ? Color.appColors.primaryColor : .white.opacity(0.7))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .opacity(isBusy && !isRendering ? 0.4 : 1)
    }
}
