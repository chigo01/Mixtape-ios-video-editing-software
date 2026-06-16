//
//  EditorTextOverlayLayerView.swift
//  Mixtape
//
//  Shared component to render text overlays over the video preview.
//

import SwiftUI

struct EditorTextOverlayLayerView: View {
    let vm: EditorViewModel

    @State private var isPositionDragging = false

    private var visibleOverlays: [EditorTextOverlay] {
        vm.textOverlays.filter { $0.isVisible(at: vm.timelinePosition) }
    }

    var body: some View {
        ZStack {
            ForEach(visibleOverlays) { overlay in
                textOverlayView(overlay)
                    .allowsHitTesting(vm.selectedTextOverlayID == overlay.id)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(12)
    }

    private func textOverlayView(_ overlay: EditorTextOverlay) -> some View {
        let isSelected = vm.selectedTextOverlayID == overlay.id

        return VStack {
            if overlay.verticalAlignment != .top {
                Spacer(minLength: 0)
            }

            HStack {
                if overlay.horizontalAlignment != .leading {
                    Spacer(minLength: 0)
                }

                draggableTextContent(overlay, isSelected: isSelected)

                if overlay.horizontalAlignment != .trailing {
                    Spacer(minLength: 0)
                }
            }

            if overlay.verticalAlignment != .bottom {
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder
    private func draggableTextContent(_ overlay: EditorTextOverlay, isSelected: Bool) -> some View {
        let content = styledTextView(overlay)
            .offset(x: overlay.xOffset, y: overlay.yOffset)
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(
                        isSelected ? Color.appColors.primaryColor : Color.clear,
                        lineWidth: 1.5
                    )
                    .padding(-4)
                    .offset(x: overlay.xOffset, y: overlay.yOffset)
            )
            .contentShape(Rectangle())

        if isSelected {
            content.gesture(positionDragGesture(for: overlay))
        } else {
            content
        }
    }

    private func positionDragGesture(for overlay: EditorTextOverlay) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if !isPositionDragging {
                    isPositionDragging = true
                    vm.beginTextOverlayPositionDrag(id: overlay.id)
                }
                vm.updateTextOverlayPositionDrag(id: overlay.id, translation: value.translation)
            }
            .onEnded { _ in
                isPositionDragging = false
                vm.commitTextOverlayPositionDrag()
            }
    }

    @ViewBuilder
    private func styledTextView(_ overlay: EditorTextOverlay) -> some View {
        let baseText = Text(overlay.text)
            .font(overlay.resolvedFont())
            .multilineTextAlignment(overlay.horizontalAlignment.alignment)
            .opacity(overlay.opacity)

        switch overlay.fontStyle {
        case .plain, .bold, .italic:
            baseText
                .foregroundColor(overlay.textColor.color)

        case .outlined:
            baseText
                .foregroundColor(overlay.textColor.color)
                .shadow(color: .black, radius: 0, x: 1, y: 1)
                .shadow(color: .black, radius: 0, x: -1, y: -1)
                .shadow(color: .black, radius: 0, x: 1, y: -1)
                .shadow(color: .black, radius: 0, x: -1, y: 1)

        case .shadow:
            baseText
                .foregroundColor(overlay.textColor.color)
                .shadow(color: .black.opacity(0.7), radius: 4, x: 2, y: 2)

        case .background:
            baseText
                .foregroundColor(overlay.textColor.color)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.black.opacity(0.6))
                )
        }
    }
}
