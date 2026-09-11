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
        print("PASS: selecting an updated point retains its ID; moving preserves identity and value")
    }
}
