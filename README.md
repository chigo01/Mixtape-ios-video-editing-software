# Mixtape

Mixtape is a native, touch-first iOS and iPadOS video editor built with SwiftUI,
AVFoundation, Core Image, and an MVVM feature architecture. It provides a continuous
multi-clip timeline, creative transitions, audio and text editing, project persistence,
and configurable video export across iPhone and adaptive iPad layouts.

> The project is under active development. Core editing and export flows work,
> while the professional roadmap below tracks the remaining production features.

## Optional sound-effects API

The **Extract Audio from Video** feature is fully on-device and does not require an API key.

Freesound search is optional. To enable it, copy `Config/Secrets.example.xcconfig` to
`Config/Secrets.xcconfig` and set `FREESOUND_API_KEY`. The secrets file is ignored by Git and
loaded through `Config/Base.xcconfig`. Clean checkouts continue to build without the key; only
online sound-effects search is unavailable.

## Features

### Platform experience

- A focused portrait editor on iPhone, with iPhone orientation locked to portrait.
- Adaptive iPad support in portrait and landscape, including Stage Manager and narrow
  window fallbacks driven by available width instead of device orientation alone.
- A wide iPad editing workspace with the preview beside the timeline and tools, while
  portrait and compact iPad windows retain the touch-friendly stacked workspace.
- Responsive project grids, adaptive PhotoKit media columns, bounded selection controls,
  and a two-column export workspace on wide iPads.
- iPad-native bottom tool drawers keep the preview and timeline visible while editing,
  with native sheet presentation retained on iPhone.
- A universal branded app icon compiled for both iPhone and iPad.

### Timeline editing

- Continuous multi-clip preview backed by one `AVMutableComposition` and `AVPlayer`.
- Video and photo clips with trim, split, reorder, normal speed, curve-based speed
  ramps, volume, and deletion.
- Per-clip crop and reframe with rotation, flips, straighten, aspect presets,
  fit/fill framing, preview drag/pinch gestures, and safe-area guides.
- Adjustable photo duration and media insertion at any clip boundary.
- Global timeline with primary-video, media-overlay, text, and audio lanes, scrubbing,
  undo/redo, and extended overlay/audio/text tails.
- Magnetic playhead and clip/overlay-edge snapping with visible alignment guides,
  zoom-aware thresholds, and haptic feedback.
- One-step duplication for video, audio, and text, plus media replacement that keeps
  compatible trim, timing, transform, color, volume, and transition settings.
- Autosaved projects that restore clip order, edits, playhead, selections, and title.
- Playback-following timeline scrolling keeps the current playhead visible and centered
  where space allows. Following pauses during manual scrolling, scrubbing, trimming,
  moving, reordering, or zooming, then resumes while playback continues.

### Preview responsiveness and autosaving

The September 15, 2026 responsiveness pass adds:

- Shared preview builds: repeated requests for the same edit reuse pending work;
  rapid edits skip intermediate waiting builds and reject outdated results.
- Preview refreshes preserve the latest playhead position and respect the current
  play/pause state. Leaving the editor invalidates pending preview requests.
- One seek per playback alignment, removing the previous duplicate seek.
- Background autosave encoding and atomic file writes after the existing 700 ms
  debounce. Autosaves, final saves, reads, and deletions use one ordered file queue;
  saving on exit still waits for completion.

**Verification:** the unsigned Debug compilation succeeded. The developer reports
that the changes are working well on their physical iPhone. Older-device performance,
measured latency, and the full regression checklist remain unverified.

**Follow-up work:** live timeline scrubbing, audio-only refreshes, adaptive preview
resolution, and moving composition preparation off the main actor remain pending.
This pass preserves the existing edit, undo, and export calculations.

### Keyframes and effect controls

- Clip, media-overlay, audio, and text keyframes share a graph editor: tap a diamond
  to select it, then drag left or right to change its timing without changing its value.
  Background/playhead scrubbing preserves the selection; releasing a point commits one undo step.
