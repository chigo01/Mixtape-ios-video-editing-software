import Foundation
@main struct KeyframeInteractionTests {
    static func main() {
        var track = EditorKeyframeTrack(property: .scale)
        let first = track.upsert(at: 1, value: 1)
        let second = track.upsert(at: 1.005, value: 2, tolerance: 0)
        let updated = track.upsert(at: 1.006, value: 1.5)
        precondition(updated == first)
        precondition(track.keyframes.last?.id == first)
        track.update(id: second, time: 0.4)
        precondition(track.keyframes.first?.id == second)
        precondition(track.keyframes.first?.value == 2)
        precondition(track.keyframes.last?.value == 1.5)
        var opacity = EditorKeyframeTrack(property: .opacity)
        opacity.applyCopilotAnimation(start: 3.5, end: 4.5, amount: 1,
                                     fadeIn: true, fadeOut: false, defaultValue: 1)
        for time in [0.0, 1.0, 3.0, 3.498, 4.5, 6.0, 10.0] {
            precondition(abs(opacity.value(at: time, default: 1) - 1) < 0.0001)
        }
        precondition(abs(opacity.value(at: 3.5, default: 1)) < 0.0001)
        precondition(opacity.value(at: 3.65, default: 1) > 0)
        var audio = EditorKeyframeTrack(property: .volume)
        audio.applyCopilotAnimation(start: 2, end: 3, amount: 0.6,
                                   fadeIn: false, fadeOut: true, defaultValue: 0.6)
        precondition(audio.value(at: 0, default: 0.6) == 0.6)
        precondition(audio.value(at: 3, default: 0.6) == 0)
        var opening = EditorKeyframeTrack(property: .opacity)
        opening.applyCopilotAnimation(start: 0, end: 1, amount: 1,
                                     fadeIn: true, fadeOut: false, defaultValue: 1)
        precondition(opening.value(at: 0, default: 1) == 0)
        precondition(opening.value(at: 2, default: 1) == 1)
        print("PASS: mid-clip fades preserve preceding footage; fade-in restores visibility; opening/audio fades retain their endpoints")
        print("PASS: selecting an updated point retains its ID; moving preserves identity and value")
    }
}
