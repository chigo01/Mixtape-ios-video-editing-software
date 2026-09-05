import Foundation

/// Model output contains only IDs. All timestamps come from measured transcript data.
struct EditorCopilotSegment: Identifiable, Equatable, Sendable {
    let id: Int
    let start: Double
    let end: Double
    let text: String
    var duration: Double { end - start }
}

struct EditorCopilotPlan: Equatable, Sendable {
    let segments: [EditorCopilotSegment]
    let targetDuration: Double
    let addsCaptions: Bool
    var duration: Double { segments.reduce(0) { $0 + $1.duration } }

    struct ClipSlice: Equatable {
        let clipIndex: Int
        let start: Double
        let end: Double
    }

    /// Resolve timeline ranges before any editor mutation. Times are clip-local,
    /// so the existing split command owns source-speed and keyframe conversion.
    func clipSlices(durations: [Double]) throws -> [ClipSlice] {
        guard durations.allSatisfy({ $0.isFinite && $0 > 0 }) else {
            throw EditorCopilotError.message("A source clip has invalid duration.")
        }
        var slices: [ClipSlice] = []
        for range in segments {
            var offset = 0.0
            for (index, duration) in durations.enumerated() {
                defer { offset += duration }
                let start = max(range.start, offset) - offset
                let end = min(range.end, offset + duration) - offset
                if end - start > 0.000_001 {
                    slices.append(.init(clipIndex: index, start: start, end: end))
                }
            }
        }
        guard abs(slices.reduce(0) { $0 + $1.end - $1.start } - duration) < 0.001 else {
            throw EditorCopilotError.message("Source clips no longer cover the selected highlights.")
        }
        return slices
    }

    /// Only whole words inside kept sections survive; removed speech is never
    /// stretched into captions for unrelated footage.
    func mappedWordRange(start: Double, end: Double) -> ClosedRange<Double>? {
        guard start.isFinite, end.isFinite, end > start else { return nil }
        var offset = 0.0
        for segment in segments {
            defer { offset += segment.duration }
            if start >= segment.start - 0.001 && end <= segment.end + 0.001 {
                let lower = max(0, start - segment.start)
                let upper = min(segment.duration, end - segment.start)
                guard upper > lower else { continue }
                return (offset + lower)...(offset + upper)
            }
        }
        return nil
    }

    enum RankingDecodeError: String, LocalizedError {
        case format, unknownID, empty, oversized
        var errorDescription: String? {
            switch self {
            case .format: return "The model did not return a readable list of sections."
            case .unknownID: return "The model selected a section outside this transcript batch."
            case .empty: return "The model did not select any sections for this brief."
            case .oversized: return "The model returned too much selection data."
            }
        }
        var canRetry: Bool { self == .unknownID }
    }

