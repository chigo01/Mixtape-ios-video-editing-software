//
//  VoiceoverRecorderView.swift
//  Mixtape
//
//  Priority 14 (core recording MVP). Records at the playhead, shows a live input-level meter,
//  and keeps every take until the user picks one to insert — retry/delete stay available for
//  the rest. Permission, interruption, and route-change states get their own recovery UI instead
//  of failing silently. See `VoiceoverRecorderService` for what is and isn't in scope.
//
//  Teleprompter: turned out to be much smaller than the original README line implied once scoped
//  to audio-only recording — no camera framing guides, no read/unread word-level highlighting,
//  just a script the user types once and an auto-scrolling overlay timed off the take's elapsed
//  recording time so they can read along. The script is session-only scratch text (not part of
//  `EditorProject`) — it's a reading aid, not a timeline object.
//
//  Punch-in mode: this same sheet doubles as the punch-in recorder — the only difference is what
//  "Use" does with the finished take (splice into an existing clip vs. insert as a new one). No
//  live playback of the surrounding take happens while punch-recording; see the Priority 14
//  writeup for why that's a deliberate simplification, not an oversight.
//

import AVFoundation
import SwiftUI

struct VoiceoverRecorderView: View {
    enum Mode {
        case insert(EditorViewModel.AudioInsertion)
        case punch(EditorViewModel.PunchInRange)
    }

    let vm: EditorViewModel
    let mode: Mode
    var onInsert: () -> Void = {}
    var onCancel: () -> Void = {}

    @State private var recorder = VoiceoverRecorderService()
    @State private var previewPlayer: AVAudioPlayer?
    @State private var playingTakeID: UUID?
    @State private var insertedTakeURL: URL?

    @State private var script: String = ""
    @State private var isScriptEditorPresented = false
    @State private var isTeleprompterOn = false
    @State private var teleprompterSpeed: Double = 0.5
    @State private var teleprompterFontSize: Double = 22
    @State private var teleprompterColor: Color = .white

    private let teleprompterColors: [Color] = [.white, .yellow, .green, .cyan, .pink, .orange]

