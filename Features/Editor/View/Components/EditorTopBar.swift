//
//  EditorTopBar.swift
//  Mixtape
//
//  Created by Favour Baruch on 14/05/2026.
//

import SwiftUI

struct EditorTopBar: View {
    var onBack: () -> Void
    var onExport: () -> Void = {}
    var onCopilot: () -> Void = {}

    var body: some View {
        HStack {
            Button(action: onBack) {
                Image(systemName: "arrow.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(Color.appColors.primaryColor)
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")

            Spacer(minLength: 0)

            Button(action: onCopilot) {
                Label(EditorCopilotService.productName, systemImage: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.appColors.primaryColor)
                    .padding(.horizontal, 10)
                    .frame(minHeight: 40)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open MixPilot")

            Button(action: onExport) {
                Text("Export")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(Color.appColors.primaryColor))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Export")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

struct EditorTimelineControls: View {
    var onUndo: () -> Void
    var onRedo: () -> Void
    var canUndo: Bool
    var canRedo: Bool
    var isMultiSelectMode: Bool = false
    var selectionCount: Int = 0
    var activeSequenceName: String?
    var onToggleMultiSelect: () -> Void = {}
    var onAddMarker: () -> Void = {}
    var onExitSequence: () -> Void = {}

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onToggleMultiSelect) {
                HStack(spacing: 5) {
                    Image(systemName: isMultiSelectMode ? "checkmark.circle.fill" : "checkmark.circle")
                    if isMultiSelectMode {
                        Text("\(selectionCount)")
                            .font(.caption.bold().monospacedDigit())
                    }
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isMultiSelectMode ? Color.appColors.primaryColor : .white)
                .frame(minWidth: 36, minHeight: 36)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isMultiSelectMode ? "Finish selecting" : "Select multiple items")

            Button(action: onAddMarker) {
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add marker at playhead")

            if let activeSequenceName {
                Button(action: onExitSequence) {
                    Label(activeSequenceName, systemImage: "arrow.turn.up.left")
                        .font(.caption.bold())
                        .foregroundStyle(Color.appColors.primaryColor)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Exit \(activeSequenceName)")
            }

            Spacer(minLength: 0)

            Button(action: onUndo) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(canUndo ? .white : Color.white.opacity(0.25))
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .disabled(!canUndo)
            .accessibilityLabel("Undo")

            Button(action: onRedo) {
                Image(systemName: "arrow.uturn.forward")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(canRedo ? .white : Color.white.opacity(0.25))
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .disabled(!canRedo)
            .accessibilityLabel("Redo")
        }
        .padding(.horizontal, 12)
    }
}
