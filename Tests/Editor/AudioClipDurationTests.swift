import Foundation

@main
struct AudioClipDurationTests {
    static func main() {
        var staleFullLength = EditorAudioClip(
            title: "Voiceover",
            fileURL: URL(fileURLWithPath: "/tmp/voiceover.m4a"),
            originalDuration: 6,
            trimStart: 0,
            trimEnd: 6,
            timelineStart: 2
        )
        precondition(staleFullLength.reconcileSourceDuration(12))
        precondition(staleFullLength.originalDuration == 12)
        precondition(staleFullLength.duration == 12)
        precondition(staleFullLength.timelineEnd == 14)

        var deliberatelyTrimmed = EditorAudioClip(
            title: "Music",
            fileURL: URL(fileURLWithPath: "/tmp/music.m4a"),
            originalDuration: 10,
            trimStart: 2,
            trimEnd: 7,
            timelineStart: 0
        )
        precondition(deliberatelyTrimmed.reconcileSourceDuration(12))
        precondition(deliberatelyTrimmed.originalDuration == 12)
        precondition(deliberatelyTrimmed.trimStart == 2)
        precondition(deliberatelyTrimmed.trimEnd == 7)
        precondition(deliberatelyTrimmed.duration == 5)

        precondition(!deliberatelyTrimmed.reconcileSourceDuration(12))
        precondition(!deliberatelyTrimmed.reconcileSourceDuration(.nan))
        print("PASS: decoded audio duration expands full clips and preserves deliberate trims")
    }
}
