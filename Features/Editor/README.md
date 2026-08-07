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
├── SpeedToolPanel           ← when SPEED tool active (inline above timeline)
├── CropReframeToolPanel     ← crop/aspect, fit/fill, rotate/flip, straighten, scale
├── EditorTimeline           ← ruler, text, primary clip, video overlay, and audio lanes
├── EditorBottomToolbar      ← default tools (split, speed, volume, filter*, text, overlay)
├── EditorClipActionBar      ← when a clip is selected: back + contextual actions + delete
├── EditorOverlayActionBar   ← overlay split, speed, volume, opacity, resize, reset, text, delete
├── EditorTextActionBar      ← when a text overlay is selected: back + edit + delete
└── EditorAudioActionBar     ← when an audio clip is selected: split, volume, delete

VolumeToolPanel              ← bottom sheet when VOLUME tool active (primary, overlay, or audio)
OverlayOpacityToolPanel      ← bottom sheet for selected-overlay transparency
TextOverlayEditorSheet       ← bottom sheet (styles, fonts, position); live-syncs to preview
AudioPickerView              ← sheet to import MP3/M4A etc. onto the audio lane

* filter: toolbar button only — no panel or CIFilter compositor yet

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
| **Editor preview** (inline + fullscreen) | SwiftUI layer — **`EditorTextOverlayLayerView`** composited on top of `PlayerLayerView` / poster. Visibility follows `overlay.isVisible(at: timelinePosition)`. |
| **Export** | Burned in via **`EditorCompositionBuilder.build(from:textOverlays:)`** → **`EditorTextOverlayRenderer`** (SwiftUI → `UIImage` via `ImageRenderer`) → **`AVVideoCompositionCoreAnimationTool`** with per-overlay opacity keyframes timed to `startTime`/`endTime`. |

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

- **Stage aspect ratio:** `EditorPreviewLayout.aspectWidthOverHeight` in `EditorClip.swift` (9∶16) — fixed editor canvas for every asset.
- **CapCut-style inline card:** `EditorScreen` constrains the preview with `maxWidth` (screen − 32pt inset) and `maxHeight` (~54% of screen). `EditorPreviewPlayer` uses `.aspectRatio(9:16, .fit)` so the card sizes itself with natural side margins — not edge-to-edge stretch.
- **Video gravity:** inline uses `.resizeAspect` (letterbox inside the 9:16 frame); fullscreen sheet uses `.resizeAspectFill`.

**Fullscreen:** Tapping the expand control calls `onFullscreen`, which presents a `fullScreenCover` with `EditorFullscreenPreviewSheet`. The **same** `EditorViewModel` (and thus the same `AVPlayer` when applicable) is used so playback state continues.

**`PlayerLayerView`** accepts `videoGravity`:

- Inline: `.resizeAspect` (letterboxed).
- Fullscreen: `.resizeAspectFill` (fills the screen, may crop).

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

**Model:** `EditorTextOverlay` (`Model/EditorTextOverlay.swift`) — text, `startTime`/`endTime`, font family/style/size, color, opacity, alignment, `xOffset`/`yOffset`.

**Adding text:** Tap **TEXT** in `EditorBottomToolbar` or `EditorClipActionBar` → `addTextOverlay()` creates a 3-second overlay at the playhead → opens **`TextOverlayEditorSheet`**.

**Timeline lane:** When `textOverlays` is non-empty, `EditorTimeline` renders a row above the clip filmstrip. Each bar shows truncated text; tap to select; **drag body** to move along the timeline. Selected overlays reuse **`ClipTrimHandleRepresentable`** to drag start/end times (same UIKit trim handles as clips, but times are global seconds).

**Editing:** `TextOverlayEditorSheet` has **Styles** and **Fonts** tabs — font presets, colors, size slider, opacity, alignment, position offsets. Changes call `updateTextOverlay(_:)` live. **Done** commits; empty text on dismiss deletes the overlay.

**Selection chrome:** `EditorScreen` swaps the bottom bar — clip → **`EditorClipActionBar`**; text → **`EditorTextActionBar`**; audio → **`EditorAudioActionBar`**; nothing selected → **`EditorBottomToolbar`**.

**Persistence:** Saved as **`SavedTextOverlay`** inside `EditorProject` JSON. Restored in `EditorViewModel.init(project:)`.

### 6.9 Background audio (CapCut-style)

**Model:** `EditorAudioClip` (`Model/EditorAudioClip.swift`) — imported file URL, `timelineStart`, `trimStart`/`trimEnd`, `volume`, `split(atSourceTime:)`.

**Adding audio:** Tap **+** on the audio lane → **`AudioPickerView`** sheet → file copied to app documents → `loadAudioClip(from:insertAfterIndex:)`.

