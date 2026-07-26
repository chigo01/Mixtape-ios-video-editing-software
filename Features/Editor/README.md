# Editor feature tutorial

This document explains **what the Mixtape editing flow does today** — from **New Project and media selection** through the **timeline editor** — **how the pieces fit together**, and **where to learn more** (Apple docs, WWDC, and guides). Read it alongside the source; filenames below point you at the code.

---

## 1. From the home screen to the editor (project + media pick)

The flow before **`EditorScreen`** is: **home list → New Project → pick photos/videos → Next (preload) → editor**. Projects are **saved automatically** as JSON (`EditorProject`) — clip order, trim, speed, volume, text overlays, **background audio clips**, playhead, selection, and **project title** — not raw video files.

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
- **`EditorProjectResolver.clips(from:)`** rehydrates **`EditorClip`** from **`SavedEditorClip`** (`assetLocalIdentifier` + trim/speed) via PhotoKit.
- **`EditorViewModel(project:)`** loads resolved clips. After this point, the editor only needs **`EditorClip`**, **`timelinePosition`**, and the player.

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
| **Full timeline length** | `totalDuration` = `max(videoDuration, audioEnd, textEnd)` — ruler and playback can extend past the last video frame when music or text runs longer. |
| **Text on screen** | `textOverlays` with global `startTime`/`endTime`; preview filters by `isVisible(at: timelinePosition)`. |
| **Background music** | `audioClips: [EditorAudioClip]` — each has `timelineStart`, trim range, volume; mixed in composition on separate tracks. |

So: **scrubbing the ruler** or **moving the playhead** updates `timelinePosition` only. The preview then asks: “At this global time, which clip is playing, and where inside that clip?”

**Key file:** `ViewModel/EditorViewModel.swift` — see `timelinePosition`, `clipAndLocalTime(at:)`, `timelineOffsetForClipIndex(_:)`.

**Clip duration on the timeline:** `Features/Editor/Model/EditorClip.swift` — `duration` and `sourceTime(forExportedLocal:)` connect **exported timeline seconds** to **source asset time** (trim + speed).

---

## 3. Architecture overview

**Navigation flow:** `ProjectListScreen` → **`CreateProjectScreen`** (picker) → **`EditorScreen`** (this subtree). The home screen owns the `NavigationStack` path; after project creation the picker route is **replaced** by the editor route, so back always returns home (see **§1.1 / §1.3**).

