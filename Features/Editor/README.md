# Editor feature tutorial

This document explains **what the Mixtape editing flow does today** — from **New Project and media selection** through the **timeline editor** — **how the pieces fit together**, and **where to learn more** (Apple docs, WWDC, and guides). Read it alongside the source; filenames below point you at the code.

---

## 1. From the home screen to the editor (project + media pick)

The flow before **`EditorScreen`** is: **home list → New Project → pick photos/videos → Next (preload) → editor**. Projects are **saved automatically** as JSON (`EditorProject`) — clip order, trim, speed, volume, text overlays, **background audio clips and fades**, opening/cut/closing transitions, playhead, selection, and **project title** — not raw video files.

### 1.1 App entry and home screen

- **`MixtapeApp`** (`App/MixtapeApp.swift`) hosts **`ProjectListScreen`** in a `WindowGroup`.
- **`ProjectListScreen`** (`Features/ProjectList/View/Screens/ProjectListScreen.swift`) owns a **value-based `NavigationStack(path:)`** driven by a **`ProjectListRoute`** enum (`.createProject` / `.editor(EditorProject)`). All pushes go through **`NavigationLink(value:)`** + a single **`navigationDestination(for: ProjectListRoute.self)`** — destinations are built **lazily** when pushed.
  - **Why value-based?** The old eager `NavigationLink(destination:)` rows built an `EditorScreen` (and its `EditorViewModel` + PHAsset resolution) for **every** row on every render, and combined with `@State(initialValue:)` could push a **stale view model** — tapping the first card opened the *previously*-first project's clips after the list re-sorted by `modifiedAt`.
