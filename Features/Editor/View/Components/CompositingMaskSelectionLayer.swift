//
//  CompositingMaskSelectionLayer.swift
//  Mixtape
//

import SwiftUI

/// Direct-on-preview editor for custom polygon visibility masks.
struct CompositingMaskSelectionLayer: View {
    let vm: EditorViewModel

    private var mask: EditorOverlayMask? {
        guard vm.selectedTool == .compositing,
              let mask = vm.selectedCompositing?.mask,
              mask.shape == .polygon,
              mask.points.count >= 3 else { return nil }
        return mask
    }

    var body: some View {
        GeometryReader { geometry in
            if let mask {
                ZStack {
                    Canvas { context, _ in
                        var path = Path()
                        let points = mask.points.map {
                            CGPoint(x: $0.x * geometry.size.width, y: $0.y * geometry.size.height)
                        }
                        if let first = points.first {
                            path.move(to: first)
                            for point in points.dropFirst() { path.addLine(to: point) }
                            path.closeSubpath()
                        }
                        context.fill(path, with: .color(Color.appColors.primaryColor.opacity(0.12)))
                        context.stroke(path, with: .color(Color.appColors.primaryColor), lineWidth: 2)
                    }
                    .allowsHitTesting(false)

                    ForEach(Array(mask.points.enumerated()), id: \.element.id) { index, point in
                        Circle()
                            .fill(Color.appColors.primaryColor)
                            .frame(width: 18, height: 18)
                            .overlay(Circle().stroke(.black.opacity(0.75), lineWidth: 2))
                            .position(
                                x: point.x * geometry.size.width,
                                y: point.y * geometry.size.height
                            )
                            .contentShape(Circle().inset(by: -12))
                            .gesture(
                                DragGesture(
                                    minimumDistance: 0,
                                    coordinateSpace: .named("compositingMaskCanvas")
                                )
                                    .onChanged { value in
                                        guard geometry.size.width > 0, geometry.size.height > 0 else { return }
                                        vm.updateSelectedCompositing { settings in
                                            guard settings.mask.points.indices.contains(index) else { return }
                                            settings.mask.points[index].x = min(max(
                                                value.location.x / geometry.size.width, 0
                                            ), 1)
                                            settings.mask.points[index].y = min(max(
                                                value.location.y / geometry.size.height, 0
                                            ), 1)
                                        }
                                    }
                                    .onEnded { _ in vm.commitOverlayCompositing() }
                            )
                            .accessibilityLabel("Mask point \(index + 1)")
                    }
                }
                .coordinateSpace(name: "compositingMaskCanvas")
            }
        }
        .accessibilityElement(children: .contain)
    }
}
