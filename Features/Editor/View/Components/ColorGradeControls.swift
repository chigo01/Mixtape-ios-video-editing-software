//
//  ColorGradeControls.swift
//  Mixtape
//
//  Reusable interactive curve and color-wheel controls.
//

import SwiftUI

struct ToneCurveGraph: View {
    @Binding var points: [EditorCurvePoint]
    let color: Color
    let onCommit: () -> Void
    @State private var activePointIndex: Int?

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                drawGrid(context: &context, size: size)
                drawCurve(context: &context, size: size)
                drawPoints(context: &context, size: size)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        updateOrInsertPoint(at: gesture.location, size: geometry.size)
                    }
                    .onEnded { _ in
                        activePointIndex = nil
                        onCommit()
                    }
            )
        }
        .background(Color.black.opacity(0.18))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.1)))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityLabel("Tone curve graph")
    }

    private func drawGrid(context: inout GraphicsContext, size: CGSize) {
        var grid = Path()
        for step in 1..<4 {
            let fraction = CGFloat(step) / 4
            grid.move(to: CGPoint(x: size.width * fraction, y: 0))
            grid.addLine(to: CGPoint(x: size.width * fraction, y: size.height))
            grid.move(to: CGPoint(x: 0, y: size.height * fraction))
            grid.addLine(to: CGPoint(x: size.width, y: size.height * fraction))
        }
        context.stroke(grid, with: .color(.white.opacity(0.09)), lineWidth: 1)
    }

    private func drawCurve(context: inout GraphicsContext, size: CGSize) {
        let sorted = points.sorted { $0.x < $1.x }
        guard let first = sorted.first else { return }
        var path = Path()
        path.move(to: screenPoint(first, size: size))
        for point in sorted.dropFirst() { path.addLine(to: screenPoint(point, size: size)) }
        context.stroke(path, with: .color(color), lineWidth: 2.5)
    }

    private func drawPoints(context: inout GraphicsContext, size: CGSize) {
        for point in points {
            let center = screenPoint(point, size: size)
            let rect = CGRect(x: center.x - 7, y: center.y - 7, width: 14, height: 14)
            context.fill(Path(ellipseIn: rect), with: .color(.white))
            context.stroke(Path(ellipseIn: rect.insetBy(dx: 3, dy: 3)), with: .color(color), lineWidth: 2)
        }
    }

    private func updateOrInsertPoint(at location: CGPoint, size: CGSize) {
        guard !points.isEmpty, size.width > 0, size.height > 0 else { return }
        var working = points.sorted { $0.x < $1.x }
        let normalizedX = min(max(Double(location.x / size.width), 0), 1)
        let normalizedY = min(max(1 - Double(location.y / size.height), 0), 1)

        if activePointIndex == nil {
            let nearest = working.indices.min { lhs, rhs in
                distance(from: working[lhs], to: location, size: size)
                    < distance(from: working[rhs], to: location, size: size)
            } ?? 0
            if distance(from: working[nearest], to: location, size: size) > 24,
               working.count < 10 {
                working.append(EditorCurvePoint(x: normalizedX, y: normalizedY))
                working.sort { $0.x < $1.x }
                activePointIndex = working.firstIndex {
                    abs($0.x - normalizedX) < 0.0001 && abs($0.y - normalizedY) < 0.0001
                }
            } else {
                activePointIndex = nearest
            }
        }

        guard let index = activePointIndex, working.indices.contains(index) else { return }
        if index > 0, index < working.count - 1 {
            let lower = working[index - 1].x + 0.01
            let upper = working[index + 1].x - 0.01
            working[index].x = min(max(normalizedX, lower), upper)
        }
        working[index].y = normalizedY
        points = working
    }

    private func distance(
        from point: EditorCurvePoint,
        to location: CGPoint,
        size: CGSize
    ) -> CGFloat {
        let screen = screenPoint(point, size: size)
        return hypot(screen.x - location.x, screen.y - location.y)
    }

    private func screenPoint(_ point: EditorCurvePoint, size: CGSize) -> CGPoint {
        CGPoint(
            x: CGFloat(point.x) * size.width,
            y: CGFloat(1 - point.y) * size.height
        )
    }
}

struct ColorWheelEditor: View {
    let title: String
    @Binding var value: EditorColorWheelValue
    let onCommit: () -> Void
    let onReset: () -> Void

    var body: some View {
        VStack(spacing: 9) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white)
            ColorWheelPad(value: $value, onCommit: onCommit)
                .aspectRatio(1, contentMode: .fit)
            Slider(
                value: $value.luminance,
                in: -1...1,
                step: 0.01,
                onEditingChanged: { if !$0 { onCommit() } }
            )
            .tint(Color.white.opacity(0.8))
            Text("Y \(Int(value.luminance * 100))")
                .font(.system(size: 9, weight: .semibold).monospacedDigit())
                .foregroundColor(Color.white.opacity(0.5))
            Button("Reset", action: onReset)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(Color.appColors.primaryColor)
        }
        .frame(maxWidth: .infinity)
    }
}

struct ColorWheelPad: View {
    @Binding var value: EditorColorWheelValue
    let onCommit: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let diameter = min(geometry.size.width, geometry.size.height)
            let radius = diameter / 2
            ZStack {
                Circle()
                    .fill(AngularGradient(
                        colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red],
                        center: .center
                    ))
                Circle()
                    .fill(RadialGradient(colors: [.white, .white.opacity(0)], center: .center, startRadius: 0, endRadius: radius))
                Circle().stroke(Color.white.opacity(0.22), lineWidth: 1)
                Circle()
                    .fill(.white)
                    .frame(width: 13, height: 13)
                    .overlay(Circle().stroke(.black.opacity(0.7), lineWidth: 2))
                    .offset(
                        x: CGFloat(value.x) * radius * 0.78,
                        y: -CGFloat(value.y) * radius * 0.78
                    )
            }
            .frame(width: diameter, height: diameter)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let x = (gesture.location.x - radius) / (radius * 0.78)
                        let y = -(gesture.location.y - radius) / (radius * 0.78)
                        let magnitude = max(1, hypot(x, y))
                        value.x = Double(x / magnitude)
                        value.y = Double(y / magnitude)
                    }
                    .onEnded { _ in onCommit() }
            )
        }
        .accessibilityLabel("Color wheel")
    }
}

extension Color {
    init(rgb: UInt32) {
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}
