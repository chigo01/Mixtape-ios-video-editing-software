//
//  EditorKeyframe.swift
//  Mixtape
//

import CoreGraphics
import Foundation

/// Scalar animation channels are deliberately shared by every timeline item.
/// Complex values such as transforms are composed from several scalar tracks.
enum EditorKeyframeProperty: String, Codable, CaseIterable, Identifiable, Hashable {
    case positionX
    case positionY
    case scale
    case rotation
    case opacity
    case volume
    case cropX
    case cropY
    case cropScale
    case filterIntensity
    case textScale
    case textRotation
    case textPositionX
    case textPositionY
    case effectAmount

    var id: String { rawValue }

    var title: String {
        switch self {
        case .positionX: return "Position X"
        case .positionY: return "Position Y"
        case .scale: return "Scale"
        case .rotation: return "Rotation"
        case .opacity: return "Opacity"
        case .volume: return "Volume"
        case .cropX: return "Crop X"
        case .cropY: return "Crop Y"
        case .cropScale: return "Crop Scale"
        case .filterIntensity: return "Filter"
        case .textScale: return "Text Scale"
        case .textRotation: return "Text Rotation"
        case .textPositionX: return "Text X"
        case .textPositionY: return "Text Y"
        case .effectAmount: return "Effect"
        }
    }

    var systemImage: String {
        switch self {
        case .positionX, .positionY, .textPositionX, .textPositionY:
            return "arrow.up.and.down.and.arrow.left.and.right"
        case .scale, .cropScale, .textScale: return "arrow.up.left.and.arrow.down.right"
        case .rotation, .textRotation: return "rotate.right"
        case .opacity: return "circle.lefthalf.filled"
        case .volume: return "speaker.wave.2.fill"
        case .cropX, .cropY: return "crop"
        case .filterIntensity: return "camera.filters"
        case .effectAmount: return "sparkles"
        }
    }

    var range: ClosedRange<Double> {
        switch self {
        case .positionX, .positionY, .cropX, .cropY: return -1...1
        case .textPositionX, .textPositionY: return -1000...1000
        case .scale: return 0.25...4
        case .rotation, .textRotation: return -180...180
        case .opacity, .volume, .filterIntensity, .effectAmount: return 0...1
        case .cropScale: return 0.5...4
        case .textScale: return 0.25...4
        }
    }

    var neutralValue: Double {
        switch self {
        case .scale, .cropScale, .textScale, .opacity, .volume, .filterIntensity:
            return 1
        default:
            return 0
        }
    }
}

enum EditorKeyframeCurvePreset: String, Codable, CaseIterable, Identifiable, Hashable {
    case linear
    case easeIn
    case easeOut
    case easeInOut
    case hold
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .linear: return "Linear"
        case .easeIn: return "Ease In"
        case .easeOut: return "Ease Out"
        case .easeInOut: return "Ease In/Out"
        case .hold: return "Hold"
        case .custom: return "Custom"
        }
    }
}

/// The outgoing timing curve stored on a keyframe. Control points follow the
/// CSS/Core Animation cubic-bezier convention and remain in the unit square.
struct EditorKeyframeCurve: Codable, Hashable {
    var preset: EditorKeyframeCurvePreset
    var controlPoint1: CGPoint
    var controlPoint2: CGPoint

    static let linear = EditorKeyframeCurve(
        preset: .linear,
        controlPoint1: CGPoint(x: 0, y: 0),
        controlPoint2: CGPoint(x: 1, y: 1)
    )

    init(
        preset: EditorKeyframeCurvePreset,
        controlPoint1: CGPoint? = nil,
        controlPoint2: CGPoint? = nil
    ) {
        self.preset = preset
        let defaults = Self.defaultControlPoints(for: preset)
        self.controlPoint1 = Self.clamp(controlPoint1 ?? defaults.0)
        self.controlPoint2 = Self.clamp(controlPoint2 ?? defaults.1)
    }

    mutating func applyPreset(_ preset: EditorKeyframeCurvePreset) {
        self.preset = preset
        guard preset != .custom else { return }
        let points = Self.defaultControlPoints(for: preset)
        controlPoint1 = points.0
        controlPoint2 = points.1
    }

