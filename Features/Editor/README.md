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

- **`CreateProjectScreen`** (`Features/ProjectList/Presentation/CreateProjectScreen.swift`) owns **`@State private var vm = PhotoLibraryViewModel()`**.
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
| `ProjectList/Presentation/CreateProjectScreen.swift` | Grid, filters, selection, `EditorScreen` destination. |
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

- **`EditorViewModel`** (`@MainActor`, `@Observable`): owns timeline state, `AVPlayer?`, scrub/seek helpers, playback tick timer, and `alignPlaybackToTimeline()` so the **video** player shows the frame that matches `timelinePosition`.
- **Views** are mostly passive: they call `vm.setTimelinePositionForScrub`, `commitTimelineAfterScrub`, `togglePlay()`, etc.

This follows **unidirectional data flow**: the view model is the source of truth; SwiftUI observes it and redraws.

**Observation:**

- **`@Observable`** (iOS 17+): Swift tracks which properties views read and updates them efficiently. See [Migrating to the Observable macro](https://developer.apple.com/documentation/swiftui/migrating-from-the-observable-object-protocol-to-the-observable-macro).
- **`@ObservationIgnored`**: used for things that should **not** trigger UI refresh (e.g. `PHCachingImageManager`, `Timer`) — see `EditorViewModel`.
  
---

## 4. Playback: video vs photo

- **Video:** `AVPlayer` + `AVPlayerItem` from the photo library (`PHCachingImageManager.requestPlayerItem`). The layer is embedded via `PlayerLayerView` (`UIViewRepresentable` wrapping `AVPlayerLayer`).
- **Photo:** No persistent player for the still; the preview uses a **thumbnail/poster** from `PHImageManager` while the playhead advances on a **timer** (`playbackTick`) when `isPlaying` is true.

**Aligning the player after a seek:** `alignPlaybackToTimeline()`:

1. Resolves `playbackInfo` from `timelinePosition`.
2. If it’s video and the clip changed (or there is no player), loads the right item and seeks.
3. If it’s photo, tears down the player and shows the still.

**Seeking is async:** `player?.seek(to:toleranceBefore:toleranceAfter:)` is `async` in modern SDKs — the view model uses `await` so the playhead and frame stay in sync.

**Useful reading:**

- [AVFoundation — Playback](https://developer.apple.com/documentation/avfoundation/media_playback)
- [PHCachingImageManager](https://developer.apple.com/documentation/photokit/phcachingimagemanager) and [requestPlayerItem(forVideo:options:)](https://developer.apple.com/documentation/photokit/phimagemanager/1616953-requestplayeritem)

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
- **Long-press** on a thumbnail (in `ClipThumb`) triggers `selectClipForEditing`.

So: **orange border** ≈ edit target; **preview** ≈ `playbackInfo` at `timelinePosition`.

---

## 7. Lifecycle tied to the screen

In `EditorScreen`:

- `.task { await vm.setupPlayer() }` runs initial `alignPlaybackToTimeline()`.
- `.onDisappear { vm.teardownPlayer() }` invalidates timers, removes KVO/observers, clears the player.

When leaving the editor, always tear down expensive resources so you don’t leak `AVPlayer` or timers.

---

## 8. File map (quick reference — editor module)

Paths are under **`Features/Editor/`** unless noted. The **picker / new-project** files live under **`Features/ProjectList/`** and are listed in **§1.5** above.

| Path | Role |
|------|------|
| `Presentation/EditorScreen.swift` | Layout, fullscreen presentation wiring. |
| `Presentation/ViewModel/EditorViewModel.swift` | Timeline math, player, seek, tick, selection API. |
| `Presentation/views/EditorTimeline.swift` | Ruler, scrub, clips, audio lane, playhead, scroll content height. |
| `Presentation/views/EditorPreviewPlayer.swift` | Inline preview, HUD, `PlayerLayerView`. |
| `Presentation/views/EditorTopBar.swift` / `EditorBottomToolbar.swift` | Chrome and tools. |
| `model/EditorClip.swift` | Clip model, trim/speed, preview aspect. |
| `model/EditorTextOverlay.swift` / `EditorAudioTrack.swift` / `EditorTool.swift` | Other timeline / tool types. |

---

## 9. WWDC and deeper dives (video + articles)

**SwiftUI & gestures**

- WWDC sessions on SwiftUI layout and scroll views (search [Apple Developer Videos](https://developer.apple.com/videos/) for “SwiftUI ScrollView” / “Gestures”).

**AVFoundation (editing mindset)**

- Even before a full **AVComposition** pipeline, understanding **timebases**, **CMTime**, and **seek tolerances** pays off: [CMTime](https://developer.apple.com/documentation/coremedia/cmtime), [AVPlayer seek](https://developer.apple.com/documentation/avfoundation/avplayer/1385953-seek).

**Photos**

- [PhotoKit overview](https://developer.apple.com/documentation/photokit) — permissions, `PHAsset`, image vs video requests.

**Future: professional-style timelines**

- Many apps eventually build a **composition** (`AVMutableComposition`, `AVMutableVideoComposition`) for export. Apple’s [AVFoundation Programming Guide](https://developer.apple.com/library/archive/documentation/AudioVideo/Conceptual/AVFoundationPG/Articles/00_Introduction.html) is the classic entry (archive but still useful conceptually).

---

## 10. Suggested learning order

1. Trace **home → `CreateProjectScreen` → `PhotoLibraryViewModel.selectedIDs` → `EditorScreen(media:)`** so you see how **order** becomes **timeline order**.
2. Read **`EditorClip.duration`** and **`clipAndLocalTime(at:)`** until you can predict the preview for any **`timelinePosition`**.
3. Trace **`setTimelinePositionForScrub` → `commitTimelineAfterScrub` → `alignPlaybackToTimeline`** in the view model.
4. In **`EditorTimeline`**, follow one horizontal pan from **`ScrollView`** through to content layout (`GeometryReader` + `Spacer`).
5. In the simulator: scrub ruler vs drag filmstrip vs drag empty area below clips — match each to the gesture code paths above.

If you outgrow this README, the next documentation to write is usually **“export pipeline”** or **“undo/history”** once those features exist.
