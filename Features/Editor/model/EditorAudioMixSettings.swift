//
//  EditorAudioMixSettings.swift
//  Mixtape
//
//  Priority 13 gain staging (Features/Editor/README.md): per-track and master gain applied on
//  top of existing per-clip volume. Deliberately does not include live meters — see the Priority
//  13 writeup for why that's out of scope.
//

import Foundation

/// Gain/mute for one audio lane (`EditorAudioClip.laneIndex`) — every clip sharing a lane shares
/// this setting, the same way a track fader in a real mixer affects every clip on that track.
struct EditorAudioTrackSettings: Codable, Hashable {
    var gain: Float = 1.0
    var isMuted: Bool = false
    /// Priority 15: soloing any track silences every other track that isn't also soloed — same
    /// convention as a hardware mixer. Layered on top of `isMuted` at the call site (see
    /// `effectiveGain(anySoloed:)`) rather than folded into a single flag, so muting a soloed
    /// track and un-soloing it are still independent, recoverable actions.
    var isSoloed: Bool = false
    /// Priority 15 track header name; `nil` falls back to positional "Track N" display.
    var name: String?

    init(gain: Float = 1.0, isMuted: Bool = false, isSoloed: Bool = false, name: String? = nil) {
        self.gain = gain
        self.isMuted = isMuted
        self.isSoloed = isSoloed
        self.name = name
    }

    /// Custom decoding — a non-optional stored property's *declaration* default (`isSoloed =
    /// false`) is NOT applied by synthesized `Decodable`; synthesis still calls
    /// `container.decode(Bool.self, forKey:)` unconditionally, which throws `keyNotFound` on any
    /// project saved before this field existed. Every other backward-compatible field in this
    /// codebase already goes through an explicit `decodeIfPresent(...) ?? default` for exactly
    /// this reason (see `SavedAudioClip.laneIndex`, for one) — this struct just hadn't needed one
    /// until now, since `gain`/`isMuted` shipped together in the original Priority 13 decode.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        gain = try c.decodeIfPresent(Float.self, forKey: .gain) ?? 1.0
        isMuted = try c.decodeIfPresent(Bool.self, forKey: .isMuted) ?? false
        isSoloed = try c.decodeIfPresent(Bool.self, forKey: .isSoloed) ?? false
        name = try c.decodeIfPresent(String.self, forKey: .name)
    }

    /// The single multiplier the composition/export pipeline applies. Kept 0...1 (attenuation
    /// only, no boost) to match every other volume control in this app (`EditorAudioClip.volume`,
    /// `EditorClip.volume`, `EditorOverlayClip.volume` are all 0...1) and to avoid a real bug:
    /// `EditorCompositionBuilder.applyVolumeAutomation` clamps its *keyframed/faded* automation
    /// path to a maximum of 1.0 but does not clamp the simple (no-automation) `setVolume` path —
    /// a gain > 1.0 would silently behave differently depending on whether a clip happens to
    /// have fades or volume keyframes.
    ///
    /// `anySoloed` — whether *any* lane in the project is currently soloed — must come from the
    /// caller since a single track's settings can't see its siblings: this track is silenced
    /// when muted, or when something else is soloed and this one isn't.
    func effectiveGain(anySoloed: Bool) -> Float {
        if isMuted { return 0 }
        if anySoloed && !isSoloed { return 0 }
        return min(max(gain, 0), 1)
    }
}
