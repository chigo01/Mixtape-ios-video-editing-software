import AVFoundation
import Speech
import SwiftUI
import UniformTypeIdentifiers

enum EditorCaptionError: LocalizedError {
    case permissionDenied
    case recognizerUnavailable
    case noAudioTrack
    case silentAudio
    case noSpeech(attemptedLanguages: [String])
    case recognitionFailed(String)
    case audioRenderFailed
    case invalidSRT

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Speech Recognition access is required to create captions."
        case .recognizerUnavailable:
            return "Speech recognition is temporarily unavailable for this language."
        case .noAudioTrack:
            return "The selected caption source has no audio track. Choose Entire timeline mix if the dialogue is on a voiceover or imported audio lane."
        case .silentAudio:
            return "The selected caption source is silent. Check clip volume/mute settings or choose Video audio to recognize the embedded dialogue."
        case .noSpeech(let languages):
            let attempted = languages.isEmpty ? "the selected language" : languages.joined(separator: ", ")
            return "Audio was found, but no speech could be recognized using \(attempted). Check the spoken language or try Entire timeline mix."
        case .recognitionFailed(let detail):
            return "Speech recognition could not complete. Check your connection and try again. \(detail)"
        case .audioRenderFailed:
            return "Mixtape could not prepare the timeline audio for transcription."
        case .invalidSRT:
            return "The selected file is not a valid SRT subtitle file."
        }
    }
}

enum EditorCaptionAudioSource: String, CaseIterable, Identifiable {
    case video
    case timelineMix

    var id: String { rawValue }

    var title: String {
        switch self {
        case .video: return "Video audio"
        case .timelineMix: return "Entire timeline mix"
        }
    }

    var explanation: String {
        switch self {
        case .video:
            return "Uses embedded clip dialogue and ignores clip/master mute levels."
        case .timelineMix:
            return "Includes video, voiceovers, overlays, and imported audio with the current mix levels."
        }
    }
}

struct EditorCaptionTranscriptResult: Sendable {
    let words: [EditorCaptionWord]
    let localeIdentifier: String
}

