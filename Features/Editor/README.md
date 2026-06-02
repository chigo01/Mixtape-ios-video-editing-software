# Editor feature tutorial

This document explains **what the Mixtape editing flow does today** — from **New Project and media selection** through the **timeline editor** — **how the pieces fit together**, and **where to learn more** (Apple docs, WWDC, and guides). Read it alongside the source; filenames below point you at the code.

---

## 1. From the home screen to the editor (project + media pick)

The flow before **`EditorScreen`** is: **home list → New Project → pick photos/videos from the library → Next → editor**. There is no separate “save project” step yet; the **ordered selection** becomes the timeline.

### 1.1 App entry and home screen

- **`MixtapeApp`** (`App/MixtapeApp.swift`) hosts **`ProjectListScreen`** in a `WindowGroup`.
- **`ProjectListScreen`** (`Features/ProjectList/Presentation/ProjectListScreen.swift`) uses a **`NavigationStack`**, title copy, and a **“New Project”** **`NavigationLink`** that pushes **`CreateProjectScreen`**.
- The list of **`ProjectCardView`** rows is driven by **`projectMockModels`** today—placeholder “projects,” not wired to real persistence. The meaningful handoff into editing is **`CreateProjectScreen` → `EditorScreen(media:)`**.

### 1.2 New Project screen = library + selection

- **`CreateProjectScreen`** is a thin wrapper around **`MediaLibraryPickerScreen`** (same grid UX, different title / confirm button).
- **`MediaLibraryPickerScreen`** (`Features/ProjectList/Presentation/MediaLibraryPickerScreen.swift`) owns **`@State private var vm = PhotoLibraryViewModel()`** and is **reused inside the editor** when you tap **+** on the timeline to insert more clips.
- **`.onAppear { vm.requestAccessAndLoad() }`** starts the PhotoKit permission flow and, once **`.authorized`** or **`.limited`**, loads assets.
- **`PhotoLibraryViewModel`** (`Features/ProjectList/Presentation/ViewModel/PhotoLibraryViewModel.swift`):
  - Fetches **`PHAsset`**s with **`PHAsset.fetchAssets`** (sorted by **`creationDate`**, newest first) and wraps each as **`MediaItem`** (`id` = **`localIdentifier`**, plus **`asset`**).
  - **`selectedIDs: [String]`** stores **selection order**; that order is the order of clips in the editor.
  - **`toggleSelection`** appends or removes IDs; **`selectedItems`** maps IDs back to **`[MediaItem]`** for the editor.
  - **`filteredItems`** applies **`MediaFilter`** (all / photos / videos / favorites) and optional **search** (keywords, creation date string, etc.).
  - Uses **`PHCachingImageManager`** for grid thumbnails (see **`MediaGridItemView`**).
- **Gestures on a grid cell:** **tap** → toggle selection; **long-press** → **`MediaPreviewView`** via **`fullScreenCover(item: $previewItem)`**.
- **Limited photo access:** header **+** calls **`presentLimitedLibraryPicker`** so users can expand which assets are visible.
- **Denied / restricted:** UI prompts **Open Settings** (`openSettings()`).

### 1.3 Next → editor

- When **`selectedIDs`** is not empty, **`SelectionBottomBar`** appears in **`safeAreaInset(edge: .bottom)`**; **Next** sets **`goToEditor = true`**.
- **`navigationDestination(isPresented: $goToEditor)`** presents **`EditorScreen(media: vm.selectedItems)`** — same navigation stack, passing the **ordered** **`[MediaItem]`**.

### 1.4 `MediaItem` → `EditorClip`

- **`MediaItem`** (`Features/ProjectList/model/MediaItem.swift`) is the **picker** model ( **`PHAsset`** + helpers).
- **`EditorViewModel(media: [MediaItem])`** maps each item to **`EditorClip(asset:)`** (`Features/Editor/model/EditorClip.swift`). After this point, the editor only needs **`EditorClip`**, **`timelinePosition`**, and the player — the picker's job is done.

### 1.5 Pre-editor file map

