//
//  EditorSpeedRamp.swift
//  Mixtape
//

import Foundation

/// How speed is interpolated between control points positioned in source time.
enum EditorSpeedRampInterpolation: String, Codable, CaseIterable, Identifiable, Hashable {
    case linear
    case smooth

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

/// One editable control point. `position` is normalized source progress (0...1),
/// while `speed` is the source-time multiplier at that point.
struct EditorSpeedRampPoint: Codable, Hashable, Identifiable {
    var position: Double
    var speed: Float

    var id: Double { position }

    init(position: Double, speed: Float) {
        self.position = min(max(position, 0), 1)
        self.speed = EditorSpeedRamp.clampedSpeed(speed)
    }
}

/// Immutable piecewise-constant section used by composition insertion and all
/// source/timeline mapping. Sharing this plan prevents preview, export, split,
/// playhead, and duration calculations from drifting apart.
struct EditorSpeedRenderSegment: Hashable {
    let sourceStart: TimeInterval
    let sourceDuration: TimeInterval
    let timelineStart: TimeInterval
    let timelineDuration: TimeInterval
    let speed: Float
}

struct EditorSpeedRamp: Codable, Hashable {
    static let minimumSpeed: Float = 0.1
    static let maximumSpeed: Float = 8

    var points: [EditorSpeedRampPoint]
    var interpolation: EditorSpeedRampInterpolation

    init(
        points: [EditorSpeedRampPoint],
        interpolation: EditorSpeedRampInterpolation = .smooth
    ) {
        self.points = Self.normalized(points)
        self.interpolation = interpolation
    }

    static func clampedSpeed(_ speed: Float) -> Float {
        min(max(speed, minimumSpeed), maximumSpeed)
    }

    var isUsable: Bool { points.count >= 2 }

    func speed(atSourceProgress progress: Double) -> Float {
        let p = min(max(progress, 0), 1)
        guard let first = points.first, let last = points.last else { return 1 }
        if p <= first.position { return first.speed }
        if p >= last.position { return last.speed }

        guard let upperIndex = points.firstIndex(where: { $0.position >= p }), upperIndex > 0 else {
            return last.speed
        }
        let lower = points[upperIndex - 1]
        let upper = points[upperIndex]
        let span = max(upper.position - lower.position, 0.000_001)
        var amount = (p - lower.position) / span
        if interpolation == .smooth {
            amount = amount * amount * (3 - 2 * amount)
        }
        return Self.clampedSpeed(
            lower.speed + Float(amount) * (upper.speed - lower.speed)
        )
    }

    /// Produces a bounded render plan. Curves are sampled more densely for long
    /// clips, while explicit control-point positions are always segment edges.
    func renderSegments(sourceDuration: TimeInterval) -> [EditorSpeedRenderSegment] {
        guard sourceDuration > 0, isUsable else { return [] }
        let sampleCount = min(180, max(24, Int(ceil(sourceDuration * 12))))
        var edges = Set((0...sampleCount).map { Double($0) / Double(sampleCount) })
        points.forEach { edges.insert($0.position) }
        let sortedEdges = edges.sorted()

        var timelineCursor: TimeInterval = 0
        return zip(sortedEdges, sortedEdges.dropFirst()).compactMap { pair in
            let (lower, upper) = pair
            let normalizedSpan = upper - lower
            guard normalizedSpan > 0.000_001 else { return nil }
            let sourceStart = lower * sourceDuration
            let sourceSpan = normalizedSpan * sourceDuration
            let rate = speed(atSourceProgress: (lower + upper) / 2)
            let timelineSpan = sourceSpan / TimeInterval(max(rate, Self.minimumSpeed))
            defer { timelineCursor += timelineSpan }
            return EditorSpeedRenderSegment(
                sourceStart: sourceStart,
                sourceDuration: sourceSpan,
                timelineStart: timelineCursor,
                timelineDuration: timelineSpan,
                speed: rate
            )
        }
    }

    func timelineDuration(forSourceDuration sourceDuration: TimeInterval) -> TimeInterval {
        renderSegments(sourceDuration: sourceDuration).reduce(0) { $0 + $1.timelineDuration }
    }

    func sourceOffset(
        forTimelineTime timelineTime: TimeInterval,
        sourceDuration: TimeInterval
    ) -> TimeInterval {
        let plan = renderSegments(sourceDuration: sourceDuration)
        guard let last = plan.last else { return min(max(timelineTime, 0), sourceDuration) }
        let time = min(max(timelineTime, 0), last.timelineStart + last.timelineDuration)
        guard let segment = plan.first(where: {
            time <= $0.timelineStart + $0.timelineDuration
        }) else { return sourceDuration }
        let localTimeline = max(0, time - segment.timelineStart)
        let fraction = segment.timelineDuration > 0 ? localTimeline / segment.timelineDuration : 0
        return min(sourceDuration, segment.sourceStart + fraction * segment.sourceDuration)
    }

