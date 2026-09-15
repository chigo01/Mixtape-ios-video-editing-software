//
//  EditorViewModel+Playback.swift
//  Mixtape
//

import SwiftUI
import UIKit
import AVFoundation
import Photos

extension EditorViewModel {
    // MARK: Playback

    func togglePlay() {
        guard totalDuration > 0 else { return }
        if isPlaying {
            stopPlaybackTicking()
            player?.pause()
            isPlaying = false
        } else {
            if timelinePosition >= totalDuration - 0.05 {
                timelinePosition = 0
            }
            isPlaying = true
            Task { await ensureCompositionPlayer() }
        }
    }

    func seekTimeline(to time: TimeInterval) {
        setTimelinePositionForScrub(time)
        commitTimelineAfterScrub()
    }

    func setTimelinePositionForScrub(_ time: TimeInterval) {
        if isPlaying {
            stopPlaybackTicking()
            player?.pause()
            isPlaying = false
        }
        timelinePosition = snappedTime(time)
    }

    func commitTimelineAfterScrub() {
        clearSnapGuide()
        Task { await alignPlaybackToTimeline() }
        scheduleSave()
    }

    private func clipsFingerprint() -> String {
        let clipsHash = clips.map { clip in
            "\(clip.id.uuidString)|\(clip.trimStart)|\(clip.trimEnd)|\(clip.speed)|\(String(describing: clip.speedRamp))|\(clip.playback)|\(clip.volume)|\(clip.audioTrimStart ?? -1)|\(clip.audioTrimEnd ?? -1)|\(clip.isAudioLinked)|\(clip.cropAspect.rawValue)|\(clip.reframeMode.rawValue)|\(clip.rotationQuarterTurns)|\(clip.straightenDegrees)|\(clip.isFlippedHorizontally)|\(clip.isFlippedVertically)|\(clip.reframeScale)|\(clip.reframeXOffset)|\(clip.reframeYOffset)|\(clip.colorAdjustment)|\(clip.effects)|\(clip.compositing)|\(clip.keyframes)|\(clip.motionTracks)|\(clip.stabilization)|\(clip.transitionKind.rawValue)|\(clip.transitionDuration)|\(clip.duration)|\(clip.asset.localIdentifier)"
        }.joined(separator: ";")
        let audioHash = audioClips.map {
            "\($0.id.uuidString)|\($0.trimStart)|\($0.trimEnd)|\($0.timelineStart)|\($0.volume)|\($0.fadeInDuration)|\($0.fadeOutDuration)|\($0.keyframes)|\($0.fileURL.path)|\($0.effect.rawValue)"
        }.joined(separator: ";")
        let overlayHash = overlayClips.map {
            "\($0.id.uuidString)|\($0.trimStart)|\($0.trimEnd)|\($0.timelineStart)|\($0.laneIndex)|\($0.zIndex)|\($0.speed)|\($0.playback)|\($0.scale)|\($0.xOffset)|\($0.yOffset)|\($0.opacity)|\($0.volume)|\($0.cropAspect.rawValue)|\($0.reframeMode.rawValue)|\($0.rotationQuarterTurns)|\($0.straightenDegrees)|\($0.isFlippedHorizontally)|\($0.isFlippedVertically)|\($0.reframeScale)|\($0.reframeXOffset)|\($0.reframeYOffset)|\($0.colorAdjustment)|\($0.effects)|\($0.compositing)|\($0.keyframes)|\($0.motionTracks)|\($0.stabilization)|\($0.attachedClipID?.uuidString ?? "")|\($0.attachedTrackID?.uuidString ?? "")|\($0.asset.localIdentifier)"
        }.joined(separator: ";")
        let openingHash = "\(openingTransitionKind.rawValue)|\(openingTransitionDuration)"
        let closingHash = "\(closingTransitionKind.rawValue)|\(closingTransitionDuration)"
        let mixHash = audioTrackSettings.keys.sorted()
            .map { "\($0):\(audioTrackSettings[$0]!.gain)|\(audioTrackSettings[$0]!.isMuted)|\(audioTrackSettings[$0]!.isSoloed)" }
            .joined(separator: ";") + "|||\(masterVolume)"
        let adjustmentHash = String(describing: adjustmentLayers)
        return clipsHash + "|||" + audioHash + "|||" + overlayHash + "|||" + adjustmentHash + "|||" + openingHash + "|||" + closingHash + "|||\(canvasSettings)" + "|||" + mixHash
    }

    /// Extends the edit identity with source revisions and cache format. This keeps
    /// an exact edit from reusing a render made from an older Photos revision or a
    /// different proxy profile after the user switches performance quality.
    func renderCacheFingerprint() -> String {
        let assets = (clips.map(\.asset) + overlayClips.map(\.asset))
            .map { asset in
                let modified = asset.modificationDate?.timeIntervalSince1970 ?? 0
                return "\(asset.localIdentifier)|\(modified)|\(asset.pixelWidth)x\(asset.pixelHeight)|\(asset.duration)"
            }
            .sorted()
            .joined(separator: ";")
        return clipsFingerprint()
            + "|||preview-render-v1|\(proxySettings.quality.rawValue)|||"
            + assets
    }

    func invalidateComposition() {
        compositionFingerprint = nil
        scheduleBackgroundRenderCache()
    }

    func pausePlaybackForEdit() {
        if isPlaying {
            stopPlaybackTicking()
            player?.pause()
            isPlaying = false
        }
    }

