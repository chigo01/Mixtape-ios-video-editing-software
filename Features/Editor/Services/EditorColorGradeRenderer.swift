//
//  EditorColorGradeRenderer.swift
//  Mixtape
//
//  GPU-backed Core Image grade used by both AVPlayer preview and offline export.
//

import CoreImage
import Foundation
#if canImport(UIKit)
import UIKit
#endif

enum EditorColorGradeRenderer {
    private static let cubeDimension = 24
    private static let cubeCache: NSCache<NSString, NSData> = {
        let cache = NSCache<NSString, NSData>()
        cache.countLimit = 48
        return cache
    }()
    private static let polygonMaskCache: NSCache<NSString, CIImage> = {
        let cache = NSCache<NSString, CIImage>()
        cache.countLimit = 32
        return cache
    }()
    #if canImport(UIKit)
    private static let thumbnailCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 120
        return cache
    }()
    private static let thumbnailContext = CIContext(options: [.cacheIntermediates: true])

    static func filterThumbnail(
        preset: EditorFilterPreset,
        source: UIImage,
        intensity: Double = 1
    ) -> UIImage? {
        let key = "\(source.hash)|\(preset.rawValue)|\(intensity)" as NSString
        if let cached = thumbnailCache.object(forKey: key) { return cached }
        guard let sourceImage = source.ciImage ?? CIImage(image: source) else { return nil }
        let filtered = applyPreset(preset, intensity: intensity, to: sourceImage)
            .cropped(to: sourceImage.extent)
        guard let cgImage = thumbnailContext.createCGImage(filtered, from: sourceImage.extent) else {
            return nil
        }
        let result = UIImage(cgImage: cgImage, scale: source.scale, orientation: .up)
        thumbnailCache.setObject(result, forKey: key)
        return result
    }
    #endif

    static func apply(_ grade: EditorColorAdjustment, to source: CIImage) -> CIImage {
        guard !grade.isNeutral else { return source }
        var image = applyPreset(grade.preset, intensity: grade.presetIntensity, to: source)

        if abs(grade.exposure) > 0.0001 {
            image = image.applyingFilter(
                "CIExposureAdjust",
                parameters: [kCIInputEVKey: grade.exposure * 2]
            )
        }

        if abs(grade.brightness) > 0.0001
            || abs(grade.contrast) > 0.0001
            || abs(grade.saturation) > 0.0001 {
            image = image.applyingFilter(
                "CIColorControls",
                parameters: [
                    kCIInputBrightnessKey: grade.brightness * 0.35,
                    kCIInputContrastKey: max(0.1, 1 + grade.contrast * 0.8),
                    kCIInputSaturationKey: max(0, 1 + grade.saturation)
                ]
            )
        }

        if abs(grade.brilliance) > 0.0001 {
            image = image
                .applyingFilter(
                    "CIVibrance",
                    parameters: ["inputAmount": grade.brilliance]
                )
                .applyingFilter(
                    "CIHighlightShadowAdjust",
                    parameters: [
                        "inputHighlightAmount": 1 - max(0, grade.brilliance) * 0.18,
                        "inputShadowAmount": max(0, grade.brilliance) * 0.28
                    ]
                )
        }

        if abs(grade.vibrance) > 0.0001 {
            image = image.applyingFilter(
                "CIVibrance",
                parameters: ["inputAmount": grade.vibrance]
            )
        }

        if abs(grade.dehaze) > 0.0001 {
            // A restrained local-contrast approximation that remains fast and
            // deterministic in both the AV compositor and offline export.
            image = image.applyingFilter(
                "CIUnsharpMask",
                parameters: [
                    kCIInputRadiusKey: 18 + abs(grade.dehaze) * 22,
                    kCIInputIntensityKey: grade.dehaze * 0.55
                ]
            )
            image = image.applyingFilter(
                "CIColorControls",
                parameters: [
                    kCIInputContrastKey: max(0.6, 1 + grade.dehaze * 0.16),
                    kCIInputSaturationKey: max(0.5, 1 + grade.dehaze * 0.08)
                ]
            )
        }

        if abs(grade.highlights) > 0.0001 || abs(grade.shadows) > 0.0001 {
            image = image.applyingFilter(
                "CIHighlightShadowAdjust",
                parameters: [
                    "inputHighlightAmount": min(max(1 + grade.highlights * 0.7, 0.3), 1.7),
                    "inputShadowAmount": grade.shadows
                ]
            )
        }

        if abs(grade.whites) > 0.0001 || abs(grade.blacks) > 0.0001 {
            image = applyWhitesAndBlacks(grade, to: image)
        }

        if abs(grade.temperature) > 0.0001 || abs(grade.tint) > 0.0001 {
            image = image.applyingFilter(
                "CITemperatureAndTint",
                parameters: [
                    "inputNeutral": CIVector(x: 6500, y: 0),
                    "inputTargetNeutral": CIVector(
                        x: 6500 - grade.temperature * 2300,
                        y: grade.tint * 125
                    )
                ]
            )
        }

        if abs(grade.hue) > 0.0001 {
            image = image.applyingFilter(
                "CIHueAdjust",
                parameters: [kCIInputAngleKey: grade.hue * .pi]
            )
        }

        if grade.fade > 0.0001 {
            image = image.applyingFilter(
                "CIColorControls",
                parameters: [
                    kCIInputBrightnessKey: grade.fade * 0.08,
                    kCIInputContrastKey: 1 - grade.fade * 0.34,
                    kCIInputSaturationKey: 1 - grade.fade * 0.16
                ]
            )
        }

        if !grade.hsl.isNeutral || !grade.curves.isNeutral || !grade.wheels.isNeutral {
            image = applyAdvancedLUT(grade, to: image)
        }

        if grade.sharpness > 0.0001 {
            image = image.applyingFilter(
                "CISharpenLuminance",
                parameters: [kCIInputSharpnessKey: grade.sharpness * 1.5]
            )
        }
        if grade.clarity > 0.0001 {
            image = image.applyingFilter(
                "CIUnsharpMask",
                parameters: [
                    kCIInputRadiusKey: 2 + grade.clarity * 8,
                    kCIInputIntensityKey: grade.clarity * 0.85
                ]
            )
        }
        if grade.grain > 0.0001 {
            image = applyGrain(grade.grain, to: image)
        }
        if grade.vignette > 0.0001 {
            image = image.applyingFilter(
                "CIVignette",
                parameters: [
                    kCIInputIntensityKey: grade.vignette * 2,
                    kCIInputRadiusKey: 0.7 + grade.vignette * 1.3
                ]
            )
        }
        if grade.masks.contains(where: \.isEffective) {
            image = applyMasks(grade.masks, to: image)
        }
        return image
    }

    /// Base correction before canvas transforms. Power windows are deliberately
    /// excluded so their normalized geometry can match the visible program frame.
    static func applyBase(_ grade: EditorColorAdjustment, to source: CIImage) -> CIImage {
        var base = grade
        base.masks = []
        return apply(base, to: source)
    }

    static func applyMasks(
        _ masks: [EditorColorMask],
        to source: CIImage,
        clipProgress: Double? = nil
    ) -> CIImage {
        masks.filter(\.isEffective).reduce(source) { image, authoredMask in
            let mask = clipProgress.map { authoredMask.resolved(at: $0) } ?? authoredMask
            let corrected = applyLocalAdjustment(mask.adjustment, to: image)
                .cropped(to: image.extent)
            let matte = makeMaskImage(mask, extent: image.extent)
            return corrected.applyingFilter(
                "CIBlendWithMask",
                parameters: [
                    kCIInputBackgroundImageKey: image,
                    kCIInputMaskImageKey: matte
                ]
            )
            .cropped(to: image.extent)
        }
    }

    private static func applyLocalAdjustment(
        _ adjustment: EditorMaskedColorAdjustment,
        to source: CIImage
    ) -> CIImage {
        var image = source
        if abs(adjustment.exposure) > 0.0001 {
            image = image.applyingFilter(
                "CIExposureAdjust",
                parameters: [kCIInputEVKey: adjustment.exposure * 2]
            )
        }
        if abs(adjustment.brightness) > 0.0001
            || abs(adjustment.contrast) > 0.0001
            || abs(adjustment.saturation) > 0.0001 {
            image = image.applyingFilter(
                "CIColorControls",
                parameters: [
                    kCIInputBrightnessKey: adjustment.brightness * 0.30,
                    kCIInputContrastKey: max(0.2, 1 + adjustment.contrast * 0.65),
                    kCIInputSaturationKey: max(0, 1 + adjustment.saturation)
                ]
            )
        }
        if abs(adjustment.vibrance) > 0.0001 {
            image = image.applyingFilter(
                "CIVibrance",
                parameters: ["inputAmount": adjustment.vibrance]
            )
        }
        if abs(adjustment.temperature) > 0.0001 || abs(adjustment.tint) > 0.0001 {
            image = image.applyingFilter(
                "CITemperatureAndTint",
                parameters: [
                    "inputNeutral": CIVector(x: 6500, y: 0),
                    "inputTargetNeutral": CIVector(
                        x: 6500 - adjustment.temperature * 1800,
                        y: adjustment.tint * 100
                    )
                ]
            )
        }
        if abs(adjustment.hue) > 0.0001 {
            image = image.applyingFilter(
                "CIHueAdjust",
                parameters: [kCIInputAngleKey: adjustment.hue * .pi]
            )
        }
        if adjustment.smoothness > 0.0001 {
            image = image.applyingFilter(
                "CINoiseReduction",
                parameters: [
                    "inputNoiseLevel": adjustment.smoothness * 0.05,
                    "inputSharpness": max(0, 0.35 - adjustment.smoothness * 0.28)
                ]
            )
        }
        return image
    }

    private static func makeMaskImage(
        _ mask: EditorColorMask,
        extent: CGRect
    ) -> CIImage {
        let center = CGPoint(
            x: extent.minX + extent.width * mask.centerX,
            y: extent.maxY - extent.height * mask.centerY
        )
        let radiusX = max(extent.width * mask.width * 0.5, 1)
        let radiusY = max(extent.height * mask.height * 0.5, 1)
        let feather = min(max(mask.feather, 0), 1)
        let white = CIColor(red: 1, green: 1, blue: 1, alpha: 1)
        let black = CIColor(red: 0, green: 0, blue: 0, alpha: 1)
        let blackBackground = CIImage(color: black).cropped(to: extent)
        let matte: CIImage

        switch mask.shape {
        case .face, .ellipse:
            let innerRadius = max(0.02, 1 - feather)
            let radial = CIFilter(
                name: "CIRadialGradient",
                parameters: [
                    "inputCenter": CIVector(x: 0, y: 0),
                    "inputRadius0": innerRadius,
                    "inputRadius1": 1.0,
                    "inputColor0": white,
                    "inputColor1": black
                ]
            )?.outputImage ?? blackBackground
            matte = radial
                .transformed(by: CGAffineTransform(scaleX: radiusX, y: radiusY))
                .transformed(by: CGAffineTransform(rotationAngle: mask.rotation * .pi))
                .transformed(by: CGAffineTransform(translationX: center.x, y: center.y))
                .cropped(to: extent)

        case .rectangle:
            let rect = CGRect(x: -radiusX, y: -radiusY, width: radiusX * 2, height: radiusY * 2)
            var shape = CIImage(color: white)
                .cropped(to: rect)
                .transformed(by: CGAffineTransform(rotationAngle: mask.rotation * .pi))
                .transformed(by: CGAffineTransform(translationX: center.x, y: center.y))
            if feather > 0.0001 {
                shape = shape.applyingFilter(
                    "CIGaussianBlur",
                    parameters: [kCIInputRadiusKey: feather * min(radiusX, radiusY) * 0.5]
                )
            }
            matte = shape.composited(over: blackBackground).cropped(to: extent)

        case .linear:
            let angle = mask.rotation * .pi
            let direction = CGVector(dx: cos(angle), dy: sin(angle))
            let transition = max(8, min(extent.width, extent.height) * max(mask.feather, 0.04) * 0.5)
            matte = CIFilter(
                name: "CILinearGradient",
                parameters: [
                    "inputPoint0": CIVector(
                        x: center.x - direction.dx * transition,
                        y: center.y - direction.dy * transition
                    ),
                    "inputPoint1": CIVector(
                        x: center.x + direction.dx * transition,
                        y: center.y + direction.dy * transition
                    ),
                    "inputColor0": white,
                    "inputColor1": black
                ]
            )?.outputImage?.cropped(to: extent) ?? blackBackground

        case .polygon:
            matte = makePolygonMask(mask, extent: extent, background: blackBackground)
        }

        var result = mask.isInverted
            ? matte.applyingFilter("CIColorInvert")
            : matte
        if mask.opacity < 0.9999 {
            let amount = min(max(mask.opacity, 0), 1)
            result = result.applyingFilter(
                "CIColorMatrix",
                parameters: [
                    "inputRVector": CIVector(x: amount, y: 0, z: 0, w: 0),
                    "inputGVector": CIVector(x: 0, y: amount, z: 0, w: 0),
                    "inputBVector": CIVector(x: 0, y: 0, z: amount, w: 0)
                ]
            )
        }
        return result.cropped(to: extent)
    }

    private static func makePolygonMask(
        _ mask: EditorColorMask,
        extent: CGRect,
        background: CIImage
    ) -> CIImage {
        guard mask.points.count >= 3 else { return background }
        var hasher = Hasher()
        hasher.combine(mask.points)
        hasher.combine(mask.feather)
        hasher.combine(Int(extent.width.rounded()))
        hasher.combine(Int(extent.height.rounded()))
        let cacheKey = String(hasher.finalize()) as NSString
        if let cached = polygonMaskCache.object(forKey: cacheKey) { return cached }
        let width = max(Int(extent.width.rounded(.up)), 1)
        let height = max(Int(extent.height.rounded(.up)), 1)
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return background }

        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let path = CGMutablePath()
        for (index, point) in mask.points.enumerated() {
            let destination = CGPoint(
                x: min(max(point.x, 0), 1) * Double(width),
                y: (1 - min(max(point.y, 0), 1)) * Double(height)
            )
            if index == 0 { path.move(to: destination) } else { path.addLine(to: destination) }
        }
        path.closeSubpath()
        context.addPath(path)
        context.setFillColor(gray: 1, alpha: 1)
        context.fillPath()
        guard let cgImage = context.makeImage() else { return background }
        var result = CIImage(cgImage: cgImage)
            .transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
        if mask.feather > 0.0001 {
            result = result.applyingFilter(
                "CIGaussianBlur",
                parameters: [
                    kCIInputRadiusKey: mask.feather * min(extent.width, extent.height) * 0.08
                ]
            )
        }
        let cropped = result.cropped(to: extent)
        polygonMaskCache.setObject(cropped, forKey: cacheKey)
        return cropped
    }

    private static func applyPreset(
        _ preset: EditorFilterPreset,
        intensity: Double,
        to source: CIImage
    ) -> CIImage {
        let amount = min(max(intensity, 0), 1)
        guard preset != .original, amount > 0.0001 else { return source }
        let recipe = FilterRecipe.recipe(for: preset)
        var filtered = source

        if let effect = recipe.photoEffect {
            filtered = filtered.applyingFilter(effect)
        }
        if abs(recipe.exposure) > 0.0001 {
            filtered = filtered.applyingFilter(
                "CIExposureAdjust",
                parameters: [kCIInputEVKey: recipe.exposure]
            )
        }
        filtered = filtered.applyingFilter(
            "CIColorControls",
            parameters: [
                kCIInputBrightnessKey: recipe.brightness,
                kCIInputContrastKey: recipe.contrast,
                kCIInputSaturationKey: recipe.saturation
            ]
        )
        if abs(recipe.temperature) > 0.0001 || abs(recipe.tint) > 0.0001 {
            filtered = filtered.applyingFilter(
                "CITemperatureAndTint",
                parameters: [
                    "inputNeutral": CIVector(x: 6500, y: 0),
                    "inputTargetNeutral": CIVector(
                        x: 6500 - recipe.temperature * 2100,
                        y: recipe.tint * 110
                    )
                ]
            )
        }
        if abs(recipe.hue) > 0.0001 {
            filtered = filtered.applyingFilter(
                "CIHueAdjust",
                parameters: [kCIInputAngleKey: recipe.hue]
            )
        }
        if recipe.vignette > 0 {
            filtered = filtered.applyingFilter(
                "CIVignette",
                parameters: [kCIInputIntensityKey: recipe.vignette, kCIInputRadiusKey: 1.2]
            )
        }
        return dissolve(from: source, to: filtered, amount: amount)
    }

    private static func applyWhitesAndBlacks(
        _ grade: EditorColorAdjustment,
        to image: CIImage
    ) -> CIImage {
        let blackLift = grade.blacks * 0.10
        let whiteGain = grade.whites * 0.15
        let coefficients = CIVector(
            x: blackLift,
            y: 1 - blackLift + whiteGain * 0.35,
            z: whiteGain * 0.65,
            w: 0
        )
        return image.applyingFilter(
            "CIColorPolynomial",
            parameters: [
                "inputRedCoefficients": coefficients,
                "inputGreenCoefficients": coefficients,
                "inputBlueCoefficients": coefficients
            ]
        )
    }

    private static func applyAdvancedLUT(
        _ grade: EditorColorAdjustment,
        to image: CIImage
    ) -> CIImage {
        let key = String(advancedHash(for: grade)) as NSString
        let data: Data
        if let cached = cubeCache.object(forKey: key) {
            data = cached as Data
        } else {
            data = makeCubeData(grade)
            cubeCache.setObject(data as NSData, forKey: key)
        }
        return image.applyingFilter(
            "CIColorCubeWithColorSpace",
            parameters: [
                "inputCubeDimension": cubeDimension,
                "inputCubeData": data,
                "inputColorSpace": CGColorSpaceCreateDeviceRGB()
            ]
        )
    }

    private static func advancedHash(for grade: EditorColorAdjustment) -> Int {
        var hasher = Hasher()
        hasher.combine(grade.hsl)
        hasher.combine(grade.curves)
        hasher.combine(grade.wheels)
        return hasher.finalize()
    }

    private static func makeCubeData(_ grade: EditorColorAdjustment) -> Data {
        let dimension = cubeDimension
        var cube = [Float]()
        cube.reserveCapacity(dimension * dimension * dimension * 4)
        let divisor = Double(dimension - 1)

        for blueIndex in 0..<dimension {
            for greenIndex in 0..<dimension {
                for redIndex in 0..<dimension {
                    var rgb = SIMD3<Double>(
                        Double(redIndex) / divisor,
                        Double(greenIndex) / divisor,
                        Double(blueIndex) / divisor
                    )
                    rgb = applyHSL(grade.hsl, to: rgb)
                    rgb.x = evaluate(grade.curves.red, at: rgb.x)
                    rgb.y = evaluate(grade.curves.green, at: rgb.y)
                    rgb.z = evaluate(grade.curves.blue, at: rgb.z)
                    rgb = applyWheels(grade.wheels, to: rgb)
                    rgb.x = evaluate(grade.curves.master, at: rgb.x)
                    rgb.y = evaluate(grade.curves.master, at: rgb.y)
                    rgb.z = evaluate(grade.curves.master, at: rgb.z)
                    cube.append(Float(clamp(rgb.x)))
                    cube.append(Float(clamp(rgb.y)))
                    cube.append(Float(clamp(rgb.z)))
                    cube.append(1)
                }
            }
        }
        return cube.withUnsafeBytes { Data($0) }
    }

    private static func applyHSL(
        _ adjustments: EditorHSLAdjustments,
        to rgb: SIMD3<Double>
    ) -> SIMD3<Double> {
        guard !adjustments.isNeutral else { return rgb }
        var hsv = rgbToHSV(rgb)
        var hueShift = 0.0
        var saturation = 0.0
        var lightness = 0.0
        var totalWeight = 0.0

        for band in adjustments.bands where !band.isNeutral {
            let distance = circularHueDistance(hsv.x, band.color.centerHue)
            let weight = max(0, 1 - distance / (50 / 360))
            hueShift += band.hue * (35 / 360) * weight
            saturation += band.saturation * weight
            lightness += band.lightness * weight
            totalWeight += weight
        }
        if totalWeight > 1 { saturation /= totalWeight; lightness /= totalWeight }
        hsv.x = (hsv.x + hueShift).truncatingRemainder(dividingBy: 1)
        if hsv.x < 0 { hsv.x += 1 }
        hsv.y = clamp(hsv.y * (1 + saturation))
        hsv.z = clamp(hsv.z + lightness * 0.35)
        return hsvToRGB(hsv)
    }

    private static func applyWheels(
        _ wheels: EditorColorWheels,
        to rgb: SIMD3<Double>
    ) -> SIMD3<Double> {
        guard !wheels.isNeutral else { return rgb }
        let luma = clamp(rgb.x * 0.2126 + rgb.y * 0.7152 + rgb.z * 0.0722)
        let liftWeight = pow(1 - luma, 2)
        let gainWeight = pow(luma, 2)
        let gammaWeight = max(0, 1 - abs(luma * 2 - 1))
        var result = rgb
        result += wheelOffset(wheels.lift) * liftWeight
        result += wheelOffset(wheels.gamma) * gammaWeight
        result += wheelOffset(wheels.gain) * gainWeight
        result += wheelOffset(wheels.offset)
        return result
    }

    private static func wheelOffset(_ wheel: EditorColorWheelValue) -> SIMD3<Double> {
        let chroma = SIMD3<Double>(
            wheel.x + wheel.y * 0.45,
            -wheel.x * 0.55 + wheel.y * 0.35,
            -wheel.y - wheel.x * 0.45
        ) * 0.22
        return chroma + SIMD3(repeating: wheel.luminance * 0.22)
    }

    private static func evaluate(_ points: [EditorCurvePoint], at input: Double) -> Double {
        let sorted = points.sorted { $0.x < $1.x }
        guard let first = sorted.first, let last = sorted.last else { return input }
        if input <= first.x { return first.y }
        if input >= last.x { return last.y }
        guard let upperIndex = sorted.firstIndex(where: { $0.x >= input }), upperIndex > 0 else {
            return input
        }
        let lower = sorted[upperIndex - 1]
        let upper = sorted[upperIndex]
        let span = max(upper.x - lower.x, 0.0001)
        let progress = (input - lower.x) / span
        return lower.y + (upper.y - lower.y) * progress
    }

    private static func applyGrain(_ amount: Double, to image: CIImage) -> CIImage {
        let extent = image.extent
        guard let generatedNoise = CIFilter(name: "CIRandomGenerator")?.outputImage else {
            return image
        }
        let noise = generatedNoise
            .applyingFilter(
                "CIColorMatrix",
                parameters: [
                    "inputRVector": CIVector(x: 0.18, y: 0, z: 0, w: 0),
                    "inputGVector": CIVector(x: 0, y: 0.18, z: 0, w: 0),
                    "inputBVector": CIVector(x: 0, y: 0, z: 0.18, w: 0),
                    "inputBiasVector": CIVector(x: 0.41, y: 0.41, z: 0.41, w: 0)
                ]
            )
            .cropped(to: extent)
        let textured = noise.applyingFilter(
            "CISoftLightBlendMode",
            parameters: [kCIInputBackgroundImageKey: image]
        )
        return dissolve(from: image, to: textured, amount: amount * 0.65)
    }

    private static func dissolve(from source: CIImage, to target: CIImage, amount: Double) -> CIImage {
        source.applyingFilter(
            "CIDissolveTransition",
            parameters: [
                kCIInputTargetImageKey: target,
                kCIInputTimeKey: min(max(amount, 0), 1)
            ]
        )
    }

    private static func rgbToHSV(_ rgb: SIMD3<Double>) -> SIMD3<Double> {
        let maximum = max(rgb.x, rgb.y, rgb.z)
        let minimum = min(rgb.x, rgb.y, rgb.z)
        let delta = maximum - minimum
        var hue = 0.0
        if delta > 0.000001 {
            if maximum == rgb.x {
                hue = ((rgb.y - rgb.z) / delta).truncatingRemainder(dividingBy: 6)
            } else if maximum == rgb.y {
                hue = (rgb.z - rgb.x) / delta + 2
            } else {
                hue = (rgb.x - rgb.y) / delta + 4
            }
            hue /= 6
            if hue < 0 { hue += 1 }
        }
        return SIMD3(hue, maximum == 0 ? 0 : delta / maximum, maximum)
    }

    private static func hsvToRGB(_ hsv: SIMD3<Double>) -> SIMD3<Double> {
        let scaledHue = hsv.x * 6
        let sector = Int(floor(scaledHue)) % 6
        let fraction = scaledHue - floor(scaledHue)
        let p = hsv.z * (1 - hsv.y)
        let q = hsv.z * (1 - fraction * hsv.y)
        let t = hsv.z * (1 - (1 - fraction) * hsv.y)
        switch sector {
        case 0: return SIMD3(hsv.z, t, p)
        case 1: return SIMD3(q, hsv.z, p)
        case 2: return SIMD3(p, hsv.z, t)
        case 3: return SIMD3(p, q, hsv.z)
        case 4: return SIMD3(t, p, hsv.z)
        default: return SIMD3(hsv.z, p, q)
        }
    }

    private static func circularHueDistance(_ lhs: Double, _ rhs: Double) -> Double {
        let distance = abs(lhs - rhs)
        return min(distance, 1 - distance)
    }

    private static func clamp(_ value: Double) -> Double { min(max(value, 0), 1) }
}

