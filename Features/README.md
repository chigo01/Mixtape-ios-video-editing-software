# Feature modules

Each feature module uses the same **Model → ViewModel → View** structure. Shared infrastructure lives under `Core/` and `App/`.

```
Features/
├── Editor/
│   ├── Model/           # EditorClip, EditorTool, EditorExportSettings, …
│   ├── ViewModel/       # EditorViewModel (@Observable)
│   ├── View/
│   │   ├── Screens/     # EditorScreen, EditorExportScreen
│   │   └── Components/  # EditorTimeline, EditorPreviewPlayer, SpeedToolPanel, …
│   └── Services/        # Composition, transitions, export, and rendering
│
└── ProjectList/
    ├── Model/           # MediaItem, EditorProject, MediaFilter
    ├── ViewModel/       # PhotoLibraryViewModel, ProjectListViewModel
    ├── Services/        # ProjectStore (JSON persistence)
    └── View/
        ├── Screens/     # ProjectListScreen, CreateProjectScreen, MediaLibraryPickerScreen
        └── Components/  # ProjectCardView, MediaGridItemView, SelectionBottomBar, …
```

## MVVM roles

| Layer | Responsibility |
|-------|----------------|
| **Model** | Plain types and enums; no SwiftUI, no PhotoKit/AVFoundation orchestration. |
| **ViewModel** | Observable state and actions (`@MainActor`, `@Observable`). |
| **View** | SwiftUI only; reads ViewModel, forwards user input. |
| **Services** | Feature-specific helpers (e.g. building `AVMutableComposition`, saving projects). Not part of the UI triangle. |

## Conventions

- Screens own navigation and `@State` ViewModel instances.
- Components receive `let vm: SomeViewModel` (or bindings) from their parent screen.
- Feature state changes go through ViewModel methods so undo, persistence, player
  invalidation, and export remain consistent.
- Persisted model changes must decode older project files with safe defaults.
- Preview and export should share the same composition/rendering implementation.
- GPU rendering belongs in isolated services and immutable render instructions,
  never in SwiftUI views or mutable editor state.
- New editor capabilities should be documented in `Editor/README.md`, including
  their preview, export, undo, and persistence behavior.
- Do not add `Domain/`, `Data/`, `Presentation/`, or `Presenter/` folders — use the layout above.

## Key flows

| Flow | Entry | Exit |
|------|-------|------|
| **New project** | `ProjectListScreen` → New Project | `CreateProjectScreen` → preload → `EditorScreen(project:)` |
| **Resume project** | Tap `ProjectCardView` on home | `EditorScreen(project:)` |
| **Export** | Export button in `EditorTopBar` | `EditorExportScreen` → Photos + Share |
| **Transition edit** | Opening, cut, or closing timeline control | Categorized picker → preview → cancel or commit |
| **Background audio** | Audio-lane add button | Import → trim/move/split/fade → preview/export mix |

## Editor service boundaries

| Service | Responsibility |
|---------|----------------|
| `EditorCompositionBuilder` | Builds the shared preview/export timeline, transforms, audio mix, and standard transition instructions. |
| `EditorTransitionCompositor` | Renders GPU/Core Image transitions using immutable AVFoundation instructions. |
| `EditorExportService` | Encodes configured output, reports progress, handles cancellation, and saves to Photos. |
| `ProjectStore` | Reads and writes backward-compatible JSON project documents. |

See [Editor/README.md](Editor/README.md) for the full timeline and rendering guide.