/// Builds the same edited audio mix used by preview/export, then asks Apple's
/// Speech framework for timed words. That makes caption timing respect trims,
/// speed changes, clip gain, voiceovers, and imported dialogue tracks.
enum EditorCaptionService {
    @MainActor
    static func transcribe(
        clips: [EditorClip],
        audioClips: [EditorAudioClip],
        overlayClips: [EditorOverlayClip],
        audioTrackSettings: [Int: EditorAudioTrackSettings],
        masterVolume: Float,
        requestedLocaleIdentifier: String?,
        source: EditorCaptionAudioSource
    ) async throws -> EditorCaptionTranscriptResult {
        let authorization = await requestAuthorization()
        guard authorization == .authorized else { throw EditorCaptionError.permissionDenied }

        let recognitionClips = source == .video ? clipsForSpeechRecognition(clips) : clips
        guard let built = await EditorCompositionBuilder.build(
            from: recognitionClips,
            audioClips: source == .timelineMix ? audioClips : [],
            overlayClips: source == .timelineMix ? overlayClips : [],
            audioTrackSettings: source == .timelineMix ? audioTrackSettings : [:],
            masterVolume: source == .timelineMix ? masterVolume : 1
        ) else {
            throw EditorCaptionError.audioRenderFailed
        }

        let compositionAudioTracks = try await built.composition.loadTracks(withMediaType: .audio)
        var hasTimedAudio = false
        for track in compositionAudioTracks {
            let timeRange = try await track.load(.timeRange)
            if timeRange.duration.seconds > 0.05 {
                hasTimedAudio = true
                break
            }
        }
        guard hasTimedAudio else { throw EditorCaptionError.noAudioTrack }

        let audioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Mixtape-Caption-Audio-\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: audioURL) }

        guard let exporter = AVAssetExportSession(
            asset: built.composition,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw EditorCaptionError.audioRenderFailed
        }
        exporter.audioMix = built.audioMix
        let exportBox = ExportSessionBox(exporter)
        do {
            try await withTaskCancellationHandler {
                try await exporter.export(to: audioURL, as: .m4a)
            } onCancel: {
                exportBox.cancel()
            }
        } catch is CancellationError {
            exporter.cancelExport()
            throw CancellationError()
        } catch {
            throw EditorCaptionError.audioRenderFailed
        }

        let renderedAudioIsAudible = try await Task.detached(priority: .userInitiated) {
            try hasAudibleSamples(at: audioURL)
        }.value
        guard renderedAudioIsAudible else { throw EditorCaptionError.silentAudio }

        let candidates = recognitionLocaleCandidates(requestedIdentifier: requestedLocaleIdentifier)
        var attemptedLanguages: [String] = []
        var lastRecognitionError: Error?
        var receivedEmptyResult = false

        for locale in candidates {
            try Task.checkCancellation()
            guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
                continue
            }
            attemptedLanguages.append(locale.localizedString(forIdentifier: locale.identifier) ?? locale.identifier)

            // Server-assisted recognition is substantially more tolerant of music,
            // accents, and compressed social-video audio. If it returns no words,
            // retry on-device when that language supports it.
            let recognitionModes = recognizer.supportsOnDeviceRecognition ? [false, true] : [false]
            for requiresOnDevice in recognitionModes {
                let request = SFSpeechURLRecognitionRequest(url: audioURL)
                request.shouldReportPartialResults = true
                request.addsPunctuation = true
                request.taskHint = .dictation
                request.requiresOnDeviceRecognition = requiresOnDevice

                do {
                    let transcription = try await recognize(request: request, with: recognizer)
                    let words = captionWords(
                        from: transcription,
                        fallbackDuration: built.duration.seconds
                    )
                    if !words.isEmpty {
                        return EditorCaptionTranscriptResult(
                            words: words,
                            localeIdentifier: locale.identifier
                        )
                    }
                    receivedEmptyResult = true
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    lastRecognitionError = error
                }
            }
        }

        if attemptedLanguages.isEmpty {
            throw EditorCaptionError.recognizerUnavailable
        }
        if !receivedEmptyResult, let lastRecognitionError {
            throw EditorCaptionError.recognitionFailed(lastRecognitionError.localizedDescription)
        }
        throw EditorCaptionError.noSpeech(attemptedLanguages: attemptedLanguages)
    }

    static func supportedLanguageOptions() -> [(identifier: String, title: String)] {
        SFSpeechRecognizer.supportedLocales()
            .sorted {
                ($0.localizedString(forIdentifier: $0.identifier) ?? $0.identifier)
                    < ($1.localizedString(forIdentifier: $1.identifier) ?? $1.identifier)
            }
            .map { locale in
                (locale.identifier, locale.localizedString(forIdentifier: locale.identifier) ?? locale.identifier)
            }
    }

    static func makeCaptionOverlays(
        from result: EditorCaptionTranscriptResult,
        wordsPerSegment: Int = 7,
        maximumSegmentDuration: TimeInterval = 3.5,
        maximumCharactersPerSegment: Int = 42,
        pauseBreakDuration: TimeInterval = 0.65
    ) -> [EditorTextOverlay] {
        var groups: [[EditorCaptionWord]] = []
        var current: [EditorCaptionWord] = []

        for word in result.words {
            let proposedCharacterCount = current.map(\.text).joined(separator: " ").count
                + (current.isEmpty ? 0 : 1) + word.text.count
            let followsPause = current.last.map {
                word.startTime - $0.endTime >= pauseBreakDuration
            } ?? false
            if let first = current.first,
               current.count >= wordsPerSegment
                || word.endTime - first.startTime > maximumSegmentDuration
                || proposedCharacterCount > maximumCharactersPerSegment
                || followsPause {
                groups.append(current)
                current = []
            }
            current.append(word)
            if word.text.last.map({ ".!?".contains($0) }) == true {
                groups.append(current)
                current = []
            }
        }
        if !current.isEmpty { groups.append(current) }

        return groups.compactMap { words in
            guard let first = words.first, let last = words.last else { return nil }
            return EditorTextOverlay(
                text: words.map(\.text).joined(separator: " "),
                startTime: first.startTime,
                endTime: max(last.endTime, first.startTime + 0.1),
                fontSize: 34,
                fontStyle: .background,
                verticalAlignment: .bottom,
                yOffset: -26,
                captionWords: words,
                captionHighlightColor: .yellow,
                captionLocaleIdentifier: result.localeIdentifier
            )
        }
    }

    private static func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
    }

    private static func clipsForSpeechRecognition(_ clips: [EditorClip]) -> [EditorClip] {
        clips.map { source in
            var clip = source
            clip.volume = 1
            var tracks = clip.keyframes
            tracks.replace(EditorKeyframeTrack(property: .volume))
            clip.keyframes = tracks
            return clip
        }
    }

    private static func recognitionLocaleCandidates(requestedIdentifier: String?) -> [Locale] {
        let supported = SFSpeechRecognizer.supportedLocales()
        var identifiers: [String] = []

        func appendBestMatch(for locale: Locale) {
            if let exact = supported.first(where: {
                $0.identifier.replacingOccurrences(of: "_", with: "-")
                    .caseInsensitiveCompare(locale.identifier.replacingOccurrences(of: "_", with: "-")) == .orderedSame
            }) {
                identifiers.append(exact.identifier)
                return
            }
            let language = locale.language.languageCode?.identifier
            if let sameLanguage = supported.first(where: {
                $0.language.languageCode?.identifier == language
            }) {
                identifiers.append(sameLanguage.identifier)
            }
        }

        if let requestedIdentifier {
            appendBestMatch(for: Locale(identifier: requestedIdentifier))
        } else {
            appendBestMatch(for: .current)
            appendBestMatch(for: Locale(identifier: "en-US"))
            appendBestMatch(for: Locale(identifier: "en-GB"))
        }

        var seen = Set<String>()
        return identifiers.filter { seen.insert($0).inserted }.map(Locale.init(identifier:))
    }

    private static func captionWords(
        from transcription: SFTranscription,
        fallbackDuration: TimeInterval
    ) -> [EditorCaptionWord] {
        let timedWords = transcription.segments.compactMap { segment -> EditorCaptionWord? in
            let value = segment.substring.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return nil }
            return EditorCaptionWord(
                text: value,
                startTime: segment.timestamp,
                endTime: segment.timestamp + max(segment.duration, 0.05),
                confidence: segment.confidence
            )
        }
        if !timedWords.isEmpty { return timedWords }

        // Some OS/language combinations produce a formatted final string but
        // omit segment metadata. Preserve useful recognition instead of showing
        // a false "no speech" error; distribute deterministic word timing.
        let tokens = transcription.formattedString
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        guard !tokens.isEmpty else { return [] }
        let duration = max(fallbackDuration, Double(tokens.count) * 0.15)
        let step = duration / Double(tokens.count)
        return tokens.enumerated().map { index, token in
            EditorCaptionWord(
                text: token,
                startTime: Double(index) * step,
                endTime: Double(index + 1) * step,
                confidence: 0.5
            )
        }
    }

    private static func hasAudibleSamples(at url: URL) throws -> Bool {
        let file = try AVAudioFile(forReading: url)
        guard file.length > 0 else { return false }
        let format = file.processingFormat
        let capacity: AVAudioFrameCount = 8_192
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            return false
        }

        while file.framePosition < file.length {
            try Task.checkCancellation()
            try file.read(into: buffer, frameCount: capacity)
            let frames = Int(buffer.frameLength)
            guard frames > 0 else { break }
            if let channels = buffer.floatChannelData {
                for channel in 0..<Int(format.channelCount) {
                    for frame in 0..<frames where abs(channels[channel][frame]) > 0.000_5 {
                        return true
                    }
                }
            }
        }
        return false
    }

    private static func recognize(
        request: SFSpeechRecognitionRequest,
        with recognizer: SFSpeechRecognizer
    ) async throws -> SFTranscription {
        let box = SpeechTaskBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                var completed = false
                let task = recognizer.recognitionTask(with: request) { result, error in
                    guard !completed else { return }
                    if let error {
                        completed = true
                        continuation.resume(throwing: error)
                    } else if let result, result.isFinal {
                        completed = true
                        continuation.resume(returning: result.bestTranscription)
                    }
                }
                box.store(task)
            }
        } onCancel: {
            box.cancel()
        }
    }
}