| Path | Role |
|------|------|
| `App/MixtapeApp.swift` | Root scene → `ProjectListScreen`. |
| `ProjectList/Presentation/ProjectListScreen.swift` | Home; `NavigationLink` to create flow. |
| `ProjectList/Presentation/CreateProjectScreen.swift` | Thin wrapper → `MediaLibraryPickerScreen`, then `EditorScreen`. |
| `ProjectList/Presentation/MediaLibraryPickerScreen.swift` | Shared photo grid (new project + add clips in editor). |
| `ProjectList/Presentation/ViewModel/PhotoLibraryViewModel.swift` | Auth, fetch, filter, search, selection order. |
| `ProjectList/model/MediaItem.swift` | Row model wrapping `PHAsset`. |
| `ProjectList/model/MediaFilter.swift` | Filter chip enum. |
| `ProjectList/Presentation/views/SelectionBottomBar.swift` | Count, duration summary, **Next**. |
| `ProjectList/Presentation/views/MediaGridItemView.swift` | Thumbnail cell (with caching manager). |

### 1.6 References (PhotoKit, privacy, navigation)

- [PhotoKit](https://developer.apple.com/documentation/photokit) — **`PHAsset`**, **`PHFetchOptions`**, **`PHPhotoLibrary`**, **`PHAuthorizationStatus`** (including **`.limited`**).
- [Delivering an enhanced privacy experience](https://developer.apple.com/documentation/photokit/delivering_an_enhanced_privacy_experience_in_your_photos_app) — limited library, picker.
- [SwiftUI `NavigationStack`](https://developer.apple.com/documentation/swiftui/navigationstack), [`navigationDestination(isPresented:destination:)`](https://developer.apple.com/documentation/swiftui/view/navigationdestination(ispresented:destination:)).

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

**Key file:** `Presentation/ViewModel/EditorViewModel.swift` — see `timelinePosition`, `clipAndLocalTime(at:)`, `timelineOffsetForClipIndex(_:)`.

**Clip duration on the timeline:** `Features/Editor/model/EditorClip.swift` — `duration` and `sourceTime(forExportedLocal:)` connect **exported timeline seconds** to **source asset time** (trim + speed).

---

## 3. Architecture overview

**Navigation flow:** `ProjectListScreen` → **`CreateProjectScreen`** (picker) → **`EditorScreen`** (this subtree).

```
EditorScreen
├── EditorTopBar
├── EditorPreviewPlayer      ← poster / AVPlayerLayer, HUD, fullscreen entry
├── EditorTimeline          ← ruler, overlays, clips, playhead, horizontal scroll
└── EditorBottomToolbar     ← tools (split, speed, …)
```

- **`EditorViewModel`** (`@MainActor`, `@Observable`): owns timeline state, a **single** `AVPlayer?` backed by an **`AVMutableComposition`**, scrub/seek helpers, playback tick timer, and clip-editing APIs (trim, split, insert).
- **`EditorCompositionBuilder`**: builds the continuous preview stream from all clips (see **§4**).
- **Views** are mostly passive: they call `vm.setTimelinePositionForScrub`, `commitTimelineAfterScrub`, `togglePlay()`, etc.

This follows **unidirectional data flow**: the view model is the source of truth; SwiftUI observes it and redraws.

**Observation:**

- **`@Observable`** (iOS 17+): Swift tracks which properties views read and updates them efficiently. See [Migrating to the Observable macro](https://developer.apple.com/documentation/swiftui/migrating-from-the-observable-object-protocol-to-the-observable-macro).
- **`@ObservationIgnored`**: used for things that should **not** trigger UI refresh (e.g. `PHCachingImageManager`, `Timer`) — see `EditorViewModel`.
  
---

## 4. Playback: one composition, one player (CapCut-style)

**What we learned the hard way:** swapping a **new `AVPlayer` per clip** causes visible **jump cuts** at every boundary — even when two clips are splits of the **same** video. CapCut feels like “one video” because it plays a **single stitched timeline**.

### 4.1 How it works today

1. **`EditorCompositionBuilder.makePlayerItem(from:)`** (`Presentation/ViewModel/EditorCompositionBuilder.swift`):
   - Creates **`AVMutableComposition`**.
   - For each **`EditorClip`**, inserts the trimmed source range (`trimStart` … `trimEnd`) at the correct **composition time** (sequential cursor).
   - **Videos:** `PHImageManager.requestAVAsset(forVideo:)` → insert video + audio tracks.
   - **Photos:** converts still → short silent video segment (via **`AVAssetWriter`**) so photos sit in the same composition.
2. **`AVMutableVideoComposition`** applies each source track’s **`preferredTransform`** and **aspect-fits** into a **1080×1920** portrait canvas (matches `EditorPreviewLayout` 9∶16). Without this, iPhone portrait footage looks **rotated / squashed** in the preview.
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
- [AVMutableVideoComposition](https://developer.apple.com/documentation/avfoundation/avmutablevideocomposition) — orientation, transforms, render size.
- [AVAssetTrack.preferredTransform](https://developer.apple.com/documentation/avfoundation/avassettrack/1386708-preferredtransform) — why portrait video looks wrong without a video composition.
- [AVAudioSession](https://developer.apple.com/documentation/avfaudio/avaudiosession) — categories, routing, silent switch behavior.
- [AVFoundation Programming Guide (archive)](https://developer.apple.com/library/archive/documentation/AudioVideo/Conceptual/AVFoundationPG/Articles/03_Editing.html) — **Editing Assets** chapter; still the best conceptual intro to compositions.
- WWDC: search [developer.apple.com/videos](https://developer.apple.com/videos/) for **“Edit and play back HDR video”**, **“Discover advancements in AVFoundation”** — composition + video composition patterns.

---

## 5. Preview layout and fullscreen

- **Stage aspect ratio:** `EditorPreviewLayout.aspectWidthOverHeight` in `EditorClip.swift` (e.g. 9∶16) so every asset is shown in the same **editor canvas**.
- **Inline preview:** `EditorPreviewPlayer` uses `.aspectRatio(..., contentMode: .fit)` so the stage fits inside the max height set by `EditorScreen` (a fraction of screen height).
- **Wider stage:** smaller horizontal padding on `EditorScreen` lets the preview use more width before letterboxing.

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

**Front vs back trim:** `trimStart` / `trimEnd` live on **`EditorClip`**. Timeline thumbnails use **aspect-fill** in the **cell size** (not stretched across a fake “filmstrip width”) so narrow clips don’t look vertically squashed.

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

---

## 7. Lifecycle tied to the screen

In `EditorScreen`:

- `.task { await vm.setupPlayer() }` builds the first composition and seeks to the start.
- `.onDisappear { vm.teardownPlayer() }` invalidates timers, removes observers, clears the player and composition caches.

When leaving the editor, always tear down expensive resources so you don’t leak `AVPlayer`, timers, or temp photo-video files.

---

## 8. File map (quick reference — editor module)

Paths are under **`Features/Editor/`** unless noted. The **picker / new-project** files live under **`Features/ProjectList/`** and are listed in **§1.5** above.

| Path | Role |
|------|------|
| `Presentation/EditorScreen.swift` | Layout, fullscreen presentation wiring. |
| `Presentation/ViewModel/EditorViewModel.swift` | Timeline math, composition player, trim/split/insert, seek, tick. |
| `Presentation/ViewModel/EditorCompositionBuilder.swift` | Builds `AVMutableComposition` + `AVVideoComposition` for preview. |
| `Presentation/views/EditorTimeline.swift` | Ruler, scrub, clips, + insert slots, playhead, `TimelineLayout`. |
| `Presentation/views/ClipTrimHandleView.swift` | UIKit trim handles (`UIViewRepresentable`). |
| `Presentation/views/EditorPreviewPlayer.swift` | Inline preview, HUD, `PlayerLayerView`. |
| `Presentation/views/EditorTopBar.swift` / `EditorBottomToolbar.swift` | Chrome and tools (split, speed, …). |
| `model/EditorClip.swift` | Clip model, trim/speed/split, preview aspect. |
| `Core/AudioSessionConfigurator.swift` | Speaker / headphone routing for preview audio. |
| `model/EditorTextOverlay.swift` / `EditorAudioTrack.swift` / `EditorTool.swift` | Other timeline / tool types. |

---

## 9. WWDC and deeper dives (video + articles)

**SwiftUI & gestures**

- WWDC sessions on SwiftUI layout and scroll views (search [Apple Developer Videos](https://developer.apple.com/videos/) for “SwiftUI ScrollView” / “Gestures”).

**AVFoundation (editing mindset)**

- Even before a full **AVComposition** pipeline, understanding **timebases**, **CMTime**, and **seek tolerances** pays off: [CMTime](https://developer.apple.com/documentation/coremedia/cmtime), [AVPlayer seek](https://developer.apple.com/documentation/avfoundation/avplayer/1385953-seek).

**Photos**

- [PhotoKit overview](https://developer.apple.com/documentation/photokit) — permissions, `PHAsset`, image vs video requests.

**Composition + export (you are here for preview; export is next)**

- Preview already uses **`AVMutableComposition`**. Export will likely **reuse** `EditorCompositionBuilder` (or a sibling) with **`AVAssetExportSession`**. See [Exporting a single asset](https://developer.apple.com/documentation/avfoundation/avassetexportsession) and the archive guide [Editing](https://developer.apple.com/library/archive/documentation/AudioVideo/Conceptual/AVFoundationPG/Articles/03_Editing.html).

**SwiftUI + UIKit together**

- [Integrating UIKit with SwiftUI](https://developer.apple.com/documentation/swiftui/uikit_integration) — trim handles pattern.

**Cursor + Xcode on the same repo**

- Edit Swift in **Cursor**; create/move files and targets in **Xcode** when possible so `project.pbxproj` stays consistent.
- After moving files in Finder/Cursor, expect red missing references in Xcode until you fix groups or re-add files.
- Ignore **`xcuserdata`**, **`.DS_Store`**, **`build/`** in git.

---

## 10. Suggested learning order

1. Trace **home → `CreateProjectScreen` → `MediaLibraryPickerScreen` → `EditorScreen(media:)`** so you see how **selection order** becomes **timeline order**.
2. Read **`EditorClip.duration`**, **`trimStart`/`trimEnd`**, and **`clipAndLocalTime(at:)`** until you can predict which clip owns any **`timelinePosition`**.
3. Read **`EditorCompositionBuilder.makePlayerItem`** top to bottom — that is the core of “one continuous preview.”
4. Trace **`togglePlay` → `ensureCompositionPlayer` → `playbackTick`** and watch **`timelinePosition`** track **`player.currentTime()`**.
5. Trace **`setTimelinePositionForScrub` → `commitTimelineAfterScrub` → `alignPlaybackToTimeline` → `seekPlayerToTimeline`**.
6. In **`EditorTimeline`**, follow **`TimelineLayout.contentX(forTime:)`** and the **+ insert slot** column — confirm playback time does **not** include gap seconds.
7. Select a clip → drag trim handles → **`commitTrimEdit`** → watch composition rebuild.
8. Park playhead mid-clip → **SPLIT** → play through the cut and notice **no player swap** (same composition, two source ranges).
9. In the simulator: scrub ruler vs drag filmstrip vs tap-to-select vs trim handle drag — map each to the gesture / hit-test code.

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

---

## 12. What to build next (good learning projects)

1. **Export** — pipe `EditorCompositionBuilder` output to **`AVAssetExportSession`** and save to Photos.
2. **Undo** — snapshot `clips` + `timelinePosition` on each edit; learn command pattern.
3. **Speed tool** — `scaleTimeRange` on composition segments or adjust `EditorClip.speed` + rebuild.
4. **Thumbnail filmstrip** — multiple **`AVAssetImageGenerator`** frames per clip (performance challenge).
5. **Persist projects** — Codable project file storing clip IDs + trim, not raw video.

If you outgrow this README, write a short **`EXPORT.md`** next once export ships — mirror the structure of §4.
