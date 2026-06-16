# Editor feature tutorial

This document explains **what the Mixtape editing flow does today** — from **New Project and media selection** through the **timeline editor** — **how the pieces fit together**, and **where to learn more** (Apple docs, WWDC, and guides). Read it alongside the source; filenames below point you at the code.

---

## 1. From the home screen to the editor (project + media pick)

The flow before **`EditorScreen`** is: **home list → New Project → pick photos/videos → Next (preload) → editor**. Projects are **saved automatically** as JSON (`EditorProject`) — clip order, trim, speed, and playhead — not raw video files.

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
| **Total length** | `totalDuration` = sum of each clip’s **timeline** duration (after trim/speed). |

So: **scrubbing the ruler** or **moving the playhead** updates `timelinePosition` only. The preview then asks: “At this global time, which clip is playing, and where inside that clip?”

**Key file:** `ViewModel/EditorViewModel.swift` — see `timelinePosition`, `clipAndLocalTime(at:)`, `timelineOffsetForClipIndex(_:)`.

**Clip duration on the timeline:** `Features/Editor/Model/EditorClip.swift` — `duration` and `sourceTime(forExportedLocal:)` connect **exported timeline seconds** to **source asset time** (trim + speed).

---

## 3. Architecture overview

**Navigation flow:** `ProjectListScreen` → **`CreateProjectScreen`** (picker) → **`EditorScreen`** (this subtree). The home screen owns the `NavigationStack` path; after project creation the picker route is **replaced** by the editor route, so back always returns home (see **§1.1 / §1.3**).

```
EditorScreen
├── EditorTopBar             ← back, undo/redo, Export → EditorExportScreen
├── EditorPreviewPlayer      ← 9:16 card, AVPlayerLayer, HUD, fullscreen
├── SpeedToolPanel           ← when SPEED tool active
├── EditorTimeline           ← ruler, filmstrip clips, playhead, + insert
└── EditorBottomToolbar      ← split, speed, volume, filter, text

EditorExportScreen (pushed from Export)
├── Preview + duration badge
├── Resolution / frame rate / format settings
├── File size estimate
└── Export panel             ← progress, Cancel, Share on complete
```

- **`EditorViewModel`** (`@MainActor`, `@Observable`): owns timeline state, a **single** `AVPlayer?` backed by an **`AVMutableComposition`**, scrub/seek helpers, playback tick timer, and clip-editing APIs (trim, split, insert).
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

1. **`EditorCompositionBuilder.makePlayerItem(from:)`** (`Services/EditorCompositionBuilder.swift`):
   - Creates **`AVMutableComposition`**.
   - For each **`EditorClip`**, inserts the trimmed source range (`trimStart` … `trimEnd`) at the correct **composition time** (sequential cursor).
   - **Videos:** `PHImageManager.requestAVAsset(forVideo:)` → insert video + audio tracks.
   - **Photos:** converts still → short silent video segment (via **`AVAssetWriter`**) so photos sit in the same composition.
2. An **`AVVideoComposition`** applies each source track’s **`preferredTransform`** and **aspect-fits** into a **1080×1920** portrait canvas (matches `EditorPreviewLayout` 9∶16). Without this, iPhone portrait footage looks **rotated / squashed** in the preview. On **iOS 26+** it is built with the new **`AVVideoComposition.Configuration`** value type (plus `AVVideoCompositionInstruction.Configuration` / `AVVideoCompositionLayerInstruction.Configuration`); on older OS versions we fall back to the deprecated **`AVMutableVideoComposition`** subclasses, which Apple deprecated in iOS 26.
3. **`EditorViewModel`** keeps **one** `AVPlayer` whose item is that composition.
4. **`playbackTick`** reads **`player.currentTime()`** → updates **`timelinePosition`**. No manual “advance to next clip” hop.
5. When clips change (trim commit, split, insert), **`invalidateComposition()`** forces a rebuild on next align/play.

**Seeking after scrub:** `alignPlaybackToTimeline()` → `ensureCompositionPlayer()` → `seekPlayerToTimeline()`.

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
4. **Whole-column panning:** a `GeometryReader` gives the timeline **full height**; the scroll content uses a fixed-height `VStack` plus a `Spacer` and `.contentShape(Rectangle())` so the **empty band under the tracks** is still inside the scroll view and pans horizontally — important when you add **multiple overlay rows** later (stack them above the `Spacer`).

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
| `View/Screens/EditorScreen.swift` | Editor layout, speed panel, navigates to export screen. |
| `View/Screens/EditorExportScreen.swift` | Dedicated export UI: settings, progress, share. |
| `ViewModel/EditorViewModel.swift` | Timeline, playback, undo, export orchestration, auto-save. |
| `Model/EditorExportSettings.swift` | Resolution, frame rate, format enums + size estimate. |
| `Services/EditorCompositionBuilder.swift` | Shared `build(from:frameRate:)` for preview + export; speed via `scaleTimeRange`. |
| `Services/EditorExportService.swift` | `AVAssetExportSession` with settings; save to Photos; cancel. |
| `Services/EditorUndoManager.swift` | Snapshot undo/redo stack. |
| `Services/ClipThumbnailService.swift` | Cached multi-frame filmstrip generation. |
| `View/Components/EditorTimeline.swift` | Ruler, scrub, filmstrip clips, playhead, `TimelineLayout`. |
| `View/Components/ClipFilmstripView.swift` | Tiled thumbnail row per clip. |
| `View/Components/SpeedToolPanel.swift` | Speed presets + slider when SPEED tool is active. |
| `View/Components/ClipReorderGestureView.swift` | Long-press drag reorder: `UILongPressGestureRecognizer`, `ClipReorderState`, `TimelineClipMetrics`. |
| `View/Components/ClipTrimHandleView.swift` | UIKit trim handles (`UIViewRepresentable`). |
| `View/Components/EditorPreviewPlayer.swift` | Inline preview, HUD, `PlayerLayerView`. |
| `View/Components/EditorTopBar.swift` / `EditorBottomToolbar.swift` | Undo/redo/export + editing tools. |
| `Model/EditorClip.swift` | Clip model, trim/speed/split, preview aspect. |
| `Model/EditorTimelineSnapshot.swift` | Undo snapshot (`clips`, playhead, selection). |
| `ProjectList/Model/EditorProject.swift` | Codable project document (`SavedEditorClip`, etc.). |
| `ProjectList/Services/ProjectStore.swift` | JSON persistence in Application Support. |
| `Core/AudioSessionConfigurator.swift` | Speaker / headphone routing for preview audio. |
| `Core/SwipeBackEnabler.swift` | Edge-swipe back despite hidden nav bars (see **§1.7**). |
| `Model/EditorTextOverlay.swift` / `EditorAudioTrack.swift` / `EditorTool.swift` | Other timeline / tool types. |