```
EditorScreen
├── EditorTopBar             ← back, undo/redo, Export → EditorExportScreen
├── EditorPreviewPlayer      ← 9:16 card, AVPlayerLayer, text overlay layer, HUD, fullscreen
├── SpeedToolPanel           ← when SPEED tool active (inline above timeline)
├── EditorTimeline           ← ruler, text lane, filmstrip clips, audio lane, playhead, + insert
├── EditorBottomToolbar      ← default tools (split, speed, volume, filter*, text)
├── EditorClipActionBar      ← when a clip is selected: back + contextual actions + delete
├── EditorTextActionBar      ← when a text overlay is selected: back + edit + delete
└── EditorAudioActionBar     ← when an audio clip is selected: split, volume, delete

VolumeToolPanel              ← bottom sheet when VOLUME tool active (clip or audio)
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

- **`EditorViewModel`** (`@MainActor`, `@Observable`): owns timeline state, **`textOverlays`**, **`audioClips`**, **`projectTitle`**, a **single** `AVPlayer?` backed by an **`AVMutableComposition`**, scrub/seek helpers, playback tick timer, and clip/text/audio-editing APIs (trim, split, insert, move, text overlays, delete clip, export orchestration).
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

1. **`EditorCompositionBuilder.makePlayerItem(from:audioClips:)`** (`Services/EditorCompositionBuilder.swift`):
   - Creates **`AVMutableComposition`**.
   - For each **`EditorClip`**, inserts the trimmed source range (`trimStart` … `trimEnd`) at the correct **composition time** (sequential cursor).
   - **Videos:** `PHImageManager.requestAVAsset(forVideo:)` → insert video + audio tracks (per-clip volume via **`AVAudioMix`** when not 100%).
   - **Photos:** converts still → short silent video segment (via **`AVAssetWriter`**) so photos sit in the same composition.
   - **Background audio:** each **`EditorAudioClip`** is inserted on its own composition audio track at `timelineStart` (full trim duration — not capped to video length).
   - **Extended timeline:** when audio/text extends past the last video frame, the video track gets an empty tail and video-composition instructions are extended so preview still renders correctly.
2. An **`AVVideoComposition`** applies each source track’s **`preferredTransform`** and **aspect-fits** into a **1080×1920** portrait canvas (matches `EditorPreviewLayout` 9∶16). Without this, iPhone portrait footage looks **rotated / squashed** in the preview. On **iOS 26+** it is built with the new **`AVVideoComposition.Configuration`** value type (plus `AVVideoCompositionInstruction.Configuration` / `AVVideoCompositionLayerInstruction.Configuration`); on older OS versions we fall back to the deprecated **`AVMutableVideoComposition`** subclasses, which Apple deprecated in iOS 26.
3. **`EditorViewModel`** keeps **one** `AVPlayer` whose item is that composition.
4. **`playbackTick`** reads **`player.currentTime()`** → updates **`timelinePosition`**. No manual “advance to next clip” hop.
5. When clips, audio, or per-clip volume change, **`invalidateComposition()`** forces a rebuild on next align/play. **`clipsFingerprint()`** includes clip + audio state so warmed picker compositions are skipped when audio is present.

**Seeking after scrub:** `alignPlaybackToTimeline()` → `ensureCompositionPlayer()` → `seekPlayerToTimeline()`.

**Warmed composition:** `EditorCompositionBuilder.warmUp` pre-builds video-only items on the picker **Next** screen. `consumeWarmedPlayerItem` is only used when **no** `audioClips` are loaded.

**Poster vs video layer:** `EditorPreviewPlayer` hides the still poster while the video layer is active so you don’t see double images.

### 4.2 Audio on device speaker

**`AudioSessionConfigurator`** (`Core/AudioSessionConfigurator.swift`) sets **`AVAudioSession`** category **`.playback`** at app launch. Without this, preview audio often only plays on AirPods (default **`.soloAmbient`** respects the silent switch and routing quirks).

Configured in **`MixtapeApp.init()`** and before playback starts.

### 4.3 Mental model

| Layer | Responsibility |
|-------|----------------|
| **`EditorClip[]`** | Edit model: trim, speed, asset ref |
| **`EditorCompositionBuilder`** | Preview/export-shaped **render** of all clips |
| **`AVPlayer`** | Plays global time `0 … totalDuration` |
| **`timelinePosition`** | Same global time; drives ruler + playhead UI |
| **`clipAndLocalTime(at:)`** | Maps global time → which clip is “under” the playhead (for selection, split, HUD) |

The **+ insert slots** on the timeline are **UI-only gaps** (`TimelineLayout.insertSlotWidth`). They affect **pixel layout** of the filmstrip, **not** playback seconds.

### 4.4 Useful reading

- [AVMutableComposition](https://developer.apple.com/documentation/avfoundation/avmutablecomposition) — stitching clips.
- [AVVideoComposition.Configuration](https://developer.apple.com/documentation/avfoundation/avvideocomposition/configuration) — orientation, transforms, render size (iOS 26+ replacement for the deprecated [AVMutableVideoComposition](https://developer.apple.com/documentation/avfoundation/avmutablevideocomposition)). 
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

When text overlays exist, `makeVideoComposition` uses the legacy **`AVMutableVideoComposition`** path (even on iOS 26+) because `AVVideoCompositionCoreAnimationTool` requires it. `enablePostProcessing = true` on each instruction so the animation tool runs. The iOS 26 **Configuration** path (no animation tool) uses `enablePostProcessing = false`.

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
| `ViewModel/EditorViewModel.swift` | Timeline, playback, text/audio overlays, `projectTitle`, undo, export, auto-save. |
| `Model/EditorExportSettings.swift` | Resolution, frame rate, format enums + size estimate. |
| `Services/EditorCompositionBuilder.swift` | Shared `build(from:textOverlays:audioClips:frameRate:)` for preview + export; per-clip + background audio mix; extended timeline fix. |
| `Services/EditorExportService.swift` | `AVAssetExportSession` with settings + overlays + audio; sanitized project-title filename; save to Photos. |
| `Services/EditorTextOverlayRenderer.swift` | SwiftUI text → `UIImage` for export (`ImageRenderer` + off-screen fallback). |
| `Services/EditorUndoManager.swift` | Snapshot undo/redo stack. |
| `Services/ClipThumbnailService.swift` | Cached multi-frame filmstrip generation. |
| `View/Components/EditorTimeline.swift` | Ruler, text lane, filmstrip, audio lane, scrub, playhead, `TimelineLayout`. |
| `View/Components/ClipFilmstripView.swift` | Tiled thumbnail row per clip. |
| `View/Components/SpeedToolPanel.swift` | Speed presets + slider when SPEED tool is active. |
| `View/Components/VolumeToolPanel.swift` | Volume presets + slider sheet (clip or audio clip). |
| `View/Components/AudioPickerView.swift` | Document picker for background music import. |
| `View/Components/EditorAudioActionBar.swift` | Contextual toolbar when an audio clip is selected. |
| `View/Components/ClipReorderGestureView.swift` | Long-press drag reorder: `UILongPressGestureRecognizer`, `ClipReorderState`, `TimelineClipMetrics`. |
| `View/Components/ClipTrimHandleView.swift` | UIKit trim handles (`UIViewRepresentable`) — clips, text, and audio. |
| `View/Components/EditorPreviewPlayer.swift` | Inline preview, text overlay layer, HUD, `PlayerLayerView`. |
| `View/Components/EditorTextOverlayLayerView.swift` | SwiftUI text composited over preview (inline + fullscreen). |
| `View/Components/TextOverlayEditorSheet.swift` | Bottom sheet for text content + style controls. |
| `View/Components/EditorClipActionBar.swift` | Contextual toolbar when a clip is selected (incl. delete). |
| `View/Components/EditorTextActionBar.swift` | Contextual toolbar when a text overlay is selected. |
| `View/Components/EditorTopBar.swift` / `EditorBottomToolbar.swift` | Undo/redo/export + main editing tools. |
| `Model/EditorClip.swift` | Clip model, trim/speed/volume/split, preview aspect. |
| `Model/EditorTextOverlay.swift` | Text overlay model + style enums. |
| `Model/EditorAudioClip.swift` | Background audio clip model (trim, move, split, volume). |
| `Model/EditorTimelineSnapshot.swift` | Undo snapshot (`clips`, playhead, selections, `textOverlays`, `audioClips`). |
| `Model/EditorTool.swift` | Tool enum (`filter` not wired yet). |
| `ProjectList/Model/EditorProject.swift` | Codable project document (`SavedEditorClip`, `SavedTextOverlay`, `SavedAudioClip`, etc.). |
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

- Preview calls **`EditorCompositionBuilder.build(from:audioClips:frameRate:)`** (no text overlays in preview player). Export calls **`build(from:textOverlays:audioClips:frameRate:)`** — same 1080×1920 canvas, transforms, text burn-in, and background audio. Export passes the user's frame-rate setting and **`projectTitle`** for the output filename via `EditorExportService`.

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
12. Tap **Export** → preview/scrub on **`EditorExportScreen`** → set project name → configure settings → export → confirm Photos + Share (filename = sanitized project title).
13. Add background music → trim/move/split → adjust volume → confirm playback past video end if music is longer.
14. Edit → leave editor → reopen from **`ProjectCardView`** on home — confirm `ProjectStore` round-trip (clips, text, audio, title).

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
| **Orientation fix** | Portrait video not rotated in preview | `AVVideoComposition.Configuration`, `preferredTransform` | Video composition transforms |
| **Export** | Render timeline → MP4 → Photos | `EditorExportService`, `EditorTopBar` Export | `AVAssetExportSession` |
| **Undo / Redo** | Snapshot restore after edits | `EditorUndoManager`, `EditorTimelineSnapshot` | Command / memento pattern |
| **Speed tool** | 0.25×–3× per clip; composition `scaleTimeRange` | `SpeedToolPanel`, `EditorCompositionBuilder.applySpeed` | Timeline vs source time |
| **Filmstrip thumbnails** | Multiple frames tiled per clip cell | `ClipFilmstripView`, `ClipThumbnailService` | `AVAssetImageGenerator` batching |
| **Project persistence** | JSON project files; home list opens saved edits | `EditorProject`, `ProjectStore`, `ProjectListViewModel` | Codable + PhotoKit rehydration |
| **Picker preload** | “Preparing…” on Next warms composition before editor | `EditorCompositionBuilder.warmUp`, `CreateProjectScreen` | Perceived performance |
| **Dedicated export screen** | Resolution / FPS / format settings + progress panel | `EditorExportScreen`, `EditorExportSettings` | `AVAssetExportSession` presets |
| **Smooth editor entry** | Composition build off main actor; deferred thumbnail load | `EditorViewModel`, `EditorScreen.task` | Main-thread responsiveness |
| **iOS 26 video composition** | `AVVideoComposition.Configuration` with pre-26 fallback | `EditorCompositionBuilder.makeVideoComposition` | Deprecated-API migration, `#available` |
| **Value-based home navigation** | Fixes “tap project A, open project B”; lazy destinations | `ProjectListRoute`, `ProjectListScreen` | `NavigationStack(path:)`, view identity |
| **Create flow back-stack** | Back from editor skips picker; list refreshes on return | `CreateProjectScreen.onProjectCreated`, `onChange(of: path)` | Programmatic path rewriting |
| **Project delete** | Long-press card → confirm → remove JSON | `ProjectListScreen`, `ProjectListViewModel.deleteProject` | `contextMenu`, `confirmationDialog` |
| **Card polish** | Whole card tappable; scrim overlay removed | `ProjectCardView` (`contentShape`) | Hit-testing clipped images |
| **Swipe-back restore** | Edge swipe pops despite hidden nav bars | `Core/SwipeBackEnabler.swift` | `interactivePopGestureRecognizer` delegate |
| **Clip reorder** | Long-press + drag to move clips forward/backward on timeline | `ClipReorderGestureView`, `EditorTimeline.clipsRow`, `EditorViewModel.moveClip` | `UILongPressGestureRecognizer` as continuous gesture, `@Observable` UIKit→SwiftUI bridge, `interactiveSpring` |
| **Text overlays** | Add/edit/delete overlays; timeline lane; preview layer; export burn-in | `EditorTextOverlay`, `TextOverlayEditorSheet`, `EditorTextOverlayLayerView`, `EditorTextOverlayRenderer`, `EditorCompositionBuilder` | SwiftUI overlay vs `AVVideoCompositionCoreAnimationTool` |
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

