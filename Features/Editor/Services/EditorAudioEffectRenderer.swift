//
//  EditorAudioEffectRenderer.swift
//  Mixtape
//
//  Renders an `EditorAudioEffect` onto a source audio file exactly once via `AVAudioEngine`'s
//  offline manual rendering mode, caching the result on disk keyed by (source path, effect) —
//  same shape as `AudioWaveformGenerator`'s cache. `EditorViewModel.setAudioClipEffect` awaits
//  this and only assigns `EditorAudioClip.effect` once the render has actually succeeded, so
//  `EditorCompositionBuilder` and `EditorAudioClip.playbackFileURL` never need to know rendering
//  is async — by the time a clip's `effect` is non-`.none`, its processed file already exists on
//  disk (or the effect selection failed and was rolled back).
//
//  Output is capped at the source's own frame count, not the effect's natural tail (echo/reverb
//  decay past the clip's end gets truncated) — a deliberate simplification so the processed
//  file's duration always exactly matches the source's, and none of the trim/timeline math
//  anywhere else has to special-case effect-bearing clips.
//

import AVFoundation

actor EditorAudioEffectRenderer {
    static let shared = EditorAudioEffectRenderer()

    private static let cacheDirectory: URL = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("MixtapeAudioEffects", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// Synchronous, non-actor-isolated cache lookup — safe because it only reads the filesystem,
    /// no shared mutable state — so `EditorAudioClip.playbackFileURL` and
    /// `EditorCompositionBuilder` can call it without an `await`.
    nonisolated static func cachedFileURL(sourceURL: URL, effect: EditorAudioEffect) -> URL? {
        guard effect != .none else { return nil }
        let url = destinationURL(sourceURL: sourceURL, effect: effect)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Renders (or returns the existing cached render of) `sourceURL` through `effect`. Returns
    /// `nil` if rendering fails — callers fall back to the dry source rather than surfacing a
    /// hard error, matching `AudioWaveformGenerator`'s "never break the render" convention.
    func render(sourceURL: URL, effect: EditorAudioEffect) async -> URL? {
        guard effect != .none else { return nil }
        let destination = Self.destinationURL(sourceURL: sourceURL, effect: effect)
        if FileManager.default.fileExists(atPath: destination.path) { return destination }

        do {
            try await Self.renderOffline(sourceURL: sourceURL, effect: effect, to: destination)
            return destination
        } catch {
            try? FileManager.default.removeItem(at: destination)
            return nil
        }
    }

    private static func destinationURL(sourceURL: URL, effect: EditorAudioEffect) -> URL {
        cacheDirectory
            .appendingPathComponent("\(stableHash(sourceURL.path))-\(effect.rawValue)")
            .appendingPathExtension("m4a")
    }

    private static func renderOffline(
        sourceURL: URL,
        effect: EditorAudioEffect,
        to destinationURL: URL
    ) async throws {
        let sourceFile = try AVAudioFile(forReading: sourceURL)
        let format = sourceFile.processingFormat
        let totalFrames = AVAudioFrameCount(sourceFile.length)
        guard totalFrames > 0 else { throw RenderError.emptySource }

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)

        var chain: [AVAudioNode] = [player]
        for node in effect.makeChain() {
            engine.attach(node)
            chain.append(node)
        }
        for i in 0..<(chain.count - 1) {
            engine.connect(chain[i], to: chain[i + 1], format: format)
        }
        engine.connect(chain.last!, to: engine.mainMixerNode, format: format)

        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4_096)
        try engine.start()
        // Explicit `completionHandler: nil` pins this to the classic fire-and-forget overload,
        // not the newer `async` one — the async variant suspends until playback is "consumed,"
        // which in manual rendering mode only happens as `renderOffline` is pumped below, so
        // awaiting it here would deadlock before the render loop ever runs.
        player.scheduleFile(sourceFile, at: nil, completionHandler: nil)
        player.play()

        guard let renderBuffer = AVAudioPCMBuffer(
            pcmFormat: engine.manualRenderingFormat,
            frameCapacity: engine.manualRenderingMaximumFrameCount
        ) else { throw RenderError.bufferAllocationFailed }

        let outputFile = try AVAudioFile(
            forWriting: destinationURL,
            settings: format.settings,
            commonFormat: format.commonFormat,
            interleaved: format.isInterleaved
        )

        var renderedFrames: AVAudioFrameCount = 0
        while renderedFrames < totalFrames {
            if effect.isModulated {
                effect.modulate(chain: chain, elapsedSeconds: Double(renderedFrames) / format.sampleRate)
            }
            let framesToRender = min(engine.manualRenderingMaximumFrameCount, totalFrames - renderedFrames)
            let status = try engine.renderOffline(framesToRender, to: renderBuffer)
            switch status {
            case .success:
                try outputFile.write(from: renderBuffer)
                renderedFrames += renderBuffer.frameLength
            case .insufficientDataFromInputNode, .cannotDoInCurrentContext:
                continue
            case .error:
                throw RenderError.engineRenderFailed
            @unknown default:
                throw RenderError.engineRenderFailed
            }
        }
        engine.stop()
    }

    private enum RenderError: Error {
        case emptySource
        case bufferAllocationFailed
        case engineRenderFailed
    }

    /// FNV-1a — deterministic across launches (unlike `String.hashValue`), same approach as
    /// `AudioWaveformGenerator.stableHash`.
    private static func stableHash(_ string: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}