**Timeline lane:** `EditorTimeline.audioRow` renders bars per clip (`AudioClipThumb`). Select for trim handles; **drag body** to move; **drag handles** to trim (parent scroll disabled while trimming).

**Contextual bar:** **`EditorAudioActionBar`** — SPLIT (at playhead), VOLUME (opens **`VolumeToolPanel`**), DELETE.

**Composition:** each clip → separate composition audio track + per-track volume in **`AVAudioMix`**. Timeline can extend past video when music is longer.

**Persistence:** `SavedAudioClip[]` in `EditorProject`; legacy `SavedAudioTrack` migrates to one clip on decode.

**Layout:** `TimelineLayout` positions video clips using `videoDuration`; ruler width uses `timelineExtent` (= `totalDuration`).

### 6.10 Volume tool

- Tap **VOLUME** (main toolbar, clip bar, or audio bar) → **`VolumeToolPanel`** bottom sheet.
- Targets **selected video clip** (embedded audio) or **selected audio clip** (background music).
- Presets, mute toggle, slider commits on release → `alignPlaybackToTimeline()` rebuilds **`AVAudioMix`**.

### 6.11 Contextual clip action bar

When a clip thumbnail is selected, **`EditorClipActionBar`** replaces the main toolbar (CapCut-style):

- **Back chevron** → `deselectClip()` returns to the main tool row.
- **SPLIT / SPEED / VOLUME / FILTER / TEXT** → same actions as the main toolbar (`performClipAction`).
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
| `Services/EditorCompositionBuilder.swift` | Shared preview/export composition; primary and overlay video tracks, transforms, transitions, audio mix, backing tracks, and extended timelines. |
| `Services/EditorTransitionCompositor.swift` | Metal-backed Core Image transitions; composites overlay layers after each GPU transition effect. |
| `Services/EditorExportService.swift` | Explicit `AVAssetReader`/`AVAssetWriter` encoding with bitrate/HDR settings, progress/cancel, sanitized project-title filename, and Photos save. |
| `Services/EditorTextOverlayRenderer.swift` | SwiftUI text → `UIImage` for export (`ImageRenderer` + off-screen fallback). |
| `Services/EditorUndoManager.swift` | Snapshot undo/redo stack. |
| `Services/ClipThumbnailService.swift` | Cached multi-frame filmstrip generation. |
| `View/Components/EditorTimeline.swift` | Ruler, text/primary-video/video-overlay/audio lanes, trim/move gestures, scrub, playhead, `TimelineLayout`. |
| `View/Components/ClipFilmstripView.swift` | Tiled thumbnail row per clip. |
| `View/Components/SpeedToolPanel.swift` | Speed/photo-duration controls plus the crop/reframe sheet controls. |
| `View/Components/VolumeToolPanel.swift` | Volume presets + slider sheet (clip or audio clip). |
| `View/Components/AudioPickerView.swift` | Document picker for background music import. |
| `View/Components/EditorAudioActionBar.swift` | Contextual toolbar when an audio clip is selected. |
| `View/Components/ClipReorderGestureView.swift` | Long-press drag reorder: `UILongPressGestureRecognizer`, `ClipReorderState`, `TimelineClipMetrics`. |
| `View/Components/ClipTrimHandleView.swift` | UIKit trim handles (`UIViewRepresentable`) — clips, text, and audio. |
| `View/Components/EditorPreviewPlayer.swift` | Inline preview, overlay drag/pinch selection layer, text layer, HUD, `PlayerLayerView`. |
| `View/Components/EditorTextOverlayLayerView.swift` | SwiftUI text composited over preview (inline + fullscreen). |
| `View/Components/TextOverlayEditorSheet.swift` | Bottom sheet for text content + style controls. |
| `View/Components/EditorClipActionBar.swift` | Contextual primary-clip and video-overlay action bars. |
| `View/Components/EditorTextActionBar.swift` | Contextual toolbar when a text overlay is selected. |
| `View/Components/EditorTopBar.swift` / `EditorBottomToolbar.swift` | Undo/redo/export + main editing tools. |
| `Model/EditorClip.swift` | Primary and overlay clip models; trim/split, overlay timing/transform, preview aspect. |
| `Model/EditorTransition.swift` | Single transition catalog: 105 stable identifiers plus picker title, icon, category, renderer routing, and opening/cut/closing targets. |
| `Model/EditorTextOverlay.swift` | Text overlay model + style enums. |
| `Model/EditorAudioClip.swift` | Background audio clip model (trim, move, split, volume, fade in/out). |
| `Model/EditorTimelineSnapshot.swift` | Undo snapshot for primary/overlay clips, endpoints, playhead, selections, text, and audio. |
| `Model/EditorTool.swift` | Tool enum (`filter` not wired yet). |
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
10. Tap **TEXT** → edit in **`TextOverlayEditorSheet`** → scrub through the overlay's time range and confirm preview text appears/disappears. Export and confirm text is burned into the file.
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
| **Speed tool** | 0.25×–3× per clip; composition `scaleTimeRange` | `SpeedToolPanel`, `EditorCompositionBuilder.applySpeed` | Timeline vs source time |
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
| **Text overlays** | Add/edit/delete overlays; timeline lane; preview layer; export burn-in | `EditorTextOverlay`, `TextOverlayEditorSheet`, `EditorTextOverlayLayerView`, `EditorTextOverlayRenderer`, `EditorCompositionBuilder` | SwiftUI overlay vs `AVVideoCompositionCoreAnimationTool` |
| **Video overlays** | Add, trim, move, split, resize, position, reset, delete, persist, and export picture-in-picture clips | `EditorOverlayClip`, `EditorTimeline`, `EditorOverlaySelectionLayer`, `EditorCompositionBuilder` | Multi-track `AVMutableComposition` + standard/custom video compositing |
| **Contextual toolbars** | Clip-selected and text-selected bottom bars (CapCut-style) | `EditorClipActionBar`, `EditorTextActionBar`, `EditorScreen` | Conditional chrome swapping |
| **Clip delete** | Remove selected clip (min 2 clips); playhead + selection adjust | `EditorClipActionBar`, `deleteSelectedClip` | Array editing + composition invalidation |
| **Text preview drag** | Drag selected overlay on preview to reposition | `EditorTextOverlayLayerView`, `beginTextOverlayPositionDrag` | `DragGesture` + offset undo batching |
| **Text style undo** | Sheet edits + position drag register one undo step | `beginTextOverlayEdit`, `finalizeTextOverlayEdit`, `TextOverlayEditorSheet` | Memento pattern (same as speed/trim) |
| **Background audio** | Import, trim, move, split, delete; multi-clip lane | `EditorAudioClip`, `AudioClipThumb`, `EditorAudioActionBar`, `AudioPickerView` | Multi-track `AVMutableComposition` + `AVAudioMix` |
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
- **Preview:** `EditorTextOverlayLayerView` filters overlays by `isVisible(at: timelinePosition)` — also shown in fullscreen preview.
- **Timeline:** dedicated lane above clips; tap bar to select; drag body to move; drag trim handles for `startTime`/`endTime`.
- **Preview drag:** select a text overlay, then drag it directly on the inline or fullscreen preview to adjust `xOffset`/`yOffset` (same offsets as the sheet sliders).
- **Export:** `EditorTextOverlayRenderer` rasterizes each overlay → `CALayer` + opacity keyframe animation in `EditorCompositionBuilder` (see **§4.5**).
- **Empty text on dismiss** auto-deletes the overlay.

