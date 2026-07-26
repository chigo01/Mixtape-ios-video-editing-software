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

    var body: some View {
        HStack(spacing: 8) {
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
