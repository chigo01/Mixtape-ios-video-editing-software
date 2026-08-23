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
        let localTime = min(max(0, vm.timelinePosition - overlay.startTime), overlay.duration)
        let animation = overlay.animation.sample(localTime: localTime, duration: overlay.duration)
        let revealCount = overlay.isCaption ? overlay.captionWords.count : overlay.text.count
        let revealProgress = overlay.animation.revealProgress(
            localTime: localTime,
            itemCount: revealCount
        )
        // Hit shape and selection chrome are applied *before* offset so they
        // travel with the glyphs. Applying `contentShape` after offset pinned
        // the drag target to the un-offset alignment slot.
        let content = styledTextView(
            overlay,
            canvasScale: canvasScale,
            revealProgress: revealProgress
        )
            .blur(radius: CGFloat(animation.blurRadius) * canvasScale)
            .scaleEffect(CGFloat(animation.scale))
            .opacity(animation.opacity)
            .rotationEffect(
                .degrees(
                    overlay.keyframes.value(
                        for: .textRotation,
                        at: max(0, vm.timelinePosition - overlay.startTime),
                        default: 0
                    ) + overlay.trackedRotationDegrees + animation.rotationDegrees
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
            .offset(
                x: (overlay.xOffset + CGFloat(animation.xOffset)) * canvasScale,
                y: (overlay.yOffset + CGFloat(animation.yOffset)) * canvasScale
            )

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
        canvasScale: CGFloat,
        revealProgress: Double = 1
    ) -> some View {
        let baseText: Text = overlay.isCaption
            ? captionText(overlay, at: vm.timelinePosition, revealProgress: revealProgress)
            : Text(revealedText(overlay.text, progress: revealProgress))
        let styledBase = baseText
            .font(overlay.resolvedFont(sizeScale: canvasScale))
            .multilineTextAlignment(overlay.horizontalAlignment.alignment)
            .opacity(overlay.opacity)

        switch overlay.fontStyle {
        case .plain, .bold, .italic:
            styledBase
                .foregroundColor(overlay.isCaption ? nil : overlay.textColor.color)

        case .outlined:
            styledBase
                .foregroundColor(overlay.isCaption ? nil : overlay.textColor.color)
                .shadow(color: .black, radius: 0, x: canvasScale, y: canvasScale)
                .shadow(color: .black, radius: 0, x: -canvasScale, y: -canvasScale)
                .shadow(color: .black, radius: 0, x: canvasScale, y: -canvasScale)
                .shadow(color: .black, radius: 0, x: -canvasScale, y: canvasScale)

        case .shadow:
            styledBase
                .foregroundColor(overlay.isCaption ? nil : overlay.textColor.color)
                .shadow(
                    color: .black.opacity(0.7),
                    radius: 4 * canvasScale,
                    x: 2 * canvasScale,
                    y: 2 * canvasScale
                )

        case .background:
            styledBase
                .foregroundColor(overlay.isCaption ? nil : overlay.textColor.color)
                .padding(.horizontal, 8 * canvasScale)
                .padding(.vertical, 4 * canvasScale)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.black.opacity(0.6))
                )
        }
    }

    private func captionText(
        _ overlay: EditorTextOverlay,
        at time: TimeInterval,
        revealProgress: Double
    ) -> Text {
        let activeID = overlay.activeCaptionWordID(at: time)
        let count = min(
            overlay.captionWords.count,
            max(0, Int(floor(Double(overlay.captionWords.count) * revealProgress)))
        )
        return overlay.captionWords.prefix(count).enumerated().reduce(Text("")) { result, pair in
            let (index, word) = pair
            let prefix = index == 0 ? "" : " "
            let color = word.id == activeID
                ? overlay.captionHighlightColor.color
                : overlay.textColor.color
            return result + Text(prefix + word.text).foregroundColor(color)
        }
    }

    private func revealedText(_ text: String, progress: Double) -> String {
        let count = min(text.count, max(0, Int(floor(Double(text.count) * progress))))
        return String(text.prefix(count))
    }
}