- **`ProjectListScreen`** lists saved **`EditorProject`** files from **`ProjectStore`**. The list **reloads whenever the path empties** (`onChange(of: path)`), so new projects and edits appear immediately on return — no app restart.
- **Project cards** are fully tappable (explicit **`contentShape`** — clipped `scaledToFill` images don't hit-test across their whole frame otherwise). **Long-press → Delete Project** shows a confirmation dialog, then `ProjectListViewModel.deleteProject` removes the JSON file via `ProjectStore`.
- Each pushed editor gets **`.id(project.id)`** so view-model state can never leak between projects.

### 1.2 New Project screen = library + selection

- **`CreateProjectScreen`** is a thin wrapper around **`MediaLibraryPickerScreen`** (same grid UX, different title / confirm button).
- **`MediaLibraryPickerScreen`** (`Features/ProjectList/View/Screens/MediaLibraryPickerScreen.swift`) owns **`@State private var vm = PhotoLibraryViewModel()`** and is **reused inside the editor** when you tap **+** on the timeline to insert more clips.
- **`.onAppear { vm.requestAccessAndLoad() }`** starts the PhotoKit permission flow and, once **`.authorized`** or **`.limited`**, loads assets.
- **`PhotoLibraryViewModel`** (`Features/ProjectList/ViewModel/PhotoLibraryViewModel.swift`):
  - Fetches **`PHAsset`**s with **`PHAsset.fetchAssets`** (sorted by **`creationDate`**, newest first) and wraps each as **`MediaItem`** (`id` = **`localIdentifier`**, plus **`asset`**).
  - **`selectedIDs: [String]`** stores **selection order**; that order is the order of clips in the editor.
  - **`toggleSelection`** appends or removes IDs; **`selectedItems`** maps IDs back to **`[MediaItem]`** for the editor.
  - **`filteredItems`** applies **`MediaFilter`** (all / photos / videos / favorites) and optional **search** (keywords, creation date string, etc.).
  - Uses **`PHCachingImageManager`** for grid thumbnails (see **`MediaGridItemView`**).
- **Gestures on a grid cell:** **tap** → toggle selection; **long-press** → **`MediaPreviewView`** via **`fullScreenCover(item: $previewItem)`**.
- **Limited photo access:** header **+** calls **`presentLimitedLibraryPicker`** so users can expand which assets are visible.
- **Denied / restricted:** UI prompts **Open Settings** (`openSettings()`).

### 1.3 Next → editor (with preload)

- When **`selectedIDs`** is not empty, **`SelectionBottomBar`** appears in **`safeAreaInset(edge: .bottom)`**.
- **Next** shows **“Preparing…”** while **`EditorCompositionBuilder.warmUp(from:)`** builds the preview composition in the background.
- After preload finishes: **`EditorProject.new(from:)`** is saved via **`ProjectStore`**, then **`CreateProjectScreen`** hands the project back through its **`onProjectCreated`** closure. The home screen **replaces** the create route with the editor route (`path = [.editor(project)]`) — so **back from the editor lands on home**, not on the media picker.
- Clip order in the saved project matches picker **selection order**.

### 1.4 `MediaItem` → `EditorClip`

- **`MediaItem`** (`Features/ProjectList/Model/MediaItem.swift`) is the **picker** model (`PHAsset` + helpers).
- **`EditorProjectResolver.clips(from:)`** rehydrates **`EditorClip`** from **`SavedEditorClip`** (`assetLocalIdentifier` + trim/speed/reframe state) via PhotoKit; **`overlayClips(from:)`** does the same for **`SavedOverlayClip`**.
- **`EditorViewModel(project:)`** loads resolved primary and overlay clips. After this point the editor operates on in-memory edit models, global **`timelinePosition`**, and the shared player.

### 1.5 Pre-editor file map

| Path | Role |
|------|------|
| `App/MixtapeApp.swift` | Root scene → `ProjectListScreen`. |
| `ProjectList/View/Screens/ProjectListScreen.swift` | Home; owns `NavigationStack(path:)` + `ProjectListRoute`; delete with confirmation. |
| `ProjectList/View/Screens/CreateProjectScreen.swift` | Picker → preload → save `EditorProject` → `onProjectCreated` (home swaps in the editor route). |
| `ProjectList/View/Screens/MediaLibraryPickerScreen.swift` | Shared photo grid (new project + add clips in editor). |
| `ProjectList/ViewModel/PhotoLibraryViewModel.swift` | Auth, fetch, filter, search, selection order. |
| `ProjectList/ViewModel/ProjectListViewModel.swift` | Loads / deletes saved projects via `ProjectStore`. |
| `ProjectList/Model/EditorProject.swift` | Codable project document (`SavedEditorClip`, etc.). |
| `ProjectList/Services/ProjectStore.swift` | JSON read/write in Application Support. |
| `ProjectList/Model/MediaItem.swift` | Row model wrapping `PHAsset`. |
| `ProjectList/Model/MediaFilter.swift` | Filter chip enum. |
| `ProjectList/View/Components/SelectionBottomBar.swift` | Count, duration, **Next** with loading state. |
| `ProjectList/View/Components/ProjectCardView.swift` | Home project card; whole card tappable (`contentShape`), text shadows for readability. |
| `ProjectList/View/Components/MediaGridItemView.swift` | Thumbnail cell (with caching manager). |
| `Core/SwipeBackEnabler.swift` | Restores edge-swipe back on screens with hidden nav bars. |

### 1.6 References (PhotoKit, privacy, navigation)

- [PhotoKit](https://developer.apple.com/documentation/photokit) — **`PHAsset`**, **`PHFetchOptions`**, **`PHPhotoLibrary`**, **`PHAuthorizationStatus`** (including **`.limited`**).
- [Delivering an enhanced privacy experience](https://developer.apple.com/documentation/photokit/delivering_an_enhanced_privacy_experience_in_your_photos_app) — limited library, picker.
- [SwiftUI `NavigationStack`](https://developer.apple.com/documentation/swiftui/navigationstack), [`navigationDestination(for:destination:)`](https://developer.apple.com/documentation/swiftui/view/navigationdestination(for:destination:)) — value-based navigation; prefer this over eager `NavigationLink(destination:)` in lists (lazy destinations, no stale state, path can be rewritten programmatically).

### 1.7 Swipe-back with custom top bars

Every pushed screen hides the system chrome (`.toolbar(.hidden, for: .navigationBar)` + `.navigationBarBackButtonHidden(true)`) and draws its own top bar. UIKit then disables `interactivePopGestureRecognizer` — the edge-swipe back gesture — because its default delegate refuses to begin without a visible back button.

**`Core/SwipeBackEnabler.swift`** restores it globally: a `UINavigationController` extension overrides `viewDidLoad` to make every navigation controller (including the one backing `NavigationStack`) its own gesture delegate, allowing the swipe whenever `viewControllers.count > 1` and nothing is presented. The count guard prevents swiping on the root, which would freeze UIKit navigation. Caveat: relies on SwiftUI being UIKit-backed (true through iOS 26).

---

## 2. Mental model: one timeline, many clips

Users think in terms of **one continuous movie** from `0:00` to the end, even when the project is made of **several** `PHAsset`s (photos and videos).

In code we represent that with:

| Idea | Where it lives |
|------|----------------|
| **Global time** (playhead on the ruler) | `EditorViewModel.timelinePosition` — a single `TimeInterval` from `0` to `totalDuration`. |
| **Which asset + time inside it** | `clipAndLocalTime(at:)` maps global time → `(clip, index, localTime)`. |
| **Video-only length** | `videoDuration` = sum of clip timeline durations (trim + speed). Used for filmstrip layout and “hold last frame” past video end. |
| **Full timeline length** | `totalDuration` = `max(videoDuration, overlayEnd, audioEnd, textEnd)` — ruler and playback can extend past the last primary-video frame. |
| **Text on screen** | `textOverlays` with global `startTime`/`endTime`; preview filters by `isVisible(at: timelinePosition)`. |
| **Background music** | `audioClips: [EditorAudioClip]` — each has `timelineStart`, trim range, volume; mixed in composition on separate tracks. |
| **Video overlays** | `overlayClips: [EditorOverlayClip]` — each has source trim, speed, global start, normalized position, scale, opacity, and source-audio volume. |

So: **scrubbing the ruler** or **moving the playhead** updates `timelinePosition` only. The preview then asks: “At this global time, which clip is playing, and where inside that clip?”

**Key file:** `ViewModel/EditorViewModel.swift` — see `timelinePosition`, `clipAndLocalTime(at:)`, `timelineOffsetForClipIndex(_:)`.

**Clip duration on the timeline:** `Features/Editor/Model/EditorClip.swift` — `duration` and `sourceTime(forExportedLocal:)` connect **exported timeline seconds** to **source asset time** (trim + speed).

---

## 3. Architecture overview

**Navigation flow:** `ProjectListScreen` → **`CreateProjectScreen`** (picker) → **`EditorScreen`** (this subtree). The home screen owns the `NavigationStack` path; after project creation the picker route is **replaced** by the editor route, so back always returns home (see **§1.1 / §1.3**).

```
EditorScreen
├── EditorTopBar             ← back, undo/redo, Export → EditorExportScreen
├── EditorPreviewPlayer      ← 9:16 card, AVPlayerLayer, overlay transform handles, text, HUD
├── SpeedToolPanel           ← adaptive bottom sheet for normal/curve speed editing
├── CropReframeToolPanel     ← crop/aspect, fit/fill, rotate/flip, straighten, scale
├── EditorTimeline           ← ruler, text, primary clip, video overlay, and audio lanes
├── EditorBottomToolbar      ← default tools (split, speed, volume, text, overlay)
├── EditorClipActionBar      ← when a clip is selected: back + contextual actions + delete
├── EditorOverlayActionBar   ← overlay split, speed, volume, opacity, resize, reset, text, delete
├── EditorTextActionBar      ← when a text overlay is selected: back + edit + delete
└── EditorAudioActionBar     ← when an audio clip is selected: split, volume, delete

VolumeToolPanel              ← bottom sheet when VOLUME tool active (primary, overlay, or audio)
ColorAdjustmentToolPanel     ← Filters/Adjust/HSL/Curves/Wheels/Masks/Scopes with live GPU preview
OverlayOpacityToolPanel      ← bottom sheet for selected-overlay transparency
OverlayCompositingToolPanel  ← Blend/Mask/Chroma sheet for primary and overlay clips
MotionTrackingToolPanel      ← Stabilize (camera shake) and Track (CapCut-style subject tracking)
TextOverlayEditorSheet       ← bottom sheet (styles, fonts, position); live-syncs to preview
AudioPickerView              ← sheet to import MP3/M4A etc. onto the audio lane
AudioLibraryPickerView       ← bundled + Freesound sound-library browser, inserts at the playhead

EditorExportScreen (pushed from Export)
├── EditorExportPreviewSection ← live composition preview, play/pause, scrub slider
├── Project name field         ← edits projectTitle (saved + used as export filename)
├── Resolution / frame rate / format settings
├── File size estimate
└── Export panel               ← progress, Cancel, Share on complete (plays exported file)
```

- **`EditorViewModel`** (`@MainActor`, `@Observable`): owns primary clips, **`overlayClips`**, **`textOverlays`**, **`audioClips`**, **`projectTitle`**, a **single** `AVPlayer?` backed by an **`AVMutableComposition`**, scrub/seek helpers, editing APIs, undo, persistence, and export orchestration.
- **`EditorCompositionBuilder`** (`Services/`): builds the continuous preview stream from all clips (see **§4**).
- **Views** (`View/Components`, `View/Screens`) are mostly passive: they call `vm.setTimelinePositionForScrub`, `commitTimelineAfterScrub`, `togglePlay()`, etc.

This follows **MVVM + unidirectional data flow**: the view model is the source of truth; SwiftUI observes it and redraws.

**Observation:**

- **`@Observable`** (iOS 17+): Swift tracks which properties views read and updates them efficiently. See [Migrating to the Observable macro](https://developer.apple.com/documentation/swiftui/migrating-from-the-observable-object-protocol-to-the-observable-macro).
- **`@ObservationIgnored`**: used for things that should **not** trigger UI refresh (e.g. `PHCachingImageManager`, `Timer`) — see `EditorViewModel`.
  
---

## 4. Playback: one composition, one player (CapCut-style)

**What we learned the hard way:** swapping a **new `AVPlayer` per clip** causes visible **jump cuts** at every boundary — even when two clips are splits of the **same** video. CapCut feels like “one video” because it plays a **single stitched timeline**.

### 4.1 How it works today

1. **`EditorCompositionBuilder.makePlayerItem(from:audioClips:overlayClips:)`** (`Services/EditorCompositionBuilder.swift`):
   - Creates **`AVMutableComposition`**.
   - For each **`EditorClip`**, inserts the trimmed source range (`trimStart` … `trimEnd`) at the correct **composition time** (sequential cursor).
   - **Videos:** `PHImageManager.requestAVAsset(forVideo:)` → insert video + audio tracks (per-clip volume via **`AVAudioMix`** when not 100%).
   - **Photos:** converts still → short silent video segment (via **`AVAssetWriter`**) so photos sit in the same composition.
   - **Video overlays:** each **`EditorOverlayClip`** gets a separate composition video track at `timelineStart`; source trim, aspect-fit, scale, normalized x/y position, opacity, and optional source audio are rendered above the primary video.
   - **Background audio:** each **`EditorAudioClip`** is inserted on its own composition audio track at `timelineStart` (full trim duration — not capped to video length).
   - **Extended timeline:** when overlay/audio/text content extends past the last primary-video frame, the video track gets an empty tail and video-composition instructions are extended so preview still renders correctly.
2. An **`AVMutableVideoComposition`** applies each source track’s **`preferredTransform`** and **aspect-fits** into a **1080×1920** portrait canvas (matches `EditorPreviewLayout` 9∶16). Without this, iPhone portrait footage looks **rotated / squashed** in the preview. The mutable instruction path is currently intentional: standard transition ramps, encoded backing-video layers, the custom GPU compositor, and offline Core Animation text burn-in all share this instruction model.
3. **`EditorViewModel`** keeps **one** `AVPlayer` whose item is that composition.
4. **`playbackTick`** reads **`player.currentTime()`** → updates **`timelinePosition`**. No manual “advance to next clip” hop.
5. When clips, video overlays, audio, or volume change, **`invalidateComposition()`** forces a rebuild on next align/play. **`clipsFingerprint()`** includes primary clip, overlay transform/timing, and audio state.

**Seeking after scrub:** `alignPlaybackToTimeline()` → `ensureCompositionPlayer()` → `seekPlayerToTimeline()`.

**Warmed composition:** `EditorCompositionBuilder.warmUp` pre-builds primary-video-only items on the picker **Next** screen. `consumeWarmedPlayerItem` is used only when no overlay or audio clips are loaded.

**Poster vs video layer:** `EditorPreviewPlayer` hides the still poster while the video layer is active so you don’t see double images.

### 4.2 Audio on device speaker

**`AudioSessionConfigurator`** (`Core/AudioSessionConfigurator.swift`) sets **`AVAudioSession`** category **`.playback`** at app launch. Without this, preview audio often only plays on AirPods (default **`.soloAmbient`** respects the silent switch and routing quirks).

Configured in **`MixtapeApp.init()`** and before playback starts.

### 4.3 Mental model

| Layer | Responsibility |
|-------|----------------|
| **`EditorClip[]`** | Edit model: trim, speed, per-clip crop/reframe transform, asset ref |
| **`EditorOverlayClip[]`** | Picture-in-picture timing, trim, position, scale, opacity, and audio |
| **`EditorCompositionBuilder`** | Preview/export-shaped **render** of all clips |
| **`AVPlayer`** | Plays global time `0 … totalDuration` |
| **`timelinePosition`** | Same global time; drives ruler + playhead UI |
| **`clipAndLocalTime(at:)`** | Maps global time → which clip is “under” the playhead (for selection, split, HUD) |

The **+ insert slots** on the timeline are **UI-only gaps** (`TimelineLayout.insertSlotWidth`). They affect **pixel layout** of the filmstrip, **not** playback seconds.

### 4.4 Useful reading

- [AVMutableComposition](https://developer.apple.com/documentation/avfoundation/avmutablecomposition) — stitching clips.
- [AVMutableVideoComposition](https://developer.apple.com/documentation/avfoundation/avmutablevideocomposition) — render size, frame duration, animation tools, and custom compositor configuration.
- [AVMutableVideoCompositionLayerInstruction](https://developer.apple.com/documentation/avfoundation/avmutablevideocompositionlayerinstruction) — overlay ordering, transforms, and opacity in the standard compositor.
- [AVVideoCompositing](https://developer.apple.com/documentation/avfoundation/avvideocompositing) — custom-compositor contract used to preserve overlays during GPU transitions.
- [AVAssetTrack.preferredTransform](https://developer.apple.com/documentation/avfoundation/avassettrack/1386708-preferredtransform) — why portrait video looks wrong without a video composition.
- [AVAudioSession](https://developer.apple.com/documentation/avfaudio/avaudiosession) — categories, routing, silent switch behavior.
- [AVFoundation Programming Guide (archive)](https://developer.apple.com/library/archive/documentation/AudioVideo/Conceptual/AVFoundationPG/Articles/03_Editing.html) — **Editing Assets** chapter; still the best conceptual intro to compositions.
- WWDC: search [developer.apple.com/videos](https://developer.apple.com/videos/) for **“Edit and play back HDR video”**, **“Discover advancements in AVFoundation”** — composition + video composition patterns.

### 4.5 Text overlays: preview vs export (two paths)

Text is **not** part of the preview `AVMutableComposition`. Instead:

| Context | How text appears |
|---------|------------------|
| **Editor preview** (inline + fullscreen) | SwiftUI layer — **`EditorTextOverlayLayerView`** composited on top of `PlayerLayerView` / poster. Visibility follows `overlay.isVisible(at: timelinePosition)`. Both canvases scale stored offsets and font size through **`EditorTextOverlayLayout`** so the glyph sits on the same part of the frame. |
| **Export** | Burned in via **`EditorCompositionBuilder.build(from:textOverlays:)`** → **`EditorTextOverlayRenderer`** (SwiftUI → `UIImage` via `ImageRenderer`) → **`AVVideoCompositionCoreAnimationTool`** with per-overlay opacity keyframes timed to `startTime`/`endTime`. The renderer layouts at **`EditorTextOverlayLayout.referenceWidth`** (screen width) then `scaleEffect`s up to the export pixel size. |

**Coordinate contract:** `xOffset` / `yOffset` and `fontSize` are stored in **points as if the canvas were screen-width** — the same space export already used. Live canvases multiply those values by `canvas.width / referenceWidth`. That is why the small inline card and the expanded preview now agree, instead of treating a 50 pt drag as a huge shift on the small card and a small one on the full-screen canvas. Motion-track seed conversion uses that same reference size, not the live `GeometryReader` size.

Preview rebuilds (`makePlayerItem`) call `build(from: clips)` **without** overlays — that is intentional. Only export passes `textOverlays`.

Offline text export attaches `AVVideoCompositionCoreAnimationTool` to the shared
**`AVMutableVideoComposition`**. `enablePostProcessing = true` is used only for
offline instructions that need the animation tool; player items never receive the
Core Animation tool because AVPlayer rejects that offline-only configuration.

**Learn:**

- [AVVideoCompositionCoreAnimationTool](https://developer.apple.com/documentation/avfoundation/avvideocompositioncoreanimationtool) — CALayer burn-in for titles.
- [ImageRenderer](https://developer.apple.com/documentation/swiftui/imagerenderer) — rasterizing SwiftUI for export.

---

## 5. Preview layout and fullscreen

- **Stage aspect ratio:** `vm.canvasSettings.aspectRatio` (`EditorCanvasSettings` in `EditorClip.swift`) — project-level 9∶16, 16∶9, 1∶1, 4∶5, or custom. `EditorPreviewLayout.defaultAspectWidthOverHeight` is only the 9∶16 fallback constant.
- **CapCut-style inline card:** `EditorScreen` constrains the preview with `maxWidth` (screen − 32pt inset) and `maxHeight` (~60% of screen, or chrome-limited). `EditorPreviewPlayer` uses `.aspectRatio(vm.canvasSettings.aspectRatio, .fit)` so the card sizes itself with natural side margins — not edge-to-edge stretch.
- **Video gravity:** inline and fullscreen both use `.resizeAspect` (letterbox inside the canvas). Fullscreen previously used `.resizeAspectFill`, which cropped the frame and made text land on a different part of the picture than the small card.

**Fullscreen:** Tapping the expand control calls `onFullscreen`, which presents a `fullScreenCover` with `EditorFullscreenPreviewSheet`. The **same** `EditorViewModel` (and thus the same `AVPlayer` when applicable) is used so playback state continues. The sheet’s `canvasSurface` is `.aspectRatio(..., .fit)` — the same fitted canvas as the inline card — with close/scrubber chrome **outside** that canvas so overlay math is not stretched to fill the phone.

**`PlayerLayerView`** accepts `videoGravity`. Both the inline player and the fullscreen canvas pass `.resizeAspect`. The host `UIView` has `isUserInteractionEnabled = false` so pans aimed at text/masks/crop chrome are not eaten by the video layer.

**Text overlay chrome** (`EditorTextOverlayLayerView`) is the same view on both canvases. See **§4.5** and **§12.7** for the shared point → canvas scale and the drag gesture.

**Docs:**

- [AVLayerVideoGravity](https://developer.apple.com/documentation/avfoundation/avlayervideogravity)
- [fullScreenCover(isPresented:onDismiss:content:)](https://developer.apple.com/documentation/swiftui/view/fullscreencover(ispresented:ondismiss:content:))

---

## 6. Timeline UI (the interesting part)

### 6.1 Pixels and time

`EditorTimeline` maps **time → horizontal position** with `pixelsPerSecond`. Clip width on screen ≈ `duration * pixelsPerSecond`. The ruler labels are placed the same way so ticks line up with the filmstrip.

**Insert slots (+ buttons):** between each clip thumbnail there is a fixed-width column (`insertSlotWidth`, 28pt). Private struct **`TimelineLayout`** converts between:

- **Global time** (playback seconds, no gaps), and
- **Content X** (filmstrip pixels, includes insert columns),

so the playhead stays aligned with clips even though the UI has visual gaps. Tapping **+** opens **`MediaLibraryPickerScreen`** as a **`fullScreenCover`**; **`EditorViewModel.insertClips(from:afterIndex:)`** splices new **`EditorClip`**s after the tapped clip.

### 6.2 Horizontal scrolling vs scrubbing

`ScrollView(.horizontal)` pans the **whole** timeline content. That conflicts with **drag-to-scrub** if every drag immediately claims the gesture and sets `scrollDisabled(true)`.

Patterns used here:

1. **Ruler + scrub rail:** `DragGesture(minimumDistance: 0)` so taps and drags map **x → time** → `setTimelinePositionForScrub` / `commitTimelineAfterScrub`.
2. **Filmstrip:** larger `minimumDistance` before scrub starts so a short horizontal drag can be interpreted as **scrolling** the strip instead of scrubbing.
3. **Playhead:** the **line** is `allowsHitTesting(false)` so drags pass through to the scroll view; only the **knob** has the scrub gesture (and without `highPriorityGesture` so scrolling wins when you’re not on the knob).
4. **Whole-column panning:** a `GeometryReader` gives the timeline **full height**; the scroll content uses a fixed-height `VStack` plus a `Spacer` and `.contentShape(Rectangle())` so the **empty band under the tracks** is still inside the scroll view and pans horizontally. The **text overlay lane** sits above the clip filmstrip (see **§6.7**).

**Mental checklist:** anything that should **pan** the timeline must live **inside** the scroll content’s bounds vertically, or users will hit “dead” black space.

**Useful reading:**

- [ScrollView](https://developer.apple.com/documentation/swiftui/scrollview)
- [scrollDisabled(_:)](https://developer.apple.com/documentation/swiftui/view/scrolldisabled(_:))
- [Gesture](https://developer.apple.com/documentation/swiftui/gesture), [DragGesture](https://developer.apple.com/documentation/swiftui/draggesture)
- [allowsHitTesting(_:)](https://developer.apple.com/documentation/swiftui/view/allowshittesting(_:))

### 6.3 Selection vs “what you’re watching”

To match a **single continuous** timeline:

- **`setTimelinePositionForScrub`** only updates `timelinePosition` (and pauses). It does **not** change `selectedClipID`.
- **`selectClipForEditing`** sets which clip **split/speed/…** should target, without moving the playhead.
- **Tap** on a thumbnail (in `ClipThumb`) selects it for editing.

So: **orange border** ≈ edit target; **preview** ≈ composition time at `timelinePosition`.

### 6.4 Trim handles (front + back)

When a clip is selected, **`ClipTrimHandleRepresentable`** overlays UIKit trim bars on the thumbnail.

| Piece | Role |
|-------|------|
| **`ClipTrimHandleView.swift`** | `UIViewRepresentable` + `UIPanGestureRecognizer` on left/right handles |
| **`setTrim(clipID:trimStart:trimEnd:)`** | Clamps to valid source range (`EditorClip.minimumSourceSpan`) |
| **`commitTrimEdit()`** | Rebuilds composition + re-seeks preview |

**Why UIKit for handles?** Precise drag clamping and hit-testing are easier with **`hitTest(_:with:)`** so only the handle bars capture touches — the clip body still receives **tap-to-select**.

**Front vs back trim:** `trimStart` / `trimEnd` live on **`EditorClip`**. Timeline cells render a **`ClipFilmstripView`** — multiple `AVAssetImageGenerator` frames tiled across the clip width (see **§12.4**). Clip lane height is **52pt** (compact, room for overlay rows later).

**Learn:**

- [UIViewRepresentable](https://developer.apple.com/documentation/swiftui/uiviewrepresentable)
- [UIPanGestureRecognizer](https://developer.apple.com/documentation/uikit/uipangesturerecognizer)
- [Hit-testing](https://developer.apple.com/documentation/uikit/uiview/1622469-hittest) — passing touches through to SwiftUI below.

### 6.5 Split at playhead

**SPLIT** in **`EditorBottomToolbar`** calls **`performToolAction(.split)`** → **`splitAtPlayhead()`**:

1. **`clipAndLocalTime(at: timelinePosition)`** finds the clip under the playhead.
2. **`EditorClip.split(atSourceTime:)`** returns left/right clips with updated trim ranges (same **`PHAsset`**, different **`trimStart`/`trimEnd`**).
3. Replaces one clip with two in **`clips`**, invalidates composition, re-aligns player.

Split is rejected if the playhead is too close to either edge (~0.25s minimum span).

**Learn:** same composition concepts as §4 — after split, both segments are adjacent ranges in one **`AVMutableComposition`**, so playback stays continuous.

### 6.6 Clip reordering (long-press drag)

Selected clips can be **reordered** by long-pressing and dragging left or right on the timeline. The system is split between **UIKit** (gesture recognition) and **SwiftUI** (visual feedback).

**Gesture layer** (`ClipReorderGestureView.swift`):

- A single **`UILongPressGestureRecognizer`** handles the **entire** drag lifecycle: `.began` → `.changed` → `.ended`. Using one continuous recognizer avoids the "pan can't pick up existing touches" problem that occurs when enabling a separate `UIPanGestureRecognizer` mid-touch.
- On `.began`: records `dragOrigin` (initial touch position), fires a **medium haptic**, and sets `ClipReorderState.isDragging = true`.
- On `.changed`: computes `tx = currentLocation.x - dragOrigin.x` and calls `TimelineClipMetrics.targetIndex(forSource:dragTranslation:)` — which finds where the dragged clip's center would fall among the other clips' centers. A **light haptic** fires each time the proposed destination changes.
- On `.ended` / `.cancelled`: commits the move via `onMove(source, dest)` if the destination differs, then resets all state.

**Shared state** (`ClipReorderState`):

- An `@Observable` class (`@MainActor`) that bridges UIKit → SwiftUI:
  - `draggingSourceIndex` — which clip is being dragged.
  - `proposedDestinationIndex` — where it would land if released.
  - `dragTranslationX` — raw horizontal offset for the dragged clip.
  - `isDragging` — active flag.
- One instance lives as `@State` on `EditorTimeline` and is passed to every `ClipThumb`.

**Visual feedback** (in `clipsRow` within `EditorTimeline.swift`):

| Element | During drag |
|---------|-------------|
| **Dragged clip** | Follows the finger (`.offset(x: dragTx)`), scales up 1.06×, gains drop shadow, slight opacity reduction, `zIndex(100)` to render above everything. |
| **Neighboring clips** in the swap range | Shift left or right by the dragged clip's width using `interactiveSpring` animation, visually opening a gap at the proposed destination. |
| **Insert slots (+)** | Fade to 15% opacity and shift with their neighbor; hit-testing disabled during drag. |
| **Horizontal scroll** | Disabled (`scrollDisabled`) while dragging so the `ScrollView` doesn't compete with the gesture. |

**Metrics** (`TimelineClipMetrics`):

- `leadingEdge(ofClipAt:)` / `centerX(ofClipAt:)` — precise position math for each clip within the HStack.
- `targetIndex(forSource:dragTranslation:)` — walks clip centers to find which slot the dragged clip's center has crossed.

**ViewModel** (`EditorViewModel.moveClip(from:to:)`):

- Removes the clip from `sourceIndex`, inserts at `destinationIndex`.
- Registers undo, pauses playback, invalidates composition, auto-saves.

**Why UIKit for the gesture?** SwiftUI's `LongPressGesture` + `DragGesture` sequencing doesn't support continuous tracking after the hold triggers — UIKit's `UILongPressGestureRecognizer` fires `.changed` on every movement, giving frame-by-frame drag updates.

**Learn:**

- [UILongPressGestureRecognizer](https://developer.apple.com/documentation/uikit/uilongpressgesturerecognizer) — continuous recognizer; `.changed` fires on movement after `.began`.
- [UIViewRepresentable](https://developer.apple.com/documentation/swiftui/uiviewrepresentable) — bridging UIKit gesture views into SwiftUI.
- [interactiveSpring](https://developer.apple.com/documentation/swiftui/animation/interactivespring(response:dampingfraction:blenduration:)) — spring animation tuned for gesture-driven interactions.

### 6.7 Photo clip duration

Photo clips expose a **DURATION** action with presets and a continuous slider. The
selected photo’s right trim handle can also stretch beyond the original default
duration because a still image has no fixed source-video endpoint.

Changing photo duration updates the timeline width and total duration, invalidates
the shared composition, regenerates the encoded still-video segment when needed,
registers undo, and persists through `SavedEditorClip`. Preview and export therefore
use the same selected duration.

### 6.8 Text overlays (timeline + editing)

**Model:** `EditorTextOverlay` (`Model/EditorTextOverlay.swift`) — text, `startTime`/`endTime`, font family/style/size, color, opacity, alignment, `xOffset`/`yOffset`. Offsets and font size are **screen-width points** (`EditorTextOverlayLayout`); live preview scales them to the current canvas. Media overlays stay normalized (−0.75…0.75 of canvas); do not mix the two.

**Adding text:** Tap **TEXT** in `EditorBottomToolbar` or `EditorClipActionBar` → `addTextOverlay()` creates a 3-second overlay at the playhead → opens **`TextOverlayEditorSheet`**.

**Timeline lane:** When `textOverlays` is non-empty, `EditorTimeline` renders a row above the clip filmstrip. Each bar shows truncated text; tap to select; **drag body** to move along the timeline. Selected overlays reuse **`ClipTrimHandleRepresentable`** to drag start/end times (same UIKit trim handles as clips, but times are global seconds).

**Editing:** `TextOverlayEditorSheet` has **Styles** and **Fonts** tabs — font presets, colors, size slider, opacity, alignment, position offsets. Changes call `updateTextOverlay(_:)` live. **Done** commits; empty text on dismiss deletes the overlay.

**Selection chrome:** `EditorScreen` swaps the bottom bar — clip → **`EditorClipActionBar`**; text → **`EditorTextActionBar`**; audio → **`EditorAudioActionBar`**; nothing selected → **`EditorBottomToolbar`**.

**Persistence:** Saved as **`SavedTextOverlay`** inside `EditorProject` JSON. Restored in `EditorViewModel.init(project:)`.

### 6.9 Background audio — multi-track (CapCut-style)

**Model:** `EditorAudioClip` (`Model/EditorAudioClip.swift`) — imported file URL, `timelineStart`, `trimStart`/`trimEnd`, `laneIndex`, `volume`, `split(atSourceTime:)`.

**Lanes:** `laneIndex` mirrors `EditorOverlayClip.laneIndex` — each lane is an independent track, and clips on different lanes are free to **overlap in time**. That is what makes it possible to drop a second piece of audio at the same playhead as an existing clip instead of being pushed to the end of a single track.

**Adding audio:** every **+** (the pinned lane-0 button, the empty-state **Add Audio** button, the
small **+** after a clip's trailing edge, and **ADD AUDIO** on the contextual bar) opens a
`confirmationDialog` — **"Record Voiceover"** (→ `VoiceoverRecorderView`, see **Priority 14**),
**"Browse Sound Library"** (→ `AudioLibraryPickerView`, see **Priority 20**), or **"Import from
Files"** (→ `AudioPickerView`, the `UIDocumentPickerViewController` wrapper) — via
`AudioSourceSheets`, a `ViewModifier` in `EditorScreen.swift`. Whichever is picked ends up calling
`EditorViewModel.loadAudioClip(from:insertion:)` (Files), `insertAudioLibraryItem(...)` (library),
or `insertRecordedVoiceover(fileURL:duration:insertion:)` (recorder), all funneling through the
same **`resolveAudioInsertion(_:)`** placement logic:
- **`.newTrackAtPlayhead`** (the lane-0 **+**, empty-state button, and contextual-bar ADD AUDIO)
  — allocates a new `laneIndex` (`(audioClips.map(\.laneIndex).max() ?? -1) + 1`) and starts the
  clip at `timelinePosition`, so it can sit alongside whatever is already playing.
- **`.afterClip(id)`** (the small **+** after a clip's trailing edge) — appends back-to-back on
  that clip's own lane (the CapCut "extend this track" gesture), unaffected by the playhead.

**Timeline lanes:** `EditorTimeline.audioLanes` groups clips by `laneIndex` the same way `overlayLanePlacements` groups video overlays, rendering one row per track (`AudioClipThumb`) inside a capped-height vertical scroller (~2 tracks tall; more tracks scroll rather than pushing the rest of the timeline chrome down). Select a clip for trim handles; **drag body** to move (including across lanes visually — the model only stores `laneIndex`, so moving a clip does not currently reassign its lane); **drag handles** to trim (parent scroll disabled while trimming).

**Contextual bar:** **`EditorAudioActionBar`** — ADD AUDIO (same "Browse Sound Library" / "Import from Files" / "Record Voiceover" chooser as the lane's own **+**, new track at the playhead), SPLIT (at playhead, same lane), VOLUME (opens **`VolumeToolPanel`**), KEYFRAME, PUNCH IN (Priority 14: marks in/out at the playhead, then re-records that range in place — see the Priority 14 writeup in §13), EFFECTS (Priority 15: opens **`EditorAudioEffectPanel`**, CapCut-style voice/sound presets — see the Priority 15 writeup in §13), DUPLICATE (same lane), DELETE.

**Waveforms:** `Services/AudioWaveformGenerator.swift` decodes real peak-amplitude data per clip (cached in memory + on disk, keyed by a stable hash of the file path) instead of the placeholder noise earlier versions drew.

**Gain staging:** the **MIX** tool (main toolbar) opens `MixToolPanel` — a master-volume slider plus one gain/mute row per track, backed by `EditorViewModel.audioTrackSettings`/`masterVolume` and applied in both preview and export via `EditorCompositionBuilder`. See **Priority 13** in §13 for the full writeup, including why live meters are intentionally not built.

**Composition:** every clip — regardless of lane — already becomes its own composition audio track with its own `AVAudioMixInputParameters` (per-clip volume, keyframed volume ramps, fade in/out). Lanes are a **timeline-UI grouping only**; overlapping clips on different lanes were always mixable at the composition/export layer, they just had no way to be placed or displayed without colliding before this change. Timeline extends past video when music runs long.

**Persistence:** `SavedAudioClip[]` in `EditorProject`, including `laneIndex` (decodes to `0` for projects saved before multi-track support); legacy `SavedAudioTrack` migrates to one clip on decode.

**Layout:** `TimelineLayout` positions video clips using `videoDuration`; ruler width uses `timelineExtent` (= `totalDuration`).

### 6.10 Volume tool

- Tap **VOLUME** (main toolbar, clip bar, or audio bar) → **`VolumeToolPanel`** bottom sheet.
- Targets **selected video clip** (embedded audio) or **selected audio clip** (background music).
- Presets, mute toggle, slider commits on release → `alignPlaybackToTimeline()` rebuilds **`AVAudioMix`**.

### 6.11 Contextual clip action bar

When a clip thumbnail is selected, **`EditorClipActionBar`** replaces the main toolbar (CapCut-style):

- **Back chevron** → `deselectClip()` returns to the main tool row.
- **SPLIT / SPEED / VOLUME / TEXT** → same actions as the main toolbar (`performClipAction`).
- **ADJUST** → clip-only Filters/Adjust workspace with preset intensity, manual color controls,
  reset/copy/paste/apply-to-all, and debounced live preview.
- **DELETE** → `deleteSelectedClip()` (disabled when only one clip remains).

Selecting a clip clears text-overlay and audio selection; selecting text or audio clears the others.

---

## 7. Lifecycle tied to the screen

In `EditorScreen`:

- `.task { await vm.setupPlayer() }` attaches the player (reuses warmed composition when available).
- `.onDisappear { vm.saveNow(); vm.teardownPlayer() }` persists the project, then tears down timers, observers, and composition caches.

When leaving the editor, always save and tear down so you don’t leak `AVPlayer`, timers, or temp photo-video files.

---

## 8. File map (quick reference — editor module)

Paths are under **`Features/Editor/`** unless noted. The **picker / new-project** files live under **`Features/ProjectList/`** and are listed in **§1.5** above.

| Path | Role |
|------|------|
| `View/Screens/EditorScreen.swift` | Editor layout, speed panel, volume sheet, contextual toolbars, text/audio sheets, export navigation. |
| `View/Screens/EditorExportScreen.swift` | Export UI: live preview + scrubber, project name, settings, progress, share. |
| `ViewModel/EditorViewModel.swift` | Timeline, playback, video/text/audio overlays, `projectTitle`, undo, export, auto-save. |
| `Model/EditorExportSettings.swift` | Resolution, frame rate, format enums + size estimate. |
| `Model/EditorSpeedRamp.swift` | Persisted curve points, presets, interpolation, source/timeline mapping, split logic, and deterministic render segments. |
| `Model/EditorOverlayCompositing.swift` | Backward-compatible blend-mode, visibility-mask, and chroma-key settings for overlay layers. |
| `Services/EditorCompositionBuilder.swift` | Shared preview/export composition; primary and overlay video tracks, transforms, transitions, audio mix, backing tracks, and extended timelines. |
| `Services/EditorTransitionCompositor.swift` | Metal-backed custom compositor; invokes color grading, transitions, and overlay composition. |
| `Services/EditorColorGradeRenderer.swift` | Core Image primary controls, 40 filter recipes, cached 3D LUT HSL/RGB-curves/wheels, detail and grain effects. |
| `Services/EditorOverlayCompositingRenderer.swift` | Cached chroma cube, spill suppression, visibility mattes, and Core Image blend-mode routing shared by preview/export. |
| `Services/EditorColorScopeAnalyzer.swift` | Downsampled post-grade pixel analysis for waveform, parade, vectorscope, histogram, and clipping percentages. |
| `Services/EditorFaceMaskDetector.swift` | Vision-assisted face detection that creates editable power-window suggestions from the current composed program frame. |
| `Services/EditorColorMaskTracker.swift` | Bidirectional Vision object tracking that samples clip-relative power-window motion for preview and export. |
| `Services/EditorExportService.swift` | Explicit `AVAssetReader`/`AVAssetWriter` encoding with bitrate/HDR settings, progress/cancel, sanitized project-title filename, and Photos save. |
| `Services/EditorTextOverlayRenderer.swift` | SwiftUI text → `UIImage` for export (`ImageRenderer` + off-screen fallback). |
| `Services/EditorUndoManager.swift` | Snapshot undo/redo stack. |
| `Services/ClipThumbnailService.swift` | Cached multi-frame filmstrip generation. |
| `View/Components/EditorTimeline.swift` | Ruler, text/primary-video/video-overlay/audio lanes, trim/move gestures, scrub, playhead, `TimelineLayout`. |
| `View/Components/ClipFilmstripView.swift` | Tiled thumbnail row per clip. |
| `View/Components/SpeedToolPanel.swift` | Speed/photo-duration controls plus the crop/reframe sheet controls. |
| `View/Components/VolumeToolPanel.swift` | Volume and overlay-opacity sheets. |
| `View/Components/ColorAdjustmentToolPanel.swift` | Categorized filter browser plus primary, HSL, curves, lift/gamma/gain/offset, and scope workspaces. |
| `View/Components/ColorGradeControls.swift` | Reusable interactive tone-curve graph and DaVinci-style color-wheel controls. |
| `View/Components/ColorScopeViews.swift` | SwiftUI Canvas scope plots, vectorscope guides, and shadow/highlight clipping readouts. |
| `View/Components/ColorMaskControls.swift` | Resolve-inspired power windows drawn directly over the program preview, including draggable polygon vertices. |
| `View/Components/OverlayCompositingToolPanel.swift` | Adaptive Blend, Mask, Key, and Shadow editor for primary and overlay clips. |
| `View/Components/CompositingMaskSelectionLayer.swift` | Direct-preview polygon path with draggable custom mask points. |
| `Model/EditorMotionTracking.swift` | CapCut-style tracking box, Gaussian smoothing, stabilization settings, and render adapters. |
| `Services/EditorMotionTracker.swift` | Vision object tracking (generic box, with a hand-pose landmark path for hand subjects) and camera-path analysis on downsampled frames, sampled near source frame rate. |
| `View/Components/MotionTrackingToolPanel.swift` | Stabilize workspace for clips; Track workspace (place box → Start tracking → auto-attaches) for the selected overlay or text. |
| `View/Components/MotionTrackingSelectionLayer.swift` | Direct-preview point crosshair and planar rectangle placement. |
| `View/Components/AudioPickerView.swift` | Document picker for background music import. |
| `Services/VoiceoverRecorderService.swift` | Priority 14 recording engine: `AVAudioRecorder` capture, permission state, input-level meter, takes, interruption/route-change recovery. |
| `View/Components/VoiceoverRecorderView.swift` | Priority 14 recording sheet UI: permission gate, level meter, takes list (preview/retry/delete/use), script + auto-scrolling teleprompter overlay (`ScriptEditorSheet`); doubles as the punch-in recorder via `Mode.punch`. |
| `View/Components/EditorAudioActionBar.swift` | Contextual toolbar when an audio clip is selected; also renders the Priority 14 punch-in in/out marking row in place of the action grid while marking is active. |
| `View/Components/ClipReorderGestureView.swift` | Long-press drag reorder: `UILongPressGestureRecognizer`, `ClipReorderState`, `TimelineClipMetrics`. |
| `View/Components/ClipTrimHandleView.swift` | UIKit trim handles (`UIViewRepresentable`) — clips, text, and audio. |
| `View/Components/EditorPreviewPlayer.swift` | Inline preview, overlay drag/pinch selection layer, text layer, HUD, `PlayerLayerView` (not hittable; overlays own pans). |
| `View/Components/EditorTextOverlayLayerView.swift` | SwiftUI text over inline + fullscreen preview; scales stored points to the live canvas; named-space drag. |
| `View/Components/TextOverlayEditorSheet.swift` | Bottom sheet for text content + style controls. |
| `View/Components/EditorClipActionBar.swift` | Contextual primary-clip and video-overlay action bars. |
| `View/Components/EditorTextActionBar.swift` | Contextual toolbar when a text overlay is selected. |
| `View/Components/EditorTopBar.swift` / `EditorBottomToolbar.swift` | Undo/redo/export + main editing tools. |
| `Model/EditorClip.swift` | Primary and overlay clip models; trim/split, color grade, overlay timing/transform, preview aspect. |
| `Model/EditorColorGrade.swift` | Codable filter catalog, primary controls, eight-band HSL, master/R/G/B curves, and lift/gamma/gain/offset values. |
| `Model/EditorTransition.swift` | Single transition catalog: 105 stable identifiers plus picker title, icon, category, renderer routing, and opening/cut/closing targets. |
| `Model/EditorTextOverlay.swift` | Text overlay model, style enums, and `EditorTextOverlayLayout` (shared preview/export point space). |
| `Model/EditorAudioClip.swift` | Multi-track background audio clip model (trim, move, split, `laneIndex`, volume, fade in/out, keyframes, CC-attribution text). |
| `Model/EditorAudioMixSettings.swift` | Per-track gain/mute (`EditorAudioTrackSettings`) for Priority 13 gain staging. |
| `View/Components/MixToolPanel.swift` | **MIX** tool sheet: master volume, per-track gain/mute/solo, and inline track renaming. |
| `Model/EditorAudioEffect.swift` | Priority 15 voice/sound effect presets, built from `AVAudioUnit` effects. |
| `Services/EditorAudioEffectRenderer.swift` | Priority 15 offline `AVAudioEngine` effect renderer + disk cache. |
| `View/Components/EditorAudioEffectPanel.swift` | **EFFECTS** tool sheet: Filters/Characters tabbed preset grid for the selected audio clip, "Original" pinned first. |
| `Model/EditorAudioLibraryItem.swift` | Source-agnostic sound-library item, category/license/source types, and the `EditorAudioLibraryProviding` protocol. |
| `ViewModel/AudioLibraryViewModel.swift` | Sound Library sheet state: merges bundled + Freesound search results, favorites, audition playback, resolve/download. |
| `View/Components/AudioLibraryPickerView.swift` | Sound Library sheet UI: search, category chips, Bundled/Freesound sections, attribution confirm. |
| `Services/AudioLibraryCache.swift` | Actor-based, budget-capped on-disk cache for downloaded library sounds, shared across projects. |
| `Services/FreesoundAudioLibraryProvider.swift` | Freesound API search + license mapping; remote `EditorAudioLibraryProviding` conformer. |
| `Services/AudioWaveformGenerator.swift` | Real per-clip waveform decoding (`AVAudioFile`) with in-memory + on-disk caching. |
| `Model/EditorTimelineSnapshot.swift` | Undo snapshot for primary/overlay clips, endpoints, playhead, selections, text, and audio. |
| `Model/EditorTool.swift` | Tool enum, including selected-clip color adjustment routing. |
| `ProjectList/Model/EditorProject.swift` | Backward-compatible Codable document (`SavedEditorClip`, `SavedOverlayClip`, text/audio DTOs). |
| `ProjectList/Services/ProjectStore.swift` | JSON persistence in Application Support. |
| `Core/AudioSessionConfigurator.swift` | Speaker / headphone routing for preview audio. |
| `Core/SwipeBackEnabler.swift` | Edge-swipe back despite hidden nav bars (see **§1.7**). |

---

## 9. WWDC and deeper dives (video + articles)

**SwiftUI & gestures**

- WWDC sessions on SwiftUI layout and scroll views (search [Apple Developer Videos](https://developer.apple.com/videos/) for “SwiftUI ScrollView” / “Gestures”).

**AVFoundation (editing mindset)**

- Even before a full **AVComposition** pipeline, understanding **timebases**, **CMTime**, and **seek tolerances** pays off: [CMTime](https://developer.apple.com/documentation/coremedia/cmtime), [AVPlayer seek](https://developer.apple.com/documentation/avfoundation/avplayer/1385953-seek).

**Photos**

- [PhotoKit overview](https://developer.apple.com/documentation/photokit) — permissions, `PHAsset`, image vs video requests.

**Composition + export**

- Preview calls **`EditorCompositionBuilder.build(from:audioClips:overlayClips:frameRate:)`** (no text overlays in the player item). Export calls **`build(from:textOverlays:audioClips:overlayClips:frameRate:)`** — the same canvas, primary/overlay transforms, and audio mix, plus offline text burn-in. Export passes the user's frame-rate setting and **`projectTitle`** for the output filename via `EditorExportService`.

**SwiftUI + UIKit together**

- [Integrating UIKit with SwiftUI](https://developer.apple.com/documentation/swiftui/uikit_integration) — trim handles pattern.

**Cursor + Xcode on the same repo**

- Edit Swift in **Cursor**; create/move files and targets in **Xcode** when possible so `project.pbxproj` stays consistent.
- After moving files in Finder/Cursor, expect red missing references in Xcode until you fix groups or re-add files.
- Ignore **`xcuserdata`**, **`.DS_Store`**, **`build/`** in git.

---

## 10. Suggested learning order

1. Trace **home → `CreateProjectScreen` → `MediaLibraryPickerScreen` → `EditorScreen(project:)`** so you see how **selection order** becomes a saved **`EditorProject`** and timeline order.
2. Read **`EditorClip.duration`**, **`trimStart`/`trimEnd`**, and **`clipAndLocalTime(at:)`** until you can predict which clip owns any **`timelinePosition`**.
3. Read **`EditorCompositionBuilder.makePlayerItem`** top to bottom — that is the core of “one continuous preview.”
4. Trace **`togglePlay` → `ensureCompositionPlayer` → `playbackTick`** and watch **`timelinePosition`** track **`player.currentTime()`**.
5. Trace **`setTimelinePositionForScrub` → `commitTimelineAfterScrub` → `alignPlaybackToTimeline` → `seekPlayerToTimeline`**.
6. In **`EditorTimeline`**, follow **`TimelineLayout.contentX(forTime:)`** and the **+ insert slot** column — confirm playback time does **not** include gap seconds.
7. Select a clip → drag trim handles → **`commitTrimEdit`** → watch composition rebuild.
8. Park playhead mid-clip → **SPLIT** → play through the cut and notice **no player swap** (same composition, two source ranges).
9. In the simulator: scrub ruler vs drag filmstrip vs tap-to-select vs trim handle drag — map each to the gesture / hit-test code.
10. Tap **TEXT** → edit in **`TextOverlayEditorSheet`** → scrub through the overlay's time range and confirm preview text appears/disappears. Drag the selected glyph on the **inline** card, then open fullscreen and confirm it sits on the same part of the frame. Export and confirm text is burned into the file.
11. Select a clip → use **`EditorClipActionBar`** → **DELETE** (with 2+ clips) or **reorder** via long-press drag.
12. Open an opening, cut, and closing transition → preview GPU and standard styles → confirm cancel, undo, persistence, and export parity.
13. Tap **Export** → preview/scrub on **`EditorExportScreen`** → set project name → configure settings → export → confirm Photos + Share (filename = sanitized project title).
14. Add background music → trim/move/split → adjust volume/fades → confirm playback past video end if music is longer.
15. Edit → leave editor → reopen from **`ProjectCardView`** on home — confirm `ProjectStore` round-trip (clips, transitions, text, audio, fades, title).

---

## 11. Changelog (recent editor work)

Use this as a map of **what we built** and **why**, in learning order:

| Feature | What it does | Key files | Concept to study |
|---------|----------------|-----------|------------------|
| **Shared media picker** | Same grid for new project + add clips | `MediaLibraryPickerScreen`, `CreateProjectScreen` | SwiftUI composition, `fullScreenCover` |
| **Insert clip (+)** | Add media after any clip on timeline | `EditorTimeline`, `EditorViewModel.insertClips` | Ordered array editing, composition invalidation |
| **Insert slot layout** | + lives in gap columns; playhead still accurate | `TimelineLayout` in `EditorTimeline.swift` | UI layout ≠ playback time |
| **Audio on speaker** | Preview heard without AirPods only | `AudioSessionConfigurator`, `MixtapeApp` | `AVAudioSession` categories |
| **Trim handles** | Drag start/end of clip source range | `ClipTrimHandleView`, `setTrim` | UIKit gestures in SwiftUI, clamping |
| **Split** | Cut clip at playhead into two | `splitAtPlayhead`, `EditorClip.split` | Non-destructive trim ranges on same asset |
| **Composition playback** | Smooth play through all clips | `EditorCompositionBuilder`, `EditorViewModel` | `AVMutableComposition` |
| **Orientation fix** | Portrait video not rotated in preview | `AVMutableVideoComposition`, `preferredTransform` | Video composition transforms |
| **Export** | Render timeline → MP4/MOV → Photos | `EditorExportService`, `EditorTopBar` Export | `AVAssetReader`, `AVAssetWriter` |
| **Undo / Redo** | Snapshot restore after edits | `EditorUndoManager`, `EditorTimelineSnapshot` | Command / memento pattern |
| **Speed tool** | Normal 0.25×–3× plus editable 0.1×–8× speed curves and six presets | `EditorSpeedRamp`, `SpeedToolPanel`, `EditorCompositionBuilder.insertSpeedAdjusted` | Shared source/timeline mapping and segmented rate rendering |
| **Crop and reframe** | Crop presets, Fit/Fill, rotate, flip, straighten, scale, position, guides | `CropReframeToolPanel`, `EditorReframeSelectionLayer`, `EditorCompositionBuilder.reframeTransform` | Persistent affine transform shared by preview/export |
| **Filmstrip thumbnails** | Multiple frames tiled per clip cell | `ClipFilmstripView`, `ClipThumbnailService` | `AVAssetImageGenerator` batching |
| **Project persistence** | JSON project files; home list opens saved edits | `EditorProject`, `ProjectStore`, `ProjectListViewModel` | Codable + PhotoKit rehydration |
| **Picker preload** | “Preparing…” on Next warms composition before editor | `EditorCompositionBuilder.warmUp`, `CreateProjectScreen` | Perceived performance |
| **Dedicated export screen** | Resolution / FPS / format settings + progress panel | `EditorExportScreen`, `EditorExportSettings` | Export configuration and progress state |
| **Smooth editor entry** | Composition build off main actor; deferred thumbnail load | `EditorViewModel`, `EditorScreen.task` | Main-thread responsiveness |
| **Value-based home navigation** | Fixes “tap project A, open project B”; lazy destinations | `ProjectListRoute`, `ProjectListScreen` | `NavigationStack(path:)`, view identity |
| **Create flow back-stack** | Back from editor skips picker; list refreshes on return | `CreateProjectScreen.onProjectCreated`, `onChange(of: path)` | Programmatic path rewriting |
| **Project delete** | Long-press card → confirm → remove JSON | `ProjectListScreen`, `ProjectListViewModel.deleteProject` | `contextMenu`, `confirmationDialog` |
| **Card polish** | Whole card tappable; scrim overlay removed | `ProjectCardView` (`contentShape`) | Hit-testing clipped images |
| **Swipe-back restore** | Edge swipe pops despite hidden nav bars | `Core/SwipeBackEnabler.swift` | `interactivePopGestureRecognizer` delegate |
| **Clip reorder** | Long-press + drag to move clips forward/backward on timeline | `ClipReorderGestureView`, `EditorTimeline.clipsRow`, `EditorViewModel.moveClip` | `UILongPressGestureRecognizer` as continuous gesture, `@Observable` UIKit→SwiftUI bridge, `interactiveSpring` |
| **Text overlays** | Add/edit/delete overlays; timeline lane; preview layer; export burn-in | `EditorTextOverlay`, `EditorTextOverlayLayout`, `TextOverlayEditorSheet`, `EditorTextOverlayLayerView`, `EditorTextOverlayRenderer`, `EditorCompositionBuilder` | SwiftUI overlay vs `AVVideoCompositionCoreAnimationTool`; shared screen-width point space |
| **Video overlays** | Add, trim, move, split, resize, position, reset, delete, persist, and export picture-in-picture clips | `EditorOverlayClip`, `EditorTimeline`, `EditorOverlaySelectionLayer`, `EditorCompositionBuilder` | Multi-track `AVMutableComposition` + standard/custom video compositing |
| **Contextual toolbars** | Clip-selected and text-selected bottom bars (CapCut-style) | `EditorClipActionBar`, `EditorTextActionBar`, `EditorScreen` | Conditional chrome swapping |
| **Clip delete** | Remove selected clip (min 2 clips); playhead + selection adjust | `EditorClipActionBar`, `deleteSelectedClip` | Array editing + composition invalidation |
| **Text preview drag** | Drag selected overlay on inline or fullscreen preview; finger 1:1; same relative spot on both canvases | `EditorTextOverlayLayerView`, `beginTextOverlayPositionDrag`, `updateTextOverlayPositionDrag` | Named-space `DragGesture`; `contentShape` before offset; translation ÷ canvas scale |
| **Text style undo** | Sheet edits + position drag register one undo step | `beginTextOverlayEdit`, `finalizeTextOverlayEdit`, `TextOverlayEditorSheet` | Memento pattern (same as speed/trim) |
| **Background audio** | Import/library-insert, trim, move, split, delete; independent overlappable tracks | `EditorAudioClip.laneIndex`, `AudioClipThumb`, `EditorAudioActionBar`, `AudioPickerView`, `AudioLibraryPickerView` | Multi-track `AVMutableComposition` + `AVAudioMix`, one composition track per clip regardless of lane |
| **Sound library** | Bundled starter SFX + live Freesound search, favorites, audition, attribution confirm | `AudioLibraryViewModel`, `BundledAudioLibraryProvider`, `FreesoundAudioLibraryProvider`, `AudioLibraryCache` | `@MainActor` provider protocol, `actor`-based download cache, `AVPlayer` streaming preview |
| **Audio waveforms** | Real per-clip waveform display, decoded once and cached | `AudioWaveformGenerator`, `AudioClipThumb` | `AVAudioFile` PCM peak analysis, memory + disk cache keyed by FNV-1a path hash |
| **Volume tool** | Per-clip and per-audio volume with live preview | `VolumeToolPanel`, `commitVolume`, `commitAudioVolume` | `AVAudioMixInputParameters` |
| **Extended timeline** | Audio/text can extend past video; composition aligned | `totalDuration`, `videoDuration`, `segmentsCoveringTimelineExtent` | Composition duration vs video-composition instructions |
| **Export preview** | Live player, scrub slider, play/pause on export screen | `EditorExportPreviewSection` | Reuses editor `AVPlayer` + exported-file player |
| **Project name on export** | Rename before export; persists to JSON | `commitProjectTitle`, export screen `PROJECT NAME` field | Debounced `ProjectStore` save |
| **Export filename** | Shared file uses sanitized project title | `EditorExportService.sanitizeFileName` | Filesystem-safe naming |
| **Export quality / bitrate** | Mbps tiers + HDR/HEVC; writer-based encode | `EditorExportQuality`, `EditorExportService.exportWithWriter` | `AVAssetWriter` + `AVVideoAverageBitRateKey` |
| **Home project rename** | Long-press card → rename with immediate persistence | `ProjectListScreen`, `ProjectListViewModel.renameProject` | Context menus, validation, persistence |
| **Audio edge fades** | Per-audio-clip fade-in/out controls and render ramps | `EditorAudioClip`, `VolumeToolPanel`, `EditorCompositionBuilder` | `AVAudioMixInputParameters.setVolumeRamp` |
| **Transition catalog** | 105 categorized opening/cut/closing choices in a separate model file | `EditorTransition`, `EditorScreen` | Stable persisted identifiers, metadata-driven UI |
| **GPU transition engine** | 35 blur/color/distortion/mask effects with orientation-safe rendering | `EditorTransitionCompositor`, `EditorCompositionBuilder` | Custom `AVVideoCompositing`, Core Image, Metal |
| **Motion tracking** | CapCut-style tracking box, smoothing, tracked text/overlays, and clip stabilization crop | `EditorMotionTracking`, `EditorMotionTracker`, `MotionTrackingToolPanel` | Vision object tracking, image registration, inverse camera path |
| **Green-frame prevention** | Encoded black/white backing tracks initialize every exported pixel | `EditorCompositionBuilder` | YUV surfaces, alpha, letterboxing, export parity |
| **Opening and closing edges** | Project-level entrance/exit transitions stay on true timeline endpoints | `EditorTransitionTarget`, `EditorViewModel`, `EditorTimeline` | Endpoint state, undo, backward-compatible Codable |

---

## 12. Feature guide (export, undo, speed, filmstrip, persist)

### 12.1 Export

- Tap **Export** in `EditorTopBar` → navigates to **`EditorExportScreen`**.
- **Preview section:** live composition playback (same `AVPlayer` as editor), play/pause, **scrub slider** with current/total time. After export completes, preview switches to the exported file.
- **Project name:** editable field — updates `projectTitle`, auto-saved on leave/export; also used as the **export filename** (`My Project.mp4`, sanitized).
- Configure **resolution** (720p / 1080p / 4K), **frame rate** (24–120), **quality** (Efficient / Balanced / High / Max with target Mbps), optional **HDR (HEVC 10-bit)**, and **format** (MP4 / MOV).
- **File size** estimate uses the selected video bitrate + AAC audio.
- Tap **EXPORT PROJECT** → `EditorViewModel.startExport(settings:)` → `EditorExportService.export(…, projectTitle:)` using **`EditorCompositionBuilder.build(from:textOverlays:audioClips:overlayClips:frameRate:)`** — primary clips + video overlays + text burn-in + mixed audio.
- Bottom **progress panel**: percentage, linear bar, **Cancel** while rendering.
- On success: saved to Photos + **Share** sheet (filename reflects project title) and **Done**.
- Requires **Photo Library Add** permission (`NSPhotoLibraryAddUsageDescription`).

### 12.2 Undo / Redo

- **Undo** / **Redo** buttons live in `EditorTopBar` (next to back).
- `EditorUndoManager` stores **`EditorTimelineSnapshot`** (`clips`, `overlayClips`, `timelinePosition`, primary/overlay/audio selections, `textOverlays`, `audioClips`).
- Registered automatically on: **split**, **insert**, **trim commit**, **speed change** (when SPEED panel closes), **volume commit**, **text overlay** add/delete/style/position/time-range edits, **clip delete**, **clip reorder**, **audio** trim/move/split/delete/volume.
- After restore: `invalidateComposition()` + `alignPlaybackToTimeline()`.

### 12.3 Speed tool

- Tap **SPEED** in the bottom toolbar → `SpeedToolPanel` appears above the timeline.
- Select a clip first. Use presets (0.5×–2×) or the slider (0.25×–3×).
- `EditorClip.speed` drives timeline width (`duration`) and `sourceTime(forExportedLocal:)`.
- `EditorCompositionBuilder` applies **`scaleTimeRange`** on inserted video/audio segments so playback matches the ruler.

#### 12.3.1 Speed ramps

- **Normal / Curve modes:** the SPEED panel keeps the existing constant-rate controls and adds a dedicated curve workspace for selected primary video clips.
- **Presets:** Montage, Hero, Bullet, Flash, Speed Up, and Slow Down provide editable starting curves from 0.1× to 8×.
- **Curve editor:** control points drag vertically to set speed and horizontally to set source-relative timing. Endpoint timing stays locked to the clip edges; intermediate points can be added at the playhead or largest open interval and removed independently.
- **Interpolation:** Linear and Smooth modes share the same persisted `EditorSpeedRamp` model. The graph uses a logarithmic speed axis so slow-motion values remain as editable as high-speed values.
- **Timing model:** points live in normalized source time. `EditorSpeedRamp` produces one bounded render plan used for clip duration, source seeking, playhead display, splitting, preview, and export, preventing separate timing implementations from drifting.
- **Rendering:** AVFoundation has no continuous composition-track rate curve, so `EditorCompositionBuilder` samples the curve into bounded contiguous source slices and scales each slice deterministically. Video and embedded source audio use the identical plan.
- **Editing integrity:** presets, point changes, interpolation, reset, clip duplication/replacement, split, undo/redo, autosave, reopen, timeline width, transitions, and composition fingerprints all carry ramp state. Older projects decode `speedRamp` as `nil` and keep their normal speed.
- **Timeline feedback:** ramped clips show a Curve badge, and the curve graph displays the current source-relative playhead.

### 12.4 Thumbnail filmstrip

- Each `ClipThumb` renders a **`ClipFilmstripView`** instead of a single poster frame.
- `ClipThumbnailService` samples multiple times across `trimStart…trimEnd` with `AVAssetImageGenerator`.
- Frame count scales with clip width (~1 frame per 26pt). Results are cached per clip/trim/speed.

### 12.5 Persist projects

- Projects are **`EditorProject`** JSON files in **Application Support / MixtapeProjects**.
- Stores **`SavedEditorClip`** (`assetLocalIdentifier`, trim, speed, volume, crop/reframe state, cut transition), **`SavedTextOverlay`**, **`SavedAudioClip`** (file path, trim, `timelineStart`, volume, fades), project-level opening/closing transitions, **`title`**, playhead, and selection — not raw video bytes.
- Legacy **`SavedAudioTrack`** in older JSON files migrates to `audioClips` on decode.
- **New project:** `CreateProjectScreen` saves on Next, then opens `EditorScreen(project:)`.
- **Resume:** `ProjectListScreen` lists saved projects via **`ProjectListViewModel`**; tap anywhere on a **`ProjectCardView`** to reopen. The list re-sorts by `modifiedAt` and reloads each time the navigation path empties.
- **Delete:** long-press a card → **Delete Project** → confirmation dialog → `ProjectStore.delete(id:)` removes the JSON file.
- **Home card UI:** cover thumbnail from first clip; title and clip count use **text shadows** for readability (the old gradient scrim overlay was removed).
- **Auto-save:** `EditorViewModel.scheduleSave()` debounces (~700ms) after edits; `saveNow()` on leave.

### 12.6 PhotoKit thumbnail loading (home + export)

- **`ProjectCardView.loadCover()`** must **not** use `withCheckedContinuation` with `.opportunistic` delivery — PhotoKit may call the handler **twice** (degraded preview, then final). Assign `coverImage` directly in the callback instead.
- Same pattern as **`MediaThumbnailView`**: callback → `@MainActor` state update, no single-resume continuation.

### 12.7 Text overlays

- Tap **TEXT** (main toolbar or clip action bar) → overlay spawns at playhead (default 3 s) → **`TextOverlayEditorSheet`** opens.
- **Styles tab:** font style chips, color palette, size slider, opacity, horizontal/vertical alignment, position offsets.
- **Fonts tab:** system + bundled iOS font families.
- **Preview:** `EditorTextOverlayLayerView` filters overlays by `isVisible(at: timelinePosition)` and is the same view on the inline card, fullscreen sheet, and export-screen preview. Stored `xOffset` / `yOffset` / `fontSize` are screen-width points (`EditorTextOverlayLayout`); each canvas scales them by `canvas.width / referenceWidth` so the glyph does not jump when you expand the preview.
- **Timeline:** dedicated lane above clips; tap bar to select; drag body to move; drag trim handles for `startTime`/`endTime`.
- **Preview drag:** select a text overlay, then drag the glyphs (or the orange box) on the inline or fullscreen preview. Hit-testing uses `contentShape` **before** `.offset()` so the grab target follows the visual text, not the un-offset alignment slot. The gesture lives in a named canvas coordinate space (`textOverlayCanvas`) so translation does not fight the moving view; `updateTextOverlayPositionDrag` divides that translation by the canvas scale to write reference points (the same numbers as the sheet sliders). If a text-position keyframe track already exists, the drag upserts at the playhead so `resolved()` does not ignore the finger. `PlayerHostView` is not hittable, so missed pans are not swallowed by the video layer.
- **Export:** `EditorTextOverlayRenderer` rasterizes each overlay at `referenceWidth` then scales to the render size → `CALayer` + opacity/transform keyframe animation in `EditorCompositionBuilder` (see **§4.5**).
- **Empty text on dismiss** auto-deletes the overlay.

### 12.8 Background audio

- Tap any **+** (lane, empty-state, or the contextual bar's **ADD AUDIO**) → chooser: **Import
  from Files** (`AudioPickerView`, copied into the app sandbox) or **Browse Sound Library**
  (`AudioLibraryPickerView` — bundled SFX + Freesound search, see **§6.9** and **Priority 20**).
- **Select** a bar → **`EditorAudioActionBar`**: add audio, split at playhead, volume sheet,
  keyframe, duplicate, delete.
- **Trim** with left/right handles (UIKit, same pattern as clips); **move** by dragging the
  selected bar body. Clips live on independent, overlappable **tracks** — see **§6.9**.
- **Split** creates two adjacent audio clips from one source file at the playhead-local time.
- Waveform bars show real decoded audio, not a placeholder — see **`AudioWaveformGenerator`** in
  **§6.9**.
- Volume changes rebuild the composition mix (`AVAudioMix`).
- **Fade in / fade out:** the audio volume sheet exposes edge-duration sliders. Values are persisted per audio clip and rendered as linear `AVAudioMix` volume ramps in preview and export.
- Timeline ruler extends when music is longer than video; preview holds the last video frame in the tail.
- **Export** includes all audio clips mixed under the video.

### 12.9 Video overlays

- Tap **OVERLAY** in the main toolbar (or **+** on an existing overlay lane) to open a video-only PhotoKit picker. Selected videos are inserted from the current playhead; multiple selections are placed sequentially.
- **Timeline modes:** normal editing collapses all overlay content into one compact summary line, preserving room for primary clips, text, and audio. Tap the summary or the main **OVERLAY** tool to enter the dedicated overlay workspace. Every imported overlay owns a persistent numbered row (`Overlay 1`, `Overlay 2`, …); split pieces remain on their parent's row. The workspace is a compact, fixed-height viewport directly below the primary timeline; only its overlay-row child list scrolls vertically. Selecting or importing a hidden row automatically scrolls that row into view.
- **Adding another layer:** **ADD OVERLAY** is available from both the main toolbar and the selected-overlay action bar. Each imported clip starts from the current insertion sequence and receives a new persistent row, even when its time range would not overlap another overlay. Later-added overlapping clips render above earlier ones.
- **Context actions:** selecting an overlay keeps the normal clip tools that apply to it — split, speed, volume, and text — and adds overlay-specific opacity, smaller/larger, reset, and delete controls. The action row scrolls horizontally so the complete set remains accessible on narrow phones.
- **Timing and sound:** overlay speed is persisted and scales both its video and source audio in preview/export; volume controls only that overlay's source-audio mix.
- **Canvas editing:** a selected, currently visible overlay gets an aspect-aware selection border in inline and fullscreen preview. Drag the body to reposition; pinch anywhere on the selection or drag its top-right resize handle to scale. Position and scale are saved as normalized canvas values, so 720p, 1080p, and 4K exports match the preview.
- **Rendering:** each overlay uses its own video and optional audio composition tracks. The standard compositor receives overlay `AVMutableVideoCompositionLayerInstruction`s. GPU transition instructions carry immutable `EditorOverlayRenderLayer` values, and `EditorTransitionCompositor` composites those frames after the primary transition effect.
- **Professional compositing:** **COMPOSITE** opens Blend, Mask, Chroma/Luma, and Shadow workspaces for primary and overlay clips. Sixteen Core Image blend modes mix against the canvas or completed lower stack. Ellipse, rectangle, linear, and 3–24 point custom polygon masks support feather, matte expansion/contraction, opacity, and inversion; polygon points drag directly on the preview. Chroma keying uses a cached 32³ chroma-distance cube with tolerance, softness, spill suppression, and edge desaturation. Luma keying isolates highlights or shadows, and post-matte shadows provide opacity, blur, distance, and direction.
- **Performance:** neutral overlays remain on AVFoundation's standard compositor. The custom GPU compositor is enabled only when a grade, keyframe animation, blur canvas, transition, blend mode, mask, chroma key, motion attachment, or stabilization requires it. Chroma cubes are cached by settings, and slider-driven preview rebuilds are debounced.
- **Project integrity:** `SavedOverlayClip` is decoded with defaults and `overlayClips` defaults to `[]`, so projects saved before this feature continue to open. Overlay mutations participate in snapshot undo/redo, composition fingerprints, debounced saves, reopen, and export.
- **Current scope:** the overlay picker accepts video assets. Still-image overlays can later reuse the model after an alpha-safe image rendering path is added; the existing H.264 still generator intentionally paints an opaque canvas and is therefore not reused for overlays.

### 12.9.1 Crop and reframe

- Select a primary video or photo clip and tap **CROP**. `CropReframeToolPanel` exposes **Fit/Fill**, Original/9:16/16:9/1:1/4:5 crop presets, clockwise 90° rotation, horizontal and vertical flips, ±45° straighten, 50–400% scale, center, and full reset.
- While the panel is open, drag directly on the preview to reposition the media and pinch to scale it. The crop boundary, optional 90% safe area, and rule-of-thirds grid remain visible above the player.
- `EditorClip` owns the complete reframe state (`cropAspect`, `reframeMode`, rotation, straighten, flips, scale, and normalized x/y position). Split clips inherit it, undo snapshots copy it, and `SavedEditorClip` decodes absent fields with neutral defaults so older projects remain compatible.
- `EditorCompositionBuilder.reframeTransform` normalizes the asset's preferred orientation, applies the selected crop and Fit/Fill scale, then applies rotation, flip, straighten, scale, and normalized translation around the canvas center. Both standard `AVMutableVideoCompositionLayerInstruction` rendering and the GPU transition compositor consume that same base transform, giving preview/export parity.
- Fit preserves the selected framing region against the black canvas background; Fill covers the full canvas and crops overflow at its edges. All mutations invalidate the composition fingerprint and rebuild at the current playhead after the gesture or slider commits.

### 12.10 Project rename and clip transitions

- **Home rename:** long-press a `ProjectCardView` → **Rename Project** → edit and save. The title is persisted immediately and the project list refreshes in modified-date order.
- **Opening, cut, and closing controls:** the leading-edge button applies a persisted entrance transition to clip one; every gap between adjacent clips has its own transition button plus a smaller add-media button; and the final slot combines a project-level exit transition with the existing add-media action. Endpoint state belongs to the project—not an asset—so reordering or appending clips keeps entrance and exit effects on the true timeline edges.
- **Transition browser:** tap any opening, cut, or closing control to open a categorized sheet with 105 choices across Basic, Camera, Motion, Light, Blur, Glitch, Mask, Artistic, and Distortion. The catalog now includes additional swing/orbit/flip-zoom/bounce camera moves, compress/stretch/pan/skew motion, four-direction blur, radial/soft blur, glass/torus/triangle distortion, vortex/pinch/bump effects, hue/invert/posterize/photo-process treatments, heat shift, and edge glow.
- **GPU transition engine:** 35 options marked **GPU** use the isolated `EditorTransitionCompositor.swift` pipeline. Core Image runs on Metal when available and provides real blur, pixel, color, artistic, distortion, glass, lens, mirror, glitch, and shader-mask processing. The standard Apple compositor remains active unless a GPU transition is selected.
- **Render architecture:** immutable `EditorTransitionRenderInstruction` values carry only track IDs, timing, transforms, and transition metadata. Preview and export instantiate the same serial GPU compositor and render into BGRA Metal-compatible buffers. The compositor never reaches into view-model or mutable editor state.
- **Orientation normalization:** the custom compositor converts each complete AVFoundation transform into Core Image pixel-buffer coordinates using the decoded source and render dimensions. Portrait, landscape, rotated, and generated-photo clips therefore retain their original presentation orientation throughout GPU effects.
- **Color-space safety:** the GPU path explicitly advertises an 8-bit SDR working space, so AVFoundation conforms HDR/wide-color inputs before rendering rather than passing unsupported 10-bit frames. Projects that use only standard transitions keep the existing Apple compositor and its current color behavior.

### Color grading and scope behavior

- The grade is non-destructive and stored per clip. Splits inherit it; reset, copy, paste, Apply all, undo, autosave, reopen, preview, and export all use the same `EditorColorAdjustment` contract.
- Primary controls and filter recipes stay in Core Image. Selective HSL, master/R/G/B curves, and four tonal wheels are fused into a cached 24³ color cube so advanced grades do not become a long per-frame filter chain.
- The Offset wheel applies a global chroma/luminance bias after Lift/Gamma/Gain. Vibrance protects already-saturated colors; Dehaze uses restrained large-radius local contrast plus saturation/contrast compensation.
- Up to eight secondary color masks can be stored per clip. Face, ellipse, rectangle, linear-gradient, and 3–12 point polygon windows support canvas-normalized geometry, feather, opacity, enable/bypass, inversion, reset, deletion, and a guide-only Hide/Show overlay control that never bypasses the local correction.
- Each mask has an independent local grade: Exposure, Brightness, Contrast, Saturation, Vibrance, Temperature, Tint, Hue, and skin-focused Smoothness. Masks are applied sequentially after the base grade through Core Image mattes and `CIBlendWithMask`, so preview and export are identical.
- Masks can be tracked forward or backward from the current playhead. Vision follows the selected subject at a mobile-conscious adaptive sample rate; normalized motion samples are persisted with the clip and smoothly interpolated on every preview/export frame. Tracking can be cancelled or cleared without deleting the window or its local grade.
- Power windows are manipulated on the actual editor preview: drag to position, pinch to resize, rotate from the sheet, or drag individual polygon vertices around an arbitrary object. Window mattes are applied after the clip-to-canvas transform so the UI, preview, and export share exactly the same coordinates.
- Detect faces samples the current composed program frame, runs Apple Vision off the main thread, expands each detection into a natural portrait ellipse, and places it on that same preview frame.
- Tracking is bounding-box based and intentionally stops when confidence becomes unreliable. Dragging or resizing a tracked mask now inserts/replaces a manual correction keyframe at the playhead and preserves surrounding Vision samples. Heavy occlusion, extreme motion blur, or scene cuts can still require correction; planar/perspective tracking remains future work.
- Scopes are monitoring-only. They analyze a maximum-256-pixel selected-clip frame off the main thread, then draw with SwiftUI Canvas. This keeps scope work out of the playback/export graph and avoids retaining full-resolution frame buffers.
- Waveform plots Rec.709 luma by horizontal image position. RGB parade plots each channel independently. The vectorscope uses Rec.709 chroma projection with neutral, saturation, and skin-tone guides. Histogram overlays luma and RGB distributions.
- Source/Graded toggles make clipping introduced by the grade easy to isolate. Shadow and highlight percentages are explicit measurements from the analyzed frame.
- Current limitation: scopes follow the selected clip's representative frame rather than sampling every playing frame. True continuous scopes should be added with a throttled `AVPlayerItemVideoOutput`/Metal analysis path after proxy rendering and thermal budgets exist.
- Current limitation: rendering is intentionally 8-bit SDR. Proper log/HDR grading requires an explicit linear/wide-gamut 16-bit Metal pipeline, transfer-function-aware scopes, tone mapping, and metadata validation before exposing HDR-specific controls.
- Selecting a style rebuilds and plays the relevant edge/cut preview. Duration is adjustable up to 2 s (clamped to available clip lengths), and **Apply to all cuts** can update every internal boundary in one operation.
- Cancel restores the endpoint/cut state; Done creates one undo step and persists the transition kind/duration. Preview and export use the same `AVVideoComposition` opacity/transform ramps over cached, encoded black/white backing-video tracks, so letterboxing and transformed or faded frames always contain initialized pixels instead of a green YUV surface. The closing effect finishes at the last video frame; any audio-only tail continues over the initialized black canvas. The Core Animation text-overlay tool is attached only during offline export because AVPlayer does not support it.

---

## 13. Professional editor roadmap

This roadmap is ordered by dependency and product value. A feature is only considered
complete when it works in **preview and export**, participates in **undo/redo**, persists
through project save/reopen, and has reasonable device-performance coverage.

### Shipped foundation

| Area | Current capability |
|------|--------------------|
| **Timeline** | Continuous playback; trim, split, reorder, insert, delete, speed, volume, photo duration, per-clip crop/reframe, filmstrips, video/text/audio overlay lanes, and extended timelines. |
| **Transitions** | 105 opening/cut/closing transitions with live preview, duration, Apply to all cuts, undo, persistence, and export parity; 35 use the isolated GPU compositor. |
| **Audio** | Imported **multi-track** audio — clips on independent, overlappable lanes with trim, move, split, duplicate, volume, volume keyframes, fade in/out, and export mixing. New tracks drop at the playhead so a second clip never has to collide with or displace an existing one. |
| **Text** | Styled text overlays with timeline trim/move, preview positioning that matches between the inline card, fullscreen preview, and export, undo, persistence, and export burn-in. |
| **Video overlays** | Picture-in-picture video with trim/move/split/delete, preview drag/pinch transforms, layer ordering, 16 blend modes, feathered visibility masks, chroma key with spill suppression, audio, undo, persistence, and GPU preview/export parity. |
| **Projects** | Autosaved JSON projects, resume, home rename, delete confirmation, PhotoKit rehydration, and modified-date ordering. |
| **Export** | Preview, project filename, 720p/1080p/4K, 24–120 fps, bitrate tiers, MP4/MOV, optional HDR/HEVC, progress, cancellation, Photos, and Share. |
| **Color** | 40 looks in seven categories; 20 primary controls; eight-band HSL; master/R/G/B curves; lift/gamma/gain/offset wheels; up to eight face/manual secondary masks with independent skin/local corrections, clean-view overlay hiding, and bidirectional subject tracking; waveform, RGB parade, vectorscope, and histogram monitoring; reset/copy/paste/apply-to-all, undo, backward-compatible persistence, and GPU preview/export parity. |
| **Rendering safety** | Orientation normalization, SDR GPU working space, and encoded black/white backing tracks that prevent green or uninitialized export frames. |
| **Keyframes** | Reusable local-time scalar tracks with hold, linear, easing, and custom cubic Bézier curves; contextual graph editing for clip, overlay, audio, and text animation; undo, persistence, split handling, and shared preview/export sampling. |
| **Motion** | CapCut-style tracking box (drag onto a subject → Start tracking → auto-attaches the selected text/overlay), transform smoothing, and adjustable clip stabilization crop with GPU preview/export parity. |

### Phase 1 — complete the core editing toolkit

| Priority | Feature | Definition of done |
|----------|---------|--------------------|
| 1 | **Color and filters — complete** | 40 categorized filters and intensity; 20 primary adjustments including Vibrance and Dehaze; selective HSL; master/R/G/B curves; lift/gamma/gain/offset wheels; direct-preview Vision face, ellipse, rectangle, linear, and polygon power windows with independent local/skin corrections, overlay hiding, and forward/backward tracking; four professional scopes with clipping readouts and Source/Graded comparison; reset/copy/paste/apply-to-all; undo/persistence; identical GPU preview/export. |
| 2 | **Crop and reframe — complete** | Per-clip crop, rotate, flip, scale, position, straighten, Original/9:16/16:9/1:1/4:5 presets, optional safe-area/rule-of-thirds guides, and Fit/Fill background framing. Preview, undo, persistence, reopen, GPU transitions, and export use the same transform. |
| 3 | **Canvas formats — complete** | 9:16, 16:9, 1:1, 4:5, and encoder-safe custom pixel sizes; color, GPU-blurred, and app-owned image backgrounds; project persistence, undo, preview, and export parity. |
| 4 | **Timeline snapping — complete** | Magnetic playhead and movable audio/text/video-overlay edges snap to all meaningful timeline edges and range markers using a point-based, zoom-aware threshold, with visible guides and latched haptic feedback. |
| 5 | **Duplicate and replace — complete** | Video, audio, and text duplication creates independent timeline items in one undoable operation. Video/photo replacement retains compatible trim span, speed, volume, crop/reframe transform, color grade, and transitions. |
| 6 | **Export range — complete** | Persistent, undoable In/Out markers appear on the timeline; the export screen reports selected duration and bitrate-based size; AVAssetReader crops the composed video, mixed audio, overlays, and timed text to the exact selected range. |

#### Phase 1 follow-up — timeline precision

These are the main non-AI editing mechanics still missing from the shipped core; they
extend the existing timeline instead of replacing its trim, split, snapping, or
keyframe behavior.

| Track | Feature | Definition of done |
|-------|---------|--------------------|
| T1 | **Precision trim and sync edits — core shipped** | A dedicated precision editor provides ripple delete/trim, roll, slip, slide, independent J/L audio handles, and explicit unlink/relink. Operations create one undo step, preserve valid transitions/keyframe ranges, persist across reopen, and use the shared preview/export composition. Track locks remain a separate track-policy follow-up. |
| T2 | **Selection and sequence structure — core shipped** | Cross-track tap and In/Out range selection, one-step batch move/delete/duplicate, named persisted groups and markers, recursively nested compounds, clear focus navigation, split/delete membership repair, and duration derived from authoritative member boundaries. Preview and export continue rendering the same flat media timeline. |

#### Selection and sequence structure

The timeline header now starts cross-track multi-selection without hiding the playhead or preview. Primary clips, captions/text, imported audio, and video overlays retain typed identities; selected items can move, duplicate, delete, group, or become a compound in one undo transaction. Existing In/Out points provide range selection, while named markers snap and remap through ripple edits.

`EditorSequence` stores groups and recursively nested compounds as references to authoritative timeline items. Enter/Up focus navigation dims and interaction-locks non-members, sequence bands use separate display lanes when ranges overlap, and compound duration is always derived from current leaf boundaries. Split commands add both resulting pieces to their container; delete and missing-media recovery prune stale members; grouped duplication remaps copied motion-track attachments. Because compounds do not create a second media representation, persistence, undo/redo, preview, and export cannot disagree about the edit.

### Phase 2 — motion and advanced compositing

| Priority | Feature | Definition of done |
|----------|---------|--------------------|
| 7 | **Keyframe engine — complete** | Reusable local-time scalar tracks and a graph/curve editor cover transform, opacity, volume, crop/reframe, filter intensity, text motion, and effect parameters. Hold, linear, ease-in, ease-out, ease-in/out, and editable cubic Bézier segments share one deterministic sampler. Clip/overlay GPU rendering, audio mix ramps, SwiftUI text preview, offline text burn-in, split/duplicate/replace, undo, autosave, reopen, and export consume the same persisted tracks. |
| 8 | **Speed ramps — complete** | Normal/Curve modes, six presets, editable points, linear/smooth interpolation, 0.1×–8× range, source/timeline remapping, split-safe persistence, undo, timeline feedback, and shared preview/export segment rendering. |
| 9 | **Reverse and freeze frame — complete** | Non-destructive reverse with deterministic disk caching, cancellable progress, reversed-or-muted embedded audio, cache regeneration from the original Photos asset, and toggle-to-restore. Playhead-accurate freeze insertion supports 0.1–10 second holds, explicit mute/continue-source audio policy, ripple-safe timeline insertion, held keyframe state, undo, persistence, split/duplicate, relinking, timeline badges, and identical preview/export composition. |
| 10 | **Multi-layer video — complete** | Multiple video-overlay tracks render in a persistent back-to-front stack. Each layer has independent trim/move, opacity, transforms, keyframes, and audio controls; contextual Send Back/Bring Front actions are undoable and export matches preview ordering. |
| 11 | **Blend, mask, and chroma key — complete** | Sixteen blend modes on primary and overlay clips; ellipse, rectangle, linear, and direct-preview custom polygon masks with feather and matte cleanup; chroma and luma keying with spill suppression; configurable layer shadows; manual correction keyframes for tracked color masks; backward-compatible persistence, undo, debounced live preview, and identical GPU export. |
| 12 | **Stabilization and motion tracking — complete** | Reusable point and planar tracks; Gaussian transform smoothing; tracked text and overlay graphics; Vision camera-path analysis with smoothness and crop sliders; undo, persistence, split-safe samples, and identical GPU preview/export. |

#### Keyframe engine

- **Model:** `EditorKeyframe`, `EditorKeyframeCurve`, `EditorKeyframeTrack`, and `EditorKeyframeTracks` store item-local seconds, scalar values, and each point's outgoing curve. Complex transforms are composed from reusable position, scale, rotation, crop, and opacity channels.
- **Editor:** contextual **KEYFRAME** actions open one graph editor for primary clips, video overlays, imported audio, and text. Dragging the graph scrubs the playhead and magnetically snaps to nearby diamonds without changing values; previous/next buttons jump between points. Values change only through the slider or numeric field. Points can be added, selected, deleted, and assigned preset or custom cubic Bézier curves, with undo/redo available inside the sheet.
- **Rendering:** the transition compositor samples clip and overlay transform/opacity/filter tracks per frame; `AVAudioMix` receives sampled volume ramps; text uses the same tracks in live SwiftUI preview and offline Core Animation burn-in.
- **Project integrity:** keyframes participate in value equality, snapshot undo/redo, composition fingerprints, autosave, backward-compatible decoding, duplication/replacement, and split operations. Projects created before Priority 7 decode with empty tracks.

#### Reverse and freeze frame

- **Reverse:** select a primary video clip and tap **REVERSE**. `EditorReverseMediaService` builds the visible source range in reverse order, optionally reverses its embedded audio, writes a deterministic high-quality file under `Library/Caches/MixtapeReverseMedia`, reports preparation/export progress, and cancels cleanly without changing the project. Tapping **REVERSE** again restores forward playback without touching the original media.
- **Cache and relinking:** `EditorClipPlayback.reverse` persists only the non-destructive treatment and audio policy. The Photos local identifier plus source range is the cache key and remains the relink authority; if iOS purges the derived file, the shared composition path regenerates it from the original asset. Cache paths are never serialized as authoritative project media.
- **Freeze:** place the playhead on a selected video and tap **FREEZE**. The editor samples that exact displayed frame, inserts a 0.1–10 second still segment, and ripples markers, captions, overlays, audio lanes, and export In/Out points so downstream sync is preserved. Animated channels are sampled into hold keyframes instead of restarting their motion.
- **Audio policy:** **Mute Clip Audio** is the safe default and leaves music, voiceover, and other lanes playing. **Continue Clip Audio** explicitly carries the source audio forward under the held image as a deliberate J-cut. Reverse clips expose reversed embedded audio by default and retain a persisted mute policy.
- **Editing and delivery:** REV/HOLD badges and direction-correct filmstrips make derived clips obvious. Reverse/freeze state participates in equality, composition fingerprints, snapshot undo/redo, autosave, backward-compatible project decoding, duplication, source-aware splitting, timeline trimming, preview, and offline export.

#### Multi-layer video

- **Layer model:** every video-overlay lane owns a persistent `zIndex`. Older projects derive their initial stack from lane order, while split clips remain on the same logical layer and newly imported overlays start at the front.
- **Editing:** expanded overlay rows retain independent trim and timeline movement. The contextual action bar exposes **SEND BACK** and **BRING FRONT**, disables impossible moves, and records each reorder in the shared undo/redo history.
- **Rendering:** the composition builder sorts overlay lanes back-to-front before creating render segments and audio tracks. Both the GPU compositor and standard AVFoundation fallback consume that deterministic order, keeping preview and export consistent.
- **Project integrity:** layer order is included in saved project data, clip equality, composition invalidation fingerprints, autosave, and backward-compatible decoding.

#### Stabilization and motion tracking

- **Track (CapCut flow):** select a text or video/photo overlay → **TRACK** → a box seeds onto the overlay's current position on the underlying video. Drag it onto the subject (corner handles resize), tap **Start tracking**, and tracking runs bidirectionally across the overlay's on-screen range and auto-attaches — no separate track list or attach step. Sampling runs near the source clip's own frame rate (not a fixed low rate) so fast subject motion doesn't outrun what the tracker can follow between frames, and a full run always covers the entire requested range — weak/low-confidence frames hold the last known position and keep retrying rather than abandoning the rest of the clip.
- **Hand tracking:** if the seed box lands on a detected hand, tracking automatically switches to Vision hand-pose landmarks (wrist/knuckle joints) instead of generic box correlation — each frame is an independent, stateless detection, so a brief miss just pauses instead of drifting onto the wrong static region and staying there. Every other subject (objects, faces, logos, stickers) keeps using bounding-box tracking. Rotation is estimated from a crop around the tracked box only (not the full frame), so background motion doesn't bleed into the subject's own spin; scale uses the geometric mean of the box's width/height ratio so an unchanged box reads as 1×, not inflated.
- **Smoothing:** the resolved path uses Light Gaussian smoothing by default (denoise Vision jitter without lagging behind fast motion). The same smoother is used by preview overlays, GPU compositing, and offline text burn-in.
- **Follow rotation / Follow scale:** toggles on the Track panel; position is always followed. Dragging the graphic after attaching preserves the offset from the tracked feature.
- **Stabilize:** Analyze Motion builds a clip-local camera path from optical-flow median translation (falling back to Vision translational registration) with tightly gated rotation. **Smooth** keeps pans and inverts high-frequency jitter; **Lock** blends that path toward the clip’s mean pose for a tripod look. Auto crop is computed from the residual so the warp stays covered; Fill edges clamps pixels instead of showing empty canvas. Strength, mode, and crop are live over the same samples — re-analyze after this change.
- **Project integrity:** tracks, attachments, and stabilization participate in undo/redo, autosave, fingerprints, duplication, split remapping, and backward-compatible decoding. Replacing media clears source-specific motion samples.

### Phase 3 — professional audio

#### Already shipped — do not rebuild

- Imported audio and embedded clip audio already render through the project mix.
- Imported audio clips already support timeline placement, trim, move, split, duplicate,
  delete, per-clip volume, volume keyframes, and independent fade-in/fade-out.
- Audio clips already live on independent, overlappable **tracks** (`EditorAudioClip.laneIndex`,
  mirroring `EditorOverlayClip.laneIndex`). Importing always opens a new track at the current
  playhead (`EditorViewModel.loadAudioClip(from:insertion:)`, `.newTrackAtPlayhead`); the small
  **+** after a clip's trailing edge instead extends that clip's own track back-to-back
  (`.afterClip`). `EditorTimeline` renders one row per track in a height-capped, vertically
  scrollable stack. See **§6.9**.
- Every audio clip — regardless of track — already renders on its own composition audio track
  with independent `AVAudioMixInputParameters` (volume, keyframed volume ramps, fades), so
  overlapping tracks already mix correctly in preview and export; Priority 15's mixer/automation
  work builds UI on top of this, not new rendering plumbing.
- Preview, persistence (`SavedAudioClip.laneIndex`, backward-compatible), undo/redo, project
  reopen, and export already share these edits.
- A Priority 20 sound library — bundled starter SFX plus live Freesound search, merged in one
  browser (browse/search/preview/favorite/download-cache/insert-at-playhead) — already ships. See
  the Priority 20 entry below for exactly what's covered and what's not.
- Priority 13 ships waveforms and gain staging: `Services/AudioWaveformGenerator.swift` decodes
  real PCM peak data from an `EditorAudioClip.fileURL` (via `AVAudioFile`), downsamples to a fixed
  bucket count, and caches results in memory + on disk (`Library/Caches/MixtapeWaveforms/`, keyed
  by an FNV-1a hash of the file path — stable across launches, unlike `String.hashValue`) so a
  clip's waveform is decoded once, not on every re-render. `AudioClipThumb` loads it via
  `.task(id: clip.fileURL)`, replacing the fake procedural noise `EditorAudioClip.waveform` used
  to carry. Track/master gain (`Model/EditorAudioMixSettings.swift`, the **MIX** tool) apply on
  top of existing per-clip volume in both preview and export. Live meters are an intentional
  product exclusion, not a gap — see the Priority 13 entry below for why.

| Priority | Feature | Definition of done |
|----------|---------|--------------------|
| 13 | **Waveforms and gain staging — complete for shipped scope** | Cached waveforms for imported/library audio; clip, track, and master gain. Live meters (peak/RMS/true-peak, clipping indicators, pre/post-fader) are an intentional product exclusion, not a gap — see the Priority 13 writeup below for why. |
| 14 | **Voiceover recording, teleprompter, and punch-in/out — complete for shipped scope** | Record at the playhead, live input-level meter, multiple takes with retry/delete, explicit recovery UI for permissions/interruptions/route changes, a script + auto-scrolling teleprompter overlay, and playhead-marked punch-in/out re-recording in place (splice-only, no live playback underneath). Count-in, mic/input selection, monitoring passthrough, latency compensation, take naming, and comping are out of scope for now — each is separate-sized work, see the Priority 14 writeup below. |
| 15 | **Audio mixer, automation, and effects — partial: mixer basics + effects shipped** | Track headers (rename), mute, solo, master + per-track gain (`MixToolPanel`), and CapCut-style voice/sound effect presets (Echo, Reverb, Robot, Chipmunk, Telephone, ...) rendered offline and cached (`EditorAudioEffectPanel`). Pan is out of scope — the composition/export pipeline (`AVAudioMix`) has no pan API at all, only volume; a real implementation needs `MTAudioProcessingTap`, the same real-time-C-callback risk class already excluded for Priority 13's meters. Routing/buses, audio roles, write/read/bypass automation, crossfades, and copy/paste automation are also out of scope — see the Priority 15 writeup below for what shipped and why. |
| 16 | **Dialogue cleanup and voice enhancement** | Non-destructive voice isolation, broadband noise reduction, de-reverb, de-hum, wind reduction, click/pop repair, gate, de-esser, plosive control, and one-tap speech enhancement. Every processor exposes strength, preview/bypass, reset, and sensible speech presets without destroying the source recording. |
| 17 | **EQ, dynamics, and mastering** | Per-clip/track parametric EQ with high/low-pass filters, compressor, expander, limiter, and optional multiband dynamics. Provide visual response curves, gain-reduction meters, safe presets, loudness normalization, LUFS-I/LRA/true-peak readouts, and platform targets with overload-safe final limiting. |
| 18 | **Ducking, crossfades, and dialogue mixing** | Detect dialogue, music, and effects; automatically duck selected beds with adjustable depth, threshold, attack, hold, and release. Add editable equal-power/linear crossfades, room-tone fill, dialogue matching, and side-chain audition so automatic results remain fully editable. |
| 19 | **Beat, rhythm, and music analysis** | Detect BPM, downbeats, beats, transients, musical bars, and likely sections; render an editable beat grid; add/remove markers; snap edits to beats; create assisted beat cuts; and retime selected montages while preserving manual edits. Report analysis confidence and allow half/double-time correction. |
| 20 | **Sound, music, SFX, and brand library** | Search and browse categorized music and sound effects (including trending, cinematic, transitions, comedy, ambience, foley, swooshes, and ASMR), preview in context, favorite/bookmark, download/cache, and insert at the playhead. Show duration, waveform, BPM, key, mood, license/attribution, download state, and offline availability. Brand Music supports team-owned tracks and reusable brand collections. |
| 21 | **Extract, separate, and reshape audio** | Extract audio from video into an editable lane; isolate dialogue, music, vocals, drums, bass, and ambience where supported; mute or retain the embedded source; and preserve sync. Add high-quality time stretch, speed, pitch shift, formant preservation, reverse audio, channel conversion, phase-safe mono/stereo handling, and source-quality warnings. |
| 22 | **Text to speech and generated narration** | Provide a script editor with line/segment splitting, character count, undo/redo, pronunciation dictionary, and writing assists (improve, expand, shorten, rewrite, and translate). Browse and preview voices; control language, speaker, style/emotion, speed, pitch, pauses, and emphasis; regenerate a selected segment; and create synchronized narration plus editable captions with cancellable progress. Multi-speaker scripts and custom/consented voices include clear provenance and privacy controls. |
| 23 | **Audio translation and dubbing** | Detect the source language, transcribe into editable speaker-labelled segments, choose target languages, translate, and generate timing-matched dubbed tracks. Preserve speaker identity only with authorization, provide neutral fallback voices, optionally retain ambience, generate translated captions, expose per-segment review/regeneration, and show progress, estimated cost, consent, and failure recovery. |
| 24 | **Professional delivery and audio integrity** | Export audio-only files and full-mix or role-based stems (dialogue/music/effects/voiceover) with AAC/PCM options, sample rate, bit depth, channel layout, dither, loudness target, and metadata. The preview engine and offline renderer use the same processing graph; edits remain sample-accurate across splits, speed ramps, device routes, save/reopen, and export-range renders. |

#### Phase 3 product rules

- Audio tools use the same bottom-sheet conventions as color, speed, and compositing,
  with adaptive iPhone/iPad layouts, live audition, bypass, reset, undo/redo, and clear
  processing progress. No tool permanently alters the source file.
- Generated, translated, downloaded, or recorded audio becomes a normal timeline clip:
  movable, trimmable, splittable, keyframeable, relinkable, and exportable.
- Cloud/AI features must disclose network use, estimated credits or limits, cancellation,
  retention/privacy behavior, licensing, and voice-consent requirements before processing.
- Long-running analysis and generation is cancellable and resumable, survives sheet
  dismissal, and never blocks ordinary timeline editing.
- “Complete” always means identical preview/export output, persistence, undo/redo,
  split/duplicate behavior, accessibility, iPad adaptation, and tested audio routing.

#### Priority 13 — Waveforms + gain staging (shipped); meters (out of scope by design)

**Shipped: waveforms.** `Services/AudioWaveformGenerator.swift` is an `actor` that opens a clip's
`fileURL` with `AVAudioFile`, reads it in chunks into an `AVAudioPCMBuffer`, and computes a
per-bucket peak amplitude (max absolute sample across all channels) downsampled to a fixed bucket
count, normalized 0...1. Results are cached both in memory and on disk
(`Library/Caches/MixtapeWaveforms/*.json`, keyed by a stable FNV-1a hash of the file path — plain
`String.hashValue` is randomized per process launch and would silently defeat a disk cache) so the
file is decoded once regardless of how many times the clip scrolls in/out of view or the app
relaunches. A file that fails to decode (missing, unsupported format, mid-copy) falls back to a
flat placeholder shape rather than throwing, so a lane never renders broken. `AudioClipThumb`
(`EditorTimeline.swift`) loads it via `.task(id: clip.fileURL)` into local `@State`, replacing the
fake procedural noise `EditorAudioClip.waveform` used to carry as decoration (that property has
been removed — nothing else referenced it, and it was never persisted). Waveforms for voiceover
and generated speech are out of scope simply because neither feature exists yet (Priorities 14 and
22); the generator already works for whatever file those produce once they land, since it only
needs a `fileURL`.

**Shipped: gain staging.** `Model/EditorAudioMixSettings.swift` adds `EditorAudioTrackSettings`
(`gain`, `isMuted`) keyed by `EditorAudioClip.laneIndex` on `EditorViewModel.audioTrackSettings`,
plus a single `EditorViewModel.masterVolume`. Both are 0...1 attenuation-only (matching every
other volume control in the app — `EditorAudioClip.volume`, `EditorClip.volume`,
`EditorOverlayClip.volume` are all 0...1 with no boost), which sidesteps a real bug that would
otherwise exist: `EditorCompositionBuilder.applyVolumeAutomation`'s keyframed/faded path clamps to
a maximum of 1.0, so a gain above unity would silently behave differently on clips with volume
keyframes vs. clips without. Track gain applies to background-audio clips only; master gain
applies everywhere (primary-clip audio, video-overlay audio, and background audio) via a new
`extraGain` parameter threaded through `applyVolumeAutomation` — applied *after* the existing
keyframe/fade clamp, not baked into `baseVolume`, since baking it into `baseVolume` would only
affect clips *without* volume keyframes (the keyframe curve ignores `baseVolume` entirely once any
keyframes exist). `EditorCompositionBuilder.build`/`makePlayerItem` and `EditorExportService.export`
all take `audioTrackSettings`/`masterVolume` parameters now, so preview and export apply gain
identically. `EditorViewModel.ensureCompositionPlayer`'s warmed-player-item fast path additionally
checks `masterVolume == 1.0` before reusing a pre-warmed item — that item was built before the
editor even loaded and has no gain awareness, so skipping this check would have silently ignored
master volume whenever there was no background audio clip. Persisted on `EditorProject`
(`audioTrackSettings`, `masterVolume`, both backward-compatible), undoable
(`EditorViewModel.commitMixChange()`, mirroring `commitAudioVolume`), and included in
`clipsFingerprint()` so a gain change actually triggers a composition rebuild. UI is a new **MIX**
tool (`EditorTool.mix`) on the main toolbar opening `MixToolPanel` — a master-volume slider plus
one gain/mute row per lane that currently has a clip (`EditorViewModel.audioLaneIndices`).
Deliberately lightweight, not a full mixer strip — track headers and solo joined it in Priority 15
(see that writeup below), but pan, routing/buses, and audio roles remain out of scope.

**Deliberately not built: meters.** Peak/RMS/true-peak meters, clipping indicators, and
pre/post-fader metering are out of scope **by product decision**, not left for later — for a
CapCut-style mobile editor, live numeric meters are a broadcast-engineering feature the target
audience doesn't use; the audience judges audio by ear and by waveform shape. Building one would
also mean the riskiest code in this app: no simple "current playback level" API exists on
`AVPlayer`, so a real meter needs `MTAudioProcessingTap` — a Core Audio C-callback API with
real-time-safety constraints (no allocations, no locks in the callback) — attached per-track, with
per-track readings summed client-side since this pipeline has no single master audio node to tap.
That's DSP whose correctness can't be verified by reading the code; it needs a device and ears. If
a real need for meters shows up later, a clipping *indicator* derived from the peak data
`AudioWaveformGenerator` already computes (no live tap, no new risk) delivers most of the practical
value at a fraction of the cost.

#### Priority 14 — Voiceover recording, teleprompter, and punch-in/out (complete for shipped scope)

**Shipped: recording.** `Services/VoiceoverRecorderService.swift` is a `@MainActor @Observable`
recorder built on `AVAudioRecorder` (not `AVAudioEngine` — no live monitoring passthrough is
built, so the simpler recorder API is enough and gives metering for free via
`isMeteringEnabled`). Reached from the same "Add Audio" `confirmationDialog` as Files import and
the sound library (`AudioSourceSheets` in `EditorScreen.swift`, now three options instead of
two), so it inherits the existing `AudioInsertion` placement logic (new track at the playhead, or
after a clip) for free. `View/Components/VoiceoverRecorderView.swift` is the recording sheet:
permission gate (with an **Open Settings** fallback when denied, mirroring
`PhotoLibraryViewModel`'s pattern), a pulsing input-level meter driven by
`averagePower(forChannel:)` on a 15 Hz timer, and a takes list (retry by just recording again,
delete via trash, preview via a throwaway `AVAudioPlayer`) until the user taps **Use**, which
hands the file to `EditorViewModel.insertRecordedVoiceover(fileURL:duration:insertion:)`. That
method mirrors `insertAudioLibraryItem` — the take becomes a normal `EditorAudioClip` (already in
`MixtapeAudio/`, so no security-scoped copy step), inheriting trim/move/split/volume/waveform
(Priority 13's `AudioWaveformGenerator` needs only a `fileURL`)/undo/persistence for free. Any
take *not* chosen is deleted when the sheet closes (`endSession(keeping:)`) so cancelled sessions
don't leak files.

A stopped recording only becomes a `Take` once its **actual encoded duration** (read back via
`AVURLAsset(url:).load(.duration)`, not `AVAudioRecorder.currentTime`) is ≥0.2s — `currentTime`
turned out to misreport right at the instant a route change forces the recorder to finalize
mid-write (see the recovery UI note below), so trusting it could either silently drop a real take
or keep a broken one.

**Recovery UI**, per the README's original ask: `AVAudioSession.interruptionNotification` and
`.routeChangeNotification` observers stop an in-progress recording and `await` the validated
result before saying anything — the banner only claims "your take was saved" when validation
actually produced one; otherwise it says the recording stopped before anything was captured.
(An earlier version of this claimed success unconditionally, which was caught by testing the
AirPods-mid-recording-disconnect case on a real device — exactly the kind of route-change
correctness that can't be verified by reading code alone.) Both notification handlers are
`nonisolated` with an explicit `Task { @MainActor in … }` hop, since `NotificationCenter` doesn't
guarantee main-thread delivery for `AVAudioSession` notifications.
`AudioSessionConfigurator.configureForRecording()` switches the shared session to
`.playAndRecord` with `.allowBluetooth`/`.defaultToSpeaker`; leaving the sheet restores
`.playback` so preview playback routing isn't left in a recording state.

**Shipped: teleprompter.** Turned out to be much smaller than the original checklist line
implied once scoped down to *audio-only* recording — no camera framing guides, no
already-read/still-to-read word highlighting, just a script the user types once
(`ScriptEditorSheet`, a plain `TextEditor`, deliberately with no AI writing assist — this is a
place to get thoughts down, not a writing tool) and an auto-scrolling overlay shown above the
record button while recording. Scroll position is `elapsedTime * speed * 36`pt — reusing the
level meter's existing 15 Hz `elapsedTime` tick rather than a second timer, and naturally
resetting to the top on every new take since `elapsedTime` restarts at 0 each time. Speed, font
size, and color are adjustable inline (no nested sheet-on-sheet). The script itself is
session-only scratch text, not persisted on `EditorProject` — it's a reading aid, not a timeline
object, so it does not survive closing and reopening the recorder sheet.

**Out of scope for now, on purpose — not an oversight.** Count-in, manual mic/input selection,
live monitoring passthrough (needs `AVAudioEngine`, not `AVAudioRecorder`), latency compensation
(needs a physical device to verify, same caveat as Priority 13's meters), take naming, and
comping (closer in scope to Priority 15's mixer/automation work than to this recorder) are each
separate-sized work, not included here.

**Shipped: punch-in/out.** Re-records over a marked range of an already-inserted clip in place.
Deliberately the "splice, no live context" version, not a true punch-in — nothing plays back
while you're recording the replacement, so there's no reference audio to time your delivery
against. Marking is playhead-driven, the same interaction pattern already used everywhere else in
this app (split-at-playhead, insert-at-playhead): select a clip, tap **PUNCH IN** on
`EditorAudioActionBar` to mark the in-point at the current playhead, scrub to the desired
out-point, tap **Set Out** (or **Cancel**) — this swaps the action bar's icon grid for a small
marking row rather than adding a new overlay, following the same bottom-bar-swap convention
§6.8 describes for clip/text/audio selection. `EditorViewModel.togglePunchInMark()` clamps both
points to the clip's own range and requires at least `EditorAudioClip.minimumSpan` (0.25s) between
them; marking is cancelled automatically if the clip is deleted or a different clip is selected
mid-mark, so it can't go stale. Confirming opens the same `VoiceoverRecorderView` sheet used for
inserting new audio (`Mode.punch` instead of `Mode.insert` — same permission/meter/takes/recovery
UI, the only difference is what **Use** does with the finished take) and hands off to
`EditorViewModel.punchInRecordedTake(clipID:start:end:fileURL:duration:)`, which splits the
original clip at the in-point and again at the out-point via the **same**
`EditorAudioClip.split(atSourceTime:)` used by `splitAtPlayhead()` for video — reusing its fade
and keyframe handling rather than re-deriving them — inserts the new recording between the
resulting head/tail, and re-anchors the tail to start right after the new recording (reflowed,
not time-stretched, since there was nothing to time it against). A true punch-in with live
playback underneath is still open — it needs simultaneous playback+record on one
`.playAndRecord` session, which is untested territory here.

#### Priority 15 — Audio mixer, automation, and effects (mixer basics + effects shipped)

**Shipped: audio effects.** `Model/EditorAudioEffect.swift` defines 30 CapCut-style voice/sound
presets across two tabs — **Filters** (Echo, Hall/Cave reverb, Telephone, Megaphone, Sweet, Mic
Hog, Lo-Fi, Clear Vocals, Deep & Clear, Bass Mic, Studio Mic, Divine Echo, Energetic, Tremble,
Distorted, Big House) and **Characters** (Robot, Chipmunk, Deep Voice, Alien, Squirrel, Elf,
Trickster, Dark Lord, Noble Leader, Bold Warrior, Noble Chief, Fussy Male, Queen, Santa) — the
same split CapCut's own "Voice filters" / "Voice characters" tabs use. Built entirely from
Apple's off-the-shelf `AVAudioUnit` effects (`AVAudioUnitTimePitch`, `AVAudioUnitReverb`,
`AVAudioUnitDistortion`, `AVAudioUnitDelay`, `AVAudioUnitEQ`), never hand-rolled DSP — these are
DSP approximations (pitch + EQ + reverb/distortion combinations), not true voice-conversion
models, so don't expect an exact timbre match to CapCut's likely ML-backed character voices.
Also not attempted: CapCut's third tab, "Speech to song" — converting spoken audio into a sung
melody is pitch/rhythm detection plus resynthesis onto a target melody, a fundamentally different
(likely ML-backed) feature, not a preset DSP chain, so it doesn't belong in this pass.

`Services/EditorAudioEffectRenderer.swift` (an `actor`, same shape as `AudioWaveformGenerator`)
renders a preset onto a clip's source file **once**, offline, via `AVAudioEngine`'s manual
rendering mode — a standard, documented, non-real-time API — and caches the result on disk keyed
by (source path, effect), so re-picking an effect or reopening the project is instant. Every
preset only touches `pitch` (cents), never `rate`, and the render is capped at the source's own
frame count (an echo/reverb tail past the clip's end gets truncated), so the processed file's
duration always exactly matches the source's — none of the existing trim/timeline/`split()` math
needs a single line changed to account for it. The one preset that isn't a static parameter set,
**Tremble**, still only touches `pitch` — `EditorAudioEffect.modulate(chain:elapsedSeconds:)` is
called once per render chunk and animates a sine-wave wobble onto the chain's
`AVAudioUnitTimePitch` node as rendering progresses, rather than setting `pitch` once up front.
That mutation is safe here specifically because manual rendering calls it synchronously between
chunks on the actor doing the render — not from a live real-time audio thread — so none of
`MTAudioProcessingTap`'s real-time-safety constraints apply; it's the same offline-render safety
argument as every other preset, just with a parameter that changes over time instead of once.

A clip only ever gets `effect` set to a non-`.none` value **after** the render has actually
finished (`EditorViewModel.setAudioClipEffect`) — so `EditorAudioClip.playbackFileURL` (which
`EditorCompositionBuilder` reads instead of `fileURL` when building background-audio tracks) never
needs to `await` anything; it's a synchronous cache-hit check with a graceful fallback to the dry
file if the cache was ever evicted. UI is `View/Components/EditorAudioEffectPanel.swift` — a grid
under a new **EFFECTS** button on `EditorAudioActionBar`, reachable per-clip; picking a preset
shows a spinner on that cell during the one-time render, and the effect becomes audible on the
next composition rebuild (no separate preview player — the timeline *is* the audition). Persisted
on `SavedAudioClip` (optional, backward-compatible), carried through `split()`/duplicate so a
punched-in or split effect-bearing clip doesn't silently revert to dry audio.

**Why this and not pan.** The original checklist put pan and effects in the same "automation"
bucket, but they're not the same class of work. Volume automation exists today because
`AVMutableAudioMixInputParameters` — the API the whole preview/export pipeline is built on —
has `setVolume`/`setVolumeRamp` built in; it has **no pan equivalent at all**. A real
implementation would need `MTAudioProcessingTap`, a real-time Core Audio C callback with
real-time-safety constraints — the same class of risk the README already excluded once for
Priority 13's meters (can't be verified by reading code, needs a device and ears). Effects, by
contrast, render **offline** — no real-time constraint, no new risk category, just standard
`AVAudioEngine` usage — which is why they shipped and pan didn't.

**Shipped: solo and track naming.** Both are cheap extensions of Priority 13's existing
`EditorAudioTrackSettings`/`MixToolPanel` — no new subsystem. `isSoloed` on
`EditorAudioTrackSettings`, and `EditorAudioTrackSettings.effectiveGain(anySoloed:)` replaces the
old no-argument `effectiveGain`: a lane is silenced if it's muted, *or* if any lane anywhere is
soloed and this one isn't. The `anySoloed` flag has to come from the caller (a single lane's
settings can't see its siblings), so `EditorCompositionBuilder` computes
`audioTrackSettings.values.contains { $0.isSoloed }` once per build; a lane with no settings
entry yet still defaults through a plain `EditorAudioTrackSettings()` rather than skipping
straight to gain `1.0`, so an untouched lane is still correctly silenced under an active solo.
Track naming is a `name: String?` field, editable inline in `MixToolPanel` (tap the track title,
`TextField`, Done) — purely cosmetic, so it's deliberately left out of `clipsFingerprint()`'s
`mixHash` (renaming shouldn't force a composition rebuild).

**Out of scope for now.** Routing/buses and audio roles (Dialogue/Music/SFX groupings with their
own shared fader) would be relatively cheap to add later — master gain already threads through
the composition as one multiplier (`extraGain`), so a bus gain is just another multiplier in the
same spot — but weren't built this pass. Write/read/bypass live automation (recording fader moves
while playing) is a genuinely new interaction model — keyframing today is manual point-placement,
not live-record — and wasn't started. Crossfades (linking two adjacent clips' fades) and
copy/paste automation (copying a keyframe curve between clips) are both small-to-medium UI work on
top of infrastructure that already exists, also not started. Sample-accurate preview/export parity
was already true before this pass — both use the same `EditorCompositionBuilder`.

#### Priority 20 — Sound library (SFX)

**Shipped: bundled starter SFX + live Freesound search, merged in one browser.** No Music or
Brand tabs — Freesound (freesound.org) is a community sample/field-recording/SFX database, not a
curated background-music catalog, so a "Music" tab with nothing behind it would just be confusing
chrome. If a real music catalog gets licensed later, `EditorAudioLibrarySource` and
`EditorAudioLibraryProviding` are the extension points; nothing about them assumes SFX-only.

**What's shipped:**

- **Bundled pack:** `Features/Editor/AudioLibrary/catalog.json` + `AudioLibrary/SFX/*.wav` — 12
  **originally synthesized** sounds (sine oscillators and filtered noise; no third-party samples,
  so no licensing burden) across five categories, generated by `Tools/gen_sfx.py` (kept outside
  `Features/Editor/AudioLibrary` so the script itself is never copied into the app bundle — only
  its output is) and bundled via a folder reference in `Mixtape.xcodeproj`.
- **Remote search:** `Services/FreesoundAudioLibraryProvider.swift` hits the Freesound text-search
  API (`Authorization: Token …` header) for whatever the user types, mapping each result's license
  URL to CC0 / CC BY / CC BY-SA / CC BY-NC(-SA) / Sampling+, with unrecognized licenses defaulting
  to "attribution required" rather than silently treating them as free-and-clear. The API key is
  **hardcoded** in that file (an explicit product decision — it lands in git history the moment
  this is committed; rotate at https://freesound.org/apiv2/apply/ if that becomes a problem, or
  move it to a gitignored config file, which doesn't require touching the rest of the file).
- **Cache:** `Services/AudioLibraryCache.swift` — an `actor` downloading Freesound previews into
  `Application Support/MixtapeAudioLibraryCache/`, keyed by sound id so the same sound inserted
  into two different projects downloads once and both share the file. Budget-capped (300MB,
  oldest-accessed evicted first) and independent of any single project's clip lifecycle —
  `EditorViewModel.releaseAudioFileIfUnused` explicitly skips both this directory and the app
  bundle path, so deleting a clip from one project never deletes a file another project (or a
  future re-insert) still needs. Trade-off: a project left unopened long enough could in principle
  reopen missing a library clip if its cache entry got evicted meanwhile — the same "silently drop
  a clip with a missing backing file" fallback `SavedAudioClip.toAudioClip()` already applies to
  missing imported audio, not a new failure mode. A real fix is Phase 5 Priority 31 (missing-media
  relink), out of scope here.
- **Model:** `Model/EditorAudioLibraryItem.swift` — source-agnostic `EditorAudioLibraryItem`
  (id, title, category, duration, tags, `source`, `license`), `EditorAudioLibraryCategory` (the
  filter chips), `EditorAudioLibraryLicense`, and the `@MainActor` `EditorAudioLibraryProviding`
  protocol both providers conform to (`BundledAudioLibraryProvider`, `FreesoundAudioLibraryProvider`)
  — `AudioLibraryViewModel` never needs to know which one it's talking to.
- **ViewModel:** `ViewModel/AudioLibraryViewModel.swift` — merges both providers' results,
  debounced remote search (driven by the view's `.task(id:)`, not a `didSet` — `@Observable`
  doesn't support property observers), favorites (a `Set<String>` of ids in `UserDefaults` —
  local-only metadata over the catalog, not a copy of any item), and single-item audition via a
  dedicated `AVPlayer` (streams Freesound previews directly, or plays a bundled/cached file — one
  playback path for both, unlike an earlier `AVAudioPlayer`-only version that couldn't stream) that
  never touches the project's own composition player or playhead.
- **UI:** `View/Components/AudioLibraryPickerView.swift` — search field, category chips (tapping
  one seeds the search query so one field drives both local filtering and the remote query),
  "Bundled" / "Freesound" sections, per-row cached/offline indicator, and an attribution
  confirmation alert that blocks insertion of any item whose license requires it until the user
  sees the required credit text.
- **Entry point:** the audio lane's **+** opens a `confirmationDialog` ("Browse Sound Library" /
  "Import from Files") instead of jumping straight to the Files picker — see `AudioSourceSheets`
  in `EditorScreen.swift`, pulled out as its own `ViewModifier` because `EditorScreen.body` is
  already one large expression; three more inline sheet modifiers pushed the type checker over its
  complexity budget.
- **Insert at playhead:** `EditorViewModel.insertAudioLibraryItem(title:fileURL:duration:attribution:insertion:)`
  reuses the exact same lane/timeline-placement logic as imported audio
  (`resolveAudioInsertion(_:)`, shared with `loadAudioClip`) — `.newTrackAtPlayhead` by default, so
  a sound effect drops at the playhead on its own track without disturbing existing audio, or
  `.afterClip` when inserted from a track's own "extend" button. Required attribution text (if any)
  is stored on `EditorAudioClip.attribution` (persisted via `SavedAudioClip`, backward-compatible)
  so it isn't lost once the clip leaves the library sheet. From insertion onward the clip is a
  completely normal `EditorAudioClip` — trim, move, split, duplicate, volume, keyframes, undo, and
  persistence all work on it with no library-specific code. This is why the multi-track work above
  had to land first: without independent, overlappable tracks, a sound effect dropped under
  existing background music would have had nowhere to go but after it.

**Not built:** a licensed music catalog (Artlist/Epidemic/Soundstripe-style — needs an account,
licensing agreement, and a product decision, not just engineering), Brand Music (needs whatever
account/organization concept the app eventually adopts for team features), and surfacing stored
attribution anywhere at export time (currently only shown at insert time).

### Phase 4 — titles, captions, and reusable creative assets

| Priority | Feature | Definition of done |
|----------|---------|--------------------|
| 25 | **Text animation — complete** | Persisted In/Out/Loop presets, adjustable timing/intensity, per-character typewriter timing, bounce, pop, zoom, directional slide, fade, blur, pulse, and wiggle. Presets compose with manual keyframes and render identically in live preview and offline export. |
| 26 | **Captions and transcript editing — core workflow shipped** | Timeline-mix speech transcription, editable timed words/segments, per-word highlighting, caption styles and safe-zone placement, transcript search/tap-to-seek, Smart Review for fillers/low-confidence words/pauses, and SRT import/export ship with persistence, undo, and preview/export parity. An explicit transcript approval UI remains to connect range deletion to the shipped precision-edit commands. |
| 27 | **Stickers and graphics — core shipped** | Persisted image/emoji/SF Symbol layers, searchable library, project-safe imports, trim/move/transform, animation presets, blend modes, reusable favorites, undo, and preview/export parity. |
| 28 | **Templates — core shipped** | Versioned local template packages, ordered primary/overlay media slots, preserved fonts/transitions/audio/canvas, preview thumbnails, validation, isolated bundled assets, undoable application, and editable results. Explicit safe-zone editing and portable import/export remain. |
| 29 | **Effects architecture — core complete** | Ordered per-clip, overlay, and time-ranged adjustment-layer effects; bypass, parameters, presets, amount keyframes, cached render plans, undo/persistence, and shared preview/export rendering. |

#### Priority 29 — Effects stack and adjustment layers (core complete)

- **Targets:** primary clips and media overlays own non-destructive effect stacks. Program-level adjustment layers occupy visible timeline ranges and apply one shared color grade plus effect stack to every clip and overlay underneath them without changing those source items.
- **Workflow:** a new adjustment layer covers the current In/Out range, or the full project when no range is marked. The Effects sheet provides a searchable, categorized library of 36 curated recipes backed by 30 GPU-accelerated render primitives. Categories cover Featured, Motion, Light, Glitch, Pixel, Retro, Stylize, and Blur; recipes can combine temporal motion, distortion, color, texture, and screen treatments. Users can still add individual primitives, reorder operations, bypass effects or the entire layer, edit parameters, and remove stack items. Each effect also opens a large keyframe timeline with a time ruler, project timecode/frame labels, amount and curve summaries, tap-to-seek diamonds, add-at-playhead, and deletion.
- **Animation:** every effect owns an `EditorKeyframeTrack` for Amount, using the same hold/linear/eased cubic sampler as the rest of the editor. The diamond control writes at the current item-local time.
- **Rendering and caching:** `EditorVisualEffectRenderer` evaluates the ordered stack inside `EditorTransitionCompositor`. Immutable enabled-stack plans are cached, and the compositor's long-lived `CIContext` caches Core Image intermediates. Preview and export pass the same clip, overlay, and adjustment-layer instructions.
- **Project integrity:** effects and adjustment layers are Codable with safe empty defaults for older projects, included in composition fingerprints and snapshot undo/redo, inherited by split/freeze/duplicate/replace operations, and autosaved.

#### Priority 27 — Stickers and reusable graphics (core shipped)

- **Library:** the Graphics tool provides searchable emoji and SF Symbol collections, app-wide favorites, and photo/PNG import. Imported artwork is normalized to PNG and atomically copied into Mixtape Application Support, preserving transparency and avoiding temporary picker URLs.
- **Timeline behavior:** every `EditorGraphicOverlay` owns a visible start/end range and a dedicated purple graphics lane with draggable trim handles and whole-item movement. Selection, duplicate, delete, transform changes, and timeline edits participate in snapshot undo and autosave.
- **Canvas controls:** graphics can be positioned directly on the preview and inspected for size, scale, rotation, opacity, horizontal flip, six blend modes, and Pop/Pulse/Float/Bounce/Spin/Wiggle animation presets.
- **Rendering:** the live SwiftUI overlay and offline Core Animation export share the same reference canvas, timing sampler, transforms, visibility and asset sources. Fullscreen and export-preview surfaces use the same graphic layer as the main editor.
- **Compatibility:** project decoding defaults missing graphic collections and selections to empty values, so older saved projects continue to open unchanged.

#### Priority 28 — Templates (core workflow shipped)

The **TEMPLATES** workspace can capture the current edit as a named, versioned
`EditorProjectTemplate`. Its manifest keeps the authoritative `EditorProject` edit graph plus ordered
primary/overlay `EditorTemplateMediaSlot` records, expected media kinds, target durations, required
font families, and normalized action/title safe-area metadata. Applying a template therefore produces
ordinary editable clips, text, captions, graphics, audio lanes, effects, adjustment layers,
transitions, keyframes, canvas settings, markers, and sequence structure—not a flattened render.

Templates are stored as packages under Application Support. Audio files, imported graphic images,
and canvas artwork are copied into the package; paths are rebased when packages move within the app
container. Applying a template materializes another private asset copy scoped to the destination
project, so deleting the source template cannot break an applied edit. PhotoKit video/image slots keep
stable source identifiers while the current project's primary and overlay media fill matching slots in
timeline order. Short replacements preserve the template's target timeline duration with a safe speed
fallback and remove incompatible reverse, tracking, stabilization, or speed-curve state as needed.

The library shows generated preview thumbnails, duration, canvas format, font count, media/overlay
slot counts, and missing-reference diagnostics. Application is one undoable timeline transaction,
keeps the destination project's identity and performance settings, invalidates preview/render caches,
autosaves, and returns the user to the normal editor. Future-schema templates are rejected safely.
Explicit guide editing and portable template import/export remain follow-up work.

#### Priority 25 — Text animation (complete)

`EditorTextAnimation` is stored on every `EditorTextOverlay` with backward-compatible project
decoding. The Text sheet's **Animate** workspace exposes independent **In**, **Out**, and **Loop**
slots, duration/speed, intensity, and per-character delay. The shipped catalog covers fade,
directional slide, zoom, bounce, blur, typewriter, pop, pulse, and wiggle; animations can be cleared
without touching text styling or manual keyframes. A selected caption animation can be applied to
the entire caption track.

Animation samples are composed after the existing local-time text keyframes: opacity and scale
multiply, while position and rotation add. Live SwiftUI preview and offline Core Animation export
use the same evaluator. Export samples transforms at 30 fps, crossfades sharp and pre-blurred render
layers for deterministic Gaussian-style blur, and creates timed prefix layers for typewriter text.
Caption typewriter reveal operates by word so karaoke highlighting stays readable. Animation data
survives save/reopen, duplicate, caption split/merge, and ordinary timeline trim/move operations.

#### Priority 26 — Captions and transcript editing (core workflow shipped)

`EditorCaptionService` offers **Video audio** (the robust default: embedded dialogue with mute/gain
ignored) and **Entire timeline mix** (voiceovers, audio lanes, mute/solo, track gain, and master gain).
Both sources follow video trims and speed changes. Apple's Speech framework returns absolute timed words and confidence values; Mixtape
groups these into short caption segments stored as ordinary `EditorTextOverlay` values with caption
metadata. Regeneration is cancellable and only replaces the existing captions after recognition
finishes successfully.

The Captions tool provides language selection, editable/searchable transcript segments, tap-to-seek,
style presets, per-word highlight color, bottom safe-zone placement, and SRT import/export. SRT timing
is millisecond based; imported untimed words receive deterministic timing distributed inside their
segment. Caption words and style fields decode with backward-compatible defaults and participate in
the existing snapshot undo and project autosave path.

Professional transcript refinement includes segment split/merge, direct word correction, 50 ms
word-boundary nudging, segment deletion, undoable delete-all, text/highlight color and global size
controls. Smart Review identifies common filler words, low-confidence recognition, and pauses of
0.65 seconds or longer. Filler removal is explicitly caption-only; pause review seeks the timeline
but never cuts media without a future approved ripple operation. Automatic segmentation also breaks
at pauses and enforces word, duration, and character-count limits for readable creator-style lines.

Live preview resolves the active word from the global playhead. Offline export creates deterministic
caption render states for the same word intervals, preserving preview/export parity without adding a
second caption compositor. Approved transcript-range ripple deletion remains deliberately gated behind
an explicit confirmation UI; it must call the shipped `EditorViewModel` precision timeline commands
as one undo transaction. Smart Review already detects fillers, low-confidence words, and
silence gaps without mutating media.

### Phase 5 — reliability, performance, and project portability

#### Priority 30 — Proxy and render cache (core workflow shipped)

The editor now has a persistent **CACHE** workspace for performance media. Each project stores its
playback policy (`EditorProxySettings`) independently: proxies on/off, automatic generation, 540p or
720p profile, background render cache, and a bounded disk budget. Missing fields decode to safe
defaults, so existing project documents open without migration work.

`EditorMediaCache` writes disposable files beneath the app's Caches directory using atomic temporary
exports. A proxy key includes the PhotoKit local identifier, asset modification date, pixel dimensions,
duration, and encoding profile. Replaced or edited source media therefore cannot accidentally reuse an
older proxy. Cache hits update recency, and the combined proxy/render store uses least-recently-used
eviction against the user-selected budget. Generated files are excluded from backup. New work pauses
below a 512 MB free-space floor, and editor teardown cancels active proxy and render exports.

Preview composition asks for a matching proxy only for ordinary forward playback. Missing proxies,
reverse playback, stills, and any failed lookup fall back to the original asset. Offline export passes
`isOfflineRender: true`, which bypasses proxy selection entirely; project documents continue to retain
the original Photos identity as their source of truth.

The background render cache is keyed by the complete composited edit fingerprint: primary/overlay
timing and transforms, speed, reverse state, effects, adjustment layers, transitions, canvas, audio
lanes, gain/mute/solo, and master volume. Edits debounce for three seconds before utility-priority
rendering, while **Render current cut now** is user-initiated. Preview uses a cached render only on an
exact fingerprint match. Text and reusable graphics remain live SwiftUI layers over that render, so
their selection handles and interaction stay immediate; offline export still burns them in through the
authoritative full-resolution composition path.

The CACHE sheet reports separate proxy/render counts and total bytes, offers 540p/720p generation,
shows batch progress and low-storage/failure messages, and can clear proxies or preview renders
independently. Clearing either cache never deletes, rewrites, or unlinks original media.

Physical-device QA should cover: iCloud-only source download; proxy generation cancellation; 540p ↔
720p switching; forward/reverse clips; video overlays; adjustment layers; edit invalidation after trim,
speed, effect, canvas, and mix changes; playback after clearing each cache; low-storage messaging; save
and reopen; and confirmation that final export resolution/detail comes from the original assets.

| Priority | Feature | Definition of done |
|----------|---------|--------------------|
| 30 | **Proxy and render cache — core shipped** | Background proxy generation, exact edit-fingerprint render reuse, LRU/low-storage controls, and original-only full-resolution export are implemented. Remaining work is device stress/performance telemetry. |
| 31 | **Project packages and relinking** | Optional copied media, missing-media UI, relink by asset/file identity, portable packages, and cleanup policies. |
| 32 | **Schema migration and recovery** | Versioned project documents, migrations, atomic saves, crash recovery snapshots, corruption diagnostics, and backup restore. |
| 33 | **Background export queue** | Multiple cancellable jobs, app lifecycle recovery, notifications, thermal/storage checks, and resumable UI state. |
| 34 | **Color management** | Scopes are complete for representative SDR graded frames. Remaining: explicit SDR/HDR pipeline, transfer functions, wide-gamut handling, tone mapping, metadata validation, continuous-playback scope sampling, and HDR-aware scope scales. |
| 35 | **Automated quality suite** | Unit tests, UI flows, golden-frame renders, orientation matrices, audio timing tests, export probes, and long-project stress tests. |
| 36 | **Performance budgets** | Signposted preview/export stages, frame-drop and memory targets, thermal testing, cancellation latency, and regression dashboards. |
| 37 | **iCloud and collaboration readiness** | Conflict-safe project sync, asset availability states, deterministic document IDs, and future collaboration-friendly edit operations. |

### Phase 6 — AI-assisted workflow

This phase adds capabilities that are not already covered by the motion, audio,
caption, or creative-asset priorities above. AI should produce analysis, suggestions,
or ordinary media assets; the deterministic editor remains responsible for every
accepted timeline mutation and rendered frame.

| Priority | Feature | Definition of done |
|----------|---------|--------------------|
| 38 | **Smart ingest and rough cut** | Index PhotoKit and Files/iCloud sources into bins with tags and semantic search; detect shots, duplicates, blur, poor exposure, speakers, actions, and likely highlights; then propose a reviewable first assembly from a duration, format, and text brief. Confidence is visible, source media is never silently discarded, and analysis is cached by asset fingerprint. |
| 39 | **Editing copilot** | Convert requests such as “make a 30-second vertical cut, keep every product mention, add captions, and duck the music” into a validated, structured edit plan. Show the proposed operations and preview/diff before applying them through existing `EditorViewModel` commands as one undoable transaction. |
| 40 | **Generative finishing and provenance** | Offer optional object removal, background replacement, frame extension, B-roll, thumbnail, and sound suggestions through cancellable on-device or disclosed cloud jobs. Generated results are labelled and imported as normal relinkable assets with model, prompt, license, consent, and attribution metadata. |

#### Where AI fits into existing priorities

| Existing work | AI's bounded role |
|---------------|-------------------|
| **Priority 12 — tracking/stabilization** | Suggest subjects, refine masks, follow faces/objects, and recommend safe auto-reframe paths; the existing motion samples and compositor remain the source of truth. |
| **Priorities 16, 18, and 19 — audio** | Classify dialogue/music/effects, propose cleanup and ducking, and detect beats/sections; accepted parameters render through the shared audio graph. |
| **Priorities 22, 23, and 26 — language** | Transcribe, punctuate, summarize, translate, and draft narration/captions; users approve timed segments before timeline or voice changes are committed. |
| **Priority 29 — effects architecture** | Host AI-generated masks or imported generative results as explicit stack items/assets, never as a hidden preview-only effect. |

#### AI implementation contract

```text
Source media
    -> cancellable analysis jobs
    -> cached, time-coded metadata (shots, words, beats, tracks, quality scores)
    -> suggestion or structured edit-plan layer
    -> user review and preview
    -> validated EditorViewModel commands in one undo transaction
    -> existing preview, persistence, and export pipeline
```

- Store analysis separately from user edits and key it by asset fingerprint, model
  version, and analysis settings so stale results are invalidated deliberately.
- Use confidence scores and make low-confidence results easy to correct. AI must never
  silently delete source media, overwrite approved edits, or bypass undo/redo.
- Run lightweight [Vision](https://developer.apple.com/documentation/vision),
  [Speech](https://developer.apple.com/documentation/speech), and
  [Sound Analysis](https://developer.apple.com/documentation/soundanalysis) work on
  device when practical; use [Core ML](https://developer.apple.com/documentation/coreml)
  for specialized on-device models.
- Gate [Foundation Models](https://developer.apple.com/documentation/foundationmodels)
  by runtime availability. Mixtape currently targets iOS/iPadOS 18.6, while model
  availability depends on OS, hardware, region, and Apple Intelligence settings.
- Cloud jobs disclose what leaves the device, estimated time/cost, cancellation,
  retention policy, and whether inputs or outputs may be used for training.
- Voice cloning and identity-preserving dubbing require explicit consent. Generated or
  downloaded media keeps provenance, license, and attribution through export.
- Keep a non-AI manual workflow for every essential action. AI is not a substitute for
  trim/split correctness, media relinking, color math, audio gain, export, or licensing.

### Platform polish

- Adaptive iPad layout with trackpad, pointer hover, keyboard shortcuts, and external display preview.
- Accessibility labels, VoiceOver timeline navigation, Dynamic Type-safe sheets, reduced-motion behavior, and contrast audits.
- Localization, right-to-left layout checks, onboarding, contextual help, and non-destructive editing education.
- Searchable command menu, edit history inspection, favorites/recent assets, and reusable presets.
- Storage management for imported audio, generated photo videos, proxies, caches, and completed exports.

### Engineering guardrails

- Keep transition/effect identifiers stable once persisted; add aliases or migrations instead of renaming raw values.
- Keep views declarative and route all mutations through `EditorViewModel`.
- Never add a preview-only effect: preview and export must use the same renderer and timing model.
- Treat orientation, color space, alpha/background pixels, audio tails, cancellation, and missing media as test dimensions.
- Avoid monolithic catalogs or render switches; use separate metadata, parameter, instruction, and renderer files as each system grows.
- Measure on physical devices, including older supported hardware, portrait/landscape inputs, photos, HDR media, and long timelines.
