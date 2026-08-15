//
//  ColorMaskControls.swift
//  Mixtape
//
//  Resolve-inspired power-window controls drawn directly over the program preview.
//

import SwiftUI

struct EditorColorMaskSelectionLayer: View {
    let vm: EditorViewModel

    private var activeMask: EditorColorMask? {
        guard vm.selectedTool == .filter,
              vm.isColorMaskEditing,
              vm.showsColorMaskOverlay,
              vm.playbackInfo?.clip.id == vm.selectedClipID else { return nil }
        guard let mask = vm.selectedColorMask, let playback = vm.playbackInfo else { return nil }
        let progress = playback.clip.duration > 0
            ? playback.localTime / playback.clip.duration
            : 0
        return mask.resolved(at: progress)
    }

    var body: some View {
        GeometryReader { geometry in
            if let mask = activeMask {
                switch mask.shape {
                case .face, .ellipse, .rectangle:
                    ShapePowerWindow(mask: mask, canvasSize: geometry.size, vm: vm)
                case .linear:
                    LinearPowerWindow(mask: mask, canvasSize: geometry.size, vm: vm)
                case .polygon:
                    PolygonPowerWindow(mask: mask, canvasSize: geometry.size, vm: vm)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct ShapePowerWindow: View {
    let mask: EditorColorMask
    let canvasSize: CGSize
    let vm: EditorViewModel

    @State private var dragOrigin: CGPoint?
    @State private var sizeOrigin: CGSize?

    var body: some View {
        let width = max(canvasSize.width * mask.width, 34)
        let height = max(canvasSize.height * mask.height, 34)
        let center = CGPoint(
            x: canvasSize.width * mask.centerX,
            y: canvasSize.height * mask.centerY
        )
        ZStack {
            windowShape
                .fill(Color.red.opacity(mask.isInverted ? 0.05 : 0.12))
                .frame(width: width, height: height)
            windowShape
                .stroke(Color.appColors.primaryColor, lineWidth: 2)
                .frame(width: width, height: height)
            windowShape
                .stroke(
                    Color.appColors.primaryColor.opacity(0.35),
                    style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                )
                .frame(
                    width: width * (1 + mask.feather * 0.28),
                    height: height * (1 + mask.feather * 0.28)
                )
            centerHandle
            resizeHandles(width: width, height: height)
        }
        .frame(width: width + 48, height: height + 48)
        .rotationEffect(.radians(mask.rotation * .pi))
        .position(center)
        .contentShape(Rectangle())
        .gesture(moveGesture)
        .simultaneousGesture(resizeGesture)
        .accessibilityLabel("\(mask.shape.title) color mask")
        .accessibilityHint("Drag to move or pinch to resize")
    }

    private var windowShape: AnyShape {
        mask.shape == .rectangle
            ? AnyShape(RoundedRectangle(cornerRadius: 4))
            : AnyShape(Ellipse())
    }

    private var centerHandle: some View {
        ZStack {
            Circle().fill(Color.black.opacity(0.75)).frame(width: 18, height: 18)
            Circle().stroke(Color.appColors.primaryColor, lineWidth: 2).frame(width: 18, height: 18)
            Circle().fill(Color.appColors.primaryColor).frame(width: 4, height: 4)
        }
    }

    @ViewBuilder
    private func resizeHandles(width: CGFloat, height: CGFloat) -> some View {
        ForEach([CGPoint(x: -width / 2, y: 0), CGPoint(x: width / 2, y: 0), CGPoint(x: 0, y: -height / 2), CGPoint(x: 0, y: height / 2)], id: \.self) { point in
            Circle()
                .fill(.white)
                .overlay(Circle().stroke(Color.black.opacity(0.7), lineWidth: 1))
                .frame(width: 10, height: 10)
                .offset(x: point.x, y: point.y)
        }
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { gesture in
                if dragOrigin == nil {
                    dragOrigin = CGPoint(x: mask.centerX, y: mask.centerY)
                }
                guard let origin = dragOrigin, canvasSize.width > 0, canvasSize.height > 0 else { return }
                var updated = mask
                updated.centerX = min(max(origin.x + gesture.translation.width / canvasSize.width, 0), 1)
                updated.centerY = min(max(origin.y + gesture.translation.height / canvasSize.height, 0), 1)
                vm.updateSelectedClipColorMask(updated)
            }
            .onEnded { _ in
                dragOrigin = nil
                vm.commitColorAdjustmentEdit()
            }
    }

    private var resizeGesture: some Gesture {
        MagnificationGesture()
            .onChanged { scale in
                if sizeOrigin == nil {
                    sizeOrigin = CGSize(width: mask.width, height: mask.height)
                }
                guard let origin = sizeOrigin else { return }
                var updated = mask
                updated.width = min(max(origin.width * scale, 0.04), 1.5)
                updated.height = min(max(origin.height * scale, 0.04), 1.5)
                vm.updateSelectedClipColorMask(updated)
            }
            .onEnded { _ in
                sizeOrigin = nil
                vm.commitColorAdjustmentEdit()
            }
    }
}

private struct LinearPowerWindow: View {
    let mask: EditorColorMask
    let canvasSize: CGSize
    let vm: EditorViewModel
    @State private var dragOrigin: CGPoint?

    var body: some View {
        let center = CGPoint(x: canvasSize.width * mask.centerX, y: canvasSize.height * mask.centerY)
        let featherWidth = max(18, min(canvasSize.width, canvasSize.height) * mask.feather)
        ZStack {
            LinearGradient(
                colors: [Color.red.opacity(mask.isInverted ? 0.04 : 0.18), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            Rectangle()
                .fill(Color.appColors.primaryColor)
                .frame(width: 2)
            HStack(spacing: featherWidth) {
                Rectangle().fill(Color.appColors.primaryColor.opacity(0.35)).frame(width: 1)
                Rectangle().fill(Color.appColors.primaryColor.opacity(0.35)).frame(width: 1)
            }
        }
        .frame(width: canvasSize.width * 1.5, height: canvasSize.height * 1.5)
        .rotationEffect(.radians(mask.rotation * .pi))
        .position(center)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { gesture in
                    if dragOrigin == nil { dragOrigin = CGPoint(x: mask.centerX, y: mask.centerY) }
                    guard let origin = dragOrigin, canvasSize.width > 0, canvasSize.height > 0 else { return }
                    var updated = mask
                    updated.centerX = min(max(origin.x + gesture.translation.width / canvasSize.width, 0), 1)
                    updated.centerY = min(max(origin.y + gesture.translation.height / canvasSize.height, 0), 1)
                    vm.updateSelectedClipColorMask(updated)
                }
                .onEnded { _ in
                    dragOrigin = nil
                    vm.commitColorAdjustmentEdit()
                }
        )
        .accessibilityLabel("Linear gradient color mask")
    }
}

private struct PolygonPowerWindow: View {
    let mask: EditorColorMask
    let canvasSize: CGSize
    let vm: EditorViewModel
    @State private var dragOrigin: [EditorColorMaskPoint]?

    var body: some View {
        ZStack {
            Canvas { context, _ in
                let path = polygonPath
                context.fill(path, with: .color(.red.opacity(mask.isInverted ? 0.05 : 0.12)))
                context.stroke(path, with: .color(Color.appColors.primaryColor), lineWidth: 2)
            }
            .contentShape(polygonPath)
            .gesture(movePolygonGesture)

            ForEach(Array(mask.points.enumerated()), id: \.element.id) { index, point in
                PolygonPointHandle(mask: mask, pointIndex: index, point: point, canvasSize: canvasSize, vm: vm)
            }
        }
        .accessibilityLabel("Polygon color mask")
        .accessibilityHint("Drag the mask or any point to reshape it")
    }

    private var polygonPath: Path {
        var path = Path()
        for (index, point) in mask.points.enumerated() {
            let destination = CGPoint(x: point.x * canvasSize.width, y: point.y * canvasSize.height)
            if index == 0 { path.move(to: destination) } else { path.addLine(to: destination) }
        }
        path.closeSubpath()
        return path
    }

    private var movePolygonGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { gesture in
                if dragOrigin == nil { dragOrigin = mask.points }
                guard let origin = dragOrigin, canvasSize.width > 0, canvasSize.height > 0 else { return }
                var updated = mask
                updated.points = origin.map { point in
                    var point = point
                    point.x = min(max(point.x + gesture.translation.width / canvasSize.width, 0), 1)
                    point.y = min(max(point.y + gesture.translation.height / canvasSize.height, 0), 1)
                    return point
                }
                vm.updateSelectedClipColorMask(updated)
            }
            .onEnded { _ in
                dragOrigin = nil
                vm.commitColorAdjustmentEdit()
            }
    }
}

private struct PolygonPointHandle: View {
    let mask: EditorColorMask
    let pointIndex: Int
    let point: EditorColorMaskPoint
    let canvasSize: CGSize
    let vm: EditorViewModel
    @State private var origin: CGPoint?

    var body: some View {
        Circle()
            .fill(.white)
            .overlay(Circle().stroke(Color.appColors.primaryColor, lineWidth: 3))
            .frame(width: 17, height: 17)
            .position(x: point.x * canvasSize.width, y: point.y * canvasSize.height)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        if origin == nil { origin = CGPoint(x: point.x, y: point.y) }
                        guard let origin, canvasSize.width > 0, canvasSize.height > 0 else { return }
                        var updated = mask
                        guard updated.points.indices.contains(pointIndex) else { return }
                        updated.points[pointIndex].x = min(max(origin.x + gesture.translation.width / canvasSize.width, 0), 1)
                        updated.points[pointIndex].y = min(max(origin.y + gesture.translation.height / canvasSize.height, 0), 1)
                        vm.updateSelectedClipColorMask(updated)
                    }
                    .onEnded { _ in
                        origin = nil
                        vm.commitColorAdjustmentEdit()
                    }
            )
    }
}
