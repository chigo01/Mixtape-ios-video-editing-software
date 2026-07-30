# Mixtape

Mixtape is a native, phone-first iOS video editor built with SwiftUI, AVFoundation,
Core Image, and an MVVM feature architecture. It provides a continuous multi-clip
timeline, creative transitions, audio and text editing, project persistence, and
configurable video export.

> The project is under active development. Core editing and export flows work,
> while the professional roadmap below tracks the remaining production features.

## Features

### Timeline editing

- Continuous multi-clip preview backed by one `AVMutableComposition` and `AVPlayer`.
- Video and photo clips with trim, split, reorder, speed, volume, and deletion.
- Adjustable photo duration and media insertion at any clip boundary.
- Global timeline with filmstrip thumbnails, text lane, audio lane, scrubbing,
  undo/redo, and extended audio/text tails.
- Autosaved projects that restore clip order, edits, playhead, selections, and title.

### Transitions and creative tools

- 105 categorized transitions across Basic, Camera, Motion, Light, Blur, Glitch,
  Mask, Artistic, and Distortion.
- Opening, between-clip, and closing transitions with adjustable duration.
- Live preview, persistence, undo/redo, and “Apply to all cuts.”
- 35 GPU transitions rendered by an isolated Metal-backed Core Image compositor.
- Orientation-safe portrait, landscape, rotated, video, and generated-photo rendering.
- Text overlays with fonts, color, size, opacity, alignment, position, timeline trim,
  timeline movement, and direct preview dragging.

### Audio

- Imported background-audio clips on a dedicated timeline lane.
- Audio trim, move, split, volume, delete, and multiple simultaneous composition tracks.
- Per-audio-clip fade-in and fade-out rendered with `AVAudioMix` volume ramps.
- Original clip audio with independent per-clip volume.

### Projects and export

- PhotoKit media browser with filters, search, selection ordering, preview, and
  limited-library support.
- Project cards with rename and confirmed deletion.
- JSON project persistence in Application Support.
- Export preview with project-name editing and progress/cancel controls.
- 720p, 1080p, and 4K export; frame-rate, bitrate-quality, format, and optional
  HDR/HEVC settings.
- Explicit `AVAssetReader`/`AVAssetWriter` export pipeline with sharing and Photos save.

## Requirements

- macOS with Xcode and the iOS SDK.
- An iPhone or iPad running iOS/iPadOS 18.6 or later.
- Photo Library access for media import.
- A physical device is recommended for validating GPU transitions, HDR, performance,
  audio routing, and Photos export.

## Getting started

1. Clone the repository.
2. Open `Mixtape.xcodeproj` in Xcode.
3. Select the `Mixtape` scheme and an iOS device.
4. Configure your development team and bundle identifier if device signing requires it.
5. Build and run.

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
    Services/         # Composition, GPU transitions, export, and rendering
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

- The Filter button does not yet provide a complete color/filter workflow.
- Editing is single-selection and uses one primary video lane.
- There are no crop/reframe, keyframe, speed-ramp, reverse, stabilization, or
  chroma-key tools yet.
- Embedded video audio does not yet display a waveform.
- Projects are local-only and do not yet support packaged media relinking or iCloud sync.
- Automated render-regression and performance test coverage is still limited.

## Roadmap

The next professional milestones are:

1. Color filters, manual color correction, LUT import, and scopes.
2. Crop, rotate, flip, reframe, canvas ratios, and background controls.
3. Keyframes for transform, opacity, volume, text, and effects.
4. Speed ramps, reverse playback, freeze frames, and optical-flow options.
5. Multi-layer video/overlay tracks, blend modes, masks, and chroma key.
6. Audio waveforms, meters, ducking, voiceover recording, EQ, and noise reduction.
7. Captions, stickers, text animation, and reusable title/template systems.
8. Proxy media, render caching, background export, and memory/performance budgets.
9. Project packaging, media relinking, schema migration, recovery, and iCloud sync.
10. Unit, UI, golden-frame, orientation, export, and long-project stress tests.

The detailed, prioritized backlog is maintained in
[Features/Editor/README.md#13-professional-editor-roadmap](Features/Editor/README.md#13-professional-editor-roadmap).