    /// Accept harmless JSON wrappers, but never mine numbers from prose/refusals.
    /// Repeated IDs and excess valid selections are normalized in ranking order.
    static func decodeRanking(_ response: String, allowedIDs: Set<Int>, limit: Int = 8) throws -> [Int] {
        var text = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.utf8.count <= 4096 else { throw RankingDecodeError.oversized }
        if text.hasPrefix("```") {
            var lines = text.components(separatedBy: "\n")
            guard ["```", "```json"].contains(lines.first?.lowercased() ?? ""),
                  lines.last == "```", lines.count >= 3 else { throw RankingDecodeError.format }
            lines.removeFirst(); lines.removeLast()
            text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let data = text.data(using: .utf8) else { throw RankingDecodeError.format }
        let decoder = JSONDecoder()
        let ids: [Int]
        if let array = try? decoder.decode([Int].self, from: data) {
            ids = array
        } else {
            // Accept only a single recognized schema key, not accompanying prose.
            guard let object = try? decoder.decode([String: [Int]].self, from: data),
                  object.count == 1, let key = object.keys.first,
                  ["sectionIDs", "ids"].contains(key), let array = object[key] else {
                throw RankingDecodeError.format
            }
            ids = array
        }
        guard !ids.isEmpty else { throw RankingDecodeError.empty }
        guard ids.allSatisfy({ allowedIDs.contains($0) }) else { throw RankingDecodeError.unknownID }
        var seen = Set<Int>()
        return Array(ids.filter { seen.insert($0).inserted }.prefix(limit))
    }

    /// Enough complete spoken sections to fill the requested excerpt.
    /// A 45s reel still uses a small cap; a 2–10 minute cut needs more than eight clips.
    static func selectionCap(forTarget duration: Double) -> Int {
        guard duration.isFinite, duration > 0 else { return 8 }
        return min(40, max(8, Int((duration / 4).rounded(.up))))
    }

    static func validated(
        rankedIDs: [Int], candidates: [EditorCopilotSegment],
        targetDuration: Double, sourceDuration: Double, addsCaptions: Bool
    ) throws -> Self {
        guard targetDuration.isFinite, allowedDuration.contains(targetDuration),
              sourceDuration.isFinite, sourceDuration > 0,
              Set(candidates.map(\.id)).count == candidates.count else {
            throw EditorCopilotError.message("Invalid duration or transcript data. Analyze again.")
        }
        let lookup = Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, $0) })
        var chosen: [EditorCopilotSegment] = []
        var seen = Set<Int>()
        var duration = 0.0
        for id in rankedIDs {
            guard let segment = lookup[id] else {
                throw EditorCopilotError.message("The model selected an unknown section. Try again.")
            }
            guard seen.insert(id).inserted else { continue }
            guard segment.start.isFinite, segment.end.isFinite,
                  segment.start >= 0, segment.end <= sourceDuration + 0.001,
                  segment.duration >= 0.3 else {
                throw EditorCopilotError.message("A selected section has invalid timing. Analyze again.")
            }
            guard duration + segment.duration <= targetDuration + 0.001 else { continue }
            guard !chosen.contains(where: { segment.start < $0.end && segment.end > $0.start }) else {
                throw EditorCopilotError.message("Selected sections overlap. Try again.")
            }
            chosen.append(segment)
            duration += segment.duration
        }
        if !rankedIDs.isEmpty, duration + 0.5 < targetDuration {
            let leftovers = candidates
                .filter { !seen.contains($0.id) }
                .sorted { $0.duration > $1.duration }
            for segment in leftovers {
                guard segment.start.isFinite, segment.end.isFinite,
                      segment.start >= 0, segment.end <= sourceDuration + 0.001,
                      segment.duration >= 0.3 else { continue }
                guard duration + segment.duration <= targetDuration + 0.001 else { continue }
                guard !chosen.contains(where: { segment.start < $0.end && segment.end > $0.start }) else { continue }
                seen.insert(segment.id)
                chosen.append(segment)
                duration += segment.duration
            }
        }
        if duration + 2 < targetDuration {
            let room = targetDuration - duration
            if let filler = candidates
                .filter({ !seen.contains($0.id) })
                .sorted(by: { $0.duration > $1.duration })
                .first(where: { segment in
                    segment.start.isFinite && segment.end.isFinite
                        && segment.duration > room
                        && !chosen.contains(where: { segment.start < $0.end && segment.end > $0.start })
                }) {
                chosen.append(EditorCopilotSegment(
                    id: filler.id,
                    start: filler.start,
                    end: filler.start + room,
                    text: filler.text
                ))
            }
        }
        guard !chosen.isEmpty else {
            throw EditorCopilotError.message("No complete section fits. Increase the target duration or change the request.")
        }
        return Self(segments: chosen.sorted { $0.start < $1.start },
                    targetDuration: targetDuration, addsCaptions: addsCaptions)
    }

    /// A single contiguous cut that does not need speech ranking.
    static func contiguousExcerpt(
        start: Double, end: Double, sourceDuration: Double, addsCaptions: Bool
    ) throws -> Self {
        guard start.isFinite, end.isFinite, sourceDuration.isFinite,
              start >= 0, end > start, sourceDuration > 0,
              end <= sourceDuration + 0.05 else {
            throw EditorCopilotError.message("That excerpt does not fit on the current timeline.")
        }
        let duration = end - start
        guard allowedDuration.contains(duration) else {
            throw EditorCopilotError.message(durationLimitMessage)
        }
        return Self(
            segments: [EditorCopilotSegment(id: 0, start: start, end: end, text: "Excerpt")],
            targetDuration: duration,
            addsCaptions: addsCaptions
        )
    }

    static func parsedHighlightDuration(from prompt: String) -> Int? {
        let text = prompt.lowercased()
        let patterns = [
            #"(\d+(?:\.\d+)?)\s*-?\s*(minutes?|mins?|min)\b"#,
            #"(\d+(?:\.\d+)?)\s*-?\s*(seconds?|secs?|sec|s)\b"#
        ]
        for pattern in patterns {
            guard let match = text.range(of: pattern, options: .regularExpression) else { continue }
            let token = String(text[match])
            let number = token.split { !$0.isNumber && $0 != "." }.first.flatMap { Double($0) }
            guard let number, number.isFinite else { continue }
            let seconds = token.contains("min") ? Int((number * 60).rounded()) : Int(number.rounded())
            if allowedIntDuration.contains(seconds) { return seconds }
        }
        return nil
    }

    static let minimumExcerptSeconds = 10
    static let maximumExcerptSeconds = 30 * 60
    static var allowedIntDuration: ClosedRange<Int> { minimumExcerptSeconds...maximumExcerptSeconds }
    static var allowedDuration: ClosedRange<Double> {
        Double(minimumExcerptSeconds)...Double(maximumExcerptSeconds)
    }
    static let durationLimitMessage = "Choose a length between 10 seconds and 30 minutes."

    static func resolvedDuration(_ requested: Int, sourceDuration: Double) throws -> Int {
        guard sourceDuration.isFinite, sourceDuration >= Double(minimumExcerptSeconds) else {
            throw EditorCopilotError.message("This clip is too short to cut an excerpt. Use a clip of at least 10 seconds.")
        }
        let ceiling = min(maximumExcerptSeconds, max(minimumExcerptSeconds, Int(sourceDuration.rounded(.down))))
        return min(max(requested, minimumExcerptSeconds), ceiling)
    }

    static func timedCutRange(
        prompt: String, playhead: Double, duration: Double
    ) -> (start: Double, end: Double)? {
        let text = prompt.lowercased()
        guard let seconds = parsedHighlightDuration(from: text) else { return nil }
        let length = Double(seconds)
        guard duration.isFinite, duration >= 10, playhead.isFinite else { return nil }
        let mentionsLocation = text.contains("here") || text.contains("playhead")
            || text.contains("this moment") || text.contains("from now")
            || text.contains("last") || text.contains("at the end")
            || text.contains("first") || text.contains("opening") || text.contains("beginning")
        let mentionsCut = text.contains("cut") || text.contains("keep") || text.contains("take")
            || text.contains("excerpt") || text.contains("clip")
        guard mentionsLocation, mentionsCut || text.contains("here") || text.contains("playhead") else {
            return nil
        }
        if text.contains("last") || text.contains("at the end") {
            let start = max(0, duration - length)
            return (start, duration)
        }
        if text.contains("first") || text.contains("opening") || text.contains("beginning") {
            return (0, min(duration, length))
        }
        var start = min(max(0, playhead), duration)
        var end = start + length
        if end > duration {
            end = duration
            start = max(0, end - length)
        }
        guard end - start >= 10 else { return nil }
        return (start, end)
    }

    static func recognitionBudget(timelineDuration: Double, targetDuration: Double) -> Double {
        guard timelineDuration.isFinite, timelineDuration > 0 else { return 0 }
        if timelineDuration <= 8 * 60 { return timelineDuration }
        let wanted = max(targetDuration * 2.5, 4 * 60)
        return min(timelineDuration, wanted, 20 * 60)
    }

    struct SpeechWindow: Equatable {
        var start: Double
        var end: Double
    }

    /// Pick a stratified set of spoken windows so a long recording is sampled, not fully transcribed.
    static func sampleSpeechWindows(
        bins: [(time: Double, rms: Double)],
        duration: Double,
        budget: Double
    ) -> [SpeechWindow] {
        guard duration.isFinite, duration > 0, budget > 0 else { return [] }
        let hop = bins.count >= 2 ? max(0.05, bins[1].time - bins[0].time) : 0.5
        let maxWindows = min(12, max(4, Int((budget / 20).rounded(.up))))
        let pieceLength = 25.0
        let voiced = bins.map(\.rms).filter { $0 > 0.000_8 }.sorted()
        var islands: [(start: Double, end: Double, score: Double)] = []
        if !voiced.isEmpty {
            let p70 = voiced[min(voiced.count - 1, Int(Double(voiced.count) * 0.7))]
            let median = voiced[voiced.count / 2]
            let threshold = max(0.004, min(p70, median * 3))
            var start: Double?
            var end = 0.0
            var score = 0.0
            for bin in bins {
                if bin.rms >= threshold {
                    if start != nil, bin.time - end <= 2.5 {
                        end = min(duration, bin.time + hop)
                        score += bin.rms
                    } else {
                        if let current = start, end - current >= 3 {
                            islands.append((current, end, score))
                        }
                        start = bin.time
                        end = min(duration, bin.time + hop)
                        score = bin.rms
                    }
                } else if let current = start, bin.time - end > 2.5 {
                    if end - current >= 3 { islands.append((current, end, score)) }
                    start = nil
                }
            }
            if let current = start, end - current >= 3 {
                islands.append((current, end, score))
            }
        }
        var pieces: [(start: Double, end: Double, score: Double)] = []
        for island in islands {
            var start = island.start
            var end = island.end
            if end - start < 20 {
                let extra = (20 - (end - start)) / 2
                start = max(0, start - extra)
                end = min(duration, end + extra)
            }
            let span = max(end - start, 0.001)
            var cursor = start
            while cursor < end - 8 {
                let next = min(end, cursor + pieceLength)
                pieces.append((cursor, next, island.score * ((next - cursor) / span)))
                cursor = next
            }
        }
        if pieces.isEmpty {
            let count = min(maxWindows, max(4, Int((budget / pieceLength).rounded(.up))))
            let step = duration / Double(count)
            return (0..<count).map { index in
                let start = min(duration, Double(index) * step)
                return SpeechWindow(start: start, end: min(duration, start + min(pieceLength, budget)))
            }
        }
        let bandCount = min(maxWindows, max(4, Int((duration / 900).rounded(.up))))
        let bandLength = duration / Double(bandCount)
        func band(_ time: Double) -> Int {
            min(bandCount - 1, max(0, Int(time / bandLength)))
        }
        var remaining = pieces
        var selected: [SpeechWindow] = []
        var used = 0.0
        for index in 0..<bandCount {
            guard selected.count < maxWindows, used < budget - 0.5 else { break }
            guard let match = remaining.enumerated()
                .filter({ band($0.element.start) == index })
                .max(by: { $0.element.score < $1.element.score }) else { continue }
            let piece = remaining.remove(at: match.offset)
            selected.append(SpeechWindow(start: piece.start, end: piece.end))
            used += piece.end - piece.start
        }
        remaining.sort { $0.score > $1.score }
        for piece in remaining {
            if selected.count >= maxWindows || used >= budget - 0.5 { break }
            selected.append(SpeechWindow(start: piece.start, end: piece.end))
            used += piece.end - piece.start
        }
        let sorted = selected.sorted { $0.start < $1.start }
        var merged: [SpeechWindow] = []
        for window in sorted {
            if let last = merged.last, window.start <= last.end + 0.75 {
                merged[merged.count - 1].end = max(last.end, window.end)
            } else {
                merged.append(window)
            }
        }
        return Array(merged.prefix(maxWindows))
    }
}