private struct FilterRecipe {
    var brightness = 0.0
    var exposure = 0.0
    var contrast = 1.0
    var saturation = 1.0
    var temperature = 0.0
    var tint = 0.0
    var hue = 0.0
    var vignette = 0.0
    var photoEffect: String?

    static func recipe(for preset: EditorFilterPreset) -> FilterRecipe {
        switch preset {
        case .original: return .init()
        case .vivid: return .init(contrast: 1.16, saturation: 1.38)
        case .warm: return .init(contrast: 1.05, saturation: 1.08, temperature: 0.72, tint: 0.05)
        case .cool: return .init(contrast: 1.05, saturation: 1.05, temperature: -0.72, tint: -0.05)
        case .cinematic: return .init(contrast: 1.22, saturation: 0.82, temperature: -0.18, tint: 0.15)
        case .faded: return .init(brightness: 0.06, contrast: 0.82, saturation: 0.72)
        case .mono: return .init(photoEffect: "CIPhotoEffectMono")
        case .noir: return .init(photoEffect: "CIPhotoEffectNoir")
        case .chrome: return .init(photoEffect: "CIPhotoEffectChrome")
        case .natural: return .init(brightness: 0.02, contrast: 1.04, saturation: 1.05)
        case .fresh: return .init(brightness: 0.05, exposure: 0.08, contrast: 0.96, saturation: 1.12, temperature: -0.12)
        case .clean: return .init(brightness: 0.06, exposure: 0.12, contrast: 1.08, saturation: 0.92)
        case .goldenHour: return .init(exposure: 0.08, contrast: 1.08, saturation: 1.16, temperature: 0.82, tint: 0.08)
        case .portraitGlow: return .init(brightness: 0.07, exposure: 0.1, contrast: 0.9, saturation: 1.04, temperature: 0.28, tint: 0.12)
        case .blush: return .init(brightness: 0.04, contrast: 0.96, saturation: 1.08, temperature: 0.18, tint: 0.34)
        case .softSkin: return .init(brightness: 0.08, exposure: 0.08, contrast: 0.86, saturation: 0.9, temperature: 0.22)
        case .tealOrange: return .init(contrast: 1.24, saturation: 1.08, temperature: -0.18, tint: 0.24, hue: -0.08)
        case .blockbuster: return .init(exposure: -0.08, contrast: 1.32, saturation: 0.88, temperature: -0.28, tint: 0.2, vignette: 0.45)
        case .moody: return .init(exposure: -0.18, contrast: 1.2, saturation: 0.72, temperature: -0.18, tint: 0.16, vignette: 0.5)
        case .nightDrive: return .init(exposure: -0.12, contrast: 1.28, saturation: 1.18, temperature: -0.55, tint: 0.32, vignette: 0.48)
        case .desert: return .init(brightness: 0.03, contrast: 1.14, saturation: 0.94, temperature: 0.62, tint: 0.08)
        case .forest: return .init(exposure: -0.05, contrast: 1.16, saturation: 1.02, temperature: -0.2, tint: -0.24, hue: 0.05)
        case .ocean: return .init(brightness: 0.02, contrast: 1.1, saturation: 1.2, temperature: -0.52, tint: -0.12)
        case .vintageBronze: return .init(contrast: 1.08, saturation: 0.72, temperature: 0.65, tint: 0.14, vignette: 0.34, photoEffect: "CIPhotoEffectTransfer")
        case .romance: return .init(brightness: 0.06, contrast: 0.88, saturation: 0.9, temperature: 0.28, tint: 0.26)
        case .retro: return .init(brightness: 0.04, contrast: 1.04, saturation: 0.78, temperature: 0.4, tint: 0.16, photoEffect: "CIPhotoEffectProcess")
        case .sepia: return .init(contrast: 1.05, saturation: 0.74, temperature: 0.52, photoEffect: "CISepiaTone")
        case .polaroid: return .init(brightness: 0.08, exposure: 0.12, contrast: 0.88, saturation: 0.82, temperature: 0.24, tint: 0.1, photoEffect: "CIPhotoEffectInstant")
        case .fadedFilm: return .init(brightness: 0.07, contrast: 0.78, saturation: 0.66, temperature: 0.22, tint: 0.08, vignette: 0.25)
        case .filmNoir: return .init(contrast: 1.35, saturation: 0, vignette: 0.65, photoEffect: "CIPhotoEffectNoir")
        case .tokyo: return .init(contrast: 1.16, saturation: 1.22, temperature: -0.22, tint: 0.42, hue: -0.12)
        case .cyberpunk: return .init(exposure: -0.05, contrast: 1.34, saturation: 1.52, temperature: -0.5, tint: 0.72, hue: 0.18, vignette: 0.46)
        case .dreamy: return .init(brightness: 0.09, exposure: 0.1, contrast: 0.75, saturation: 0.9, temperature: -0.08, tint: 0.3)
        case .neon: return .init(exposure: -0.06, contrast: 1.38, saturation: 1.62, temperature: -0.24, tint: 0.45, hue: 0.12)
        case .aqua: return .init(brightness: 0.03, contrast: 1.08, saturation: 1.24, temperature: -0.62, tint: -0.3, hue: 0.05)
        case .sunset: return .init(exposure: 0.06, contrast: 1.12, saturation: 1.3, temperature: 0.78, tint: 0.28)
        case .lavender: return .init(brightness: 0.05, contrast: 0.94, saturation: 0.96, temperature: -0.18, tint: 0.5)
        case .silver: return .init(brightness: 0.03, contrast: 1.04, saturation: 0, photoEffect: "CIPhotoEffectTonal")
        case .graphite: return .init(exposure: -0.08, contrast: 1.18, saturation: 0, photoEffect: "CIPhotoEffectMono")
        case .highContrastBW: return .init(contrast: 1.52, saturation: 0, vignette: 0.38, photoEffect: "CIPhotoEffectNoir")
        }
    }
}
