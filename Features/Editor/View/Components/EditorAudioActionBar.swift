//
//  EditorAudioActionBar.swift
//  Mixtape
//
//  CapCut-style contextual toolbar when an audio clip is selected.
//

import SwiftUI

enum EditorAudioAction: String, CaseIterable, Identifiable {
    case split
    case volume
    case delete

    var id: String { rawValue }

    var title: String {
        switch self {
        case .split: return "SPLIT"
        case .volume: return "VOLUME"
        case .delete: return "DELETE"
        }
    }

    var systemImage: String {
        switch self {
        case .split: return "scissors"
        case .volume: return "speaker.wave.2.fill"
        case .delete: return "trash"
        }
    }

    var isDestructive: Bool { self == .delete }
}

struct EditorAudioActionBar: View {
    let vm: EditorViewModel

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

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(EditorAudioAction.allCases) { action in
                        AudioActionButton(
                            action: action,
                            isSelected: action == .volume && vm.selectedTool == .volume,
                            isDisabled: action == .delete && vm.selectedAudioClip == nil
                        ) {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                vm.performAudioAction(action)
                            }
                        }
                    }
                }
                .padding(.trailing, 8)
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
                    .foregroundColor(
                        isDisabled
                            ? Color.white.opacity(0.25)
                            : (isSelected ? Color.appColors.primaryColor : Color.white.opacity(0.75))
                    )
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityLabel(action.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
