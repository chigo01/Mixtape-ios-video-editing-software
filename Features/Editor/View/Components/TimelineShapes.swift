//
//  TimelineShapes.swift
//  Mixtape
//

import SwiftUI
import UIKit
import Photos
import AVFoundation

// MARK: - Shapes

struct PlayheadShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let mid = rect.midX
        p.move(to: CGPoint(x: mid, y: rect.minY + 4))
        p.addLine(to: CGPoint(x: mid, y: rect.maxY))
        return p
    }
}

struct WaveformShape: Shape {
    let samples: [CGFloat]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard !samples.isEmpty, rect.width > 0, rect.height > 0 else { return path }

        let barCount = samples.count
        let slot = rect.width / CGFloat(barCount)
        let barWidth = max(1, slot * 0.72)
        let midY = rect.midY
        let maxHeight = max(2, rect.height - 1)

        for (index, sample) in samples.enumerated() {
            let amplitude = min(1, max(0, sample))
            let height = max(1.5, amplitude * maxHeight)
            let x = CGFloat(index) * slot + (slot - barWidth) / 2
            let y = midY - height / 2
            let bar = CGRect(x: x, y: y, width: barWidth, height: height)
            path.addRoundedRect(in: bar, cornerSize: CGSize(width: min(1.2, barWidth / 2), height: 1))
        }
        return path
    }
}
