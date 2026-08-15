//
//  EditorColorScopeAnalyzer.swift
//  Mixtape
//
//  Downsampled, read-only video scope analysis for the color grading workspace.
//  Scope work never enters the export graph and is safe to drop or recompute.
//

import CoreImage
import Foundation
import UIKit

struct EditorColorScopeSnapshot: Sendable {
    static let empty = EditorColorScopeSnapshot()

    let histogramRed: [Float]
    let histogramGreen: [Float]
    let histogramBlue: [Float]
    let histogramLuma: [Float]
    let waveform: [Float]
    let paradeRed: [Float]
    let paradeGreen: [Float]
    let paradeBlue: [Float]
    let vectorscope: [Float]
    let waveformWidth: Int
    let waveformHeight: Int
    let paradeWidth: Int
    let paradeHeight: Int
    let vectorscopeSize: Int
    let shadowClipPercent: Double
    let highlightClipPercent: Double

    init(
        histogramRed: [Float] = Array(repeating: 0, count: 256),
        histogramGreen: [Float] = Array(repeating: 0, count: 256),
        histogramBlue: [Float] = Array(repeating: 0, count: 256),
        histogramLuma: [Float] = Array(repeating: 0, count: 256),
        waveform: [Float] = [],
        paradeRed: [Float] = [],
        paradeGreen: [Float] = [],
        paradeBlue: [Float] = [],
        vectorscope: [Float] = [],
        waveformWidth: Int = 160,
        waveformHeight: Int = 96,
        paradeWidth: Int = 72,
        paradeHeight: Int = 96,
        vectorscopeSize: Int = 112,
        shadowClipPercent: Double = 0,
        highlightClipPercent: Double = 0
    ) {
        self.histogramRed = histogramRed
        self.histogramGreen = histogramGreen
        self.histogramBlue = histogramBlue
        self.histogramLuma = histogramLuma
        self.waveform = waveform.isEmpty
            ? Array(repeating: 0, count: waveformWidth * waveformHeight)
            : waveform
        self.paradeRed = paradeRed.isEmpty
            ? Array(repeating: 0, count: paradeWidth * paradeHeight)
            : paradeRed
        self.paradeGreen = paradeGreen.isEmpty
            ? Array(repeating: 0, count: paradeWidth * paradeHeight)
            : paradeGreen
        self.paradeBlue = paradeBlue.isEmpty
            ? Array(repeating: 0, count: paradeWidth * paradeHeight)
            : paradeBlue
        self.vectorscope = vectorscope.isEmpty
            ? Array(repeating: 0, count: vectorscopeSize * vectorscopeSize)
            : vectorscope
        self.waveformWidth = waveformWidth
        self.waveformHeight = waveformHeight
        self.paradeWidth = paradeWidth
        self.paradeHeight = paradeHeight
        self.vectorscopeSize = vectorscopeSize
        self.shadowClipPercent = shadowClipPercent
        self.highlightClipPercent = highlightClipPercent
    }
}

enum EditorColorScopeAnalyzer {
    private static let context = CIContext(options: [
        .cacheIntermediates: false,
        .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any
    ])

    static func analyze(source: UIImage, grade: EditorColorAdjustment) -> EditorColorScopeSnapshot? {
        guard var image = source.ciImage ?? CIImage(image: source) else { return nil }
        image = image.oriented(forExifOrientation: Int32(source.imageOrientation.exifOrientation))
        image = EditorColorGradeRenderer.apply(grade, to: image).cropped(to: image.extent)

        let maxSide: CGFloat = 256
        let scale = min(1, maxSide / max(image.extent.width, image.extent.height))
        image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let bounds = image.extent.integral
        let width = max(Int(bounds.width), 1)
        let height = max(Int(bounds.height), 1)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        context.render(
            image,
            toBitmap: &pixels,
            rowBytes: width * 4,
            bounds: bounds,
            format: .RGBA8,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
        )
        return buildSnapshot(pixels: pixels, width: width, height: height)
    }

