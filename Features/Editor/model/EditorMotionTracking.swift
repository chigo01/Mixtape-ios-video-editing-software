//
//  EditorMotionTracking.swift
//  Mixtape
//
//  CapCut-style tracking box, transform smoothing, and clip stabilization.
//  Preview and export consume the same samples.
//

import CoreGraphics
import CoreMedia
import Foundation

enum EditorMotionSmoothing: String, Codable, CaseIterable, Identifiable, Hashable {
    case none
    case light
    case medium
    case heavy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "None"
        case .light: return "Light"
        case .medium: return "Medium"
        case .heavy: return "Heavy"
        }
    }

    /// Gaussian radius in samples. Zero leaves the recorded path untouched.
    var sampleRadius: Int {
        switch self {
        case .none: return 0
        case .light: return 2
        case .medium: return 5
        case .heavy: return 10
        }
    }
}

/// One clip-local motion sample. Position is normalized in top-left canvas space.
struct EditorMotionTrackSample: Codable, Hashable {
    var progress: Double
    var x: Double
    var y: Double
    /// Radians, clockwise from the seed orientation.
    var rotation: Double
    /// Scale relative to the seed (1 = unchanged).
    var scale: Double
    var confidence: Double

    static func seed(
        progress: Double,
        x: Double,
        y: Double,
        rotation: Double = 0,
        scale: Double = 1
    ) -> EditorMotionTrackSample {
        EditorMotionTrackSample(
            progress: min(max(progress, 0), 1),
            x: min(max(x, 0), 1),
            y: min(max(y, 0), 1),
            rotation: rotation,
            scale: max(scale, 0.01),
            confidence: 1
        )
    }

    mutating func sanitize() {
        progress = min(max(progress, 0), 1)
        x = min(max(x, -0.25), 1.25)
        y = min(max(y, -0.25), 1.25)
        rotation = min(max(rotation, -.pi), .pi)
        scale = min(max(scale, 0.05), 8)
        confidence = min(max(confidence, 0), 1)
    }
}