    var body: some View {
        VStack(spacing: 0) {
            header

            if recorder.permissionState == .denied {
                permissionDeniedState
            } else {
                recordingSurface
                if !recorder.takes.isEmpty {
                    Divider().overlay(Color.white.opacity(0.08)).padding(.vertical, 14)
                    takesList
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .background(Color.black.ignoresSafeArea())
        .onAppear {
            recorder.requestPermissionIfNeeded()
            recorder.beginSession()
        }
        .onDisappear {
            stopPreview()
            recorder.endSession(keeping: insertedTakeURL)
        }
        .alert(
            "Recording problem",
            isPresented: Binding(
                get: { recorder.errorMessage != nil },
                set: { if !$0 { recorder.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(recorder.errorMessage ?? "")
        }
        .sheet(isPresented: $isScriptEditorPresented) {
            ScriptEditorSheet(script: $script) { isScriptEditorPresented = false }
        }
    }

    private var headerTitle: String {
        switch mode {
        case .insert: return "Record Voiceover"
        case .punch: return "Punch In"
        }
    }

    private var header: some View {
        HStack {
            Text(headerTitle)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white)
            Spacer()
            Button {
                onCancel()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
        }
        .padding(.bottom, 8)
    }

    // MARK: Permission denied

    private var permissionDeniedState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "mic.slash.fill")
                .font(.system(size: 34))
                .foregroundColor(.white.opacity(0.5))
            Text("Microphone access is off")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
            Text("Mixtape needs microphone access to record a voiceover. Turn it on in Settings.")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Button("Open Settings") { recorder.openSettings() }
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.black)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Capsule().fill(Color.appColors.primaryColor))
            Spacer()
        }
    }

    // MARK: Recording surface

    private var recordingSurface: some View {
        VStack(spacing: 14) {
            if let message = recorder.recoveryMessage {
                recoveryBanner(message)
            }

            inputRow

            scriptControlsRow
            if isTeleprompterOn && !script.isEmpty {
                teleprompterOverlay
                teleprompterSettingsRow
            }

            Text(formattedTime(recorder.isRecording ? recorder.elapsedTime : 0))
                .font(.system(size: 32, weight: .semibold).monospacedDigit())
                .foregroundColor(.white)
                .opacity(recorder.isRecording ? 1 : 0.35)

            recordButton
                .padding(.vertical, 6)

            Text(recorder.isRecording ? "Tap to stop" : recordHintText)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.5))
        }
        .padding(.top, 4)
    }

    private var recordHintText: String {
        switch mode {
        case .insert: return "Tap to record at the playhead"
        case .punch: return "Tap to record the replacement"
        }
    }

    // MARK: Teleprompter

    private var scriptControlsRow: some View {
        HStack(spacing: 10) {
            Button {
                isScriptEditorPresented = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "pencil")
                    Text(script.isEmpty ? "Add script" : "Edit script")
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.8))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .disabled(recorder.isRecording)

            if !script.isEmpty {
                Button {
                    isTeleprompterOn.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "text.viewfinder")
                        Text("Teleprompter")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(isTeleprompterOn ? .black : .white.opacity(0.8))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        Capsule().fill(isTeleprompterOn ? Color.appColors.primaryColor : Color.white.opacity(0.08))
                    )
                }
                .buttonStyle(.plain)
                .disabled(recorder.isRecording)
            }

            Spacer(minLength: 0)
        }
        .opacity(recorder.isRecording ? 0.5 : 1)
    }

    /// Scroll offset is driven off `recorder.elapsedTime` (already ticking at 15 Hz for the
    /// level meter) rather than a separate timer — it naturally resets to the top on every new
    /// take since `elapsedTime` restarts at 0.
    private var teleprompterScrollOffset: CGFloat {
        guard recorder.isRecording else { return 0 }
        return CGFloat(recorder.elapsedTime) * CGFloat(teleprompterSpeed) * 36
    }

    private var teleprompterOverlay: some View {
        Text(script)
            .font(.system(size: teleprompterFontSize, weight: .medium))
            .foregroundColor(teleprompterColor)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(12)
            .offset(y: -teleprompterScrollOffset)
            .animation(.linear(duration: 0.1), value: teleprompterScrollOffset)
            .frame(height: 130, alignment: .top)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.06)))
            .clipped()
    }

    private var teleprompterSettingsRow: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Text("Speed")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
                    .frame(width: 44, alignment: .leading)
                Slider(value: $teleprompterSpeed, in: 0.15...1.5)
                    .tint(Color.appColors.primaryColor)
            }
            HStack(spacing: 10) {
                Text("Size")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
                    .frame(width: 44, alignment: .leading)
                Slider(value: $teleprompterFontSize, in: 14...32)
                    .tint(Color.appColors.primaryColor)
            }
            HStack(spacing: 10) {
                Text("Color")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
                    .frame(width: 44, alignment: .leading)
                HStack(spacing: 8) {
                    ForEach(teleprompterColors, id: \.self) { color in
                        Circle()
                            .fill(color)
                            .frame(width: 20, height: 20)
                            .overlay(
                                Circle().stroke(Color.white, lineWidth: teleprompterColor == color ? 2 : 0)
                            )
                            .onTapGesture { teleprompterColor = color }
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.04)))
    }

    private func recoveryBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.yellow)
            Text(message)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.85))
            Spacer(minLength: 0)
            Button {
                recorder.recoveryMessage = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.yellow.opacity(0.12)))
    }

    private var inputRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "mic.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.5))
            Text(recorder.currentInputName ?? "Microphone")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.5))
        }
    }

    private var recordButton: some View {
        ZStack {
            Circle()
                .stroke(Color.red.opacity(0.35), lineWidth: 3)
                .frame(width: 92, height: 92)
                .scaleEffect(1 + CGFloat(recorder.inputLevel) * 0.35)
                .opacity(recorder.isRecording ? 1 : 0)
                .animation(.linear(duration: 0.07), value: recorder.inputLevel)

            Circle()
                .fill(Color.red)
                .frame(width: 74, height: 74)

            RoundedRectangle(cornerRadius: recorder.isRecording ? 6 : 30)
                .fill(Color.white)
                .frame(
                    width: recorder.isRecording ? 26 : 60,
                    height: recorder.isRecording ? 26 : 60
                )
                .animation(.easeInOut(duration: 0.18), value: recorder.isRecording)
        }
        .contentShape(Circle())
        .onTapGesture {
            stopPreview()
            if recorder.isRecording {
                Task { await recorder.stopRecording() }
            } else {
                recorder.startRecording()
            }
        }
        .disabled(recorder.permissionState != .granted)
        .opacity(recorder.permissionState == .granted ? 1 : 0.4)
    }

    // MARK: Takes

    private var takesList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Takes")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.55))

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(recorder.takes.reversed()) { take in
                        takeRow(take)
                    }
                }
            }
            .frame(maxHeight: 220)
        }
    }

    private func takeRow(_ take: VoiceoverRecorderService.Take) -> some View {
        HStack(spacing: 10) {
            Button {
                togglePreview(take)
            } label: {
                Image(systemName: playingTakeID == take.id ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(Color.appColors.primaryColor)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(take.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                Text(formattedTime(take.duration))
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
            }

            Spacer()

            Button {
                stopPreview()
                recorder.deleteTake(take)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)

            Button {
                stopPreview()
                insertedTakeURL = take.fileURL
                switch mode {
                case .insert(let insertion):
                    vm.insertRecordedVoiceover(fileURL: take.fileURL, duration: take.duration, insertion: insertion)
                case .punch(let range):
                    vm.punchInRecordedTake(
                        clipID: range.clipID, start: range.start, end: range.end,
                        fileURL: take.fileURL, duration: take.duration
                    )
                }
                onInsert()
            } label: {
                Text("Use")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Color.appColors.primaryColor))
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
    }

    // MARK: Preview playback

    private func togglePreview(_ take: VoiceoverRecorderService.Take) {
        if playingTakeID == take.id {
            stopPreview()
            return
        }
        stopPreview()
        guard let player = try? AVAudioPlayer(contentsOf: take.fileURL) else { return }
        previewPlayer = player
        playingTakeID = take.id
        player.play()
        Task {
            try? await Task.sleep(nanoseconds: UInt64(player.duration * 1_000_000_000))
            if playingTakeID == take.id { stopPreview() }
        }
    }

    private func stopPreview() {
        previewPlayer?.stop()
        previewPlayer = nil
        playingTakeID = nil
    }

    private func formattedTime(_ time: TimeInterval) -> String {
        let total = max(0, Int(time.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Plain script entry — no AI writing assist (improve/expand/shorten). The point here is a place
/// to get your thoughts down before recording, not a writing tool.
private struct ScriptEditorSheet: View {
    @Binding var script: String
    var onDone: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Script")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                Button("Done") { onDone() }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Color.appColors.primaryColor)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 10)

            TextEditor(text: $script)
                .scrollContentBackground(.hidden)
                .font(.system(size: 16))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .focused($isFocused)
        }
        .background(Color.black.ignoresSafeArea())
        .onAppear { isFocused = true }
    }
}
