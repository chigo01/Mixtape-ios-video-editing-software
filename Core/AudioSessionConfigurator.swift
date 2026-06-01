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
}