enum EditorCopilotError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let message): return message }
    }
}

enum EditorCopilotRequestKind: Equatable, Sendable {
    case highlights(duration: Int, captions: Bool)
    case excerpt(start: Double, end: Double, captions: Bool)
    case edits
    case unsupported(String)
}

struct EditorCopilotEditOperation: Identifiable, Equatable, Sendable {
    enum Kind: String, Equatable, Sendable, CaseIterable {
        case addEffect, addKeyframe, addText, setVolume, addMarker, addCaptions, addTransition
        case split, setSpeed, crop, rotate, flip, setFilter
    }

    let id: Int
    let kind: Kind
    let start: Double
    let end: Double
    let amount: Double
    let effect: String?
    let property: String?
    let text: String?
    let fadeIn: Bool
    let fadeOut: Bool

    var duration: Double { max(0, end - start) }

    var title: String {
        switch kind {
        case .addEffect: return "Add \(Self.displayName(effect) ?? "effect")"
        case .addKeyframe: return "Keyframe \(Self.displayName(property) ?? "property")"
        case .addText: return "Add text"
        case .setVolume: return amount <= 0.001 ? "Mute clip" : "Set volume"
        case .addMarker: return "Add marker"
        case .addCaptions: return "Add captions"
        case .addTransition: return "\(Self.displayName(effect) ?? "Fade") transition"
        case .split: return "Split clip"
        case .setSpeed: return amount < 1 ? "Slow motion" : "Change speed"
        case .crop: return "Crop \(Self.displayName(effect) ?? "frame")"
        case .rotate: return "Rotate"
        case .flip: return text == "vertical" ? "Flip vertical" : "Flip horizontal"
        case .setFilter: return "\(Self.displayName(effect) ?? "Color") filter"
        }
    }