    @discardableResult
    func ensureCompositionPlayer() async -> Bool {
        guard !isCopilotPreviewDiscarded, !Task.isCancelled else { return false }
        let requestID = UUID()
        previewRequestID = requestID
        let fingerprint = clipsFingerprint()
        let buildKey = previewBuildKey()
        let needsRebuild = fingerprint != compositionFingerprint || player?.currentItem == nil

        if !needsRebuild {
            await seekPlayerToTimeline(exact: !isPlaying)
            guard previewRequestID == requestID, !Task.isCancelled,
                  !isCopilotPreviewDiscarded else { return false }
            if isPlaying {
                player?.play()
                startPlaybackTicking()
            }
            return true
        }

        let clipsSnapshot = clips
        let graphicOverlaysSnapshot = graphicOverlays
        let audioClipsSnapshot = audioClips
        let overlayClipsSnapshot = overlayClips
        let adjustmentLayersSnapshot = adjustmentLayers
        let openingKindSnapshot = openingTransitionKind
        let openingDurationSnapshot = openingTransitionDuration
        let closingKindSnapshot = closingTransitionKind
        let closingDurationSnapshot = closingTransitionDuration
        let canvasSnapshot = canvasSettings
        let audioTrackSettingsSnapshot = audioTrackSettings
        let masterVolumeSnapshot = masterVolume
        let proxySettingsSnapshot = proxySettings
        let renderCacheFingerprintSnapshot = renderCacheFingerprint()

        let item = await previewBuilds.value(for: buildKey) {
            if !proxySettingsSnapshot.isEnabled,
               !proxySettingsSnapshot.backgroundRenderCache,
               graphicOverlaysSnapshot.isEmpty,
               audioClipsSnapshot.isEmpty,
               overlayClipsSnapshot.isEmpty,
               adjustmentLayersSnapshot.isEmpty,
               openingKindSnapshot == .none,
               closingKindSnapshot == .none,
               canvasSnapshot == .default,
               abs(masterVolumeSnapshot - 1.0) < 0.001,
               let warmed = EditorCompositionBuilder.consumeWarmedPlayerItem(matching: clipsSnapshot) {
                return warmed
            }
            return await EditorCompositionBuilder.makePlayerItem(
                from: clipsSnapshot,
                graphicOverlays: graphicOverlaysSnapshot,
                audioClips: audioClipsSnapshot,
                overlayClips: overlayClipsSnapshot,
                adjustmentLayers: adjustmentLayersSnapshot,
                openingTransitionKind: openingKindSnapshot,
                openingTransitionDuration: openingDurationSnapshot,
                closingTransitionKind: closingKindSnapshot,
                closingTransitionDuration: closingDurationSnapshot,
                canvasSettings: canvasSnapshot,
                audioTrackSettings: audioTrackSettingsSnapshot,
                masterVolume: masterVolumeSnapshot,
                proxySettings: proxySettingsSnapshot,
                renderCacheFingerprint: renderCacheFingerprintSnapshot
            )
        }

        guard let item, !isCopilotPreviewDiscarded, !Task.isCancelled,
              previewRequestID == requestID, buildKey == previewBuildKey() else { return false }

        if player == nil {
            AudioSessionConfigurator.configureForVideoPlayback()
            let newPlayer = AVPlayer(playerItem: item)
            newPlayer.actionAtItemEnd = .pause
            newPlayer.automaticallyWaitsToMinimizeStalling = true
            player = newPlayer
        } else {
            player?.replaceCurrentItem(with: item)
        }

        attachCompositionEndObserver(for: item)
        compositionFingerprint = fingerprint
        // The user may have scrubbed while the composition was being prepared.
        timelinePosition = min(timelinePosition, totalDuration)
        await seekPlayerToTimeline(exact: true)

        guard !isCopilotPreviewDiscarded, !Task.isCancelled,
              previewRequestID == requestID else { return false }
        if isPlaying {
            player?.play()
            startPlaybackTicking()
        }
        return true
    }

    private func previewBuildKey() -> String {
        renderCacheFingerprint() + "|||\(proxySettings)"
    }

    private func seekPlayerToTimeline(exact: Bool) async {
        let target = CMTime(seconds: timelinePosition, preferredTimescale: 600)
        if exact {
            await player?.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
        } else {
            await player?.seek(
                to: target,
                toleranceBefore: CMTime(seconds: 0.03, preferredTimescale: 600),
                toleranceAfter: CMTime(seconds: 0.03, preferredTimescale: 600)
            )
        }
    }

    private func startPlaybackTicking() {
        stopPlaybackTicking()
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.playbackTick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
    }

    func stopPlaybackTicking() {
        tickTimer?.invalidate()
        tickTimer = nil
    }

    private func playbackTick() {
        guard isPlaying, totalDuration > 0, let player else { return }

        let current = player.currentTime().seconds
        if current.isFinite, current >= 0 {
            timelinePosition = min(current, totalDuration)
        }

        if timelinePosition >= totalDuration - 0.02 {
            timelinePosition = totalDuration
            player.pause()
            stopPlaybackTicking()
            isPlaying = false
        }
    }

    func resumePlaybackAfterAlign() {
        guard isPlaying else { return }
        player?.play()
    }

    func alignPlaybackToTimeline() async {
        guard !clips.isEmpty else { return }
        await ensureCompositionPlayer()
    }

    private func attachCompositionEndObserver(for item: AVPlayerItem) {
        removeEndObserver()
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handlePlaybackEnded() }
        }
    }

    func removeEndObserver() {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
    }

    private func handlePlaybackEnded() {
        timelinePosition = totalDuration
        player?.pause()
        stopPlaybackTicking()
        isPlaying = false
    }
}