/// A CapCut-style tracking box: dragged onto a subject in one clip, then used
/// to drive an attached text or graphic overlay's position, rotation, and scale.
struct EditorMotionTrack: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var seedX: Double
    var seedY: Double
    var seedWidth: Double
    var seedHeight: Double
    var seedRotation: Double
    var seedProgress: Double
    var smoothing: EditorMotionSmoothing
    var samples: [EditorMotionTrackSample]

    init(
        id: UUID = UUID(),
        name: String,
        seedX: Double = 0.5,
        seedY: Double = 0.5,
        seedWidth: Double = 0.28,
        seedHeight: Double = 0.18,
        seedRotation: Double = 0,
        seedProgress: Double = 0,
        smoothing: EditorMotionSmoothing = .light,
        samples: [EditorMotionTrackSample] = []
    ) {
        self.id = id
        self.name = name
        self.seedX = min(max(seedX, 0), 1)
        self.seedY = min(max(seedY, 0), 1)
        self.seedWidth = min(max(seedWidth, 0.02), 0.9)
        self.seedHeight = min(max(seedHeight, 0.02), 0.9)
        self.seedRotation = seedRotation
        self.seedProgress = min(max(seedProgress, 0), 1)
        self.smoothing = smoothing
        self.samples = Self.normalized(samples)
    }

    var isTracked: Bool { samples.count > 1 }

    var seedSample: EditorMotionTrackSample {
        .seed(
            progress: seedProgress,
            x: seedX,
            y: seedY,
            rotation: seedRotation,
            scale: 1
        )
    }

    func resolved(at progress: Double) -> EditorMotionTrackSample {
        let raw = Self.interpolated(samples, at: progress, fallback: seedSample)
        return EditorMotionSmoother.sample(samples, at: progress, radius: smoothing.sampleRadius, fallback: raw)
    }

    mutating func replaceSamples(_ newSamples: [EditorMotionTrackSample]) {
        samples = Self.normalized(newSamples)
    }

    mutating func translate(dx: Double, dy: Double) {
        seedX = min(max(seedX + dx, 0), 1)
        seedY = min(max(seedY + dy, 0), 1)
        for index in samples.indices {
            samples[index].x = min(max(samples[index].x + dx, -0.25), 1.25)
            samples[index].y = min(max(samples[index].y + dy, -0.25), 1.25)
        }
    }

    mutating func resize(width: Double, height: Double) {
        seedWidth = min(max(width, 0.02), 0.9)
        seedHeight = min(max(height, 0.02), 0.9)
    }

    /// Inserts a user correction at the playhead without translating the
    /// entire recorded path. Re-running Vision can then use this sample as a
    /// trustworthy new seed while samples on either side remain editable.
    mutating func correct(at progress: Double, x: Double, y: Double) {
        let progress = min(max(progress, 0), 1)
        let current = resolved(at: progress)
        var correction = current
        correction.progress = progress
        correction.x = min(max(x, -0.25), 1.25)
        correction.y = min(max(y, -0.25), 1.25)
        correction.confidence = 1
        samples.removeAll { abs($0.progress - progress) < 0.002 }
        samples.append(correction)
        samples = Self.normalized(samples)
    }

    func split(at progress: Double) -> (left: EditorMotionTrack, right: EditorMotionTrack) {
        let splitProgress = min(max(progress, 0.000_1), 0.999_9)
        let leftSamples = samples
            .filter { $0.progress <= splitProgress }
            .map { sample -> EditorMotionTrackSample in
                var copy = sample
                copy.progress = min(max(sample.progress / splitProgress, 0), 1)
                return copy
            }
        let rightSamples = samples
            .filter { $0.progress >= splitProgress }
            .map { sample -> EditorMotionTrackSample in
                var copy = sample
                copy.progress = min(
                    max((sample.progress - splitProgress) / (1 - splitProgress), 0),
                    1
                )
                return copy
            }
        var left = self
        left.seedProgress = min(seedProgress / splitProgress, 1)
        left.samples = Self.normalized(leftSamples)
        var right = self
        right.id = UUID()
        right.seedProgress = min(max((seedProgress - splitProgress) / (1 - splitProgress), 0), 1)
        right.samples = Self.normalized(rightSamples)
        return (left, right)
    }

    static func interpolated(
        _ samples: [EditorMotionTrackSample],
        at progress: Double,
        fallback: EditorMotionTrackSample
    ) -> EditorMotionTrackSample {
        let ordered = samples.sorted { $0.progress < $1.progress }
        guard let first = ordered.first else { return fallback }
        let progress = min(max(progress, 0), 1)
        if progress <= first.progress { return first }
        guard let last = ordered.last, progress < last.progress else {
            return ordered.last ?? fallback
        }
        let lower = ordered.last(where: { $0.progress <= progress }) ?? first
        let upper = ordered.first(where: { $0.progress >= progress }) ?? last
        let span = max(upper.progress - lower.progress, 0.000_001)
        let amount = min(max((progress - lower.progress) / span, 0), 1)
        func blend(_ a: Double, _ b: Double) -> Double { a + (b - a) * amount }
        var sample = lower
        sample.progress = progress
        sample.x = blend(lower.x, upper.x)
        sample.y = blend(lower.y, upper.y)
        sample.rotation = blend(lower.rotation, upper.rotation)
        sample.scale = blend(lower.scale, upper.scale)
        sample.confidence = blend(lower.confidence, upper.confidence)
        return sample
    }

    private static func normalized(_ samples: [EditorMotionTrackSample]) -> [EditorMotionTrackSample] {
        var unique: [EditorMotionTrackSample] = []
        for var sample in samples.sorted(by: { $0.progress < $1.progress }) {
            sample.sanitize()
            if let last = unique.last, abs(last.progress - sample.progress) < 0.000_01 {
                unique[unique.count - 1] = sample
            } else {
                unique.append(sample)
            }
        }
        return Array(unique.prefix(720))
    }
}

enum EditorStabilizationMode: String, Codable, CaseIterable, Identifiable, Hashable {
    case smooth
    case lock

    var id: String { rawValue }

    var title: String {
        switch self {
        case .smooth: return "Smooth"
        case .lock: return "Lock"
        }
    }

    var detail: String {
        switch self {
        case .smooth: return "Keep pans, remove jitter"
        case .lock: return "Pin the frame like a tripod"
        }
    }
}