    var detail: String {
        switch kind {
        case .split:
            return "At \(Self.timecode(start))"
        case .setSpeed:
            return String(format: "%.2f× · %@", amount, Self.timecode(start))
        case .crop:
            return "\(Self.displayName(effect) ?? "Frame") · \(Self.timecode(start))"
        case .rotate:
            return "\(Int(amount) * 90)° · \(Self.timecode(start))"
        case .flip:
            return Self.timecode(start)
        case .setFilter:
            return "\(Self.displayName(effect) ?? "Filter") · \(Self.timecode(start))"
        case .addTransition:
            return "\(Self.timecode(start)) · \(String(format: "%.1f", max(amount, 0.1)))s"
        case .addCaptions:
            return "Transcribe speech on the current timeline and replace captions."
        case .addMarker:
            let name = text?.trimmingCharacters(in: .whitespacesAndNewlines)
            let label = (name?.isEmpty == false) ? name! : "Marker"
            return "\(label) at \(Self.timecode(start))"
        case .addText:
            let preview = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Text"
            return "“\(preview)” · \(Self.timecode(start))–\(Self.timecode(end))"
        case .setVolume:
            return "\(Int((amount * 100).rounded()))% · \(Self.timecode(start))"
        case .addKeyframe:
            var parts = ["\(Self.timecode(start))"]
            if end - start > 0.05 { parts.append(Self.timecode(end)) }
            parts.append(Self.formatValue(amount, property: property))
            if fadeIn { parts.append("fade in") }
            if fadeOut { parts.append("fade out") }
            return parts.joined(separator: " · ")
        case .addEffect:
            var parts = ["\(Self.timecode(start))–\(Self.timecode(end))"]
            parts.append("\(Int((amount * 100).rounded()))%")
            if fadeIn { parts.append("fade in") }
            if fadeOut { parts.append("fade out") }
            return parts.joined(separator: " · ")
        }
    }

    private static func displayName(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        return raw.replacingOccurrences(
            of: "([a-z])([A-Z])",
            with: "$1 $2",
            options: .regularExpression
        )
        .capitalized
    }

    private static func timecode(_ time: Double) -> String {
        let clamped = max(0, time)
        let minutes = Int(clamped) / 60
        let seconds = clamped.truncatingRemainder(dividingBy: 60)
        return String(format: "%d:%05.2f", minutes, seconds)
    }

    private static func formatValue(_ amount: Double, property: String?) -> String {
        switch property {
        case "opacity", "volume", "filterIntensity", "effectAmount":
            return "\(Int((amount * 100).rounded()))%"
        case "rotation", "textRotation":
            return String(format: "%.0f°", amount)
        case "scale", "cropScale", "textScale":
            return String(format: "%.2f×", amount)
        default:
            return String(format: "%.2f", amount)
        }
    }
}

struct EditorCopilotEditDraft: Equatable, Sendable {
    var kind: EditorCopilotEditOperation.Kind
    var start: Double
    var end: Double
    var amount: Double
    var effect: String
    var property: String
    var text: String
    var fadeIn: Bool
    var fadeOut: Bool
}

struct EditorCopilotEditPlan: Equatable, Sendable {
    let operations: [EditorCopilotEditOperation]
    let summary: String
    var needsCaptions: Bool { operations.contains { $0.kind == .addCaptions } }
    var needsTranscript: Bool { needsCaptions }

    static let transitionIDs: Set<String> = [
        "fade", "mix", "dipToBlack", "dipToWhite", "blink", "fadeLift", "fadeDrop",
        "zoomIn", "zoomOut", "shrink", "expand", "snapBack", "clapAndPull",
        "diveAndBounce", "dofWiggle", "tiltLeft", "tiltRight", "cameraShake",
        "swingLeft", "swingRight", "orbitLeft", "orbitRight",
        "flipZoomIn", "flipZoomOut", "bounceIn", "bounceOut",
        "slideLeft", "slideRight", "slideUp", "slideDown",
        "pushLeft", "pushRight", "pushUp", "pushDown",
        "driftLeft", "driftRight",
        "diagonalUpLeft", "diagonalUpRight", "diagonalDownLeft", "diagonalDownRight",
        "whipLeft", "whipRight", "elasticLeft", "elasticRight",
        "compressLeft", "compressRight", "stretchUp", "stretchDown",
        "panLeftZoom", "panRightZoom", "skewLeft", "skewRight",
        "spinLeft", "spinRight", "spinZoom", "rollLeft", "rollRight",
        "flipHorizontal", "flipVertical", "squeezeHorizontal", "squeezeVertical",
        "stretchLeft", "stretchRight", "dragSwitch",
        "flash", "flashZoom", "glare", "strobe", "lightSweep",
        "motionBlurLeft", "motionBlurRight", "motionBlurUp", "motionBlurDown",
        "zoomBlur", "gaussianBlur", "radialBlur",
        "pixelDissolve", "crystallize", "rgbSplit", "glitch",
        "ripple", "fisheye", "kaleidoscope",
        "bumpPulse", "pinchPulse", "vortexLeft", "vortexRight",
        "glassWarp", "triangleMirror", "torusLens",
        "comicFlash", "bloom", "vignettePulse",
        "hueSpin", "colorInvert", "posterize", "noirFlash", "sepiaFlash",
        "chromeFlash", "processFlash", "falseColor", "edgeGlow",
        "circleReveal", "radialWipe"
    ]

