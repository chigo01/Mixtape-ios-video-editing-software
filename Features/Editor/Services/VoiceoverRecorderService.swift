//
//  VoiceoverRecorderService.swift
//  Mixtape
//
//  Priority 14 (core recording MVP): records a voiceover take at the current playhead into a
//  standalone .m4a file. Deliberately scoped down from the full README checklist — count-in,
//  teleprompter, punch-in/out, manual input selection, live monitoring passthrough, and
//  cross-take comping are not built here. What is built: tap-to-record, a live input-level
//  meter, multiple takes with retry/delete, and explicit recovery UI for permission denial,
//  session interruptions (calls/Siri), and route changes (headphones/Bluetooth unplugged
//  mid-take) — a take-in-progress is preserved rather than silently lost.
//
//  A finished take is just a file on disk until the caller (`VoiceoverRecorderView`) hands its
//  URL to `EditorViewModel.insertRecordedVoiceover`, which wraps it as a normal `EditorAudioClip`
//  — from that point it is indistinguishable from an imported or library clip: trim, move,
//  split, volume, waveform (via the Priority 13 `AudioWaveformGenerator`), undo, and persistence
//  all just work.
//

import AVFoundation
import Observation
import UIKit

@MainActor
@Observable
final class VoiceoverRecorderService: NSObject {

    enum PermissionState {
        case undetermined
        case granted
        case denied
    }

    struct Take: Identifiable, Equatable {
        let id: UUID
        let fileURL: URL
        var duration: TimeInterval
        let recordedAt: Date
        var displayName: String
    }

    private(set) var permissionState: PermissionState = .undetermined
    private(set) var isRecording = false
    /// Normalized 0...1 input level, refreshed ~15x/sec while recording, for the level meter.
    private(set) var inputLevel: Float = 0
    private(set) var elapsedTime: TimeInterval = 0
    private(set) var takes: [Take] = []
    private(set) var currentInputName: String?
    /// Non-fatal recovery banner: interruption or route change that stopped an in-progress take.
    var recoveryMessage: String?
    var errorMessage: String?

    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var meterTimer: Timer?
    @ObservationIgnored private var recordingStartDate: Date?
    @ObservationIgnored private var sessionIsActive = false
    @ObservationIgnored private var takeCounter = 0

    private let recordingsDirectory: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("MixtapeAudio", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    // MARK: Session lifecycle

    func requestPermissionIfNeeded() {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            permissionState = .granted
        case .denied:
            permissionState = .denied
        case .undetermined:
            AVAudioApplication.requestRecordPermission { [weak self] granted in
                Task { @MainActor in
                    self?.permissionState = granted ? .granted : .denied
                }
            }
        @unknown default:
            permissionState = .denied
        }
    }