/// Handheld-camera compensation stored on a clip. Strength, mode, and crop are
/// live over the same analyzed path so sliders do not require re-analysis.
struct EditorStabilizationSettings: Codable, Hashable {
    var isEnabled: Bool
    var mode: EditorStabilizationMode
    /// 0 keeps the original camera path; 1 is maximum smoothing or full lock.
    var smoothness: Double
    /// Extra punch-in on top of auto-crop, or the sole crop when auto is off. 0...0.5.
    var crop: Double
    var autoCrop: Bool
    /// Replicate edge pixels instead of showing empty canvas after the warp.
    var fillEdges: Bool
    /// Auto-crop computed from the current path/mode/strength. Recalculated
    /// on analysis and slider changes — not a per-frame cost.
    var fittedCrop: Double
    var samples: [EditorMotionTrackSample]

    static let disabled = EditorStabilizationSettings(
        isEnabled: false,
        mode: .smooth,
        smoothness: 0.72,
        crop: 0,
        autoCrop: true,
        fillEdges: true,
        samples: []
    )

    init(
        isEnabled: Bool = false,
        mode: EditorStabilizationMode = .smooth,
        smoothness: Double = 0.72,
        crop: Double = 0,
        autoCrop: Bool = true,
        fillEdges: Bool = true,
        fittedCrop: Double = 0,
        samples: [EditorMotionTrackSample] = []
    ) {
        self.isEnabled = isEnabled
        self.mode = mode
        self.smoothness = min(max(smoothness, 0), 1)
        self.crop = min(max(crop, 0), 0.5)
        self.autoCrop = autoCrop
        self.fillEdges = fillEdges
        self.fittedCrop = min(max(fittedCrop, 0), 0.5)
        self.samples = Self.normalizedForStabilization(samples)
        if autoCrop { self.fittedCrop = recommendedCrop() }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        mode = try c.decodeIfPresent(EditorStabilizationMode.self, forKey: .mode) ?? .smooth
        smoothness = min(max(try c.decodeIfPresent(Double.self, forKey: .smoothness) ?? 0.72, 0), 1)
        crop = min(max(try c.decodeIfPresent(Double.self, forKey: .crop) ?? 0, 0), 0.5)
        autoCrop = try c.decodeIfPresent(Bool.self, forKey: .autoCrop) ?? false
        fillEdges = try c.decodeIfPresent(Bool.self, forKey: .fillEdges) ?? true
        fittedCrop = 0
        samples = Self.normalizedForStabilization(
            try c.decodeIfPresent([EditorMotionTrackSample].self, forKey: .samples) ?? []
        )
        if autoCrop { fittedCrop = recommendedCrop() }
    }

    var isAnalyzed: Bool { samples.count > 1 }

    var isActive: Bool {
        isEnabled && (isAnalyzed && smoothness > 0.001 || effectiveCrop > 0.001)
    }

    /// Crop actually applied: auto coverage from the path, plus the slider.
    var effectiveCrop: Double {
        let automatic = autoCrop ? fittedCrop : 0
        return min(max(automatic + crop, 0), 0.5)
    }

    mutating func refreshFittedCrop() {
        fittedCrop = autoCrop && isAnalyzed ? recommendedCrop() : 0
    }

    /// Gaussian radius in samples. Smooth uses a short window so pans survive;
    /// Lock uses a longer one as the blend toward the mean pose.
    var sampleRadius: Int {
        guard samples.count > 2 else { return 0 }
        let seconds = mode == .lock
            ? (0.35 + smoothness * 1.6)
            : (0.18 + smoothness * 1.15)
        let radius = Int((seconds * 24).rounded())
        return min(max(radius, 0), max(1, samples.count / 2))
    }

    func transform(at progress: Double, renderSize: CGSize) -> CGAffineTransform {
        guard isEnabled else { return .identity }
        let cropScale = 1 / max(1 - effectiveCrop, 0.5)
        let center = CGPoint(x: renderSize.width / 2, y: renderSize.height / 2)
        let residual = residualMotion(at: progress)
        // Invert residual translation. Vision registration is Y-up; AVFoundation
        // layer instructions are top-left (Y down), so X flips and Y does not.
        let tx = -residual.dx * Double(renderSize.width)
        let ty = residual.dy * Double(renderSize.height)
        let cosine = cos(-residual.rotation) * cropScale
        let sine = sin(-residual.rotation) * cropScale
        return CGAffineTransform(
            a: cosine,
            b: sine,
            c: -sine,
            d: cosine,
            tx: center.x + tx - cosine * center.x - (-sine) * center.y,
            ty: center.y + ty - sine * center.x - cosine * center.y
        )
    }

