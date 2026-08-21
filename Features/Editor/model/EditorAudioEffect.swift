//
//  EditorAudioEffect.swift
//  Mixtape
//
//  Priority 15 audio effects: CapCut-style voice/sound presets for background audio clips, split
//  into the same two categories CapCut's "Voice filters" / "Voice characters" tabs use. Built
//  entirely from Apple's off-the-shelf `AVAudioUnit` effects (`AVAudioUnitTimePitch`,
//  `AVAudioUnitReverb`, `AVAudioUnitDistortion`, `AVAudioUnitDelay`, `AVAudioUnitEQ`) rendered
//  offline via `AVAudioEngine`'s manual rendering mode — deliberately not real-time
//  `MTAudioProcessingTap` DSP, the class of risk the README already excluded once for Priority
//  13's meters (a real-time C callback that can't be verified by reading code). Offline
//  rendering is standard, documented Apple API.
//
//  Not covered: CapCut's third tab, "Speech to song" (converting spoken audio into a sung
//  melody). That's a fundamentally different kind of feature — pitch/rhythm detection plus
//  resynthesis onto a target melody, likely ML-backed — not a preset DSP chain, so it doesn't
//  belong in this file. Also not attempted: matching CapCut's exact voice-character timbres
//  (Jessie, Squirrel, etc. are plausibly trained voice-conversion models on their end) — these
//  presets are DSP approximations (pitch + EQ + reverb/distortion), not voice conversion.
//
//  Every preset only shifts `pitch` (cents), never `rate` — so a clip's duration is identical
//  before and after the effect, and none of the existing trim/timeline math needs to change to
//  account for it. The one exception in spirit, `.tremble`, still never touches `rate` either —
//  it modulates `pitch` over time instead of setting it once; see `modulate(chain:elapsedSeconds:)`
//  and `EditorAudioEffectRenderer`.
//

import AVFoundation

enum EditorAudioEffect: String, Codable, CaseIterable, Identifiable, Hashable {
    case none

    // MARK: Filters — production-style vocal treatments
    case echo
    case reverbHall
    case reverbCave
    case telephone
    case megaphone
    case sweet
    case micHog
    case loFi
    case clearVocals
    case deepAndClear
    case bassMic
    case studioMic
    case divineEcho
    case energetic
    case tremble
    case distorted
    case bigHouse

    // MARK: Characters — dramatic voice presets
    case robot
    case chipmunk
    case deepVoice
    case alien
    case squirrel
    case elf
    case trickster
    case darkLord
    case nobleLeader
    case boldWarrior
    case nobleChief
    case fussyMale
    case queen
    case santa

    var id: String { rawValue }

    enum Category: String, CaseIterable, Identifiable {
        case filters = "Filters"
        case characters = "Characters"
        var id: String { rawValue }
    }

    /// `.none` has no category of its own — the panel always shows it as a pinned "Original"
    /// cell regardless of which tab is selected, the same way CapCut does.
    var category: Category {
        switch self {
        case .none,
             .echo, .reverbHall, .reverbCave, .telephone, .megaphone, .sweet, .micHog, .loFi,
             .clearVocals, .deepAndClear, .bassMic, .studioMic, .divineEcho, .energetic,
             .tremble, .distorted, .bigHouse:
            return .filters
        case .robot, .chipmunk, .deepVoice, .alien, .squirrel, .elf, .trickster, .darkLord,
             .nobleLeader, .boldWarrior, .nobleChief, .fussyMale, .queen, .santa:
            return .characters
        }
    }

    var title: String {
        switch self {
        case .none: return "Original"
        case .echo: return "Echo"
        case .reverbHall: return "Hall"
        case .reverbCave: return "Cave"
        case .telephone: return "Telephone"
        case .megaphone: return "Megaphone"
        case .sweet: return "Sweet"
        case .micHog: return "Mic Hog"
        case .loFi: return "Lo-Fi"
        case .clearVocals: return "Clear Vocals"
        case .deepAndClear: return "Deep & Clear"
        case .bassMic: return "Bass Mic"
        case .studioMic: return "Studio Mic"
        case .divineEcho: return "Divine Echo"
        case .energetic: return "Energetic"
        case .tremble: return "Tremble"
        case .distorted: return "Distorted"
        case .bigHouse: return "Big House"
        case .robot: return "Robot"
        case .chipmunk: return "Chipmunk"
        case .deepVoice: return "Deep Voice"
        case .alien: return "Alien"
        case .squirrel: return "Squirrel"
        case .elf: return "Elf"
        case .trickster: return "Trickster"
        case .darkLord: return "Dark Lord"
        case .nobleLeader: return "Noble Leader"
        case .boldWarrior: return "Bold Warrior"
        case .nobleChief: return "Noble Chief"
        case .fussyMale: return "Fussy Male"
        case .queen: return "Queen"
        case .santa: return "Santa"
        }
    }