    static let effectIDs: Set<String> = [
        "gaussianBlur", "motionBlur", "bloom", "sharpen", "vignette", "grain",
        "pixelate", "crystallize", "comic", "monochrome", "sepia", "hueShift",
        "zoomBlur", "edgeGlow", "posterize", "invert", "falseColor", "noir", "chrome",
        "rgbSplit", "scanlines", "lineScreen", "dotScreen", "hexPixelate",
        "kaleidoscope", "twirl", "bump", "zoomPulse", "shake", "strobe"
    ]

    static let cropIDs: Set<String> = ["original", "vertical", "landscape", "square", "portrait"]
    static let filterIDs: Set<String> = [
        "vivid", "warm", "cool", "cinematic", "faded", "mono", "noir", "chrome",
        "natural", "fresh", "clean", "goldenHour", "portraitGlow", "blush", "softSkin",
        "tealOrange", "blockbuster", "moody", "nightDrive", "desert", "forest", "ocean",
        "vintageBronze", "romance", "retro", "sepia", "polaroid", "fadedFilm", "filmNoir",
        "tokyo", "cyberpunk", "dreamy", "neon", "aqua", "sunset", "lavender", "silver",
        "graphite", "highContrastBW"
    ]

    static let propertyIDs: Set<String> = [
        "positionX", "positionY", "scale", "rotation", "opacity", "volume",
        "cropX", "cropY", "cropScale", "filterIntensity", "textScale",
        "textRotation", "textPositionX", "textPositionY", "effectAmount"
    ]

    private static let effectAliases: [String: String] = [
        "blur": "gaussianBlur", "gaussian": "gaussianBlur", "gaussian blur": "gaussianBlur",
        "motion": "motionBlur", "motion blur": "motionBlur",
        "glow": "bloom", "dreamy": "bloom",
        "sharp": "sharpen",
        "grain": "grain", "film grain": "grain", "noise": "grain",
        "film": "grain",
        "black and white": "monochrome", "black & white": "monochrome",
        "b&w": "monochrome", "bw": "monochrome", "mono": "monochrome",
        "glitch": "rgbSplit", "rgb": "rgbSplit", "chromatic": "rgbSplit",
        "zoom": "zoomPulse", "pulse": "zoomPulse",
        "camera shake": "shake", "shake": "shake",
        "flash": "strobe",
        "hue": "hueShift", "tint": "hueShift",
        "comic book": "comic",
        "old film": "sepia",
        "pixel": "pixelate"
    ]

    private static let propertyAliases: [String: String] = [
        "x": "positionX", "position": "positionX", "pos x": "positionX",
        "y": "positionY", "pos y": "positionY",
        "zoom": "scale", "size": "scale",
        "rotate": "rotation", "angle": "rotation",
        "alpha": "opacity", "fade": "opacity",
        "gain": "volume", "audio": "volume", "loudness": "volume",
        "effect": "effectAmount", "amount": "effectAmount", "intensity": "effectAmount",
        "filter": "filterIntensity", "grade": "filterIntensity"
    ]

    static func resolvedEffectID(_ raw: String) -> String? {
        resolve(raw, allowed: effectIDs, aliases: effectAliases)
    }

    static func resolvedPropertyID(_ raw: String) -> String? {
        resolve(raw, allowed: propertyIDs, aliases: propertyAliases)
    }

    static func resolvedTransitionID(_ raw: String) -> String? {
        resolve(raw, allowed: transitionIDs, aliases: transitionAliases)
    }

    static func resolvedCropID(_ raw: String) -> String? {
        resolve(raw, allowed: cropIDs, aliases: [
            "9:16": "vertical", "9/16": "vertical", "tiktok": "vertical", "reels": "vertical",
            "16:9": "landscape", "16/9": "landscape", "widescreen": "landscape",
            "1:1": "square", "1/1": "square",
            "4:5": "portrait", "4/5": "portrait"
        ])
    }

    static func resolvedFilterID(_ raw: String) -> String? {
        resolve(raw, allowed: filterIDs, aliases: [
            "cinema": "cinematic", "movie": "cinematic", "film": "cinematic",
            "vintage": "retro", "old": "sepia", "bw": "mono", "b&w": "mono",
            "black and white": "mono", "teal": "tealOrange", "golden": "goldenHour"
        ])
    }