    /// Crop that keeps the canvas covered after the inverse warp at the
    /// current mode and strength, with a small pad for interpolation.
    func recommendedCrop() -> Double {
        guard isAnalyzed, smoothness > 0.001 else { return 0 }
        var maxScale = 1.0
        let steps = min(64, max(samples.count, 8))
        for index in 0...steps {
            let progress = Double(index) / Double(steps)
            let residual = residualMotion(at: progress)
            maxScale = max(
                maxScale,
                Self.coverageScale(
                    dx: residual.dx,
                    dy: residual.dy,
                    rotation: residual.rotation
                )
            )
        }
        maxScale = min(maxScale * 1.08, 2.0)
        return max(0, 1 - 1 / maxScale)
    }

    func residualMotion(at progress: Double) -> (dx: Double, dy: Double, rotation: Double) {
        guard isAnalyzed, smoothness > 0.001 else { return (0, 0, 0) }
        let fallback = samples.first ?? .seed(progress: 0, x: 0.5, y: 0.5)
        let raw = EditorMotionTrack.interpolated(samples, at: progress, fallback: fallback)
        let target = targetPose(at: progress, raw: raw)
        var dx = raw.x - target.x
        var dy = raw.y - target.y
        var rotation = Self.wrappedDelta(raw.rotation, minus: target.rotation)
        dx = min(max(dx, -0.4), 0.4)
        dy = min(max(dy, -0.4), 0.4)
        rotation = min(max(rotation, -25 * .pi / 180), 25 * .pi / 180)
        return (dx, dy, rotation)
    }

    private func targetPose(
        at progress: Double,
        raw: EditorMotionTrackSample
    ) -> EditorMotionTrackSample {
        let local = EditorMotionSmoother.sampleAtProgress(
            samples,
            at: progress,
            radius: sampleRadius,
            fallback: raw
        )
        guard mode == .lock else { return local }
        let mean = meanPose
        if smoothness >= 0.995 { return mean }
        return Self.blend(local, toward: mean, amount: smoothness)
    }

    private var meanPose: EditorMotionTrackSample {
        guard !samples.isEmpty else { return .seed(progress: 0.5, x: 0.5, y: 0.5) }
        let count = Double(samples.count)
        let x = samples.reduce(0.0) { $0 + $1.x } / count
        let y = samples.reduce(0.0) { $0 + $1.y } / count
        let rotation = samples.reduce(0.0) { $0 + $1.rotation } / count
        return EditorMotionTrackSample(
            progress: 0.5,
            x: x,
            y: y,
            rotation: rotation,
            scale: 1,
            confidence: 1
        )
    }

    private static func blend(
        _ from: EditorMotionTrackSample,
        toward: EditorMotionTrackSample,
        amount: Double
    ) -> EditorMotionTrackSample {
        let amount = min(max(amount, 0), 1)
        var sample = from
        sample.x = from.x + (toward.x - from.x) * amount
        sample.y = from.y + (toward.y - from.y) * amount
        sample.rotation = from.rotation + wrappedDelta(toward.rotation, minus: from.rotation) * amount
        return sample
    }

    /// Scale about the canvas center needed so a translated/rotated unit
    /// frame still covers the canvas.
    private static func coverageScale(dx: Double, dy: Double, rotation: Double) -> Double {
        let cosine = abs(cos(rotation))
        let sine = abs(sin(rotation))
        let halfX = 0.5 * (cosine + sine) + abs(dx)
        let halfY = 0.5 * (sine + cosine) + abs(dy)
        return max(halfX / 0.5, halfY / 0.5, 1)
    }

    fileprivate static func wrappedDelta(_ value: Double, minus origin: Double) -> Double {
        var delta = value - origin
        while delta > .pi { delta -= 2 * .pi }
        while delta < -.pi { delta += 2 * .pi }
        return delta
    }

    func split(at progress: Double) -> (left: EditorStabilizationSettings, right: EditorStabilizationSettings) {
        let splitProgress = min(max(progress, 0.000_1), 0.999_9)
        let leftSamples = samples
            .filter { $0.progress <= splitProgress }
            .map { sample -> EditorMotionTrackSample in
                var copy = sample
                copy.progress = min(max(sample.progress / splitProgress, 0), 1)
                return copy
            }
        let rightSamples = samples
            .filter { $0.progress >= splitProgress }
            .map { sample -> EditorMotionTrackSample in
                var copy = sample
                copy.progress = min(
                    max((sample.progress - splitProgress) / (1 - splitProgress), 0),
                    1
                )
                return copy
            }
        return (
            EditorStabilizationSettings(
                isEnabled: isEnabled,
                mode: mode,
                smoothness: smoothness,
                crop: crop,
                autoCrop: autoCrop,
                fillEdges: fillEdges,
                samples: leftSamples
            ),
            EditorStabilizationSettings(
                isEnabled: isEnabled,
                mode: mode,
                smoothness: smoothness,
                crop: crop,
                autoCrop: autoCrop,
                fillEdges: fillEdges,
                samples: rightSamples
            )
        )
    }