### 12.8 Background audio

- Tap **+** on the audio lane → **`AudioPickerView`** imports an audio file (copied into the app sandbox).
- **Select** a bar → **`EditorAudioActionBar`**: split at playhead, volume sheet, delete.
- **Trim** with left/right handles (UIKit, same pattern as clips); **move** by dragging the selected bar body.
- **Split** creates two adjacent audio clips from one source file at the playhead-local time.
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
| **Audio** | Imported multi-clip audio lane with trim, move, split, volume, fade in/out, and export mixing. |
| **Text** | Styled text overlays with timeline trim/move, preview positioning, undo, persistence, and export burn-in. |
| **Video overlays** | Picture-in-picture video with trim/move/split/delete, preview drag/pinch transforms, audio, undo, persistence, and standard/GPU export parity. |
| **Projects** | Autosaved JSON projects, resume, home rename, delete confirmation, PhotoKit rehydration, and modified-date ordering. |
| **Export** | Preview, project filename, 720p/1080p/4K, 24–120 fps, bitrate tiers, MP4/MOV, optional HDR/HEVC, progress, cancellation, Photos, and Share. |
| **Rendering safety** | Orientation normalization, SDR GPU working space, and encoded black/white backing tracks that prevent green or uninitialized export frames. |

### Phase 1 — complete the core editing toolkit

