Speed-curve regression checks:

```sh
swiftc -module-cache-path /tmp/mixtape-swift-cache Features/Editor/Model/EditorSpeedRamp.swift Tests/Editor/SpeedRampTests.swift -o /tmp/mixtape-speed-tests
/tmp/mixtape-speed-tests
python3 Tests/Editor/run_media_tests.py
```

The media test requires macOS AVFoundation encoding services. It compiles the production composition insertion methods, generates a four-second video, applies all six presets to a trimmed range, and checks source/target continuity and exported duration within one 30 fps frame. The model tests cover point constraints, speeds, timeline/source round trips, and persistence.

On an iPhone, open Speed → Curve. Tap each point: selection and preview should move without changing the speed. Drag slightly off-center: the point should follow smoothly without jumping, endpoints should stay anchored, and neighbors must not cross. Release to apply the edit. Drag the white top handle or graph background to scrub without editing points. Check playback, Undo/Redo, save/reopen, and export using a clip with visible motion and audible speech. Native touch responsiveness and perceptual audio/video quality still require this device check.

Keyframe identity regression check (standalone model executable; no simulator):

```sh
swiftc -module-cache-path /tmp/mixtape-swift-cache Features/Editor/Model/EditorKeyframe.swift Tests/Editor/KeyframeInteractionTests.swift -o /tmp/mixtape-keyframe-tests
/tmp/mixtape-keyframe-tests
```

Additional physical-device acceptance checks:

- In Clip, Media Overlay, Audio, and Text keyframes, tap a point and drag it backward/forward. Confirm its value and identity stay unchanged, the curve follows the drag, endpoints remain reachable, and Undo restores the previous time.
- Scrub the graph background or playhead handle and confirm the selected keyframe stays selected. Check that preview and local time agree.
- In effect keyframes, confirm Amount-only effects show one labelled slider; Zoom Pulse, Shake, and Strobe show Amount and Speed; other effects use their actual secondary control. There should be no standalone slider below the ruler.
- Give neighboring effect points different Amount/Speed values, then check playback, save/reopen, point movement/deletion, split, freeze, Undo/Redo, and export.
- Play a project wider than the visible timeline. Confirm the timeline follows the playhead, clamps at project ends, pauses following during manual interaction, and resumes while playback continues. Repeat at different zoom levels and with overlay/audio tracks expanded. Pausing playback should leave manual scrolling available.

The recent keyframe and playback-following changes received source syntax checks and focused model checks, not simulator or physical-device validation. The synthetic-video speed-ramp test does not establish touch responsiveness or effect-rendering quality.