    enum CodingKeys: String, CodingKey {
        case isEnabled, mode, smoothness, crop, autoCrop, fillEdges, samples
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(isEnabled, forKey: .isEnabled)
        try c.encode(mode, forKey: .mode)
        try c.encode(smoothness, forKey: .smoothness)
        try c.encode(crop, forKey: .crop)
        try c.encode(autoCrop, forKey: .autoCrop)
        try c.encode(fillEdges, forKey: .fillEdges)
        try c.encode(samples, forKey: .samples)
    }

    fileprivate static func normalizedForStabilization(
        _ samples: [EditorMotionTrackSample]
    ) -> [EditorMotionTrackSample] {
        var unique: [EditorMotionTrackSample] = []
        var previousRotation: Double?
        for var sample in samples.sorted(by: { $0.progress < $1.progress }) {
            sample.progress = min(max(sample.progress, 0), 1)
            sample.x = min(max(sample.x, -0.25), 1.25)
            sample.y = min(max(sample.y, -0.25), 1.25)
            sample.scale = 1
            sample.confidence = min(max(sample.confidence, 0), 1)
            // Keep rotation continuous so lerp never takes the long way
            // through 0 between +π and −π (that spun the frame in preview).
            if let previous = previousRotation {
                sample.rotation = previous + wrappedDelta(sample.rotation, minus: previous)
            }
            previousRotation = sample.rotation
            if let last = unique.last, abs(last.progress - sample.progress) < 0.000_01 {
                unique[unique.count - 1] = sample
            } else {
                unique.append(sample)
            }
        }
        return Array(unique.prefix(720))
    }
}

enum EditorMotionSmoother {
    static func sample(
        _ samples: [EditorMotionTrackSample],
        at progress: Double,
        radius: Int,
        fallback: EditorMotionTrackSample
    ) -> EditorMotionTrackSample {
        let ordered = samples.sorted { $0.progress < $1.progress }
        guard radius > 0, ordered.count > 2 else { return fallback }
        let progress = min(max(progress, 0), 1)
        let index = ordered.enumerated().min(by: {
            abs($0.element.progress - progress) < abs($1.element.progress - progress)
        })?.offset ?? 0
        let lower = max(0, index - radius)
        let upper = min(ordered.count - 1, index + radius)
        let sigma = max(Double(radius) / 2.4, 0.65)
        var weightSum = 0.0
        var x = 0.0
        var y = 0.0
        var rotation = 0.0
        var scale = 0.0
        var confidence = 0.0
        for sampleIndex in lower...upper {
            let delta = Double(sampleIndex - index)
            let weight = exp(-(delta * delta) / (2 * sigma * sigma))
            let sample = ordered[sampleIndex]
            x += sample.x * weight
            y += sample.y * weight
            rotation += sample.rotation * weight
            scale += sample.scale * weight
            confidence += sample.confidence * weight
            weightSum += weight
        }
        guard weightSum > 0 else { return fallback }
        return EditorMotionTrackSample(
            progress: progress,
            x: x / weightSum,
            y: y / weightSum,
            rotation: rotation / weightSum,
            scale: scale / weightSum,
            confidence: confidence / weightSum
        )
    }

