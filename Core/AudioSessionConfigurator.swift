//
//  AudioSessionConfigurator.swift
//  Mixtape
//

import AVFoundation

/// Configures playback through the device speaker (not muted by the silent switch).
enum AudioSessionConfigurator {
    static func configureForVideoPlayback() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .moviePlayback)
            try session.setActive(true)
        } catch {
            #if DEBUG
            print("AudioSessionConfigurator: \(error.localizedDescription)")
            #endif
        }
    }

    /// Switches to `.playAndRecord` for voiceover capture. `.allowBluetooth`/`.allowBluetoothA2DP`
    /// keep a paired headset usable as the input, `.defaultToSpeaker` avoids the recorder silently
    /// routing monitoring audio to the earpiece when no headset is attached.
    static func configureForRecording() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .default,
            options: [.allowBluetooth, .allowBluetoothA2DP, .defaultToSpeaker]
        )
        try session.setActive(true)
    }
}
