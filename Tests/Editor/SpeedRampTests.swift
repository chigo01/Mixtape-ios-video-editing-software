import Foundation

// swiftc -module-cache-path /tmp/mixtape-swift-cache Features/Editor/Model/EditorSpeedRamp.swift Tests/Editor/SpeedRampTests.swift -o /tmp/mixtape-speed-tests
@main
struct SpeedRampTests {
    static func near(_ actual: Double, _ expected: Double, tolerance: Double = 0.000001) {
        precondition(abs(actual - expected) <= tolerance, "Expected \(expected), got \(actual)")
    }

    static func main() throws {
        var ramp = EditorSpeedRamp(points: [
            .init(position: 0, speed: 1), .init(position: 0.5, speed: 1), .init(position: 1, speed: 1)
        ])
        ramp.movePoint(at: 1, position: 2, speed: 20)
        near(ramp.points[1].position, 0.98)
        near(Double(ramp.points[1].speed), 8)
        ramp.movePoint(at: 1, position: -1, speed: 0.01)
        near(ramp.points[1].position, 0.02)
        near(Double(ramp.points[1].speed), 0.1)
        ramp.movePoint(at: 0, position: 0.8, speed: 2)
        ramp.movePoint(at: 2, position: 0.2, speed: 2)
        near(ramp.points[0].position, 0)
        near(ramp.points[2].position, 1)

        let constant = EditorSpeedRamp(points: [.init(position: 0, speed: 2), .init(position: 1, speed: 2)])
        near(constant.timelineDuration(forSourceDuration: 14.31), 7.155)
        near(constant.timelineTime(forSourceOffset: 6, sourceDuration: 14.31), 3)

        for preset in EditorSpeedRampPreset.allCases {
            for duration in [0.1, 14.31, 61.733, 600.0] {
                let curve = preset.ramp
                let plan = curve.renderSegments(sourceDuration: duration)
                var sourceEnd = 0.0
                var timelineEnd = 0.0
                for segment in plan {
                    near(segment.sourceStart, sourceEnd)
                    near(segment.timelineStart, timelineEnd)
                    precondition(segment.sourceDuration > 0 && segment.timelineDuration > 0)
                    near(segment.sourceDuration / segment.timelineDuration, Double(segment.speed))
                    sourceEnd += segment.sourceDuration
                    timelineEnd += segment.timelineDuration
                }
                near(sourceEnd, duration)
                near(timelineEnd, curve.timelineDuration(forSourceDuration: duration))
                for step in 0...100 {
                    let source = duration * Double(step) / 100
                    let timeline = curve.timelineTime(forSourceOffset: source, sourceDuration: duration)
                    near(curve.sourceOffset(forTimelineTime: timeline, sourceDuration: duration), source)
                }
                for point in curve.points {
                    near(Double(curve.speed(atSourceProgress: point.position)), Double(point.speed))
                }
                let restored = try JSONDecoder().decode(EditorSpeedRamp.self, from: JSONEncoder().encode(curve))
                precondition(restored == curve)
                precondition(restored.renderSegments(sourceDuration: duration) == plan)
            }
        }
        print("PASS: point constraints, applied speeds, contiguous render plans, source/playhead mapping, and persistence")
    }
}