    var systemImage: String {
        switch self {
        case .none: return "waveform"
        case .echo: return "arrow.triangle.2.circlepath"
        case .reverbHall: return "building.columns"
        case .reverbCave: return "mountain.2"
        case .telephone: return "phone"
        case .megaphone: return "megaphone"
        case .sweet: return "heart"
        case .micHog: return "mic.fill"
        case .loFi: return "waveform.path"
        case .clearVocals: return "sparkle"
        case .deepAndClear: return "waveform.badge.magnifyingglass"
        case .bassMic: return "speaker.wave.3.fill"
        case .studioMic: return "recordingtape"
        case .divineEcho: return "sun.max"
        case .energetic: return "bolt.fill"
        case .tremble: return "waveform.path.ecg"
        case .distorted: return "waveform.badge.exclamationmark"
        case .bigHouse: return "house"
        case .robot: return "cpu"
        case .chipmunk: return "hare"
        case .deepVoice: return "tortoise"
        case .alien: return "sparkles"
        case .squirrel: return "leaf"
        case .elf: return "wand.and.stars"
        case .trickster: return "theatermasks"
        case .darkLord: return "flame"
        case .nobleLeader: return "crown"
        case .boldWarrior: return "shield"
        case .nobleChief: return "star.circle"
        case .fussyMale: return "person.wave.2"
        case .queen: return "crown.fill"
        case .santa: return "gift"
        }
    }

