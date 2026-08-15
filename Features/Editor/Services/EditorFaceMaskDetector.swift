//
//  EditorFaceMaskDetector.swift
//  Mixtape
//
//  Vision-assisted static face mask suggestions for the selected clip frame.
//

import CoreImage
import ImageIO
import UIKit
import Vision

struct EditorFaceMaskSuggestion: Sendable {
    let centerX: Double
    let centerY: Double
    let width: Double
    let height: Double
}

enum EditorFaceMaskDetector {
    static func detectFaces(in image: UIImage) throws -> [EditorFaceMaskSuggestion] {
        let cgImage: CGImage
        if let source = image.cgImage {
            cgImage = source
        } else if let ciImage = image.ciImage,
                  let rendered = CIContext().createCGImage(ciImage, from: ciImage.extent) {
            cgImage = rendered
        } else {
            return []
        }

        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(
            cgImage: cgImage,
            orientation: image.imageOrientation.cgImageOrientation,
            options: [:]
        )
        try handler.perform([request])
        return (request.results ?? [])
            .map(\.boundingBox)
            .sorted { $0.width * $0.height > $1.width * $1.height }
            .map { bounds in
                let expandedWidth = min(Double(bounds.width) * 1.34, 0.96)
                let expandedHeight = min(Double(bounds.height) * 1.48, 0.96)
                let centerX = min(max(Double(bounds.midX), expandedWidth / 2), 1 - expandedWidth / 2)
                let centerYFromTop = 1 - Double(bounds.midY)
                let centerY = min(max(centerYFromTop, expandedHeight / 2), 1 - expandedHeight / 2)
                return EditorFaceMaskSuggestion(
                    centerX: centerX,
                    centerY: centerY,
                    width: expandedWidth,
                    height: expandedHeight
                )
            }
    }
}

private extension UIImage.Orientation {
    var cgImageOrientation: CGImagePropertyOrientation {
        switch self {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}