    func solve(_ progress: Double) -> Double {
        let x = min(max(progress, 0), 1)
        if preset == .hold { return x >= 1 ? 1 : 0 }
        if preset == .linear { return x }

        // Invert the bezier x component with a bounded binary search, then
        // evaluate y. This is deterministic in preview and offline rendering.
        var lower = 0.0
        var upper = 1.0
        for _ in 0..<14 {
            let candidate = (lower + upper) / 2
            if cubic(candidate, p1: controlPoint1.x, p2: controlPoint2.x) < x {
                lower = candidate
            } else {
                upper = candidate
            }
        }
        return cubic(
            (lower + upper) / 2,
            p1: controlPoint1.y,
            p2: controlPoint2.y
        )
    }

    private func cubic(_ t: Double, p1: Double, p2: Double) -> Double {
        let inverse = 1 - t
        return 3 * inverse * inverse * t * p1
            + 3 * inverse * t * t * p2
            + t * t * t
    }

    private static func defaultControlPoints(
        for preset: EditorKeyframeCurvePreset
    ) -> (CGPoint, CGPoint) {
        switch preset {
        case .linear, .hold: return (CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1))
        case .easeIn: return (CGPoint(x: 0.42, y: 0), CGPoint(x: 1, y: 1))
        case .easeOut: return (CGPoint(x: 0, y: 0), CGPoint(x: 0.58, y: 1))
        case .easeInOut: return (CGPoint(x: 0.42, y: 0), CGPoint(x: 0.58, y: 1))
        case .custom: return (CGPoint(x: 0.25, y: 0.1), CGPoint(x: 0.25, y: 1))
        }
    }

    private static func clamp(_ point: CGPoint) -> CGPoint {
        CGPoint(x: min(max(point.x, 0), 1), y: min(max(point.y, 0), 1))
    }
}

struct EditorKeyframe: Codable, Identifiable, Hashable {
    var id: UUID
    /// Seconds relative to the owning item's visible timeline start.
    var time: TimeInterval
    var value: Double
    /// Controls interpolation from this point to the next point.
    var curve: EditorKeyframeCurve

    init(
        id: UUID = UUID(),
        time: TimeInterval,
        value: Double,
        curve: EditorKeyframeCurve = .linear
    ) {
        self.id = id
        self.time = max(0, time)
        self.value = value
        self.curve = curve
    }
}

struct EditorKeyframeTrack: Codable, Identifiable, Hashable {
    var property: EditorKeyframeProperty
    private(set) var keyframes: [EditorKeyframe]

    var id: EditorKeyframeProperty { property }
    var isEmpty: Bool { keyframes.isEmpty }

    init(property: EditorKeyframeProperty, keyframes: [EditorKeyframe] = []) {
        self.property = property
        self.keyframes = Self.normalized(keyframes, range: property.range)
    }

    func value(at time: TimeInterval, default defaultValue: Double) -> Double {
        guard let first = keyframes.first else { return defaultValue }
        if time <= first.time { return first.value }
        guard let last = keyframes.last, time < last.time else { return keyframes.last?.value ?? defaultValue }

        guard let upperIndex = keyframes.firstIndex(where: { $0.time > time }) else {
            return last.value
        }
        let lower = keyframes[upperIndex - 1]
        let upper = keyframes[upperIndex]
        let span = max(upper.time - lower.time, 0.000_001)
        let progress = lower.curve.solve((time - lower.time) / span)
        return lower.value + (upper.value - lower.value) * progress
    }

    mutating func upsert(
        at time: TimeInterval,
        value: Double,
        curve: EditorKeyframeCurve? = nil,
        tolerance: TimeInterval = 1.0 / 120.0
    ) -> UUID {
        let time = max(0, time)
        let value = min(max(value, property.range.lowerBound), property.range.upperBound)
        if let index = keyframes.firstIndex(where: { abs($0.time - time) <= tolerance }) {
            keyframes[index].time = time
            keyframes[index].value = value
            if let curve { keyframes[index].curve = curve }
            keyframes.sort { $0.time < $1.time }
            return keyframes[index].id
        }
        let point = EditorKeyframe(time: time, value: value, curve: curve ?? .linear)
        keyframes.append(point)
        keyframes.sort { $0.time < $1.time }
        return point.id
    }

    mutating func remove(id: UUID) {
        keyframes.removeAll { $0.id == id }
    }