    /// Fresh node instances for one offline render pass. `AVAudioNode`s are single-use once
    /// attached to an engine, so this is a factory — never share instances across renders.
    func makeChain() -> [AVAudioNode] {
        switch self {
        case .none:
            return []

        // MARK: Filters

        case .echo:
            let delay = AVAudioUnitDelay()
            delay.delayTime = 0.32
            delay.feedback = 35
            delay.wetDryMix = 40
            return [delay]

        case .reverbHall:
            let reverb = AVAudioUnitReverb()
            reverb.loadFactoryPreset(.largeHall2)
            reverb.wetDryMix = 45
            return [reverb]

        case .reverbCave:
            let reverb = AVAudioUnitReverb()
            reverb.loadFactoryPreset(.cathedral)
            reverb.wetDryMix = 65
            return [reverb]

        case .telephone:
            let eq = AVAudioUnitEQ(numberOfBands: 2)
            eq.bands[0].filterType = .highPass
            eq.bands[0].frequency = 400
            eq.bands[0].bypass = false
            eq.bands[1].filterType = .lowPass
            eq.bands[1].frequency = 2_800
            eq.bands[1].bypass = false
            eq.globalGain = 6
            return [eq]

        case .megaphone:
            let distortion = AVAudioUnitDistortion()
            distortion.loadFactoryPreset(.multiCellphoneConcert)
            distortion.wetDryMix = 65
            let eq = AVAudioUnitEQ(numberOfBands: 2)
            eq.bands[0].filterType = .highPass
            eq.bands[0].frequency = 500
            eq.bands[0].bypass = false
            eq.bands[1].filterType = .lowPass
            eq.bands[1].frequency = 3_500
            eq.bands[1].bypass = false
            eq.globalGain = 8
            return [distortion, eq]

        case .sweet:
            let eq = AVAudioUnitEQ(numberOfBands: 2)
            eq.bands[0].filterType = .lowShelf
            eq.bands[0].frequency = 200
            eq.bands[0].gain = 2
            eq.bands[0].bypass = false
            eq.bands[1].filterType = .highShelf
            eq.bands[1].frequency = 6_000
            eq.bands[1].gain = 3
            eq.bands[1].bypass = false
            let reverb = AVAudioUnitReverb()
            reverb.loadFactoryPreset(.smallRoom)
            reverb.wetDryMix = 12
            return [eq, reverb]

        case .micHog:
            let eq = AVAudioUnitEQ(numberOfBands: 1)
            eq.bands[0].filterType = .lowShelf
            eq.bands[0].frequency = 150
            eq.bands[0].gain = 9
            eq.bands[0].bypass = false
            let distortion = AVAudioUnitDistortion()
            distortion.loadFactoryPreset(.multiDistortedFunk)
            distortion.wetDryMix = 15
            return [eq, distortion]

        case .loFi:
            let distortion = AVAudioUnitDistortion()
            distortion.loadFactoryPreset(.drumsLoFi)
            distortion.wetDryMix = 55
            let eq = AVAudioUnitEQ(numberOfBands: 1)
            eq.bands[0].filterType = .lowPass
            eq.bands[0].frequency = 3_400
            eq.bands[0].bypass = false
            return [distortion, eq]

        case .clearVocals:
            let eq = AVAudioUnitEQ(numberOfBands: 2)
            eq.bands[0].filterType = .highPass
            eq.bands[0].frequency = 120
            eq.bands[0].bypass = false
            eq.bands[1].filterType = .parametric
            eq.bands[1].frequency = 3_000
            eq.bands[1].bandwidth = 1.5
            eq.bands[1].gain = 4
            eq.bands[1].bypass = false
            return [eq]

        case .deepAndClear:
            let pitch = AVAudioUnitTimePitch()
            pitch.pitch = -250
            let eq = AVAudioUnitEQ(numberOfBands: 1)
            eq.bands[0].filterType = .parametric
            eq.bands[0].frequency = 2_500
            eq.bands[0].bandwidth = 1.5
            eq.bands[0].gain = 3
            eq.bands[0].bypass = false
            return [pitch, eq]

        case .bassMic:
            let eq = AVAudioUnitEQ(numberOfBands: 1)
            eq.bands[0].filterType = .lowShelf
            eq.bands[0].frequency = 180
            eq.bands[0].gain = 12
            eq.bands[0].bypass = false
            return [eq]

        case .studioMic:
            let eq = AVAudioUnitEQ(numberOfBands: 2)
            eq.bands[0].filterType = .highPass
            eq.bands[0].frequency = 90
            eq.bands[0].bypass = false
            eq.bands[1].filterType = .highShelf
            eq.bands[1].frequency = 8_000
            eq.bands[1].gain = 2
            eq.bands[1].bypass = false
            let reverb = AVAudioUnitReverb()
            reverb.loadFactoryPreset(.smallRoom)
            reverb.wetDryMix = 8
            return [eq, reverb]

        case .divineEcho:
            let delay = AVAudioUnitDelay()
            delay.delayTime = 0.28
            delay.feedback = 30
            delay.wetDryMix = 30
            let reverb = AVAudioUnitReverb()
            reverb.loadFactoryPreset(.cathedral)
            reverb.wetDryMix = 55
            return [delay, reverb]

        case .energetic:
            let pitch = AVAudioUnitTimePitch()
            pitch.pitch = 180
            let eq = AVAudioUnitEQ(numberOfBands: 1)
            eq.bands[0].filterType = .highShelf
            eq.bands[0].frequency = 5_000
            eq.bands[0].gain = 4
            eq.bands[0].bypass = false
            return [pitch, eq]

        case .tremble:
            // Base pitch starts flat — `modulate(chain:elapsedSeconds:)` animates it every
            // render chunk to produce the wobble; nothing here sets a static shift.
            let pitch = AVAudioUnitTimePitch()
            pitch.pitch = 0
            return [pitch]

        case .distorted:
            let distortion = AVAudioUnitDistortion()
            distortion.loadFactoryPreset(.multiDistortedSquared)
            distortion.wetDryMix = 70
            return [distortion]

        case .bigHouse:
            let reverb = AVAudioUnitReverb()
            reverb.loadFactoryPreset(.largeChamber)
            reverb.wetDryMix = 60
            return [reverb]

        // MARK: Characters

        case .robot:
            let pitch = AVAudioUnitTimePitch()
            pitch.pitch = -420
            let distortion = AVAudioUnitDistortion()
            distortion.loadFactoryPreset(.speechRadioTower)
            distortion.wetDryMix = 25
            return [pitch, distortion]

        case .chipmunk:
            let pitch = AVAudioUnitTimePitch()
            pitch.pitch = 700
            return [pitch]

        case .deepVoice:
            let pitch = AVAudioUnitTimePitch()
            pitch.pitch = -500
            return [pitch]

        case .alien:
            let distortion = AVAudioUnitDistortion()
            distortion.loadFactoryPreset(.speechAlienChatter)
            distortion.wetDryMix = 55
            let pitch = AVAudioUnitTimePitch()
            pitch.pitch = 150
            return [distortion, pitch]

        case .squirrel:
            let pitch = AVAudioUnitTimePitch()
            pitch.pitch = 900
            return [pitch]

        case .elf:
            let pitch = AVAudioUnitTimePitch()
            pitch.pitch = 550
            let reverb = AVAudioUnitReverb()
            reverb.loadFactoryPreset(.smallRoom)
            reverb.wetDryMix = 15
            return [pitch, reverb]

        case .trickster:
            let pitch = AVAudioUnitTimePitch()
            pitch.pitch = 350
            let distortion = AVAudioUnitDistortion()
            distortion.loadFactoryPreset(.multiEcho2)
            distortion.wetDryMix = 20
            return [pitch, distortion]

        case .darkLord:
            let pitch = AVAudioUnitTimePitch()
            pitch.pitch = -750
            let distortion = AVAudioUnitDistortion()
            distortion.loadFactoryPreset(.multiEverythingIsBroken)
            distortion.wetDryMix = 12
            let reverb = AVAudioUnitReverb()
            reverb.loadFactoryPreset(.cathedral)
            reverb.wetDryMix = 35
            return [pitch, distortion, reverb]

        case .nobleLeader:
            let pitch = AVAudioUnitTimePitch()
            pitch.pitch = -180
            let reverb = AVAudioUnitReverb()
            reverb.loadFactoryPreset(.mediumHall2)
            reverb.wetDryMix = 30
            return [pitch, reverb]

        case .boldWarrior:
            let pitch = AVAudioUnitTimePitch()
            pitch.pitch = -350
            let distortion = AVAudioUnitDistortion()
            distortion.loadFactoryPreset(.multiDistortedFunk)
            distortion.wetDryMix = 25
            return [pitch, distortion]

        case .nobleChief:
            let pitch = AVAudioUnitTimePitch()
            pitch.pitch = -300
            let eq = AVAudioUnitEQ(numberOfBands: 1)
            eq.bands[0].filterType = .lowShelf
            eq.bands[0].frequency = 200
            eq.bands[0].gain = 5
            eq.bands[0].bypass = false
            return [pitch, eq]

        case .fussyMale:
            let pitch = AVAudioUnitTimePitch()
            pitch.pitch = 120
            let eq = AVAudioUnitEQ(numberOfBands: 1)
            eq.bands[0].filterType = .parametric
            eq.bands[0].frequency = 1_500
            eq.bands[0].bandwidth = 1.0
            eq.bands[0].gain = 6
            eq.bands[0].bypass = false
            return [pitch, eq]

        case .queen:
            let pitch = AVAudioUnitTimePitch()
            pitch.pitch = 320
            let reverb = AVAudioUnitReverb()
            reverb.loadFactoryPreset(.mediumHall)
            reverb.wetDryMix = 25
            return [pitch, reverb]

        case .santa:
            let pitch = AVAudioUnitTimePitch()
            pitch.pitch = -280
            let eq = AVAudioUnitEQ(numberOfBands: 1)
            eq.bands[0].filterType = .lowShelf
            eq.bands[0].frequency = 200
            eq.bands[0].gain = 4
            eq.bands[0].bypass = false
            let reverb = AVAudioUnitReverb()
            reverb.loadFactoryPreset(.mediumRoom)
            reverb.wetDryMix = 15
            return [pitch, eq, reverb]
        }
    }

    /// Whether this preset needs its chain re-tuned as the offline render progresses, rather
    /// than configured once up front — currently only `.tremble`'s wobble, which a static
    /// `AVAudioUnitTimePitch.pitch` can't express.
    var isModulated: Bool { self == .tremble }

    /// Called once per render chunk with elapsed source time, so `.tremble` can animate its
    /// `AVAudioUnitTimePitch` node as rendering progresses. Safe to mutate here — manual
    /// rendering calls this synchronously between chunks on the actor doing the render, not from
    /// a live real-time audio thread, so none of `MTAudioProcessingTap`'s constraints apply.
    func modulate(chain: [AVAudioNode], elapsedSeconds: TimeInterval) {
        guard self == .tremble,
              let pitchNode = chain.first(where: { $0 is AVAudioUnitTimePitch }) as? AVAudioUnitTimePitch
        else { return }
        let wobble = sin(elapsedSeconds * 2 * .pi * 6.5)
        pitchNode.pitch = Float(wobble * 160)
    }
}