    static func draftsFromPrompt(
        _ prompt: String, playhead: Double, duration: Double
    ) -> [EditorCopilotEditDraft]? {
        let n = prompt.lowercased()
        var drafts: [EditorCopilotEditDraft] = []
        func add(_ kind: EditorCopilotEditOperation.Kind, amount: Double = 0,
                 effect: String = "none", property: String = "none",
                 text: String = "", fadeIn: Bool = false, fadeOut: Bool = false) {
            drafts.append(.init(
                kind: kind, start: playhead, end: playhead, amount: amount,
                effect: effect, property: property, text: text, fadeIn: fadeIn, fadeOut: fadeOut
            ))
        }
        if n.contains("caption") || n.contains("subtitle") { add(.addCaptions) }
        let wantsSplit = n.contains("split") || n.contains("cut here")
            || n.contains("blade") || n.contains("razor")
        let wantsTransition = n.contains("transition")
            || n.contains("crossfade") || n.contains("cross fade") || n.contains("dissolve")
            || ((n.contains("fade") && !n.contains("fade in") && !n.contains("fade out"))
                && (n.contains("playhead") || n.contains("cut") || n.contains("here")))
        if wantsTransition {
            add(.addTransition, amount: 0.5, effect: transitionKind(fromPrompt: n))
        }
        // A fade at the playhead already cuts there. A second split then fails
        // because the playhead is sitting on the new clip edge.
        if wantsSplit && !wantsTransition {
            add(.split)
        }
        if n.contains("mute") || n.contains("silence") {
            add(.setVolume, amount: 0)
        } else if n.contains("volume") || n.contains("quieter") || n.contains("louder") {
            let volume: Double
            if n.contains("quieter") || n.contains("lower") { volume = 0.4 }
            else if n.contains("louder") || n.contains("boost") { volume = 1 }
            else { volume = parsedSpeed(from: n) ?? 0.8 }
            add(.setVolume, amount: min(max(volume, 0), 1))
        }
        if n.contains("slow") || n.contains("slow-mo") || n.contains("slowmo")
            || n.contains("half speed") || n.contains("speed up") || n.contains("faster")
            || n.contains("2x") || n.contains("3x") || n.contains("0.5x") || n.contains("speed") {
            add(.setSpeed, amount: parsedSpeed(from: n) ?? (n.contains("slow") ? 0.5 : 2))
        }
        if let crop = cropKind(fromPrompt: n) { add(.crop, effect: crop) }
        if n.contains("rotate") || n.contains("90") || n.contains("180") || n.contains("270") {
            let turns = n.contains("180") ? 2 : n.contains("270") ? 3 : 1
            add(.rotate, amount: Double(turns))
        }
        if n.contains("flip") || n.contains("mirror") {
            add(.flip, text: n.contains("vert") ? "vertical" : "horizontal")
        }
        if let filter = filterKind(fromPrompt: n) { add(.setFilter, amount: 1, effect: filter) }
        if n.contains("fade in") && !wantsTransition {
            add(.addKeyframe, amount: 1, property: "opacity", fadeIn: true)
        } else if n.contains("fade out") && !wantsTransition {
            add(.addKeyframe, amount: 1, property: "opacity", fadeOut: true)
        }
        if let effect = namedEffect(fromPrompt: n) { add(.addEffect, amount: 0.65, effect: effect) }
        if n.contains("title") || n.contains("add text") || n.contains("on-screen text") {
            let quoted = quotedText(from: prompt) ?? "Title"
            add(.addText, amount: 1, text: quoted)
        }
        if n.contains("marker") { add(.addMarker, text: quotedText(from: prompt) ?? "Marker") }
        if n.contains("opacity") || n.contains("transparent") {
            add(.addKeyframe, amount: n.contains("transparent") ? 0.4 : 0.7, property: "opacity")
        }
        return drafts.isEmpty ? nil : Array(drafts.prefix(8))
    }

    private static func parsedSpeed(from prompt: String) -> Double? {
        if prompt.contains("0.5x") || prompt.contains("half") { return 0.5 }
        if prompt.contains("3x") { return 3 }
        if prompt.contains("2x") || prompt.contains("double") || prompt.contains("twice") { return 2 }
        if prompt.contains("slow") { return 0.5 }
        if prompt.contains("speed up") || prompt.contains("faster") { return 2 }
        if let match = prompt.range(of: #"(\d+(?:\.\d+)?)\s*x"#, options: .regularExpression) {
            return Double(prompt[match].replacingOccurrences(of: "x", with: "").trimmingCharacters(in: .whitespaces))
        }
        return nil
    }

    private static func cropKind(fromPrompt prompt: String) -> String? {
        if prompt.contains("9:16") || prompt.contains("9/16") || prompt.contains("vertical")
            || prompt.contains("tiktok") || prompt.contains("reels") { return "vertical" }
        if prompt.contains("16:9") || prompt.contains("16/9") || prompt.contains("landscape")
            || prompt.contains("widescreen") { return "landscape" }
        if prompt.contains("1:1") || prompt.contains("square") { return "square" }
        if prompt.contains("4:5") || prompt.contains("4/5") { return "portrait" }
        if prompt.contains("crop") { return "vertical" }
        return nil
    }

    private static func filterKind(fromPrompt prompt: String) -> String? {
        let padded = " \(prompt.lowercased()) "
        let ranked = filterIDs.sorted { spacedName($0).count > spacedName($1).count }
        for id in ranked {
            if padded.contains(" \(spacedName(id)) ") || padded.contains(" \(id.lowercased()) ") {
                return id
            }
        }
        let aliases = [
            "cinema": "cinematic", "cinematic": "cinematic", "vintage": "retro",
            "warm": "warm", "cool": "cool", "noir": "noir", "sepia": "sepia",
            "black and white": "mono", "b&w": "mono"
        ]
        for (alias, id) in aliases where padded.contains(alias) { return id }
        if prompt.contains("filter") || prompt.contains("grade") || prompt.contains("color") {
            return "cinematic"
        }
        return nil
    }