| Priority | Feature | Definition of done |
|----------|---------|--------------------|
| 1 | **Color and filters** | Filter browser, intensity, exposure, contrast, saturation, temperature, tint, highlights/shadows, vignette, reset/copy, and identical GPU preview/export. |
| 2 | **Crop and reframe — complete** | Per-clip crop, rotate, flip, scale, position, straighten, Original/9:16/16:9/1:1/4:5 presets, optional safe-area/rule-of-thirds guides, and Fit/Fill background framing. Preview, undo, persistence, reopen, GPU transitions, and export use the same transform. |
| 3 | **Canvas formats** | 9:16, 16:9, 1:1, 4:5, and custom sizes with blur/color/image backgrounds and project-level persistence. |
| 4 | **Timeline snapping** | Magnetic playhead and clip/overlay edge snapping, visible guides, zoom-aware thresholds, and haptic feedback. |
| 5 | **Duplicate and replace** | Duplicate video/audio/text; replace a clip while preserving compatible trim, timing, transform, filters, and transitions. |
| 6 | **Export range** | In/out markers, selected-range export, range duration/size estimate, and correct audio/text trimming. |

### Phase 2 — motion and advanced compositing

| Priority | Feature | Definition of done |
|----------|---------|--------------------|
| 7 | **Keyframe engine** | A reusable time/value model and curve editor for transform, opacity, volume, crop, filters, text, and effects. |
| 8 | **Speed ramps** | Multiple speed points, curve presets, source/timeline remapping, pitch options, and transition-safe rendering. |
| 9 | **Reverse and freeze frame** | Cached reverse media generation, cancellable progress, freeze insertion, audio policy, and project relinking. |
| 10 | **Multi-layer video** | Additional video/overlay tracks with z-order, independent trim/move, opacity, transforms, and audio handling. |
| 11 | **Blend, mask, and chroma key** | Blend modes, shape/feather/invert masks, green-screen keying, spill suppression, and GPU export parity. |
| 12 | **Stabilization and motion tracking** | Vision-based subject/point tracking, transform smoothing, tracked text/stickers, and adjustable stabilization crop. |

### Phase 3 — professional audio

| Priority | Feature | Definition of done |
|----------|---------|--------------------|
| 13 | **Waveforms and meters** | Cached waveforms for imported and embedded clip audio, peak/RMS meters, clipping indication, and zoom-aware drawing. |
| 14 | **Voiceover recording** | Countdown, monitoring, punch-in, permission/error handling, waveform creation, and automatic timeline placement. |
| 15 | **Audio automation** | Volume keyframes, pan, crossfades, mute/solo, track gain, and master limiting. |
| 16 | **Audio cleanup** | Noise reduction, EQ, compressor, de-esser, normalize/loudness target, and speech enhancement presets. |
| 17 | **Ducking and beat tools** | Speech/music detection, adjustable auto-ducking, BPM/beat markers, snap-to-beat, and assisted beat cuts. |

### Phase 4 — titles, captions, and reusable creative assets

| Priority | Feature | Definition of done |
|----------|---------|--------------------|
| 18 | **Text animation** | In/out/loop presets, per-character timing, typewriter, bounce, slide, blur, and keyframe interoperability. |
| 19 | **Captions** | Speech transcription, editable timed segments, word highlighting, caption styles, safe zones, and SRT import/export. |
| 20 | **Stickers and graphics** | Image/emoji/SF Symbol overlays, animated assets, trim/move/transform, blend modes, and reusable favorites. |
| 21 | **Templates** | Versioned project templates with replaceable media slots, fonts, transitions, audio, safe zones, and preview thumbnails. |
| 22 | **Effects architecture** | Stackable per-clip and adjustment-layer effects with ordering, enable/bypass, parameters, presets, and render caching. |

### Phase 5 — reliability, performance, and project portability

| Priority | Feature | Definition of done |
|----------|---------|--------------------|
| 23 | **Proxy and render cache** | Background proxy generation, cache invalidation by edit fingerprint, low-storage controls, and full-resolution export. |
| 24 | **Project packages and relinking** | Optional copied media, missing-media UI, relink by asset/file identity, portable packages, and cleanup policies. |
| 25 | **Schema migration and recovery** | Versioned project documents, migrations, atomic saves, crash recovery snapshots, corruption diagnostics, and backup restore. |
| 26 | **Background export queue** | Multiple cancellable jobs, app lifecycle recovery, notifications, thermal/storage checks, and resumable UI state. |
| 27 | **Color management** | Explicit SDR/HDR pipeline, transfer functions, wide-gamut handling, tone mapping, metadata validation, and scopes. |
| 28 | **Automated quality suite** | Unit tests, UI flows, golden-frame renders, orientation matrices, audio timing tests, export probes, and long-project stress tests. |
| 29 | **Performance budgets** | Signposted preview/export stages, frame-drop and memory targets, thermal testing, cancellation latency, and regression dashboards. |
| 30 | **iCloud and collaboration readiness** | Conflict-safe project sync, asset availability states, deterministic document IDs, and future collaboration-friendly edit operations. |

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