---

## 9. WWDC and deeper dives (video + articles)

**SwiftUI & gestures**

- WWDC sessions on SwiftUI layout and scroll views (search [Apple Developer Videos](https://developer.apple.com/videos/) for “SwiftUI ScrollView” / “Gestures”).

**AVFoundation (editing mindset)**

- Even before a full **AVComposition** pipeline, understanding **timebases**, **CMTime**, and **seek tolerances** pays off: [CMTime](https://developer.apple.com/documentation/coremedia/cmtime), [AVPlayer seek](https://developer.apple.com/documentation/avfoundation/avplayer/1385953-seek).

**Photos**

- [PhotoKit overview](https://developer.apple.com/documentation/photokit) — permissions, `PHAsset`, image vs video requests.

**Composition + export**

- Preview and export both call **`EditorCompositionBuilder.build(from:frameRate:)`** — one pipeline, same 1080×1920 canvas and transforms. Export passes the user’s frame-rate setting in (the resulting `AVVideoComposition` is immutable, so `frameDuration` is set at build time, not patched afterwards). Export uses **`AVAssetExportSession.export(to:as:)`** via `EditorExportService`. See [AVAssetExportSession](https://developer.apple.com/documentation/avfoundation/avassetexportsession).

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
10. Tap **Export** → configure settings on **`EditorExportScreen`** → watch `EditorExportService` progress → confirm Photos + Share.
11. Edit → leave editor → reopen from **`ProjectCardView`** on home — confirm `ProjectStore` round-trip.

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

---

## 12. Feature guide (export, undo, speed, filmstrip, persist)

### 12.1 Export

- Tap **Export** in `EditorTopBar` → navigates to **`EditorExportScreen`**.
- Configure **resolution** (720p / 1080p / 4K), **frame rate** (24–120), and **format** (MP4 / MOV).
- **File size** shows a rough estimate from duration + resolution.
- Tap **EXPORT PROJECT** → `EditorViewModel.startExport(settings:)` runs `EditorExportService.export(clips:settings:)` using the same **`EditorCompositionBuilder.build(from:frameRate:)`** pipeline as preview.
- Bottom **progress panel**: percentage, linear bar, **Cancel** while rendering.
- On success: saved to Photos + **Share** sheet (system `UIActivityViewController`) and **Done**.
- Requires **Photo Library Add** permission (`NSPhotoLibraryAddUsageDescription`).

### 12.2 Undo / Redo

- **Undo** / **Redo** buttons live in `EditorTopBar` (next to back).
- `EditorUndoManager` stores **`EditorTimelineSnapshot`** (`clips`, `timelinePosition`, `selectedClipID`, `textOverlays`).
- Registered automatically on: **split**, **insert**, **trim commit**, **speed change** (when SPEED panel closes).
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
- Stores **`SavedEditorClip`** (`assetLocalIdentifier`, trim, speed, volume) — not raw video bytes.
- **New project:** `CreateProjectScreen` saves on Next, then opens `EditorScreen(project:)`.
- **Resume:** `ProjectListScreen` lists saved projects via **`ProjectListViewModel`**; tap anywhere on a **`ProjectCardView`** to reopen. The list re-sorts by `modifiedAt` and reloads each time the navigation path empties.
- **Delete:** long-press a card → **Delete Project** → confirmation dialog → `ProjectStore.delete(id:)` removes the JSON file.
- **Home card UI:** cover thumbnail from first clip; title and clip count use **text shadows** for readability (the old gradient scrim overlay was removed).
- **Auto-save:** `EditorViewModel.scheduleSave()` debounces (~700ms) after edits; `saveNow()` on leave.

### 12.6 PhotoKit thumbnail loading (home + export)

- **`ProjectCardView.loadCover()`** must **not** use `withCheckedContinuation` with `.opportunistic` delivery — PhotoKit may call the handler **twice** (degraded preview, then final). Assign `coverImage` directly in the callback instead.
- Same pattern as **`MediaThumbnailView`**: callback → `@MainActor` state update, no single-resume continuation.

---

## 13. What to build next

1. **Volume tool** — per-clip `volume` + `AVAudioMix` in composition/export.
2. **Text overlays** — add/edit/delete `textOverlays` + burn-in on export.
3. **Background music** — wire `audioTrack` into composition (separate lane already stubbed in UI).
4. **Filter tool** — `CIFilter` via `AVVideoComposition` or custom compositor.
5. **Export preview playback** — tap play on `EditorExportScreen` preview header.
6. **Project rename** — edit title on home (delete already ships via long-press + confirmation).