---

## 12. Feature guide (export, undo, speed, filmstrip, persist)

### 12.1 Export

- Tap **Export** in `EditorTopBar` → navigates to **`EditorExportScreen`**.
- **Preview section:** live composition playback (same `AVPlayer` as editor), play/pause, **scrub slider** with current/total time. After export completes, preview switches to the exported file.
- **Project name:** editable field — updates `projectTitle`, auto-saved on leave/export; also used as the **export filename** (`My Project.mp4`, sanitized).
- Configure **resolution** (720p / 1080p / 4K), **frame rate** (24–120), **quality** (Efficient / Balanced / High / Max with target Mbps), optional **HDR (HEVC 10-bit)**, and **format** (MP4 / MOV).
- **File size** estimate uses the selected video bitrate + AAC audio.
- Tap **EXPORT PROJECT** → `EditorViewModel.startExport(settings:)` → `EditorExportService.export(…, projectTitle:)` using **`EditorCompositionBuilder.build(from:textOverlays:audioClips:frameRate:)`** — clips + text burn-in + background audio.
- Bottom **progress panel**: percentage, linear bar, **Cancel** while rendering.
- On success: saved to Photos + **Share** sheet (filename reflects project title) and **Done**.
- Requires **Photo Library Add** permission (`NSPhotoLibraryAddUsageDescription`).