private final class SpeechTaskBox: @unchecked Sendable {
    private let lock = NSLock()
    private var task: SFSpeechRecognitionTask?
    private var isCancelled = false

    func store(_ task: SFSpeechRecognitionTask) {
        lock.lock()
        self.task = task
        let shouldCancel = isCancelled
        lock.unlock()
        if shouldCancel { task.cancel() }
    }

    func cancel() {
        lock.lock()
        isCancelled = true
        let task = task
        lock.unlock()
        task?.cancel()
    }
}

private final class ExportSessionBox: @unchecked Sendable {
    private let exporter: AVAssetExportSession

    init(_ exporter: AVAssetExportSession) {
        self.exporter = exporter
    }

    func cancel() {
        exporter.cancelExport()
    }
}

enum EditorSRTCodec {
    static func encode(_ captions: [EditorTextOverlay]) -> String {
        captions.filter(\.isCaption).sorted { $0.startTime < $1.startTime }
            .enumerated().map { index, caption in
                "\(index + 1)\n\(timestamp(caption.startTime)) --> \(timestamp(caption.endTime))\n\(caption.text)"
            }.joined(separator: "\n\n") + "\n"
    }

    static func decode(_ data: Data) throws -> [EditorTextOverlay] {
        guard let source = String(data: data, encoding: .utf8) else {
            throw EditorCaptionError.invalidSRT
        }
        let normalized = source.replacingOccurrences(of: "\r\n", with: "\n")
        let blocks = normalized.components(separatedBy: "\n\n")
        var captions: [EditorTextOverlay] = []

        for block in blocks {
            let lines = block.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            guard lines.count >= 2 else { continue }
            let timingIndex = lines.firstIndex(where: { $0.contains("-->") })
            guard let timingIndex else { continue }
            let times = lines[timingIndex].components(separatedBy: "-->")
            guard times.count == 2,
                  let start = parseTimestamp(times[0]),
                  let end = parseTimestamp(times[1]), end > start else { continue }
            let text = lines.dropFirst(timingIndex + 1).joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let tokens = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            let step = (end - start) / Double(max(tokens.count, 1))
            let words = tokens.enumerated().map { index, token in
                EditorCaptionWord(
                    text: token,
                    startTime: start + Double(index) * step,
                    endTime: start + Double(index + 1) * step
                )
            }
            captions.append(EditorTextOverlay(
                text: text,
                startTime: start,
                endTime: end,
                fontSize: 34,
                fontStyle: .background,
                verticalAlignment: .bottom,
                yOffset: -26,
                captionWords: words
            ))
        }
        guard !captions.isEmpty else { throw EditorCaptionError.invalidSRT }
        return captions
    }

    private static func timestamp(_ seconds: TimeInterval) -> String {
        let milliseconds = max(0, Int((seconds * 1_000).rounded()))
        return String(
            format: "%02d:%02d:%02d,%03d",
            milliseconds / 3_600_000,
            (milliseconds / 60_000) % 60,
            (milliseconds / 1_000) % 60,
            milliseconds % 1_000
        )
    }

    private static func parseTimestamp(_ source: String) -> TimeInterval? {
        let values = source.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ".", with: ",")
            .split(whereSeparator: { ":,".contains($0) })
        guard values.count == 4,
              let hours = Double(values[0]), let minutes = Double(values[1]),
              let seconds = Double(values[2]), let milliseconds = Double(values[3]) else { return nil }
        return hours * 3_600 + minutes * 60 + seconds + milliseconds / 1_000
    }
}

struct CaptionSRTDocument: FileDocument {
    static var readableContentTypes: [UTType] { [UTType(filenameExtension: "srt") ?? .plainText] }
    var text: String

    init(text: String = "") { self.text = text }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let text = String(data: data, encoding: .utf8) else {
            throw EditorCaptionError.invalidSRT
        }
        self.text = text
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
