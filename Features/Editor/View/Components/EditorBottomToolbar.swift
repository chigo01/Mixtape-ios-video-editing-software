//
//  EditorBottomToolbar.swift
//  Mixtape
//
//  Created by Favour Baruch on 14/05/2026.
//

import SwiftUI
import PhotosUI

struct EditorBottomToolbar: View {
    let vm: EditorViewModel
    var isOverlayMode = false
    var onAddOverlay: () -> Void = {}

    var body: some View {
        GeometryReader { geometry in
            let tools = EditorTool.mainTools
            let itemWidth = max(68, geometry.size.width / CGFloat(max(tools.count, 1)))
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(tools) { tool in
                        ToolButton(
                            tool: tool,
                            isSelected: vm.selectedTool == tool || (tool == .overlay && isOverlayMode)
                        ) {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                if tool == .overlay {
                                    onAddOverlay()
                                } else {
                                    vm.performToolAction(tool)
                                }
                            }
                        }
                        .frame(width: itemWidth)
                    }
                }
                .frame(minWidth: geometry.size.width, alignment: .leading)
            }
        }
        .frame(height: 62)
        .padding(.horizontal, 4)
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

private struct ToolButton: View {
    let tool: EditorTool
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: tool.systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(isSelected ? Color.appColors.primaryColor : .white)
                Text(tool.title)
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.5)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .foregroundColor(isSelected ? Color.appColors.primaryColor : Color.white.opacity(0.75))
            }
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .center)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tool.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