### 12.2 Undo / Redo

- **Undo** / **Redo** buttons live in `EditorTopBar` (next to back).
- `EditorUndoManager` stores **`EditorTimelineSnapshot`** (`clips`, `timelinePosition`, `selectedClipID`, `selectedAudioClipID`, `textOverlays`, `audioClips`).
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
- Stores **`SavedEditorClip`** (`assetLocalIdentifier`, trim, speed, volume), **`SavedTextOverlay`**, **`SavedAudioClip`** (file path, trim, `timelineStart`, volume), **`title`**, playhead, and selection — not raw video bytes.
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
- Timeline ruler extends when music is longer than video; preview holds the last video frame in the tail.
- **Export** includes all audio clips mixed under the video.

---

## 13. What to build next

Prioritized backlog. Items marked **done** shipped recently — kept here for context.

### Near term (core editor gaps)

| Priority | Feature | Current state |
|----------|---------|---------------|
| 1 | **Filter tool** | Toolbar toggles `selectedTool == .filter`; no panel, no `CIFilter` / custom compositor in `EditorCompositionBuilder`. |
| 2 | **Home-screen project rename** | **Partial:** rename on export screen saves `projectTitle`; no edit UI on `ProjectCardView` / long-press menu yet. |
| 3 | **Audio fade in/out** | Volume is step/preset only; no envelope or keyframed fade on audio clip edges. |
| 4 | **Clip transitions** | Hard cuts only; no crossfade / dip-to-black between adjacent video clips. |
| 5 | **Photo clip duration** | **Done:** photo-only DURATION presets/slider plus an uncapped right trim handle; updates timeline, preview/export, undo, and persistence. |

