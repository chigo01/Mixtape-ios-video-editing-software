//
//  EditorViewModel.swift
//  Mixtape
//
//  Created by Favour Baruch on 14/05/2026.
//

import SwiftUI
import AVFoundation
import Photos

@MainActor
@Observable
final class EditorViewModel {

    // MARK: Timeline state

    private(set) var clips: [EditorClip]
    var selectedClipID: UUID?
    var textOverlays: [EditorTextOverlay]
    var audioTrack: EditorAudioTrack?

    /// Global playhead: 0 … totalDuration across every clip in order.
    var timelinePosition: TimeInterval = 0

    var isPlaying: Bool = false
    var selectedTool: EditorTool?

    // MARK: Player

    private(set) var player: AVPlayer?

    @ObservationIgnored
    private let phManager = PHCachingImageManager()
    @ObservationIgnored
    private var endObserver: NSObjectProtocol?
    @ObservationIgnored
    private var tickTimer: Timer?
    @ObservationIgnored
    private var videoClipIDAtLoad: UUID?

    // MARK: Init

    init(media: [MediaItem]) {
        let clips = media.map { EditorClip(asset: $0.asset) }
        self.clips = clips
        self.selectedClipID = clips.first?.id
        self.textOverlays = []
        self.audioTrack = nil
    }

    // MARK: Derived

    var totalDuration: TimeInterval {
        clips.reduce(0) { $0 + $1.duration }
    }

    var selectedClip: EditorClip? {
        guard let id = selectedClipID else { return nil }
        return clips.first { $0.id == id }
    }

    /// Clip currently under the global playhead (what the preview should show).
    var playbackInfo: (clip: EditorClip, index: Int, localTime: TimeInterval)? {
        clipAndLocalTime(at: timelinePosition)
    }

    var playbackClipID: UUID? { playbackInfo?.clip.id }

    /// `MM:SS:CC` (hundredths) — HUD uses global timeline.
    var currentTimeString: String {
        formatPlaybackTime(timelinePosition)
    }

    func formatPlaybackTime(_ t: TimeInterval) -> String {
        let safe = max(0, t)
        let total = Int((safe * 100).rounded(.down))
        let minutes = total / 6000
        let seconds = (total / 100) % 60
        let hundredths = total % 100
        return String(format: "%02d:%02d:%02d", minutes, seconds, hundredths)
    }

    func timelineOffsetForClipIndex(_ index: Int) -> TimeInterval {
        guard index > 0 else { return 0 }
        return clips.prefix(index).reduce(0) { $0 + $1.duration }
    }

    func clipAndLocalTime(at timelineT: TimeInterval) -> (clip: EditorClip, index: Int, localTime: TimeInterval)? {
        guard !clips.isEmpty else { return nil }
        let clamped = min(max(0, timelineT), totalDuration)
        var acc: TimeInterval = 0
        for (i, clip) in clips.enumerated() {
            let d = clip.duration
            if d <= 0 { continue }
            if clamped < acc + d - 1e-9 || i == clips.count - 1 {
                let local = min(max(0, clamped - acc), d)
                return (clip, i, local)
            }
            acc += d
        }
        guard let last = clips.last else { return nil }
        return (last, clips.count - 1, last.duration)
    }

// MARK: Selection

    /// Clip targeted by editing tools. Does **not** move the playhead—timeline seeks are one continuous sequence.
    func selectClipForEditing(_ id: UUID) {
        selectedClipID = id
    }

    /// Jump playhead to the start of a clip (e.g. future “go to clip” affordance).
    func jumpToClipStart(_ id: UUID) {
        guard let idx = clips.firstIndex(where: { $0.id == id }) else { return }
        timelinePosition = timelineOffsetForClipIndex(idx)
        Task {
            await alignPlaybackToTimeline()
            if isPlaying { resumePlaybackAfterAlign() }
        }
    }

