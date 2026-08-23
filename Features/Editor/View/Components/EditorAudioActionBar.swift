//
//  EditorAudioActionBar.swift
//  Mixtape
//
//  CapCut-style contextual toolbar when an audio clip is selected.
//

import SwiftUI

enum EditorAudioAction: String, CaseIterable, Identifiable {
    case add
    case split
    case volume
    case keyframe
    case punchIn
    case effects
    case duplicate
    case delete

    var id: String { rawValue }

    var title: String {
        switch self {
        case .add: return "ADD AUDIO"
        case .split: return "SPLIT"
        case .volume: return "VOLUME"
        case .keyframe: return "KEYFRAME"
        case .punchIn: return "PUNCH IN"
        case .effects: return "EFFECTS"
        case .duplicate: return "DUPLICATE"
        case .delete: return "DELETE"
        }
    }

    var systemImage: String {
        switch self {
        case .add: return "plus.circle.fill"
        case .split: return "scissors"
        case .volume: return "speaker.wave.2.fill"
        case .keyframe: return "diamond.fill"
        case .punchIn: return "mic.badge.plus"
        case .effects: return "waveform.badge.magnifyingglass"
        case .duplicate: return "plus.square.on.square"
        case .delete: return "trash"
        }
    }

    var isDestructive: Bool { self == .delete }
}

struct EditorAudioActionBar: View {
    let vm: EditorViewModel
    /// Opens the same "Browse Sound Library" / "Import from Files" chooser as the timeline's own
    /// **+** buttons, always inserting a new track at the current playhead — reachable from here
    /// too so adding another sound doesn't require deselecting the current clip first.
    var onAddAudio: () -> Void = {}

    var body: some View {
        HStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    vm.deselectAudioClip()
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to main tools")

            if isMarkingPunchIn {
                punchInMarkingRow
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(EditorAudioAction.allCases) { action in
                            AudioActionButton(
                                action: action,
                                isSelected: (action == .volume && vm.selectedTool == .volume)
                                    || (action == .keyframe && vm.selectedTool == .keyframe)
                                    || (action == .effects && vm.selectedTool == .audioEffect),
                                isDisabled: action == .delete && vm.selectedAudioClip == nil
                            ) {
                                if action == .add {
                                    onAddAudio()
                                    return
                                }
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    vm.performAudioAction(action)
                                }
                            }
                        }
                    }
                    .padding(.trailing, 8)
                }
            }
        }
        .padding(.leading, 4)
        .padding(.top, 12)
        .padding(.bottom, 18)
        .background(
            Rectangle()
                .fill(Color.white.opacity(0.02))
                .overlay(
                    Rectangle()
                        .frame(height: 0.5)
                        .foregroundColor(Color.white.opacity(0.06)),
                    alignment: .top
                )
        )
    }

    private var isMarkingPunchIn: Bool {
        vm.punchInClipID != nil && vm.punchInClipID == vm.selectedAudioClipID
    }

    /// Shown in place of the normal action grid between the two punch-in taps: the in-point is
    /// already marked (first tap), and this is where scrubbing to the out-point and confirming
    /// or backing out happens — same bottom-bar-swap pattern the editor already uses for
    /// clip/text/audio selection (see README §6.8), just one level deeper.
    private var punchInMarkingRow: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("In marked at \(formattedTime(vm.punchInStartTime ?? 0))")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                Text("Scrub to the out point, then tap Set Out")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.55))
            }
            Spacer(minLength: 8)
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    vm.cancelPunchInMark()
                }
            } label: {
                Text("Cancel")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    vm.togglePunchInMark()
                }
            } label: {
                Text("Set Out")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.appColors.primaryColor))
            }
            .buttonStyle(.plain)
        }
        .padding(.trailing, 12)
    }

    private func formattedTime(_ time: TimeInterval) -> String {
        let total = max(0, Int(time.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private struct AudioActionButton: View {
    let action: EditorAudioAction
    let isSelected: Bool
    let isDisabled: Bool
    let onTap: () -> Void

    private var accentColor: Color {
        if action.isDestructive { return Color.red.opacity(0.9) }
        return isSelected ? Color.appColors.primaryColor : .white
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                Image(systemName: action.systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(isDisabled ? Color.white.opacity(0.25) : accentColor)
                Text(action.title)
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.5)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .foregroundColor(
                        isDisabled
                            ? Color.white.opacity(0.25)
                            : (isSelected ? Color.appColors.primaryColor : Color.white.opacity(0.75))
                    )
            }
            .padding(.vertical, 6)
            .frame(width: 78)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityLabel(action.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
