//
//  EditorOverlayCompositingRenderer.swift
//  Mixtape
//
//  Core Image implementation shared by live preview and offline export.
//

import CoreImage
import Foundation
import simd

enum EditorOverlayCompositingRenderer {
    private static let chromaCubeDimension = 32
    private static let chromaCubeCache = NSCache<NSString, NSData>()

    static func applyChromaKey(
        _ settings: EditorChromaKeySettings,
        to source: CIImage
    ) -> CIImage {
        guard settings.isEnabled else { return source }
        let data = chromaCubeData(for: settings)
        return source.applyingFilter(
            "CIColorCube",
            parameters: [
                "inputCubeDimension": chromaCubeDimension,
                "inputCubeData": data
            ]
        )
    }

    static func applyMask(_ mask: EditorOverlayMask, to source: CIImage) -> CIImage {
        guard mask.isEnabled else { return source }
        let extent = source.extent
        guard extent.width > 0, extent.height > 0 else { return source }

        var matte = maskImage(mask, extent: extent).cropped(to: extent)
        if abs(mask.expansion) > 0.001 {
            let radius = abs(mask.expansion) * min(extent.width, extent.height) * 0.08
            matte = matte.applyingFilter(
                mask.expansion > 0 ? "CIMorphologyMaximum" : "CIMorphologyMinimum",
                parameters: [kCIInputRadiusKey: radius]
            ).cropped(to: extent)
        }
        if mask.feather > 0.0001 {
            let radius = max(1, mask.feather * min(extent.width, extent.height) * 0.12)
            matte = matte
                .clampedToExtent()
                .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])
                .cropped(to: extent)
        }
        if mask.isInverted {
            matte = matte.applyingFilter("CIColorInvert")
        }
        if mask.opacity < 0.9999 {
            let value = CGFloat(mask.opacity)
            matte = matte.applyingFilter(
                "CIColorMatrix",
                parameters: [
                    "inputRVector": CIVector(x: value, y: 0, z: 0, w: 0),
                    "inputGVector": CIVector(x: 0, y: value, z: 0, w: 0),
                    "inputBVector": CIVector(x: 0, y: 0, z: value, w: 0)
                ]
            )
        }

        let transparent = CIImage(color: .clear).cropped(to: extent)
        return source.applyingFilter(
            "CIBlendWithMask",
            parameters: [
                kCIInputBackgroundImageKey: transparent,
                kCIInputMaskImageKey: matte
            ]
        ).cropped(to: extent)
    }

    static func applyLumaKey(_ settings: EditorLumaKeySettings, to source: CIImage) -> CIImage {
        guard settings.isEnabled else { return source }
        let extent = source.extent
        let scale = 1 / max(settings.softness, 0.01)
        let bias = 0.5 - settings.threshold * scale
        var matte = source
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0])
            .applyingFilter(
                "CIColorMatrix",
                parameters: [
                    "inputRVector": CIVector(x: scale, y: 0, z: 0, w: 0),
                    "inputGVector": CIVector(x: 0, y: scale, z: 0, w: 0),
                    "inputBVector": CIVector(x: 0, y: 0, z: scale, w: 0),
                    "inputBiasVector": CIVector(x: bias, y: bias, z: bias, w: 0)
                ]
            )
            .applyingFilter("CIColorClamp")
        if settings.isInverted { matte = matte.applyingFilter("CIColorInvert") }
        return source.applyingFilter(
            "CIBlendWithMask",
            parameters: [
                kCIInputBackgroundImageKey: CIImage(color: .clear).cropped(to: extent),
                kCIInputMaskImageKey: matte
            ]
        ).cropped(to: extent)
    }

    static func backgroundWithShadow(
        from foreground: CIImage,
        over background: CIImage,
        settings: EditorLayerShadowSettings,
        extent: CGRect
    ) -> CIImage {
        guard settings.isEnabled, settings.opacity > 0 else { return background }
        let radius = settings.blur * min(extent.width, extent.height) * 0.06
        let angle = settings.angle * 2 * .pi
        let distance = settings.distance * min(extent.width, extent.height)
        var shadow = foreground.applyingFilter(
            "CIColorMatrix",
            parameters: [
                "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: settings.opacity)
            ]
        )
        if radius > 0.1 {
            shadow = shadow.clampedToExtent()
                .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])
                .cropped(to: extent)
        }
        shadow = shadow.transformed(by: CGAffineTransform(
            translationX: cos(angle) * distance,
            y: -sin(angle) * distance
        ))
        return shadow.applyingFilter(
            "CISourceOverCompositing",
            parameters: [kCIInputBackgroundImageKey: background]
        ).cropped(to: extent)
    }

    static func composite(
        _ foreground: CIImage,
        over background: CIImage,
        using mode: EditorOverlayBlendMode,
        extent: CGRect
    ) -> CIImage {
        let filterName: String
        switch mode {
        case .normal: filterName = "CISourceOverCompositing"
        case .multiply: filterName = "CIMultiplyBlendMode"
        case .screen: filterName = "CIScreenBlendMode"
        case .overlay: filterName = "CIOverlayBlendMode"
        case .softLight: filterName = "CISoftLightBlendMode"
        case .hardLight: filterName = "CIHardLightBlendMode"
        case .darken: filterName = "CIDarkenBlendMode"
        case .lighten: filterName = "CILightenBlendMode"
        case .colorDodge: filterName = "CIColorDodgeBlendMode"
        case .colorBurn: filterName = "CIColorBurnBlendMode"
        case .difference: filterName = "CIDifferenceBlendMode"
        case .exclusion: filterName = "CIExclusionBlendMode"
        case .hue: filterName = "CIHueBlendMode"
        case .saturation: filterName = "CISaturationBlendMode"
        case .color: filterName = "CIColorBlendMode"
        case .luminosity: filterName = "CILuminosityBlendMode"
        }
        return foreground.applyingFilter(
            filterName,
            parameters: [kCIInputBackgroundImageKey: background]
        ).cropped(to: extent)
    }

    private static func maskImage(_ mask: EditorOverlayMask, extent: CGRect) -> CIImage {
        let center = CGPoint(
            x: extent.minX + extent.width * mask.centerX,
            y: extent.maxY - extent.height * mask.centerY
        )
        let width = max(1, extent.width * mask.width)
        let height = max(1, extent.height * mask.height)
        let angle = CGFloat(mask.rotation * .pi)
        let black = CIImage(color: .black).cropped(to: extent)

        switch mask.shape {
        case .none:
            return CIImage(color: .white).cropped(to: extent)
        case .ellipse:
            let radial = CIFilter(
                name: "CIRadialGradient",
                parameters: [
                    "inputCenter": CIVector(x: 0, y: 0),
                    "inputRadius0": 0.98,
                    "inputRadius1": 1.0,
                    "inputColor0": CIColor.white,
                    "inputColor1": CIColor.black
                ]
            )?.outputImage ?? CIImage(color: .black)
            let shape = radial
                .transformed(by: CGAffineTransform(scaleX: width / 2, y: height / 2))
                .transformed(by: CGAffineTransform(rotationAngle: angle))
                .transformed(by: CGAffineTransform(translationX: center.x, y: center.y))
            return shape.composited(over: black)
        case .rectangle:
            let rect = CGRect(x: -width / 2, y: -height / 2, width: width, height: height)
            let shape = CIImage(color: .white)
                .cropped(to: rect)
                .transformed(by: CGAffineTransform(rotationAngle: angle))
                .transformed(by: CGAffineTransform(translationX: center.x, y: center.y))
            return shape.composited(over: black)
        case .linear:
            let span = hypot(extent.width, extent.height)
            let direction = CGVector(dx: cos(angle), dy: sin(angle))
            let start = CGPoint(
                x: center.x - direction.dx * span / 2,
                y: center.y - direction.dy * span / 2
            )
            let end = CGPoint(
                x: center.x + direction.dx * span / 2,
                y: center.y + direction.dy * span / 2
            )
            return CIFilter(
                name: "CILinearGradient",
                parameters: [
                    "inputPoint0": CIVector(cgPoint: start),
                    "inputPoint1": CIVector(cgPoint: end),
                    "inputColor0": CIColor.white,
                    "inputColor1": CIColor.black
                ]
            )?.outputImage?.cropped(to: extent) ?? black
        case .polygon:
            return polygonMask(mask.points, extent: extent)
        }
    }

    private static func polygonMask(
        _ points: [EditorOverlayMaskPoint],
        extent: CGRect
    ) -> CIImage {
        guard points.count >= 3 else { return CIImage(color: .black).cropped(to: extent) }
        let width = max(1, Int(extent.width.rounded(.up)))
        let height = max(1, Int(extent.height.rounded(.up)))
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return CIImage(color: .black).cropped(to: extent) }
        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.beginPath()
        context.move(to: CGPoint(x: points[0].x * Double(width), y: (1 - points[0].y) * Double(height)))
        for point in points.dropFirst() {
            context.addLine(to: CGPoint(x: point.x * Double(width), y: (1 - point.y) * Double(height)))
        }
        context.closePath()
        context.setFillColor(gray: 1, alpha: 1)
        context.fillPath()
        guard let image = context.makeImage() else {
            return CIImage(color: .black).cropped(to: extent)
        }
        return CIImage(cgImage: image)
            .transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
            .cropped(to: extent)
    }

    private static func chromaCubeData(for settings: EditorChromaKeySettings) -> Data {
        let key = NSString(
            format: "%.4f|%.4f|%.4f|%.4f|%.4f|%.4f|%.4f",
            settings.red,
            settings.green,
            settings.blue,
            settings.threshold,
            settings.softness,
            settings.spillSuppression,
            settings.edgeDesaturation
        )
        if let cached = chromaCubeCache.object(forKey: key) { return cached as Data }

        let dimension = chromaCubeDimension
        var values = [Float]()
        values.reserveCapacity(dimension * dimension * dimension * 4)
        let keyColor = SIMD3<Float>(
            Float(settings.red),
            Float(settings.green),
            Float(settings.blue)
        )
        let lower = Float(max(0, settings.threshold - settings.softness))
        let upper = Float(settings.threshold + settings.softness)

        for blue in 0..<dimension {
            for green in 0..<dimension {
                for red in 0..<dimension {
                    var color = SIMD3<Float>(
                        Float(red) / Float(dimension - 1),
                        Float(green) / Float(dimension - 1),
                        Float(blue) / Float(dimension - 1)
                    )
                    let distance = simd_distance(chroma(color), chroma(keyColor))
                    let alpha = smoothstep(lower, upper, distance)
                    let luminance = color.x * 0.2126 + color.y * 0.7152 + color.z * 0.0722
                    let gray = SIMD3<Float>(repeating: luminance)
                    let edge = max(0, 1 - alpha)
                    color = mix(color, gray, amount: edge * Float(settings.spillSuppression))
                    color = mix(
                        color,
                        gray,
                        amount: alpha * (1 - alpha) * 4 * Float(settings.edgeDesaturation)
                    )
                    // Core Image consumes premultiplied RGBA; premultiplying here
                    // prevents keyed colors from leaking into soft edges.
                    values.append(color.x * alpha)
                    values.append(color.y * alpha)
                    values.append(color.z * alpha)
                    values.append(alpha)
                }
            }
        }

        let data = values.withUnsafeBufferPointer { Data(buffer: $0) }
        chromaCubeCache.setObject(data as NSData, forKey: key)
        return data
    }

    private static func chroma(_ color: SIMD3<Float>) -> SIMD2<Float> {
        let y = color.x * 0.2126 + color.y * 0.7152 + color.z * 0.0722
        return SIMD2<Float>(color.z - y, color.x - y)
    }

    private static func smoothstep(_ lower: Float, _ upper: Float, _ value: Float) -> Float {
        let amount = min(max((value - lower) / max(upper - lower, 0.0001), 0), 1)
        return amount * amount * (3 - 2 * amount)
    }

    private static func mix(
        _ source: SIMD3<Float>,
        _ target: SIMD3<Float>,
        amount: Float
    ) -> SIMD3<Float> {
        source + (target - source) * min(max(amount, 0), 1)
    }
}
