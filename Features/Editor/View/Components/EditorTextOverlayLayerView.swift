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

    var body: some View {
        GeometryReader { geometry in
            let canvasScale = EditorTextOverlayLayout.canvasScale(for: geometry.size)
            let referenceCanvas = EditorTextOverlayLayout.referenceCanvasSize(
                matching: geometry.size
            )
            let visibleOverlays = vm.textOverlays
                .filter { $0.isVisible(at: vm.timelinePosition) }
                .map {
                    vm.resolvedTextOverlay(
                        $0,
                        at: vm.timelinePosition,
                        canvasSize: referenceCanvas
                    )
                }
            ZStack {
                ForEach(visibleOverlays) { overlay in
                    textOverlayView(overlay, canvasScale: canvasScale)
                        .allowsHitTesting(
                            vm.selectedTool != .track
                                && vm.selectedTextOverlayID == overlay.id
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(EditorTextOverlayLayout.previewPadding * canvasScale)
            .coordinateSpace(name: EditorTextOverlayLayout.canvasSpaceName)
        }
    }

    private func textOverlayView(
        _ overlay: EditorTextOverlay,
        canvasScale: CGFloat
    ) -> some View {
        let isSelected = vm.selectedTextOverlayID == overlay.id

        return VStack {
            if overlay.verticalAlignment != .top {
                Spacer(minLength: 0)
                    .allowsHitTesting(false)
            }

            HStack {
                if overlay.horizontalAlignment != .leading {
                    Spacer(minLength: 0)
                        .allowsHitTesting(false)
                }

                draggableTextContent(
                    overlay,
                    isSelected: isSelected,
                    canvasScale: canvasScale
                )

                if overlay.horizontalAlignment != .trailing {
                    Spacer(minLength: 0)
                        .allowsHitTesting(false)
                }
            }

            if overlay.verticalAlignment != .bottom {
                Spacer(minLength: 0)
                    .allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder
    private func draggableTextContent(
        _ overlay: EditorTextOverlay,
        isSelected: Bool,
        canvasScale: CGFloat
    ) -> some View {
        // Hit shape and selection chrome are applied *before* offset so they
        // travel with the glyphs. Applying `contentShape` after offset pinned
        // the drag target to the un-offset alignment slot.
        let content = styledTextView(overlay, canvasScale: canvasScale)
            .rotationEffect(
                .degrees(
                    overlay.keyframes.value(
                        for: .textRotation,
                        at: max(0, vm.timelinePosition - overlay.startTime),
                        default: 0
                    ) + overlay.trackedRotationDegrees
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(
                        isSelected && vm.selectedTool != .track
                            ? Color.appColors.primaryColor
                            : Color.clear,
                        lineWidth: 1.5
                    )
                    .padding(-4)
            )
            .contentShape(Rectangle().inset(by: -16))
            .offset(x: overlay.xOffset * canvasScale, y: overlay.yOffset * canvasScale)

        if isSelected {
            content.highPriorityGesture(
                positionDragGesture(for: overlay, canvasScale: canvasScale)
            )
        } else {
            content
        }
    }

    private func positionDragGesture(
        for overlay: EditorTextOverlay,
        canvasScale: CGFloat
    ) -> some Gesture {
        DragGesture(
            minimumDistance: 1,
            coordinateSpace: .named(EditorTextOverlayLayout.canvasSpaceName)
        )
        .onChanged { value in
            if !isPositionDragging {
                isPositionDragging = true
                vm.beginTextOverlayPositionDrag(id: overlay.id)
            }
            vm.updateTextOverlayPositionDrag(
                id: overlay.id,
                translation: value.translation,
                canvasScale: canvasScale
            )
        }
        .onEnded { _ in
            isPositionDragging = false
            vm.commitTextOverlayPositionDrag()
        }
    }

    @ViewBuilder
    private func styledTextView(
        _ overlay: EditorTextOverlay,
        canvasScale: CGFloat
    ) -> some View {
        let baseText = Text(overlay.text)
            .font(overlay.resolvedFont(sizeScale: canvasScale))
            .multilineTextAlignment(overlay.horizontalAlignment.alignment)
            .opacity(overlay.opacity)

        switch overlay.fontStyle {
        case .plain, .bold, .italic:
            baseText
                .foregroundColor(overlay.textColor.color)

        case .outlined:
            baseText
                .foregroundColor(overlay.textColor.color)
                .shadow(color: .black, radius: 0, x: canvasScale, y: canvasScale)
                .shadow(color: .black, radius: 0, x: -canvasScale, y: -canvasScale)
                .shadow(color: .black, radius: 0, x: canvasScale, y: -canvasScale)
                .shadow(color: .black, radius: 0, x: -canvasScale, y: canvasScale)

        case .shadow:
            baseText
                .foregroundColor(overlay.textColor.color)
                .shadow(
                    color: .black.opacity(0.7),
                    radius: 4 * canvasScale,
                    x: 2 * canvasScale,
                    y: 2 * canvasScale
                )

        case .background:
            baseText
                .foregroundColor(overlay.textColor.color)
                .padding(.horizontal, 8 * canvasScale)
                .padding(.vertical, 4 * canvasScale)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.black.opacity(0.6))
                )
        }
    }
}