    /// Switches the shared audio session into recording mode and starts watching for
    /// interruptions/route changes. Call when the recorder sheet appears.
    func beginSession() {
        guard !sessionIsActive else { return }
        do {
            try AudioSessionConfigurator.configureForRecording()
            sessionIsActive = true
        } catch {
            errorMessage = "Couldn't access the microphone: \(error.localizedDescription)"
            return
        }
        refreshCurrentInputName()

        NotificationCenter.default.addObserver(
            self, selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleRouteChange(_:)),
            name: AVAudioSession.routeChangeNotification, object: nil
        )
    }

    /// Restores playback-only audio routing and stops watching session notifications. Call when
    /// the recorder sheet is dismissed. Any unrecorded/unused take files are removed so a
    /// cancelled session doesn't leak audio files into `MixtapeAudio/`.
    func endSession(keeping keptTakeURL: URL?) {
        // Dismissing mid-recording abandons that in-progress take rather than validating and
        // keeping it — it was never offered to the user as a take to choose from.
        if let abandonedURL = finalizeRecordingFile() {
            try? FileManager.default.removeItem(at: abandonedURL)
        }
        NotificationCenter.default.removeObserver(self, name: AVAudioSession.interruptionNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: AVAudioSession.routeChangeNotification, object: nil)
        for take in takes where take.fileURL != keptTakeURL {
            try? FileManager.default.removeItem(at: take.fileURL)
        }
        takes.removeAll()
        sessionIsActive = false
        AudioSessionConfigurator.configureForVideoPlayback()
    }

    // MARK: Recording

    func startRecording() {
        guard permissionState == .granted, !isRecording else { return }
        errorMessage = nil
        recoveryMessage = nil

        let url = recordingsDirectory.appendingPathComponent("voiceover-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]

        do {
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.delegate = self
            recorder.isMeteringEnabled = true
            guard recorder.record() else {
                errorMessage = "Recording couldn't start. Try again."
                return
            }
            self.recorder = recorder
            recordingStartDate = Date()
            elapsedTime = 0
            isRecording = true
            startMeterTimer()
        } catch {
            errorMessage = "Recording couldn't start: \(error.localizedDescription)"
        }
    }

    /// Stops the `AVAudioRecorder` and returns the file it was writing to, or `nil` if nothing
    /// was recording. Split out from `stopRecording()` so a caller that's tearing down (session
    /// end, dismiss-while-recording) can finalize the recorder without waiting on file
    /// validation.
    @discardableResult
    private func finalizeRecordingFile() -> URL? {
        guard isRecording, let recorder else { return nil }
        let url = recorder.url
        recorder.stop()
        self.recorder = nil
        isRecording = false
        stopMeterTimer()
        inputLevel = 0
        return url
    }

    /// Stops the active recording and, once the file is finalized, validates it and appends a
    /// take. Duration is read back from the encoded file with `AVURLAsset` rather than trusted
    /// from `AVAudioRecorder.currentTime` — `currentTime` can misreport by the time this runs
    /// when a route change (e.g. a Bluetooth input disconnecting) forces the recorder to
    /// finalize mid-write, which previously caused a real take to be silently discarded (or an
    /// empty one to be kept) while the caller still reported "your take was saved".
    @discardableResult
    func stopRecording() async -> Take? {
        guard let url = finalizeRecordingFile() else { return nil }
        let duration = (try? await AVURLAsset(url: url).load(.duration))?.seconds ?? 0

        guard duration.isFinite, duration >= 0.2 else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }

        takeCounter += 1
        let take = Take(
            id: UUID(), fileURL: url, duration: duration,
            recordedAt: Date(), displayName: "Take \(takeCounter)"
        )
        takes.append(take)
        return take
    }

    func deleteTake(_ take: Take) {
        takes.removeAll { $0.id == take.id }
        try? FileManager.default.removeItem(at: take.fileURL)
    }

    // MARK: Meter timer

    private func startMeterTimer() {
        meterTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 15.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tickMeter() }
        }
        RunLoop.main.add(timer, forMode: .common)
        meterTimer = timer
    }

    private func stopMeterTimer() {
        meterTimer?.invalidate()
        meterTimer = nil
    }

    private func tickMeter() {
        guard let recorder, isRecording else { return }
        recorder.updateMeters()
        let db = recorder.averagePower(forChannel: 0)
        // Map the recorder's -160...0 dB scale to a perceptually usable 0...1 range; anything
        // below -50 dB reads as silence on a compact meter, so that's the floor.
        let floor: Float = -50
        let normalized = db <= floor ? 0 : (db - floor) / -floor
        inputLevel = min(max(normalized, 0), 1)
        if let start = recordingStartDate {
            elapsedTime = Date().timeIntervalSince(start)
        }
    }

    // MARK: Route + interruption recovery

    private func refreshCurrentInputName() {
        currentInputName = AVAudioSession.sharedInstance().currentRoute.inputs.first?.portName
    }

    // These fire from NotificationCenter, which does not guarantee delivery on the main thread
    // for AVAudioSession notifications — every touch of actor-isolated state happens inside the
    // `Task { @MainActor in ... }` hop below, not directly in the `@objc` method body.

    @objc private nonisolated func handleInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue),
              type == .began else { return }
        Task { @MainActor in
            guard self.isRecording else { return }
            let take = await self.stopRecording()
            self.recoveryMessage = take != nil
                ? "Recording stopped because something else needed audio (a call, Siri, or another app). Your take up to that point was saved — tap Record to start a new one."
                : "Recording stopped because something else needed audio (a call, Siri, or another app), before enough was captured to save anything. Tap Record to try again."
        }
    }

    @objc private nonisolated func handleRouteChange(_ notification: Notification) {
        guard let info = notification.userInfo,
              let reasonValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }
        Task { @MainActor in
            let previousInputName = self.currentInputName
            self.refreshCurrentInputName()

            guard reason == .oldDeviceUnavailable, self.isRecording else { return }
            let from = previousInputName ?? "the previous input"
            let to = self.currentInputName ?? "the built-in microphone"
            let take = await self.stopRecording()
            self.recoveryMessage = take != nil
                ? "Recording stopped because \(from) was disconnected. Your take up to that point was saved — tap Record to continue on \(to)."
                : "Recording stopped because \(from) was disconnected before enough was captured to save anything. Tap Record to continue on \(to)."
        }
    }

    func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

extension VoiceoverRecorderService: AVAudioRecorderDelegate {
    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor in
            self.errorMessage = "Recording failed: \(error?.localizedDescription ?? "unknown encoder error")"
            self.isRecording = false
            self.stopMeterTimer()
        }
    }
}