    private static func buildSnapshot(
        pixels: [UInt8],
        width: Int,
        height: Int
    ) -> EditorColorScopeSnapshot {
        let waveformWidth = 160
        let scopeHeight = 96
        let paradeWidth = 72
        let vectorscopeSize = 112
        var histR = [Float](repeating: 0, count: 256)
        var histG = [Float](repeating: 0, count: 256)
        var histB = [Float](repeating: 0, count: 256)
        var histL = [Float](repeating: 0, count: 256)
        var waveform = [Float](repeating: 0, count: waveformWidth * scopeHeight)
        var paradeR = [Float](repeating: 0, count: paradeWidth * scopeHeight)
        var paradeG = [Float](repeating: 0, count: paradeWidth * scopeHeight)
        var paradeB = [Float](repeating: 0, count: paradeWidth * scopeHeight)
        var vectorscope = [Float](repeating: 0, count: vectorscopeSize * vectorscopeSize)
        var shadowClips = 0
        var highlightClips = 0

        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                let r8 = Int(pixels[offset])
                let g8 = Int(pixels[offset + 1])
                let b8 = Int(pixels[offset + 2])
                let r = Double(r8) / 255
                let g = Double(g8) / 255
                let b = Double(b8) / 255
                let luma = min(max(0.2126 * r + 0.7152 * g + 0.0722 * b, 0), 1)
                let l8 = min(max(Int((luma * 255).rounded()), 0), 255)

                histR[r8] += 1
                histG[g8] += 1
                histB[b8] += 1
                histL[l8] += 1

                let waveX = min(x * waveformWidth / width, waveformWidth - 1)
                let waveY = scopeHeight - 1 - min(l8 * scopeHeight / 256, scopeHeight - 1)
                waveform[waveY * waveformWidth + waveX] += 1

                let paradeX = min(x * paradeWidth / width, paradeWidth - 1)
                incrementParade(&paradeR, value: r8, x: paradeX, width: paradeWidth, height: scopeHeight)
                incrementParade(&paradeG, value: g8, x: paradeX, width: paradeWidth, height: scopeHeight)
                incrementParade(&paradeB, value: b8, x: paradeX, width: paradeWidth, height: scopeHeight)

                // Rec.709 chroma projection. Center is neutral; skin tones trend upper-right.
                let cb = (b - luma) / 1.8556
                let cr = (r - luma) / 1.5748
                let vectorX = min(max(Int((0.5 + cb) * Double(vectorscopeSize - 1)), 0), vectorscopeSize - 1)
                let vectorY = min(max(Int((0.5 - cr) * Double(vectorscopeSize - 1)), 0), vectorscopeSize - 1)
                vectorscope[vectorY * vectorscopeSize + vectorX] += 1

                if r8 <= 1 && g8 <= 1 && b8 <= 1 { shadowClips += 1 }
                if r8 >= 254 || g8 >= 254 || b8 >= 254 { highlightClips += 1 }
            }
        }

        normalizeHistogram(&histR)
        normalizeHistogram(&histG)
        normalizeHistogram(&histB)
        normalizeHistogram(&histL)
        normalizeDensity(&waveform)
        normalizeDensity(&paradeR)
        normalizeDensity(&paradeG)
        normalizeDensity(&paradeB)
        normalizeDensity(&vectorscope)
        let pixelCount = Double(max(width * height, 1))
        return EditorColorScopeSnapshot(
            histogramRed: histR,
            histogramGreen: histG,
            histogramBlue: histB,
            histogramLuma: histL,
            waveform: waveform,
            paradeRed: paradeR,
            paradeGreen: paradeG,
            paradeBlue: paradeB,
            vectorscope: vectorscope,
            waveformWidth: waveformWidth,
            waveformHeight: scopeHeight,
            paradeWidth: paradeWidth,
            paradeHeight: scopeHeight,
            vectorscopeSize: vectorscopeSize,
            shadowClipPercent: Double(shadowClips) / pixelCount * 100,
            highlightClipPercent: Double(highlightClips) / pixelCount * 100
        )
    }

    private static func incrementParade(
        _ bins: inout [Float],
        value: Int,
        x: Int,
        width: Int,
        height: Int
    ) {
        let y = height - 1 - min(value * height / 256, height - 1)
        bins[y * width + x] += 1
    }

    private static func normalizeHistogram(_ values: inout [Float]) {
        let peak = max(values.max() ?? 1, 1)
        for index in values.indices {
            values[index] = sqrt(values[index] / peak)
        }
    }

    private static func normalizeDensity(_ values: inout [Float]) {
        let peak = max(values.max() ?? 1, 1)
        let denominator = log1p(peak)
        for index in values.indices {
            values[index] = log1p(values[index]) / denominator
        }
    }
}

private extension UIImage.Orientation {
    var exifOrientation: UInt32 {
        switch self {
        case .up: return 1
        case .down: return 3
        case .left: return 8
        case .right: return 6
        case .upMirrored: return 2
        case .downMirrored: return 4
        case .leftMirrored: return 5
        case .rightMirrored: return 7
        @unknown default: return 1
        }
    }
}
