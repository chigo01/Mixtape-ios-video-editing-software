import Foundation

@main
struct PlanValidationTests {
    static func main() throws {
        let candidates = [
            EditorCopilotSegment(id: 0, start: 0, end: 6, text: "Opening"),
            EditorCopilotSegment(id: 1, start: 10, end: 17, text: "Explanation"),
            EditorCopilotSegment(id: 2, start: 25, end: 34, text: "Conclusion")
        ]
        func plan(_ ids: [Int], _ input: [EditorCopilotSegment] = candidates,
                  target: Double = 15, source: Double = 40) throws -> EditorCopilotPlan {
            try .validated(rankedIDs: ids, candidates: input,
                           targetDuration: target, sourceDuration: source, addsCaptions: true)
        }
        func rejects(_ name: String, _ operation: () throws -> Void) {
            do { try operation(); fatalError("Expected rejection: \(name)") }
            catch { print("PASS: \(name)") }
        }
        let selected = try plan([2, 0, 1])
        precondition(selected.segments.map(\.id) == [0, 2], "Ranking must determine selection, source time must determine assembly order")
        precondition(selected.duration == 15)
        print("PASS: ranked selection, source ordering and exact duration budget")
        let duplicate = try plan([1, 1, 0])
        precondition(duplicate.segments.map(\.id) == [0, 1] && duplicate.duration == 13)
        print("PASS: duplicate selections cannot duplicate footage")
        rejects("unknown model ID") { _ = try plan([999]) }
        rejects("empty model output") { _ = try plan([]) }
        rejects("NaN duration") { _ = try plan([0], target: .nan) }
        rejects("infinite source duration") { _ = try plan([0], source: .infinity) }
        rejects("out of bounds source range") { _ = try plan([2], source: 30) }
        rejects("negative source time") { _ = try plan([0], [.init(id: 0, start: -1, end: 4, text: "invalid")]) }
        rejects("non-finite source range") { _ = try plan([0], [.init(id: 0, start: 0, end: .nan, text: "invalid")]) }
        rejects("overlapping sections") { _ = try plan([0, 1], [.init(id: 0, start: 0, end: 6, text: "a"), .init(id: 1, start: 5, end: 10, text: "b")]) }
        rejects("duplicate candidate IDs") { _ = try plan([0], [candidates[0], candidates[0]]) }
        rejects("no section fits without cutting speech") { _ = try plan([0], [.init(id: 0, start: 0, end: 20, text: "long")], target: 10) }
        let adjacent = try plan([1, 0], [.init(id: 0, start: 0, end: 5, text: "a"), .init(id: 1, start: 5, end: 10, text: "b")])
        precondition(adjacent.duration == 10)
        print("PASS: adjacent sections remain legal")
        let crossing = try plan([0], [.init(id: 0, start: 3, end: 13, text: "crossing")])
        let slices = try crossing.clipSlices(durations: [5, 5, 10])
        precondition(slices == [.init(clipIndex: 0, start: 3, end: 5), .init(clipIndex: 1, start: 0, end: 5), .init(clipIndex: 2, start: 0, end: 3)])
        print("PASS: a highlight crossing three clips resolves to exact local slices")
        let gaps = try selected.clipSlices(durations: [10, 15, 15])
        precondition(gaps == [.init(clipIndex: 0, start: 0, end: 6), .init(clipIndex: 2, start: 0, end: 9)])
        print("PASS: removed clips do not leak into the assembly")
        precondition(selected.mappedWordRange(start: 26, end: 27) == 7...8)
        precondition(selected.mappedWordRange(start: 11, end: 12) == nil)
        precondition(selected.mappedWordRange(start: 5, end: 7) == nil)
        precondition(selected.mappedWordRange(start: .nan, end: 5) == nil)
        precondition(selected.mappedWordRange(start: 6.0001, end: 6.0002) == nil)
        precondition(selected.mappedWordRange(start: -0.0002, end: -0.0001) == nil)
        print("PASS: caption timing shifts with cuts; removed and straddling words are excluded")
        rejects("stale clip coverage") { _ = try crossing.clipSlices(durations: [5, 5]) }
        rejects("invalid source clip duration") { _ = try crossing.clipSlices(durations: [.nan]) }
        let allowed = Set([0, 1, 2])
        let decoded = try EditorCopilotPlan.decodeRanking(" [2,0,1] ", allowedIDs: allowed)
        precondition(decoded == [2, 0, 1])
        print("PASS: plain-text model output is decoded strictly")
        for valid in ["```json\n[2,0,1]\n```", "```\n[2,0,1]\n```", "{\"sectionIDs\":[2,0,1]}", "{\"ids\":[2,0,1]}", "[2,2,0,1,0]"] {
            let result = try EditorCopilotPlan.decodeRanking(valid, allowedIDs: allowed)
            precondition(result == [2,0,1])
        }
        print("PASS: fenced JSON, recognized schema wrappers and duplicate IDs normalize safely")
        let capped = try EditorCopilotPlan.decodeRanking("[9,8,7,6,5,4,3,2,1]", allowedIDs: Set(1...9))
        precondition(capped == [9,8,7,6,5,4,3,2])
        print("PASS: excess valid selections retain the top eight in ranking order")
        let longer = try EditorCopilotPlan.decodeRanking("[9,8,7,6,5,4,3,2,1]", allowedIDs: Set(1...9), limit: 12)
        precondition(longer == [9,8,7,6,5,4,3,2,1])
        print("PASS: a longer excerpt can keep more than eight ranked sections")
        precondition(EditorCopilotPlan.selectionCap(forTarget: 45) == 12)
        precondition(EditorCopilotPlan.selectionCap(forTarget: 120) == 30)
        let many = (0..<20).map { EditorCopilotSegment(id: $0, start: Double($0) * 10, end: Double($0) * 10 + 6, text: "s") }
        let twoMinutes = try EditorCopilotPlan.validated(
            rankedIDs: Array(0..<8), candidates: many, targetDuration: 120, sourceDuration: 250, addsCaptions: false
        )
        precondition(abs(twoMinutes.duration - 120) < 0.01)
        print("PASS: a 2-minute request fills to two minutes instead of stopping at eight clips")
        for invalid in ["I cannot help. Section 1", "I cannot help. [1]", "[99]", "[true]", "[1.5]", "[]", "{\"ids\":[1],\"other\":[2]}", "```json\n[1]\n``` extra"] {
            rejects("invalid ranking: \(invalid)") { _ = try EditorCopilotPlan.decodeRanking(invalid, allowedIDs: allowed) }
        }
        precondition(EditorCopilotPlan.RankingDecodeError.unknownID.canRetry)
        precondition(!EditorCopilotPlan.RankingDecodeError.format.canRetry)
        precondition(!EditorCopilotPlan.RankingDecodeError.empty.canRetry)
        print("PASS: prose/refusals and empty selections cannot trigger retries")

        func edit(_ drafts: [EditorCopilotEditDraft], duration: Double = 40, playhead: Double = 12.4,
                  summary: String = "Draft") throws -> EditorCopilotEditPlan {
            try .validated(drafts: drafts, timelineDuration: duration, playhead: playhead, summary: summary)
        }
        func effectDraft(start: Double = 12.4, end: Double = 15.4, effect: String = "vignette",
                         amount: Double = 0.7, fadeIn: Bool = true, fadeOut: Bool = true) -> EditorCopilotEditDraft {
            .init(kind: .addEffect, start: start, end: end, amount: amount, effect: effect,
                  property: "none", text: "", fadeIn: fadeIn, fadeOut: fadeOut)
        }
        let vignette = try edit([effectDraft()])
        precondition(vignette.operations.count == 1)
        precondition(vignette.operations[0].kind == .addEffect)
        precondition(vignette.operations[0].effect == "vignette")
        precondition(vignette.operations[0].fadeIn && vignette.operations[0].fadeOut)
        precondition(abs(vignette.operations[0].start - 12.4) < 0.0001)
        print("PASS: timed effect at the playhead is accepted and keyframed")
        let fade = try edit([.init(kind: .addTransition, start: 17.1, end: 17.1, amount: 0, effect: "fade",
                                   property: "none", text: "", fadeIn: false, fadeOut: false)],
                            duration: 119, playhead: 17.1)
        precondition(fade.operations[0].kind == .addTransition)
        precondition(fade.operations[0].effect == "fade")
        precondition(abs(fade.operations[0].amount - 0.5) < 0.0001)
        precondition(abs(fade.operations[0].start - 17.1) < 0.0001)
        print("PASS: a fade transition at the playhead is a legal edit")
        precondition(EditorCopilotEditPlan.transitionKind(fromPrompt: "Apply fade transition at this playhead") == "fade")
        precondition(EditorCopilotEditPlan.transitionKind(fromPrompt: "slide left at the playhead") == "slideLeft")
        precondition(EditorCopilotEditPlan.transitionKind(fromPrompt: "slide right transition here") == "slideRight")
        precondition(EditorCopilotEditPlan.transitionKind(fromPrompt: "dip to black between these clips") == "dipToBlack")
        precondition(EditorCopilotEditPlan.transitionKind(fromPrompt: "add a flash cut here") == "flash")
        precondition(EditorCopilotEditPlan.transitionKind(fromPrompt: "put a transition at the playhead") == "fade")
        print("PASS: playhead transitions resolve any named catalog cut, not only fade")
        let split = try EditorCopilotEditPlan.validated(
            drafts: EditorCopilotEditPlan.draftsFromPrompt("Split the clip at this playhead.", playhead: 17.1, duration: 119) ?? [],
            timelineDuration: 119, playhead: 17.1, summary: ""
        )
        precondition(split.operations.contains { $0.kind == .split })
        let splitAndFade = try EditorCopilotEditPlan.validated(
            drafts: EditorCopilotEditPlan.draftsFromPrompt(
                "Split at this playhead and add fade in transition", playhead: 40.2, duration: 119
            ) ?? [],
            timelineDuration: 119, playhead: 40.2, summary: ""
        )
        precondition(splitAndFade.operations.contains { $0.kind == .addTransition && $0.effect == "fade" })
        precondition(!splitAndFade.operations.contains { $0.kind == .split })
        precondition(!splitAndFade.operations.contains { $0.kind == .addKeyframe })
        print("PASS: split plus fade-in transition is one cut, not a split that fails on the new edge")
        let stacked = try edit([
            .init(kind: .addTransition, start: 17.1, end: 17.1, amount: 0.5, effect: "fade",
                  property: "none", text: "", fadeIn: false, fadeOut: false),
            .init(kind: .split, start: 17.1, end: 17.1, amount: 0, effect: "none",
                  property: "none", text: "", fadeIn: false, fadeOut: false)
        ], duration: 119, playhead: 17.1)
        precondition(stacked.operations.count == 1)
        precondition(stacked.operations[0].kind == .addTransition)
        print("PASS: a same-time split is dropped when a transition already cuts there")
        let slow = try EditorCopilotEditPlan.validated(
            drafts: EditorCopilotEditPlan.draftsFromPrompt("slow motion here", playhead: 10, duration: 40) ?? [],
            timelineDuration: 40, playhead: 10, summary: ""
        )
        precondition(slow.operations.contains { $0.kind == .setSpeed && abs($0.amount - 0.5) < 0.001 })
        let crop = try EditorCopilotEditPlan.validated(
            drafts: EditorCopilotEditPlan.draftsFromPrompt("crop 9:16 at the playhead", playhead: 5, duration: 20) ?? [],
            timelineDuration: 20, playhead: 5, summary: ""
        )
        precondition(crop.operations.contains { $0.kind == .crop && $0.effect == "vertical" })
        print("PASS: split, speed, and crop briefs become ordinary editor operations")
        let captionBrief = try EditorCopilotEditPlan.validated(
            drafts: EditorCopilotEditPlan.draftsFromPrompt("Add captions to the current timeline.", playhead: 17.1, duration: 119) ?? [],
            timelineDuration: 119, playhead: 17.1, summary: ""
        )
        precondition(captionBrief.operations.contains { $0.kind == .addCaptions && abs($0.start) < 0.0001 })
        print("PASS: captions still cover the full timeline from 0; MixPilot restore must use the playhead, not operation start")
        let aliased = try edit([effectDraft(effect: "blur")])
        precondition(aliased.operations[0].effect == "gaussianBlur")
        print("PASS: effect aliases resolve to catalog IDs")
        let short = try edit([effectDraft(start: 12.4, end: 12.4)], duration: 40, playhead: 12.4)
        precondition(short.operations[0].duration >= 0.45)
        print("PASS: instantaneous effects expand to a placeable window")
        let autoFade = try edit([effectDraft(fadeIn: false, fadeOut: false)])
        precondition(autoFade.operations[0].fadeIn && autoFade.operations[0].fadeOut)
        print("PASS: timed effects keyframe in and out by default")
        let zoom = try edit([.init(kind: .addKeyframe, start: 12.4, end: 13.4, amount: 0, effect: "none",
                                   property: "zoom", text: "", fadeIn: true, fadeOut: true)])
        precondition(zoom.operations[0].property == "scale")
        precondition(abs(zoom.operations[0].amount - 1.2) < 0.0001)
        print("PASS: zoom keyframes map to scale with a usable default")
        let title = try edit([.init(kind: .addText, start: 0, end: 0.1, amount: 1, effect: "none",
                                    property: "none", text: "  Mixtape  ", fadeIn: false, fadeOut: false)])
        precondition(title.operations[0].text == "Mixtape")
        precondition(title.operations[0].duration >= 0.45)
        print("PASS: text overlays keep trimmed copy and a visible duration")
        let volume = try edit([.init(kind: .addMarker, start: 8, end: 9, amount: 0, effect: "none",
                                     property: "none", text: "Hit", fadeIn: true, fadeOut: true)])
        precondition(volume.operations[0].kind == .addMarker)
        precondition(volume.operations[0].start == 8 && volume.operations[0].end == 8)
        precondition(volume.operations[0].fadeIn == false)
        print("PASS: markers collapse to a single time")
        let captions = try edit([.init(kind: .addCaptions, start: 3, end: 4, amount: 1, effect: "none",
                                       property: "none", text: "ignore", fadeIn: true, fadeOut: true)])
        precondition(captions.needsCaptions && captions.operations[0].start == 0 && captions.operations[0].end == 40)
        print("PASS: caption operations cover the current timeline")
        rejects("empty edit plan") { _ = try edit([]) }
        rejects("unknown effect") { _ = try edit([effectDraft(effect: "teleport")]) }
        rejects("missing keyframe property") {
            _ = try edit([.init(kind: .addKeyframe, start: 1, end: 1, amount: 1, effect: "none",
                                property: "none", text: "", fadeIn: false, fadeOut: false)])
        }
        rejects("empty title text") {
            _ = try edit([.init(kind: .addText, start: 0, end: 3, amount: 1, effect: "none",
                                property: "none", text: "   ", fadeIn: false, fadeOut: false)])
        }
        rejects("non-finite edit time") { _ = try edit([effectDraft(start: .nan)]) }
        rejects("invalid timeline duration") { _ = try edit([effectDraft()], duration: 0) }
        let tooMany = Array(repeating: effectDraft(), count: 9)
        rejects("too many edits") { _ = try edit(tooMany) }
        print("PASS: invalid general edits cannot become a draft")
        precondition(EditorCopilotPlan.parsedHighlightDuration(from: "Extract a 2-minute excerpt of the most useful moments.") == 120)
        precondition(EditorCopilotPlan.parsedHighlightDuration(from: "keep the best 5 minutes") == 300)
        precondition(EditorCopilotPlan.parsedHighlightDuration(from: "make a 10 minute cut") == 600)
        precondition(EditorCopilotPlan.parsedHighlightDuration(from: "make a 45 second highlight") == 45)
        precondition(EditorCopilotPlan.parsedHighlightDuration(from: "Extract the most useful highlights.") == nil)
        precondition(EditorCopilotPlan.parsedHighlightDuration(from: "give me 45 minutes") == nil)
        print("PASS: excerpt duration is parsed from the brief")
        let clamped = try EditorCopilotPlan.resolvedDuration(600, sourceDuration: 480)
        let unchanged = try EditorCopilotPlan.resolvedDuration(45, sourceDuration: 12813)
        precondition(clamped == 480 && unchanged == 45)
        print("PASS: requested length cannot exceed the source clip")
        let lastCut = EditorCopilotPlan.timedCutRange(
            prompt: "cut the last 2 minutes", playhead: 12800, duration: 12813
        )
        precondition(lastCut?.start == 12813 - 120 && lastCut?.end == 12813)
        precondition(EditorCopilotPlan.timedCutRange(
            prompt: "Extract a 2-minute excerpt of the most useful moments.",
            playhead: 12800, duration: 12813
        ) == nil)
        print("PASS: explicit playhead/end cuts skip speech ranking")
        let excerpt = try EditorCopilotPlan.contiguousExcerpt(
            start: 12693, end: 12813, sourceDuration: 12813, addsCaptions: false
        )
        precondition(excerpt.duration == 120 && excerpt.segments.count == 1)
        print("PASS: a 2-minute webinar excerpt is a legal contiguous cut")
        precondition(EditorCopilotPlan.recognitionBudget(timelineDuration: 12813, targetDuration: 120) == 300)
        precondition(EditorCopilotPlan.recognitionBudget(timelineDuration: 12813, targetDuration: 600) == 20 * 60)
        precondition(EditorCopilotPlan.recognitionBudget(timelineDuration: 120, targetDuration: 45) == 120)
        let bins = (0..<720).map { index -> (time: Double, rms: Double) in
            let time = Double(index) * 0.5
            let talking = (time.truncatingRemainder(dividingBy: 900) < 40)
            return (time, talking ? 0.08 : 0.001)
        }
        let windows = EditorCopilotPlan.sampleSpeechWindows(bins: bins, duration: 360, budget: 90)
        precondition(!windows.isEmpty)
        precondition(windows.count <= 12)
        precondition(windows.reduce(0) { $0 + ($1.end - $1.start) } <= 120)
        print("PASS: long-timeline speech sampling stays inside the recognition budget")
        let bursts = (0..<4_000).map { index -> (time: Double, rms: Double) in
            let time = Double(index) * 0.5
            let talking = Int(time) % 4 == 0
            return (time, talking ? 0.09 : 0.000_2)
        }
        let limited = EditorCopilotPlan.sampleSpeechWindows(bins: bursts, duration: 2_000, budget: 300)
        precondition(!limited.isEmpty && limited.count <= 12)
        precondition(limited.allSatisfy { $0.end - $0.start >= 8 })
        print("PASS: noisy speech bursts merge into a small number of windows")
        print("All copilot plan validation tests passed.")
    }
}