- Larger point targets, reachable graph endpoints, and Bézier handles that preserve
  the initial finger offset make selection and curve editing easier.
- Effect keyframe cards provide an Amount slider and only the secondary control
  supported by that effect. Zoom Pulse, Shake, and Strobe expose Speed; other effects
  may expose Direction, Radius, Scale, or Segments. Amount-only effects keep one slider.
- Effect values apply on release, interpolate between keyframes, and use the shared
  preview/export renderer. Secondary values persist with projects and retain split/freeze behavior;
  older projects fall back to their existing effect settings.
- Effect timelines use a draggable playhead and diamonds, without a separate slider
  beneath the ruler. Speed-curve editors support point selection, speed/timing dragging,
  and background scrubbing, with edits applied on release.

Source syntax and focused model checks have passed. Synthetic-video checks cover all six
speed presets with contiguous segments and export timing within one 30 fps frame.
Physical-device checks for touch responsiveness, playback following, and perceptual
preview/export quality remain pending; see [editor verification](Tests/Editor/README.md).

### Transitions and creative tools

- 105 categorized transitions across Basic, Camera, Motion, Light, Blur, Glitch,
  Mask, Artistic, and Distortion.
- Opening, between-clip, and closing transitions with adjustable duration.
- Live preview, persistence, undo/redo, and “Apply to all cuts.”
- 35 GPU transitions rendered by an isolated Metal-backed Core Image compositor.
- Orientation-safe portrait, landscape, rotated, video, and generated-photo rendering.
- Text overlays with fonts, color, size, opacity, alignment, position, timeline trim,
  timeline movement, and direct preview dragging. Stored offsets are screen-width
  points scaled to the live canvas, so the inline card, fullscreen preview, and
  export place the glyph on the same part of the frame.
- CapCut-style photo and video overlays with PhotoKit import, picture-in-picture
  compositing, timeline trim/move/split/delete, speed, volume, opacity, direct preview
  positioning, pinch resize, automatic stacked lanes for overlapping overlays,
  persistence, undo/redo, and preview/export parity.
- Still-image overlays begin at the standard three-second duration and can be extended
  directly with the timeline's right trim handle, using the same generated-video path
  for preview and export as primary still-image clips.
- Project-level 9:16, 16:9, 1:1, 4:5, and custom canvases with solid-color,
  adjustable GPU-blurred, or imported-image backgrounds in both preview and export.
  Backgrounds update live, include reset/image-removal controls, crop oversized artwork
  to the canvas without affecting editor layout, and survive app-container relocation
  during development rebuilds.
- Forty categorized looks, twenty primary color controls, selective HSL, RGB/master
  curves, lift/gamma/gain/offset wheels, and waveform, parade, vectorscope, and
  histogram monitoring with copy/paste and apply-to-all workflows.
- Reusable point and planar motion tracks with transform smoothing, tracked text
  and overlay graphics, and clip stabilization (Smooth or Lock, optical-flow
  camera path, auto crop, edge fill) shared by preview and export.

### Audio

- Imported background-audio clips on a dedicated timeline lane.
- A sound-effects library with bundled effects and optional Freesound search, previews, downloads, and
  license attribution.
- One-tap audio extraction from a selected Photos video, including iCloud-backed originals.
- Extracted audio is saved as a project-owned `.m4a` file and inserted at the current playhead
  or immediately after the selected audio clip.
- Audio trim, move, split, volume, delete, and multiple simultaneous composition tracks.
- Per-audio-clip fade-in and fade-out rendered with `AVAudioMix` volume ramps.
- Original clip audio with independent per-clip volume.

#### Extract audio from video

In the editor, choose **Add Audio → Extract Audio from Video**, select one video, then tap
**Extract Audio**. Mixtape validates that the video contains audio, shows extraction progress,
and adds the result as a normal audio clip. The resulting clip supports the same timeline tools
as imported audio, including trim, move, split, volume, fades, delete, duplication, undo, and
project persistence.