    /// Time-weighted Gaussian so 30 fps preview between sparse analysis
    /// samples does not sawtooth against a nearest-index smoother.
    static func sampleAtProgress(
        _ samples: [EditorMotionTrackSample],
        at progress: Double,
        radius: Int,
        fallback: EditorMotionTrackSample
    ) -> EditorMotionTrackSample {
        let ordered = samples.sorted { $0.progress < $1.progress }
        guard radius > 0, ordered.count > 2 else { return fallback }
        let progress = min(max(progress, 0), 1)
        let dt = max(
            (ordered.last!.progress - ordered.first!.progress) / Double(max(ordered.count - 1, 1)),
            0.000_1
        )
        let sigma = max(Double(radius) * dt / 2.4, dt * 0.75)
        var weightSum = 0.0
        var x = 0.0
        var y = 0.0
        var rotation = 0.0
        var scale = 0.0
        var confidence = 0.0
        for sample in ordered {
            let delta = sample.progress - progress
            let weight = exp(-(delta * delta) / (2 * sigma * sigma))
            if weight < 0.000_1 { continue }
            x += sample.x * weight
            y += sample.y * weight
            rotation += sample.rotation * weight
            scale += sample.scale * weight
            confidence += sample.confidence * weight
            weightSum += weight
        }
        guard weightSum > 0 else { return fallback }
        return EditorMotionTrackSample(
            progress: progress,
            x: x / weightSum,
            y: y / weightSum,
            rotation: rotation / weightSum,
            scale: scale / weightSum,
            confidence: confidence / weightSum
        )
    }
}

/// Immutable per-frame adapter used by the GPU compositor for clip stabilization.
struct EditorRenderStabilization: Hashable {
    let settings: EditorStabilizationSettings

    var isActive: Bool { settings.isActive }

    func transform(at progress: Double, renderSize: CGSize) -> CGAffineTransform {
        settings.transform(at: progress, renderSize: renderSize)
    }
}

/// Follows a host clip's track so overlays and (via CA) titles stay locked to footage.
struct EditorRenderTrackedMotion: Hashable {
    let hostTimeRange: CMTimeRange
    let samples: [EditorMotionTrackSample]
    let seedX: Double
    let seedY: Double
    let seedRotation: Double
    let seedScale: Double
    let smoothing: EditorMotionSmoothing
    let attachRotation: Bool
    let attachScale: Bool

    var isActive: Bool { samples.count > 1 }

    func extraTransform(at compositionTime: CMTime, renderSize: CGSize) -> CGAffineTransform {
        let sample = resolved(at: compositionTime)
        let dx = sample.x - seedX
        let dy = sample.y - seedY
        let rotation = attachRotation ? sample.rotation - seedRotation : 0
        let scale = attachScale
            ? sample.scale / max(seedScale, 0.000_001)
            : 1
        // This is concatenated after the overlay's own placement. Pivot around
        // the tracked seed so optional rotation/scale happens on the subject
        // rather than around the center of the project canvas.
        let pivot = CGPoint(
            x: seedX * Double(renderSize.width),
            y: seedY * Double(renderSize.height)
        )
        let tx = dx * Double(renderSize.width)
        // Same sign as overlay/text yOffset: SwiftUI down is positive, then
        // the compositor's Core Image flip maps it onto the preview.
        let ty = dy * Double(renderSize.height)
        let cosine = cos(rotation)
        let sine = sin(rotation)
        let a = cosine * scale
        let b = sine * scale
        let c = -sine * scale
        let d = cosine * scale
        return CGAffineTransform(
            a: a,
            b: b,
            c: c,
            d: d,
            tx: pivot.x + tx - a * pivot.x - c * pivot.y,
            ty: pivot.y + ty - b * pivot.x - d * pivot.y
        )
    }

    func resolved(at compositionTime: CMTime) -> EditorMotionTrackSample {
        let duration = max(hostTimeRange.duration.seconds, 0.000_001)
        let progress = min(
            max((compositionTime - hostTimeRange.start).seconds / duration, 0),
            1
        )
        let fallback = EditorMotionTrackSample.seed(
            progress: progress,
            x: seedX,
            y: seedY,
            rotation: seedRotation,
            scale: seedScale
        )
        let raw = EditorMotionTrack.interpolated(samples, at: progress, fallback: fallback)
        return EditorMotionSmoother.sample(
            samples,
            at: progress,
            radius: smoothing.sampleRadius,
            fallback: raw
        )
    }
}

enum EditorMotionTrackingError: LocalizedError {
    case unavailableFrame
    case lostSubject
    case notVideo
    case cancelled

    var errorDescription: String? {
        switch self {
        case .unavailableFrame:
            return "This clip could not be read for analysis. Wait for Photos to finish loading the video, then try again."
        case .lostSubject:
            return "The tracker lost the subject. Try a tighter box on a higher-contrast area."
        case .notVideo:
            return "Motion tracking needs a video clip."
        case .cancelled:
            return "Tracking cancelled."
        }
    }
}
