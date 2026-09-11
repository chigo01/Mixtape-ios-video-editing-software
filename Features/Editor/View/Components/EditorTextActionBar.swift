//
//  EditorTextActionBar.swift
//  Mixtape
//

import SwiftUI

struct EditorTextActionBar: View {
    let vm: EditorViewModel
    var onBack: () -> Void = {}

    var body: some View {
        HStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    vm.dismissTextEditor()
                    vm.selectedTextOverlayID = nil
                    onBack()
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ClipActionButton(
                        action: .text,
                        isSelected: vm.isTextEditorPresented,
                        isDisabled: false
                    ) {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            vm.performToolAction(.text)
                        }
                    }

                    ClipActionButton(
                        action: .keyframe,
                        isSelected: vm.selectedTool == .keyframe,
                        isDisabled: false
                    ) {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            vm.performToolAction(.keyframe)
                        }
                    }

                    ClipActionButton(
                        action: .track,
                        isSelected: vm.selectedTool == .track,
                        isDisabled: false
                    ) {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            vm.performToolAction(.track)
                        }
                    }

                    ClipActionButton(
                        action: .duplicate,
                        isSelected: false,
                        isDisabled: false
                    ) {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            vm.duplicateSelectedTextOverlay()
                        }
                    }

                    ClipActionButton(
                        action: .delete,
                        isSelected: false,
                        isDisabled: false
                    ) {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            if let id = vm.selectedTextOverlayID {
                                vm.deleteTextOverlay(id: id)
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }
        }
        .frame(height: 60)
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