    func selectTool(_ tool: EditorTool) {
        selectedTool = (selectedTool == tool) ? nil : tool
    }

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
            Task {
                await alignPlaybackToTimeline()
                resumePlaybackAfterAlign()
                startPlaybackTicking()
            }
        }
    }

    func seekTimeline(to time: TimeInterval) {
        setTimelinePositionForScrub(time)
        commitTimelineAfterScrub()
    }

    /// Lightweight scrubbing: updates global playhead only; pauses playback. Does not retarget the editing selection.
    func setTimelinePositionForScrub(_ time: TimeInterval) {
        if isPlaying {
            stopPlaybackTicking()
            player?.pause()
            isPlaying = false
        }
        timelinePosition = min(max(0, time), totalDuration)
    }

    func commitTimelineAfterScrub() {
        Task { await alignPlaybackToTimeline() }
    }

    // MARK: Lifecycle

    func setupPlayer() async {
        await alignPlaybackToTimeline()
    }

    func teardownPlayer() {
        stopPlaybackTicking()
        removeEndObserver()
        player?.pause()
        player = nil
        videoClipIDAtLoad = nil
        isPlaying = false
    }

    // MARK: - Tick (photos advance from clock; videos follow AVPlayer)

    private func startPlaybackTicking() {
        stopPlaybackTicking()
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.playbackTick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
    }

    private func stopPlaybackTicking() {
        tickTimer?.invalidate()
        tickTimer = nil
    }

    private func playbackTick() {
        guard isPlaying, totalDuration > 0 else { return }

        guard let info = clipAndLocalTime(at: timelinePosition) else { return }

        if info.clip.isVideo, player == nil || videoClipIDAtLoad != info.clip.id {
            Task {
                await alignPlaybackToTimeline()
                resumePlaybackAfterAlign()
            }
            return
        }

        if info.clip.isVideo, let player {
            let base = timelineOffsetForClipIndex(info.index)
            let src = player.currentTime().seconds
            let spd = TimeInterval(max(info.clip.speed, 0.001))
            let local = min(
                max(0, (src - info.clip.trimStart) / spd),
                info.clip.duration
            )
            timelinePosition = min(base + local, totalDuration)
        } else {
            timelinePosition += 1.0 / 30.0
            timelinePosition = min(timelinePosition, totalDuration)
            let after = clipAndLocalTime(at: timelinePosition)
            if after?.clip.id != info.clip.id {
                Task { await alignPlaybackToTimeline() }
            }
        }

        if timelinePosition >= totalDuration - 0.02 {
            timelinePosition = totalDuration
            player?.pause()
            stopPlaybackTicking()
            isPlaying = false
        }
    }

    private func resumePlaybackAfterAlign() {
        guard isPlaying, let info = playbackInfo else { return }
        if info.clip.isVideo { player?.play() }
    }

    // MARK: - Align preview + player to timelinePosition

    private func alignPlaybackToTimeline() async {
        guard let info = clipAndLocalTime(at: timelinePosition) else { return }

        if info.clip.isVideo {
            if videoClipIDAtLoad != info.clip.id || player == nil {
                await loadVideoPlayer(for: info.clip)
                videoClipIDAtLoad = info.clip.id
            }
            let src = info.clip.sourceTime(forExportedLocal: info.localTime)
            await player?.seek(
                to: CMTime(seconds: src, preferredTimescale: 600),
                toleranceBefore: .zero,
                toleranceAfter: .zero
            )
        } else {
            removeEndObserver()
            player?.pause()
            player = nil
            videoClipIDAtLoad = nil
        }
    }

    private func loadVideoPlayer(for clip: EditorClip) async {
        removeEndObserver()
        player?.pause()
        player = nil

        let options = PHVideoRequestOptions()
        options.deliveryMode = .automatic
        options.isNetworkAccessAllowed = true

        let item: AVPlayerItem? = await withCheckedContinuation { cont in
            phManager.requestPlayerItem(forVideo: clip.asset, options: options) { result, _ in
                cont.resume(returning: result)
            }
        }

        guard let item else { return }

        let newPlayer = AVPlayer(playerItem: item)
        newPlayer.actionAtItemEnd = .pause
        newPlayer.automaticallyWaitsToMinimizeStalling = true
        player = newPlayer

        attachEndObserver(for: item)
    }

    private func attachEndObserver(for item: AVPlayerItem) {
        removeEndObserver()
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleVideoItemEnded() }
        }
    }

    private func removeEndObserver() {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
    }

    private func handleVideoItemEnded() {
        guard isPlaying else { return }
        guard let id = videoClipIDAtLoad,
              let idx = clips.firstIndex(where: { $0.id == id }) else { return }

        let clip = clips[idx]
        let end = timelineOffsetForClipIndex(idx) + clip.duration
        timelinePosition = min(end, totalDuration)

        if timelinePosition >= totalDuration - 0.03 {
            timelinePosition = totalDuration
            stopPlaybackTicking()
            player?.pause()
            isPlaying = false
            return
        }

        Task {
            await alignPlaybackToTimeline()
            resumePlaybackAfterAlign()
        }
    }
}