    mutating func update(id: UUID, time: TimeInterval? = nil, value: Double? = nil) {
        guard let index = keyframes.firstIndex(where: { $0.id == id }) else { return }
        if let time { keyframes[index].time = max(0, time) }
        if let value {
            keyframes[index].value = min(
                max(value, property.range.lowerBound),
                property.range.upperBound
            )
        }
        keyframes.sort { $0.time < $1.time }
    }

    mutating func updateCurve(id: UUID, curve: EditorKeyframeCurve) {
        guard let index = keyframes.firstIndex(where: { $0.id == id }) else { return }
        keyframes[index].curve = curve
    }

    private static func normalized(
        _ keyframes: [EditorKeyframe],
        range: ClosedRange<Double>
    ) -> [EditorKeyframe] {
        keyframes
            .map {
                var point = $0
                point.time = max(0, point.time)
                point.value = min(max(point.value, range.lowerBound), range.upperBound)
                return point
            }
            .sorted { $0.time < $1.time }
    }
}

struct EditorKeyframeTracks: Codable, Hashable {
    private(set) var tracks: [EditorKeyframeTrack]

    static let empty = EditorKeyframeTracks()
    var isEmpty: Bool { tracks.allSatisfy(\.isEmpty) }

    init(tracks: [EditorKeyframeTrack] = []) {
        var unique: [EditorKeyframeProperty: EditorKeyframeTrack] = [:]
        for track in tracks { unique[track.property] = track }
        self.tracks = unique.values.sorted { $0.property.rawValue < $1.property.rawValue }
    }

    func track(for property: EditorKeyframeProperty) -> EditorKeyframeTrack {
        tracks.first(where: { $0.property == property })
            ?? EditorKeyframeTrack(property: property)
    }

    func value(
        for property: EditorKeyframeProperty,
        at time: TimeInterval,
        default defaultValue: Double
    ) -> Double {
        track(for: property).value(at: time, default: defaultValue)
    }

    mutating func replace(_ track: EditorKeyframeTrack) {
        tracks.removeAll { $0.property == track.property }
        if !track.isEmpty { tracks.append(track) }
        tracks.sort { $0.property.rawValue < $1.property.rawValue }
    }

    mutating func trim(to duration: TimeInterval) {
        let duration = max(0, duration)
        for index in tracks.indices {
            for keyframe in tracks[index].keyframes where keyframe.time > duration {
                tracks[index].update(id: keyframe.id, time: duration)
            }
        }
    }

    func split(at time: TimeInterval) -> (left: EditorKeyframeTracks, right: EditorKeyframeTracks) {
        let splitTime = max(0, time)
        var leftTracks: [EditorKeyframeTrack] = []
        var rightTracks: [EditorKeyframeTrack] = []
        for track in tracks {
            let boundaryValue = track.value(
                at: splitTime,
                default: track.property.neutralValue
            )
            var left = EditorKeyframeTrack(
                property: track.property,
                keyframes: track.keyframes.filter { $0.time < splitTime }
            )
            var right = EditorKeyframeTrack(
                property: track.property,
                keyframes: track.keyframes
                    .filter { $0.time > splitTime }
                    .map {
                        var point = $0
                        point.time -= splitTime
                        return point
                    }
            )
            if !track.isEmpty {
                _ = left.upsert(at: splitTime, value: boundaryValue)
                _ = right.upsert(at: 0, value: boundaryValue)
            }
            if !left.isEmpty { leftTracks.append(left) }
            if !right.isEmpty { rightTracks.append(right) }
        }
        return (EditorKeyframeTracks(tracks: leftTracks), EditorKeyframeTracks(tracks: rightTracks))
    }

    /// Captures the visible value of every animated channel as a constant hold.
    /// Freeze-frame clips use this so motion does not restart from keyframe zero.
    func held(at time: TimeInterval) -> EditorKeyframeTracks {
        EditorKeyframeTracks(tracks: tracks.compactMap { track in
            guard !track.isEmpty else { return nil }
            return EditorKeyframeTrack(
                property: track.property,
                keyframes: [EditorKeyframe(
                    time: 0,
                    value: track.value(at: max(0, time), default: track.property.neutralValue),
                    curve: EditorKeyframeCurve(preset: .hold)
                )]
            )
        })
    }
}
