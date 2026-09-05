import AVFoundation
import CoreMedia
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
    case onDeviceUnavailable

    var errorDescription: String? {
        switch self {
        case .onDeviceUnavailable:
            return "On-device speech recognition is unavailable for this language. MixPilot will not upload audio. Choose another supported language or install its speech resources."
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
        source: EditorCaptionAudioSource,
        requiresOnDeviceRecognition: Bool = false,
        timeRange: ClosedRange<TimeInterval>? = nil,
        highlightSampleTarget: TimeInterval? = nil,
        onProgress: @MainActor (String) -> Void = { _ in }
    ) async throws -> EditorCaptionTranscriptResult {
        let authorization = await requestAuthorization()
        guard authorization == .authorized else { throw EditorCaptionError.permissionDenied }
        try Task.checkCancellation()
        onProgress("Preparing timeline audio…")

        let recognitionClips = source == .video ? clipsForSpeechRecognition(clips) : clips
        guard let built = await EditorCompositionBuilder.build(
            from: recognitionClips,
            audioClips: source == .timelineMix ? audioClips : [],
            overlayClips: source == .timelineMix ? overlayClips : [],
            audioTrackSettings: source == .timelineMix ? audioTrackSettings : [:],
            masterVolume: source == .timelineMix ? masterVolume : 1
        ) else {
            try Task.checkCancellation()
            throw EditorCaptionError.audioRenderFailed
        }

        try Task.checkCancellation()
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

        let totalDuration = built.duration.seconds
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Mixtape-Caption-Chunks-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let shouldSample = highlightSampleTarget.map { $0 > 0 && totalDuration > 8 * 60 } ?? false
        let chunks: [AudioChunk]
        if shouldSample, let target = highlightSampleTarget {
            onProgress(totalDuration >= 3600
                ? String(format: "Scanning %.1f hours for speech…", totalDuration / 3600)
                : String(format: "Scanning %.0f minutes for speech…", totalDuration / 60))
            chunks = try await sampleSpeechChunks(
                composition: built.composition,
                duration: totalDuration,
                targetDuration: target,
                directory: directory,
                onProgress: onProgress
            )
        } else if let timeRange {
            onProgress("Preparing selected audio…")
            chunks = try await extractRangeChunks(
                composition: built.composition,
                range: timeRange,
                duration: totalDuration,
                directory: directory
            )
        } else {
            let audioURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("Mixtape-Caption-Audio-\(UUID().uuidString).m4a")
            defer { try? FileManager.default.removeItem(at: audioURL) }
            try await exportAudio(from: built, to: audioURL, timeRange: nil)
            onProgress("Preparing speech sections…")
            let preparation = Task.detached(priority: .userInitiated) {
                try prepareChunks(audioURL: audioURL, directory: directory)
            }
            chunks = try await withTaskCancellationHandler {
                try await preparation.value
            } onCancel: { preparation.cancel() }
        }
        guard chunks.contains(where: \.isAudible) else { throw EditorCaptionError.silentAudio }
        let candidates = recognitionLocaleCandidates(requestedIdentifier: requestedLocaleIdentifier)

        var allWords: [EditorCaptionWord] = []
        var preferredLocale: Locale?
        var preferredMode: Bool?
        for (index, chunk) in chunks.enumerated() {
            try Task.checkCancellation()
            onProgress("Recognizing section \(index + 1) of \(chunks.count)…")
            guard chunk.isAudible else { continue }
            // Once a language/mode works, reuse it instead of repeating language
            // discovery for every section. Requests remain serial to avoid Speech throttling.
            let locales = preferredLocale.map { [$0] } ?? candidates
            var recognized: [EditorCaptionWord]?
            var lastError: Error?
            for locale in locales {
                guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
                    lastError = EditorCaptionError.recognizerUnavailable
                    continue
                }
                if requiresOnDeviceRecognition && !recognizer.supportsOnDeviceRecognition {
                    lastError = EditorCaptionError.onDeviceUnavailable
                    continue
                }
                var modes = requiresOnDeviceRecognition ? [true] : (recognizer.supportsOnDeviceRecognition ? [true, false] : [false])
                if let preferredMode, modes.contains(preferredMode) {
                    modes = [preferredMode] + modes.filter { $0 != preferredMode }
                }
                for onDevice in modes {
                    try Task.checkCancellation()
                    let request = SFSpeechURLRecognitionRequest(url: chunk.url)
                    request.shouldReportPartialResults = false
                    request.addsPunctuation = true
                    request.taskHint = .dictation
                    request.requiresOnDeviceRecognition = onDevice
                    do {
                        let transcription = try await recognize(request: request, with: recognizer)
                        let words = captionWords(from: transcription, fallbackDuration: chunk.duration)
                        if !words.isEmpty {
                            recognized = words
                            preferredLocale = locale
                            preferredMode = onDevice
                            break
                        }
                        // An explicit empty final result is valid for music/non-speech.
                        recognized = []
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        if isBenignNoSpeech(error) {
                            recognized = []
                            break
                        }
                        lastError = error
                    }
                }
                if let recognized, !recognized.isEmpty { break }
            }
            guard let recognized else {
                if requiresOnDeviceRecognition {
                    throw EditorCopilotError.message(
                        "On-device transcription could not finish. No audio was uploaded. "
                        + (lastError?.localizedDescription ?? "Try another spoken language.")
                    )
                }
                throw EditorCaptionError.recognitionFailed(
                    "Section \(index + 1) of \(chunks.count) could not finish. Existing captions were kept. "
                    + (lastError?.localizedDescription ?? "Try selecting the spoken language.")
                )
            }
            for var word in recognized {
                let midpoint = chunk.start + (word.startTime + word.endTime) / 2
                // Overlapping context belongs to exactly one section, preventing
                // duplicated boundary words while retaining the original timeline clock.
                guard midpoint >= chunk.ownedStart, midpoint < chunk.ownedEnd else { continue }
                word.startTime = max(chunk.ownedStart, chunk.start + word.startTime)
                word.endTime = min(chunk.ownedEnd, chunk.start + word.endTime)
                guard word.endTime > word.startTime else { continue }
                allWords.append(word)
            }
        }
        guard !allWords.isEmpty else {
            throw EditorCaptionError.noSpeech(attemptedLanguages: candidates.map(\.identifier))
        }
        return EditorCaptionTranscriptResult(
            words: allWords.sorted { $0.startTime < $1.startTime },
            localeIdentifier: preferredLocale?.identifier ?? Locale.current.identifier
        )
    }

    private struct AudioChunk: Sendable {
        let url: URL
        let start: TimeInterval
        let duration: TimeInterval
        let ownedStart: TimeInterval
        let ownedEnd: TimeInterval
        let isAudible: Bool
    }

    /// Decode once, then write bounded PCM files without an AAC export per section.
    private static func prepareChunks(audioURL: URL, directory: URL) throws -> [AudioChunk] {
        let input = try AVAudioFile(forReading: audioURL)
        let format = input.processingFormat
        let sampleRate = format.sampleRate
        guard sampleRate.isFinite, sampleRate > 0 else { throw EditorCaptionError.audioRenderFailed }
        let duration = Double(input.length) / sampleRate
        let sectionDuration = 30.0
        let context = 0.5
        var chunks: [AudioChunk] = []
        var ownedStart = 0.0
        while ownedStart < duration {
            try Task.checkCancellation()
            let ownedEnd = min(duration, ownedStart + sectionDuration)
            let start = max(0, ownedStart - context)
            let end = min(duration, ownedEnd + context)
            let url = directory.appendingPathComponent("section-\(chunks.count).caf")
            let output = try AVAudioFile(forWriting: url, settings: format.settings)
            input.framePosition = AVAudioFramePosition((start * sampleRate).rounded(.down))
            let endFrame = min(input.length, AVAudioFramePosition((end * sampleRate).rounded(.down)))
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8_192) else {
                throw EditorCaptionError.audioRenderFailed
            }
            var audible = false
            while input.framePosition < endFrame {
                try Task.checkCancellation()
                let count = AVAudioFrameCount(min(8_192, endFrame - input.framePosition))
                try input.read(into: buffer, frameCount: count)
                guard buffer.frameLength > 0 else { throw EditorCaptionError.audioRenderFailed }
                if !audible, let channels = buffer.floatChannelData {
                    for channel in 0..<Int(format.channelCount) {
                        for frame in 0..<Int(buffer.frameLength) where abs(channels[channel][frame]) > 0.000_5 {
                            audible = true
                            break
                        }
                    }
                }
                try output.write(from: buffer)
            }
            chunks.append(AudioChunk(url: url, start: start, duration: end - start,
                                     ownedStart: ownedStart, ownedEnd: ownedEnd, isAudible: audible))
            ownedStart = ownedEnd
        }
        return chunks
    }

    private static func exportAudio(
        from built: EditorCompositionBuildResult,
        to audioURL: URL,
        timeRange: ClosedRange<TimeInterval>?
    ) async throws {
        guard let exporter = AVAssetExportSession(
            asset: built.composition,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw EditorCaptionError.audioRenderFailed
        }
        exporter.audioMix = built.audioMix
        if let timeRange {
            let start = CMTime(seconds: max(0, timeRange.lowerBound), preferredTimescale: 600)
            let duration = CMTime(
                seconds: max(0.1, timeRange.upperBound - timeRange.lowerBound),
                preferredTimescale: 600
            )
            exporter.timeRange = CMTimeRange(start: start, duration: duration)
        }
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
            try Task.checkCancellation()
            throw EditorCaptionError.audioRenderFailed
        }
    }

    @MainActor
    private static func sampleSpeechChunks(
        composition: AVMutableComposition,
        duration: TimeInterval,
        targetDuration: TimeInterval,
        directory: URL,
        onProgress: @MainActor (String) -> Void
    ) async throws -> [AudioChunk] {
        let budget = EditorCopilotPlan.recognitionBudget(
            timelineDuration: duration, targetDuration: targetDuration
        )
        let scan = Task.detached(priority: .userInitiated) {
            try energyBins(from: composition, duration: duration)
        }
        let bins: [(time: Double, rms: Double)]
        do {
            bins = try await withTaskCancellationHandler {
                try await scan.value
            } onCancel: { scan.cancel() }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            bins = []
        }
        try Task.checkCancellation()
        var windows = EditorCopilotPlan.sampleSpeechWindows(
            bins: bins, duration: duration, budget: budget
        )
        if windows.isEmpty {
            let count = max(4, Int((budget / 30).rounded(.up)))
            let step = duration / Double(count)
            windows = (0..<count).map { index in
                let start = Double(index) * step
                return .init(start: start, end: min(duration, start + 30))
            }
        }
        windows = Array(windows.prefix(12))
        onProgress("Transcribing \(windows.count) spoken sections…")
        var chunks: [AudioChunk] = []
        for (index, window) in windows.enumerated() {
            try Task.checkCancellation()
            onProgress("Preparing sampled section \(index + 1) of \(windows.count)…")
            let url = directory.appendingPathComponent("sample-\(index).caf")
            do {
                let extracted = Task.detached(priority: .userInitiated) {
                    try extractPCMChunk(
                        from: composition, start: window.start, end: window.end, url: url
                    )
                }
                let chunk = try await withTaskCancellationHandler {
                    try await extracted.value
                } onCancel: { extracted.cancel() }
                if chunk.isAudible { chunks.append(chunk) }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                continue
            }
        }
        return chunks
    }

    private static func extractRangeChunks(
        composition: AVMutableComposition,
        range: ClosedRange<TimeInterval>,
        duration: TimeInterval,
        directory: URL
    ) async throws -> [AudioChunk] {
        let start = min(max(0, range.lowerBound), duration)
        let end = min(max(start + 0.3, range.upperBound), duration)
        let url = directory.appendingPathComponent("range.caf")
        let extracted = Task.detached(priority: .userInitiated) {
            try extractPCMChunk(from: composition, start: start, end: end, url: url)
        }
        let chunk = try await withTaskCancellationHandler {
            try await extracted.value
        } onCancel: { extracted.cancel() }
        if chunk.duration <= 32 {
            return [chunk]
        }
        let audioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Mixtape-Caption-Range-\(UUID().uuidString).caf")
        defer { try? FileManager.default.removeItem(at: audioURL) }
        try FileManager.default.copyItem(at: chunk.url, to: audioURL)
        return try prepareChunks(audioURL: audioURL, directory: directory).map { section in
            AudioChunk(
                url: section.url,
                start: start + section.start,
                duration: section.duration,
                ownedStart: start + section.ownedStart,
                ownedEnd: start + section.ownedEnd,
                isAudible: section.isAudible
            )
        }
    }

    nonisolated private static func energyBins(
        from composition: AVMutableComposition,
        duration: TimeInterval
    ) throws -> [(time: Double, rms: Double)] {
        let hop = 0.5
        guard let track = composition.tracks(withMediaType: .audio).first else {
            throw EditorCaptionError.noAudioTrack
        }
        let reader = try AVAssetReader(asset: composition)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVSampleRateKey: 8_000,
            AVNumberOfChannelsKey: 1
        ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw EditorCaptionError.audioRenderFailed }
        reader.add(output)
        guard reader.startReading() else { throw EditorCaptionError.audioRenderFailed }
        var bins: [(time: Double, rms: Double)] = []
        var samples: [Float] = []
        samples.reserveCapacity(4_000)
        var time = 0.0
        while let buffer = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            defer { CMSampleBufferInvalidate(buffer) }
            guard let data = CMSampleBufferGetDataBuffer(buffer) else { continue }
            let length = CMBlockBufferGetDataLength(data)
            var bytes = [Int16](repeating: 0, count: length / MemoryLayout<Int16>.size)
            CMBlockBufferCopyDataBytes(data, atOffset: 0, dataLength: length, destination: &bytes)
            for sample in bytes {
                samples.append(Float(sample) / Float(Int16.max))
                if samples.count >= 4_000 {
                    bins.append((time, rms(samples)))
                    time += hop
                    samples.removeAll(keepingCapacity: true)
                }
            }
        }
        if !samples.isEmpty {
            bins.append((time, rms(samples)))
        }
        if bins.isEmpty, duration > 0 {
            throw EditorCaptionError.audioRenderFailed
        }
        return bins
    }

    nonisolated private static func extractPCMChunk(
        from composition: AVMutableComposition,
        start: TimeInterval,
        end: TimeInterval,
        url: URL
    ) throws -> AudioChunk {
        guard let track = composition.tracks(withMediaType: .audio).first else {
            throw EditorCaptionError.noAudioTrack
        }
        let reader = try AVAssetReader(asset: composition)
        reader.timeRange = CMTimeRange(
            start: CMTime(seconds: max(0, start), preferredTimescale: 600),
            duration: CMTime(seconds: max(0.2, end - start), preferredTimescale: 600)
        )
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1
        ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw EditorCaptionError.audioRenderFailed }
        reader.add(output)
        guard reader.startReading() else { throw EditorCaptionError.audioRenderFailed }

        var samples: [Float] = []
        samples.reserveCapacity(Int(max(0.2, end - start) * 16_000))
        var audible = false
        while let buffer = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            defer { CMSampleBufferInvalidate(buffer) }
            guard let data = CMSampleBufferGetDataBuffer(buffer) else { continue }
            let length = CMBlockBufferGetDataLength(data)
            let frames = length / MemoryLayout<Float>.size
            guard frames > 0 else { continue }
            var packet = [Float](repeating: 0, count: frames)
            CMBlockBufferCopyDataBytes(data, atOffset: 0, dataLength: length, destination: &packet)
            if !audible, packet.contains(where: { abs($0) > 0.003 }) { audible = true }
            samples.append(contentsOf: packet)
        }
        guard !samples.isEmpty else {
            return AudioChunk(
                url: url, start: start, duration: max(0.2, end - start),
                ownedStart: start, ownedEnd: end, isAudible: false
            )
        }

        guard let sourceFormat = AVAudioFormat(
            standardFormatWithSampleRate: 16_000, channels: 1
        ) else {
            throw EditorCaptionError.audioRenderFailed
        }
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        let file = try AVAudioFile(forWriting: url, settings: sourceFormat.settings)
        let processing = file.processingFormat
        var offset = 0
        let packetFrames = 16_384
        while offset < samples.count {
            try Task.checkCancellation()
            let count = min(packetFrames, samples.count - offset)
            guard let pcm = AVAudioPCMBuffer(
                pcmFormat: processing,
                frameCapacity: AVAudioFrameCount(count)
            ) else {
                throw EditorCaptionError.audioRenderFailed
            }
            pcm.frameLength = AVAudioFrameCount(count)
            if let channels = pcm.floatChannelData {
                for channel in 0..<Int(processing.channelCount) {
                    for frame in 0..<count {
                        channels[channel][frame] = samples[offset + frame]
                    }
                }
            }
            try file.write(from: pcm)
            offset += count
        }
        return AudioChunk(
            url: url, start: start, duration: max(0.2, end - start),
            ownedStart: start, ownedEnd: end, isAudible: audible
        )
    }

    nonisolated private static func rms(_ samples: [Float]) -> Double {
        guard !samples.isEmpty else { return 0 }
        var sum: Float = 0
        for sample in samples { sum += sample * sample }
        return Double((sum / Float(samples.count)).squareRoot())
    }

    nonisolated private static func isBenignNoSpeech(_ error: Error) -> Bool {
        if error is CancellationError { return false }
        let ns = error as NSError
        let text = ns.localizedDescription.lowercased()
        if text.contains("no speech") || text.contains("no match") { return true }
        // Apple Speech uses 1110 / 216 for empty audio in several OS versions.
        if ns.domain == "kAFAssistantErrorDomain" && [1110, 216, 203].contains(ns.code) {
            return true
        }
        return false
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

    private static func recognize(
        request: SFSpeechRecognitionRequest,
        with recognizer: SFSpeechRecognizer
    ) async throws -> SFTranscription {
        let box = SpeechTaskBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                box.install(continuation)
                let task = recognizer.recognitionTask(with: request) { result, error in
                    if let result, result.isFinal {
                        box.finish(.success(result.bestTranscription))
                    } else if let error {
                        box.finish(.failure(error))
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
    private var continuation: CheckedContinuation<SFTranscription, Error>?
    private var terminalResult: Result<SFTranscription, Error>?
    private var timeout: DispatchWorkItem?

    func install(_ continuation: CheckedContinuation<SFTranscription, Error>) {
        lock.lock()
        if let result = terminalResult {
            lock.unlock()
            continuation.resume(with: result)
            return
        }
        self.continuation = continuation
        let timeout = DispatchWorkItem { [weak self] in
            self?.finish(.failure(EditorCaptionError.recognitionFailed("Speech recognition timed out.")))
        }
        self.timeout = timeout
        lock.unlock()
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 60, execute: timeout)
    }

    func store(_ task: SFSpeechRecognitionTask) {
        lock.lock()
        let shouldCancel = terminalResult != nil
        if !shouldCancel { self.task = task }
        lock.unlock()
        if shouldCancel { task.cancel() }
    }

    func cancel() {
        finish(.failure(CancellationError()))
    }

    func finish(_ result: Result<SFTranscription, Error>) {
        lock.lock()
        guard terminalResult == nil else { lock.unlock(); return }
        terminalResult = result
        let task = task
        let continuation = continuation
        let timeout = timeout
        self.task = nil
        self.continuation = nil
        self.timeout = nil
        lock.unlock()
        timeout?.cancel()
        task?.cancel()
        continuation?.resume(with: result)
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
