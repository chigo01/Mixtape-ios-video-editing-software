//
//  EditorClipActionBar.swift
//  Mixtape
//
//  CapCut-style contextual toolbar shown when a timeline clip is selected.
//

import SwiftUI

enum EditorClipAction: String, CaseIterable, Identifiable {
    case split
    case speed
    case duration
    case volume
    case filter
    case text
    case delete

    var id: String { rawValue }

    var title: String {
        switch self {
        case .split: return "SPLIT"
        case .speed: return "SPEED"
        case .duration: return "DURATION"
        case .volume: return "VOLUME"
        case .filter: return "FILTER"
        case .text: return "TEXT"
        case .delete: return "DELETE"
        }
    }

    var systemImage: String {
        switch self {
        case .split: return "scissors"
        case .speed: return "speedometer"
        case .duration: return "timer"
        case .volume: return "speaker.wave.2.fill"
        case .filter: return "slider.horizontal.3"
        case .text: return "textformat"
        case .delete: return "trash"
        }
    }

    var isDestructive: Bool { self == .delete }
}

struct EditorClipActionBar: View {
    let vm: EditorViewModel

    private var availableActions: [EditorClipAction] {
        EditorClipAction.allCases.filter { action in
            action != .duration || vm.selectedClip?.isPhoto == true
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    vm.deselectClip()
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
                    ForEach(availableActions) { action in
                        ClipActionButton(
                            action: action,
                            isSelected: action.tool.map { vm.selectedTool == $0 } ?? false,
                            isDisabled: action == .delete && !vm.canDeleteSelectedClip
                        ) {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                vm.performClipAction(action)
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

extension EditorClipAction {
    var tool: EditorTool? {
        switch self {
        case .split: return .split
        case .speed: return .speed
        case .duration: return .duration
        case .volume: return .volume
        case .filter: return .filter
        case .text: return .text
        case .delete: return nil
        }
    }
}

struct ClipActionButton: View {
    let action: EditorClipAction
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
