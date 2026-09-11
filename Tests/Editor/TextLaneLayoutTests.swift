import Foundation

@main
struct TextLaneLayoutTests {
    static func main() {
        let caption1 = EditorTextLaneInterval(id: UUID(), start: 0, end: 2)
        let caption2 = EditorTextLaneInterval(id: UUID(), start: 2, end: 4)
        let captions = [caption1, caption2]
        let initial = EditorTextLaneLayout.assign(captions)
        precondition(initial[caption1.id] == 0 && initial[caption2.id] == 0)

        let title = EditorTextLaneInterval(id: UUID(), start: 1, end: 3)
        let withTitle = EditorTextLaneLayout.assign(captions + [title], preserving: initial)
        precondition(withTitle[title.id] == 1)
        precondition(withTitle[caption1.id] == 0 && withTitle[caption2.id] == 0)

        let duplicate = EditorTextLaneInterval(id: UUID(), start: 1, end: 3)
        let three = EditorTextLaneLayout.assign(captions + [title, duplicate], preserving: withTitle)
        precondition(three[duplicate.id] == 2)
        let earlier = EditorTextLaneInterval(id: UUID(), start: 0, end: 4)
        let four = EditorTextLaneLayout.assign(captions + [title, duplicate, earlier], preserving: three)
        precondition(four[earlier.id] == 3)
        precondition(four[caption1.id] == 0 && four[caption2.id] == 0)
        precondition(EditorTextLaneLayout.assign(captions, preserving: four) == initial)
        precondition(EditorTextLaneLayout.assign([]).isEmpty)

        // A moved/trimmed clip must no longer collide in its previous lane.
        let moved = EditorTextLaneInterval(id: caption2.id, start: 1.5, end: 4)
        let movedLanes = EditorTextLaneLayout.assign([caption1, moved, title], preserving: withTitle)
        assertNoCollisions([caption1, moved, title], lanes: movedLanes)

        let many = (0..<5000).map {
            EditorTextLaneInterval(id: UUID(), start: Double($0) * 0.4, end: Double($0 + 1) * 0.4)
        }
        let start = Date()
        let packed = EditorTextLaneLayout.assign(many)
        precondition(Set(packed.values) == [0])
        let added = EditorTextLaneInterval(id: UUID(), start: 900, end: 905)
        let updated = EditorTextLaneLayout.assign(many + [added], preserving: packed)
        precondition(updated[added.id] == 1)
        precondition(many.allSatisfy { updated[$0.id] == 0 })
        print("PASS: shared caption/text lanes, overlap, duplicates, earlier insertion, move/trim, deletion, and 5,000-caption project (\(Date().timeIntervalSince(start))s)")
    }

    static func assertNoCollisions(_ items: [EditorTextLaneInterval], lanes: [UUID: Int]) {
        for a in items {
            for b in items where a.id != b.id && lanes[a.id] == lanes[b.id] {
                precondition(a.end <= b.start || b.end <= a.start)
            }
        }
    }
}