    func timelineTime(
        forSourceOffset sourceOffset: TimeInterval,
        sourceDuration: TimeInterval
    ) -> TimeInterval {
        let plan = renderSegments(sourceDuration: sourceDuration)
        guard let last = plan.last else { return min(max(sourceOffset, 0), sourceDuration) }
        let offset = min(max(sourceOffset, 0), sourceDuration)
        guard let segment = plan.first(where: {
            offset <= $0.sourceStart + $0.sourceDuration
        }) else { return last.timelineStart + last.timelineDuration }
        let localSource = max(0, offset - segment.sourceStart)
        let fraction = segment.sourceDuration > 0 ? localSource / segment.sourceDuration : 0
        return segment.timelineStart + fraction * segment.timelineDuration
    }

    /// Crops and renormalizes a ramp when the clip is split in source time.
    func split(atSourceProgress progress: Double) -> (left: EditorSpeedRamp, right: EditorSpeedRamp) {
        let p = min(max(progress, 0.000_001), 0.999_999)
        let boundarySpeed = speed(atSourceProgress: p)
        let leftPoints = points.filter { $0.position < p } + [
            EditorSpeedRampPoint(position: p, speed: boundarySpeed)
        ]
        let rightPoints = [EditorSpeedRampPoint(position: p, speed: boundarySpeed)]
            + points.filter { $0.position > p }

        return (
            EditorSpeedRamp(
                points: leftPoints.map {
                    EditorSpeedRampPoint(position: $0.position / p, speed: $0.speed)
                },
                interpolation: interpolation
            ),
            EditorSpeedRamp(
                points: rightPoints.map {
                    EditorSpeedRampPoint(
                        position: ($0.position - p) / (1 - p),
                        speed: $0.speed
                    )
                },
                interpolation: interpolation
            )
        )
    }

    private static func normalized(_ rawPoints: [EditorSpeedRampPoint]) -> [EditorSpeedRampPoint] {
        var byPosition: [Double: EditorSpeedRampPoint] = [:]
        rawPoints.forEach { point in
            let position = min(max(point.position, 0), 1)
            byPosition[position] = EditorSpeedRampPoint(position: position, speed: point.speed)
        }
        var result = byPosition.values.sorted { $0.position < $1.position }
        if result.isEmpty {
            result = [
                EditorSpeedRampPoint(position: 0, speed: 1),
                EditorSpeedRampPoint(position: 1, speed: 1)
            ]
        } else {
            if result[0].position > 0 {
                result.insert(EditorSpeedRampPoint(position: 0, speed: result[0].speed), at: 0)
            }
            if result[result.count - 1].position < 1 {
                result.append(EditorSpeedRampPoint(position: 1, speed: result[result.count - 1].speed))
            }
        }
        return result
    }
}

enum EditorSpeedRampPreset: String, CaseIterable, Identifiable {
    case montage
    case hero
    case bullet
    case flash
    case accelerate
    case decelerate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .montage: return "Montage"
        case .hero: return "Hero"
        case .bullet: return "Bullet"
        case .flash: return "Flash"
        case .accelerate: return "Speed Up"
        case .decelerate: return "Slow Down"
        }
    }

    var systemImage: String {
        switch self {
        case .montage: return "waveform.path.ecg"
        case .hero: return "sparkles"
        case .bullet: return "scope"
        case .flash: return "bolt.fill"
        case .accelerate: return "chart.line.uptrend.xyaxis"
        case .decelerate: return "chart.line.downtrend.xyaxis"
        }
    }

    var ramp: EditorSpeedRamp {
        let values: [(Double, Float)]
        switch self {
        case .montage: values = [(0, 1), (0.18, 3.5), (0.42, 0.55), (0.7, 2.5), (1, 1)]
        case .hero: values = [(0, 1), (0.35, 0.35), (0.62, 0.35), (1, 1.5)]
        case .bullet: values = [(0, 1), (0.35, 1), (0.5, 0.18), (0.65, 1), (1, 1)]
        case .flash: values = [(0, 0.75), (0.2, 5), (0.52, 1), (0.8, 4), (1, 0.75)]
        case .accelerate: values = [(0, 0.5), (1, 4)]
        case .decelerate: values = [(0, 4), (1, 0.5)]
        }
        return EditorSpeedRamp(
            points: values.map { EditorSpeedRampPoint(position: $0.0, speed: $0.1) },
            interpolation: .smooth
        )
    }
}
