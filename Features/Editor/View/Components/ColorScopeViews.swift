//
//  ColorScopeViews.swift
//  Mixtape
//
//  SwiftUI renderers for the editor's downsampled grading scopes.
//

import SwiftUI

enum EditorColorScopeMode: String, CaseIterable, Identifiable {
    case waveform = "Waveform"
    case parade = "Parade"
    case vectorscope = "Vector"
    case histogram = "Histogram"

    var id: String { rawValue }
}

struct EditorVideoScopesView: View {
    let snapshot: EditorColorScopeSnapshot
    let mode: EditorColorScopeMode

    var body: some View {
        VStack(spacing: 8) {
            Canvas { context, size in
                drawGrid(context: &context, size: size)
                switch mode {
                case .waveform:
                    drawDensity(
                        snapshot.waveform,
                        columns: snapshot.waveformWidth,
                        rows: snapshot.waveformHeight,
                        color: .init(red: 0.55, green: 1, blue: 0.72),
                        context: &context,
                        rect: CGRect(origin: .zero, size: size)
                    )
                case .parade:
                    drawParade(context: &context, size: size)
                case .vectorscope:
                    drawVectorscope(context: &context, size: size)
                case .histogram:
                    drawHistogram(context: &context, size: size)
                }
            }
            .background(Color.black.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )

            HStack(spacing: 8) {
                clippingBadge(
                    title: "Shadows",
                    value: snapshot.shadowClipPercent,
                    color: .blue
                )
                clippingBadge(
                    title: "Highlights",
                    value: snapshot.highlightClipPercent,
                    color: .red
                )
                Spacer()
                Text("Graded frame")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.42))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private func drawGrid(context: inout GraphicsContext, size: CGSize) {
        var grid = Path()
        for step in 1..<4 {
            let y = size.height * CGFloat(step) / 4
            grid.move(to: CGPoint(x: 0, y: y))
            grid.addLine(to: CGPoint(x: size.width, y: y))
        }
        context.stroke(grid, with: .color(.white.opacity(0.09)), lineWidth: 0.6)
    }

    private func drawParade(context: inout GraphicsContext, size: CGSize) {
        let gap: CGFloat = 7
        let width = (size.width - gap * 2) / 3
        let channels: [([Float], Color)] = [
            (snapshot.paradeRed, .red),
            (snapshot.paradeGreen, .green),
            (snapshot.paradeBlue, .blue)
        ]
        for (index, channel) in channels.enumerated() {
            let rect = CGRect(x: CGFloat(index) * (width + gap), y: 0, width: width, height: size.height)
            drawDensity(
                channel.0,
                columns: snapshot.paradeWidth,
                rows: snapshot.paradeHeight,
                color: channel.1,
                context: &context,
                rect: rect
            )
        }
    }

    private func drawVectorscope(context: inout GraphicsContext, size: CGSize) {
        let side = min(size.width, size.height) - 12
        let rect = CGRect(
            x: (size.width - side) / 2,
            y: (size.height - side) / 2,
            width: side,
            height: side
        )
        context.stroke(
            Path(ellipseIn: rect),
            with: .color(.white.opacity(0.18)),
            lineWidth: 0.7
        )
        context.stroke(
            Path(ellipseIn: rect.insetBy(dx: side * 0.25, dy: side * 0.25)),
            with: .color(.white.opacity(0.09)),
            lineWidth: 0.6
        )
        var crosshair = Path()
        crosshair.move(to: CGPoint(x: rect.midX, y: rect.minY))
        crosshair.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        crosshair.move(to: CGPoint(x: rect.minX, y: rect.midY))
        crosshair.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        context.stroke(crosshair, with: .color(.white.opacity(0.08)), lineWidth: 0.6)

        // Approximate 11 o'clock skin-tone reference line.
        var skinLine = Path()
        skinLine.move(to: CGPoint(x: rect.midX, y: rect.midY))
        skinLine.addLine(to: CGPoint(x: rect.midX + side * 0.20, y: rect.midY - side * 0.34))
        context.stroke(skinLine, with: .color(.yellow.opacity(0.30)), lineWidth: 0.8)

        drawDensity(
            snapshot.vectorscope,
            columns: snapshot.vectorscopeSize,
            rows: snapshot.vectorscopeSize,
            color: .init(red: 0.45, green: 1, blue: 0.75),
            context: &context,
            rect: rect
        )
    }

    private func drawHistogram(context: inout GraphicsContext, size: CGSize) {
        drawHistogramPath(snapshot.histogramLuma, color: .white.opacity(0.35), context: &context, size: size)
        drawHistogramPath(snapshot.histogramRed, color: .red.opacity(0.78), context: &context, size: size)
        drawHistogramPath(snapshot.histogramGreen, color: .green.opacity(0.78), context: &context, size: size)
        drawHistogramPath(snapshot.histogramBlue, color: .blue.opacity(0.9), context: &context, size: size)
    }

    private func drawHistogramPath(
        _ values: [Float],
        color: Color,
        context: inout GraphicsContext,
        size: CGSize
    ) {
        guard values.count > 1 else { return }
        var path = Path()
        path.move(to: CGPoint(x: 0, y: size.height))
        for index in values.indices {
            let x = CGFloat(index) / CGFloat(values.count - 1) * size.width
            let y = size.height * (1 - CGFloat(values[index]) * 0.94)
            path.addLine(to: CGPoint(x: x, y: y))
        }
        path.addLine(to: CGPoint(x: size.width, y: size.height))
        path.closeSubpath()
        context.fill(path, with: .color(color))
    }

    private func drawDensity(
        _ values: [Float],
        columns: Int,
        rows: Int,
        color: Color,
        context: inout GraphicsContext,
        rect: CGRect
    ) {
        guard values.count == columns * rows, columns > 0, rows > 0 else { return }
        let cellWidth = rect.width / CGFloat(columns)
        let cellHeight = rect.height / CGFloat(rows)
        for row in 0..<rows {
            for column in 0..<columns {
                let density = values[row * columns + column]
                guard density > 0.025 else { continue }
                let cell = CGRect(
                    x: rect.minX + CGFloat(column) * cellWidth,
                    y: rect.minY + CGFloat(row) * cellHeight,
                    width: max(cellWidth, 0.75),
                    height: max(cellHeight, 0.75)
                )
                context.fill(
                    Path(cell),
                    with: .color(color.opacity(Double(min(0.92, density * 0.9 + 0.08))))
                )
            }
        }
    }

    private func clippingBadge(title: String, value: Double, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(value > 0.05 ? color : Color.white.opacity(0.2))
                .frame(width: 5, height: 5)
            Text("\(title) \(value, specifier: "%.1f")%")
                .font(.system(size: 9, weight: .semibold).monospacedDigit())
                .foregroundColor(value > 0.05 ? .white : Color.white.opacity(0.45))
        }
    }

    private var accessibilitySummary: String {
        String(
            format: "%@ scope. Shadow clipping %.1f percent. Highlight clipping %.1f percent.",
            mode.rawValue,
            snapshot.shadowClipPercent,
            snapshot.highlightClipPercent
        )
    }
}