Exports are stored under the app's Application Support `MixtapeAudio` directory rather than a
temporary download cache. Saved paths are repaired when iOS changes the app-container location
during a rebuild, so extracted audio remains available after reinstalling a development build
over the existing app data.

### Projects and export

- PhotoKit media browser with filters, search, selection ordering, preview, and
  limited-library support.
- Project cards with rename and confirmed deletion.
- JSON project persistence in Application Support.
- Export preview with project-name editing and progress/cancel controls.
- 720p, 1080p, and 4K export; frame-rate, bitrate-quality, format, and optional
  HDR/HEVC settings.
- Explicit `AVAssetReader`/`AVAssetWriter` export pipeline with sharing and Photos save.
- Persistent In/Out markers and selected-range export with range-aware duration and
  file-size estimates; video, mixed audio, text, and overlays are trimmed together.

## Requirements

- macOS with Xcode and the iOS SDK.
- An iPhone or iPad running iOS/iPadOS 18.6 or later.
- iPhone runs in portrait; iPad supports portrait, upside-down portrait, and both
  landscape orientations.
- Photo Library access for media import.
- A physical device is recommended for validating GPU transitions, HDR, performance,
  audio routing, and Photos export.

## Getting started

1. Clone the repository.
2. Open `Mixtape.xcodeproj` in Xcode.
3. Select the `Mixtape` scheme and an iOS device.
4. Optionally create `Config/Secrets.xcconfig` and add a Freesound API key.
5. Configure your development team and bundle identifier if device signing requires it.
6. Build and run.

An unsigned command-line build can be used for compilation checks:

```sh
xcodebuild \
  -project Mixtape.xcodeproj \
  -scheme Mixtape \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## Architecture

```text
App/                 # MixtapeApp entry point
Core/                # Theme, shared UI, audio session, navigation helpers
Features/
  Editor/
    Model/            # Timeline, transition, text, audio, and export models
    ViewModel/        # Observable editor state and editing operations
    View/             # Screens and reusable SwiftUI components
    Services/         # Composition, audio extraction, GPU transitions, export, and rendering
  ProjectList/
    Model/            # Persisted project and PhotoKit media models
    ViewModel/        # Project list and media-library state
    View/             # Project list, media picker, and project cards
    Services/         # JSON project storage
```

The UI follows unidirectional data flow: views send user actions to observable view
models, while feature services own AVFoundation, PhotoKit, rendering, and persistence
work.

For the module layout and contribution conventions, see
[Features/README.md](Features/README.md). For the complete editor design, rendering
pipeline, feature guide, and engineering notes, see
[Features/Editor/README.md](Features/Editor/README.md).

## Current limitations

- Color scopes currently analyze a representative selected-clip frame rather than
  continuously sampling every frame during playback.
- Editing is single-selection, with one primary video lane plus multiple independently
  ordered photo-or-video overlay layers.
- Reverse generation is not implemented yet.
- Embedded video audio does not yet display a waveform.
- Projects are local-only and do not yet support packaged media relinking or iCloud sync.
- Automated render-regression and performance test coverage is still limited.

## Roadmap

Phase 1, the Phase 2 keyframe engine, multi-layer video, compositing, and
motion tracking are complete. The next professional milestones are:

1. Reverse playback, freeze frames, and optical-flow options.
2. Professional audio: waveforms/meters, voiceover studio, mixer automation,
   cleanup/mastering, ducking and beat tools, licensed sound libraries, text-to-speech,
   translation/dubbing, stem delivery, and sample-accurate preview/export parity.
3. Captions, stickers, text animation, and reusable title/template systems.
4. Proxy media, render caching, background export, and memory/performance budgets.
5. Project packaging, media relinking, schema migration, recovery, and iCloud sync.
6. Unit, UI, golden-frame, orientation, export, and long-project stress tests.

The detailed, prioritized backlog is maintained in
[Features/Editor/README.md#13-professional-editor-roadmap](Features/Editor/README.md#13-professional-editor-roadmap).