    private static func namedEffect(fromPrompt prompt: String) -> String? {
        let padded = " \(prompt.lowercased()) "
        let ranked = effectIDs.sorted { spacedName($0).count > spacedName($1).count }
        for id in ranked {
            let spaced = " \(spacedName(id)) "
            if padded.contains(spaced) || padded.contains(" \(id.lowercased()) ") { return id }
        }
        return resolvedEffectID(prompt)
    }

    private static func quotedText(from prompt: String) -> String? {
        if let match = prompt.range(of: #"[“"'](.+?)[”"']"#, options: .regularExpression) {
            return String(prompt[match]).trimmingCharacters(in: CharacterSet(charactersIn: "“”\"'"))
        }
        if let range = prompt.range(of: "says ", options: .caseInsensitive) {
            let rest = prompt[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            if !rest.isEmpty { return String(rest.prefix(80)) }
        }
        return nil
    }

    /// Picks a catalog transition from a free-form brief. Unspecified cuts default to fade.
    static func transitionKind(fromPrompt prompt: String) -> String {
        let padded = " " + prompt.lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            + " "
        let ranked = transitionIDs.sorted {
            spacedName($0).count > spacedName($1).count
        }
        for id in ranked {
            let spaced = " \(spacedName(id)) "
            let raw = " \(id.lowercased()) "
            if padded.contains(spaced) || padded.contains(raw) { return id }
        }
        let aliases = transitionAliases.keys.sorted { $0.count > $1.count }
        for alias in aliases where padded.contains(" \(alias) ") {
            if let id = transitionAliases[alias] { return id }
        }
        return "fade"
    }

    private static let transitionAliases: [String: String] = [
        "crossfade": "mix", "cross fade": "mix", "dissolve": "fade",
        "dip to black": "dipToBlack", "dip to white": "dipToWhite",
        "slide": "slideLeft", "push": "pushLeft", "zoom": "zoomIn"
    ]

    private static func spacedName(_ camel: String) -> String {
        camel.replacingOccurrences(
            of: "([a-z])([A-Z])",
            with: "$1 $2",
            options: .regularExpression
        ).lowercased()
    }

    static func validated(
        drafts: [EditorCopilotEditDraft],
        timelineDuration: Double,
        playhead: Double,
        summary: String
    ) throws -> Self {
        guard timelineDuration.isFinite, timelineDuration > 0 else {
            throw EditorCopilotError.message("The timeline has no duration to edit.")
        }
        guard playhead.isFinite else {
            throw EditorCopilotError.message("The playhead time is invalid. Move it and try again.")
        }
        guard !drafts.isEmpty else {
            throw EditorCopilotError.message("The model did not return any timeline edits. Try a more specific request.")
        }
        guard drafts.count <= 8 else {
            throw EditorCopilotError.message("Too many edits in one request. Ask for up to eight changes.")
        }
        var operations: [EditorCopilotEditOperation] = []
        for (index, draft) in drafts.enumerated() {
            operations.append(try normalize(draft, id: index, duration: timelineDuration, playhead: playhead))
        }
        operations = coalesced(operations)
        guard !operations.isEmpty else {
            throw EditorCopilotError.message("The model did not return any timeline edits. Try a more specific request.")
        }
        let trimmedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedSummary = trimmedSummary.isEmpty
            ? operations.map(\.title).joined(separator: " · ")
            : String(trimmedSummary.prefix(160))
        return Self(operations: operations, summary: resolvedSummary)
    }

    /// A transition at a time already cuts there. Drop a same-time split so
    /// Apply does not fail with "too close to a clip edge".
    private static func coalesced(
        _ operations: [EditorCopilotEditOperation]
    ) -> [EditorCopilotEditOperation] {
        let transitionTimes = operations.compactMap { operation -> Double? in
            operation.kind == .addTransition ? operation.start : nil
        }
        return operations.filter { operation in
            guard operation.kind == .split else { return true }
            return !transitionTimes.contains { abs($0 - operation.start) <= 0.05 }
        }
    }

    private static func normalize(
        _ draft: EditorCopilotEditDraft,
        id: Int,
        duration: Double,
        playhead: Double
    ) throws -> EditorCopilotEditOperation {
        guard draft.start.isFinite, draft.end.isFinite else {
            throw EditorCopilotError.message("An edit used a non-finite time. No changes were applied.")
        }
        var start = draft.start
        var end = draft.end
        if abs(start - playhead) <= 0.04 { start = playhead }
        if abs(end - playhead) <= 0.04 { end = playhead }
        if end < start { swap(&start, &end) }
        start = min(max(0, start), duration)
        end = min(max(0, end), duration)

        var effect = optionalToken(draft.effect).flatMap(resolvedEffectID)
        var property = optionalToken(draft.property).flatMap(resolvedPropertyID)
        var text = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.count > 120 { text = String(text.prefix(120)) }
        var amount = draft.amount.isFinite ? draft.amount : 0
        var fadeIn = draft.fadeIn
        var fadeOut = draft.fadeOut

        switch draft.kind {
        case .addEffect:
            guard let resolved = effect else {
                throw EditorCopilotError.message("That effect is not available. Try vignette, bloom, grain, blur, or shake.")
            }
            effect = resolved
            property = nil
            text = ""
            if amount <= 0.01 { amount = 0.65 }
            amount = min(max(amount, 0.05), 1)
            if end - start < 0.45 {
                end = min(duration, start + 3)
                if end - start < 0.45 { start = max(0, end - 3) }
            }
            guard end - start >= 0.45 else {
                throw EditorCopilotError.message("There is not enough timeline to place that effect.")
            }
            if !fadeIn && !fadeOut {
                fadeIn = true
                fadeOut = true
            }
        case .addKeyframe:
            guard let resolved = property else {
                throw EditorCopilotError.message("Choose a keyframe property such as opacity, scale, or volume.")
            }
            property = resolved
            effect = nil
            if ["scale", "cropScale", "textScale"].contains(resolved), amount <= 0.01 || abs(amount - 1) < 0.001 {
                amount = 1.2
            }
            if resolved == "opacity", amount <= 0.01 {
                amount = 1
            }
            amount = clamp(amount, property: resolved)
            if end < start { end = start }
            if (fadeIn || fadeOut) && end - start < 0.2 {
                end = min(duration, start + 1)
                if fadeIn && !fadeOut { start = max(0, end - 1) }
            }
        case .addText:
            guard !text.isEmpty else {
                throw EditorCopilotError.message("Add the exact title or caption text you want on screen.")
            }
            effect = nil
            property = nil
            amount = min(max(amount <= 0.01 ? 1 : amount, 0.05), 1)
            if end - start < 0.45 {
                end = min(duration, start + 3)
                if end - start < 0.45 { start = max(0, end - 3) }
            }
            guard end - start >= 0.45 else {
                throw EditorCopilotError.message("There is not enough timeline to place that text.")
            }
        case .addTransition:
            effect = optionalToken(draft.effect).flatMap(resolvedTransitionID)
                ?? optionalToken(draft.text).flatMap(resolvedTransitionID)
                ?? "fade"
            property = nil
            text = ""
            fadeIn = false
            fadeOut = false
            if amount <= 0.05 || amount > 2 { amount = 0.5 }
            amount = min(max(amount, 0.1), 2)
            end = start
        case .split:
            effect = nil
            property = nil
            text = ""
            amount = 0
            fadeIn = false
            fadeOut = false
            end = start
        case .setSpeed:
            effect = nil
            property = nil
            text = ""
            fadeIn = false
            fadeOut = false
            if amount <= 0.01 { amount = 0.5 }
            amount = min(max(amount, 0.25), 3)
            end = start
        case .crop:
            effect = optionalToken(draft.effect).flatMap(resolvedCropID)
                ?? optionalToken(draft.text).flatMap(resolvedCropID)
                ?? "vertical"
            property = nil
            text = ""
            amount = 0
            fadeIn = false
            fadeOut = false
            end = start
        case .rotate:
            effect = nil
            property = nil
            text = ""
            fadeIn = false
            fadeOut = false
            if amount >= 90 { amount = (amount / 90).rounded() }
            if amount <= 0 { amount = 1 }
            amount = min(max(amount.rounded(), 1), 3)
            end = start
        case .flip:
            effect = nil
            property = nil
            let axis = text.lowercased()
            text = axis.contains("vert") || axis.contains("up") ? "vertical" : "horizontal"
            amount = 0
            fadeIn = false
            fadeOut = false
            end = start
        case .setFilter:
            effect = optionalToken(draft.effect).flatMap(resolvedFilterID)
                ?? optionalToken(draft.text).flatMap(resolvedFilterID)
                ?? "cinematic"
            property = nil
            text = ""
            if amount <= 0.01 { amount = 1 }
            amount = min(max(amount, 0.1), 1)
            fadeIn = false
            fadeOut = false
            end = start
        case .setVolume:
            effect = nil
            property = "volume"
            text = ""
            amount = min(max(amount, 0), 1)
            end = start
        case .addMarker:
            effect = nil
            property = nil
            amount = 0
            fadeIn = false
            fadeOut = false
            end = start
        case .addCaptions:
            effect = nil
            property = nil
            text = ""
            amount = 0
            fadeIn = false
            fadeOut = false
            start = 0
            end = duration
        }

        return EditorCopilotEditOperation(
            id: id, kind: draft.kind, start: start, end: end, amount: amount,
            effect: effect, property: property,
            text: text.isEmpty ? nil : text,
            fadeIn: fadeIn, fadeOut: fadeOut
        )
    }

    private static func optionalToken(_ raw: String) -> String? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.isEmpty || value == "none" || value == "n/a" || value == "-" { return nil }
        return value
    }

    private static func resolve(_ raw: String, allowed: Set<String>, aliases: [String: String]) -> String? {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .lowercased()
        if normalized.isEmpty { return nil }
        let compact = normalized.replacingOccurrences(of: " ", with: "")
        if allowed.contains(normalized) { return normalized }
        if allowed.contains(compact) { return compact }
        if let alias = aliases[normalized] ?? aliases[compact], allowed.contains(alias) {
            return alias
        }
        let camel = allowed.first { $0.lowercased() == compact }
        if let camel { return camel }
        return allowed.first {
            $0.lowercased().contains(compact) || compact.contains($0.lowercased())
        }
    }

    private static func clamp(_ amount: Double, property: String) -> Double {
        let range: ClosedRange<Double>
        switch property {
        case "positionX", "positionY", "cropX", "cropY": range = -1...1
        case "textPositionX", "textPositionY": range = -1000...1000
        case "scale", "textScale": range = 0.25...4
        case "cropScale": range = 0.5...4
        case "rotation", "textRotation": range = -180...180
        default: range = 0...1
        }
        if !amount.isFinite { return range.contains(1) ? 1 : range.lowerBound }
        return min(max(amount, range.lowerBound), range.upperBound)
    }
}