### Export & sharing

| Priority | Feature | Current state |
|----------|---------|---------------|
| 6 | **Export quality / bitrate** | **Done:** quality tiers (6–35 Mbps @1080p), live Mbps label, HDR/HEVC toggle; `AVAssetWriter` with explicit bitrate. |
| 7 | **Photos library display name** | Share sheet uses project title; asset name inside Photos may still be generic. |
| 8 | **Export range** | Always full `totalDuration`; no in/out markers for partial export. |

### Timeline & media

| Priority | Feature | Current state |
|----------|---------|---------------|
| 9 | **Duplicate clip** | No one-tap duplicate (video or audio). |
| 10 | **Per-clip crop / rotate** | Only global aspect-fit in video composition; no reframe UI. |
| 11 | **Video audio waveform** | Audio lane shows imported music; clip embedded audio has no waveform strip. |
| 12 | **Snap playhead** | Free scrub; no magnetic snap to clip/overlay edges or beat grid. |
| 13 | **Multi-select** | Single selection only across clips, text, and audio. |

### Text & creative

| Priority | Feature | Current state |
|----------|---------|---------------|
| 14 | **Text animations** | Static opacity keyframes (on/off); no typewriter, slide-in, or bounce presets. |
| 15 | **Stickers / emoji layer** | Text only; no sticker track or SF Symbol overlays. |
| 16 | **Templates** | Fixed 9:16 canvas; no 1:1 / 16:9 / TikTok-safe-zone presets. |

### Platform & polish

| Priority | Feature | Current state |
|----------|---------|---------------|
| 17 | **Beat sync / auto-cut** | Manual editing only; no BPM detection or cut-to-beat assist. |
| 18 | **Voiceover recording** | Import audio files only; no in-app mic capture lane. |
| 19 | **iCloud project sync** | Local JSON in Application Support only. |
| 20 | **iPad layout** | Phone-first; no split view, keyboard shortcuts, or pointer hover on timeline. |
| 21 | **Haptics on snap** | Reorder has haptics; trim/split/playhead snap do not. |

### Recently shipped (for reference)

| Feature | Notes |
|---------|-------|
| ~~Export preview playback~~ | Live player + scrub slider on `EditorExportScreen`. |
| ~~Project name on export~~ | Field on export screen; persists + drives share filename. |
| ~~Background audio~~ | Multi-clip lane, trim, move, split, volume, export mix. |
| ~~Volume tool~~ | `VolumeToolPanel` for clip and audio clip. |
| ~~Extended timeline~~ | Audio/text can run past video end without breaking preview. |
| ~~Export quality / bitrate~~ | Efficient–Max tiers, Mbps label, HDR/HEVC toggle, writer encode. |
| ~~Photo clip duration~~ | Photo-only DURATION presets/slider + uncapped right-edge stretching with timeline, preview/export, undo, and persistence support. |
