# Features — MVVM layout

Each feature module uses the same **Model → ViewModel → View** structure. Shared infrastructure lives under `Core/` and `App/`.

```
Features/
├── Editor/
│   ├── Model/           # EditorClip, EditorTool, EditorExportSettings, …
│   ├── ViewModel/       # EditorViewModel (@Observable)
│   ├── View/
│   │   ├── Screens/     # EditorScreen, EditorExportScreen
│   │   └── Components/  # EditorTimeline, EditorPreviewPlayer, SpeedToolPanel, …
│   └── Services/        # EditorCompositionBuilder, EditorExportService, …
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
- Do not add `Domain/`, `Data/`, `Presentation/`, or `Presenter/` folders — use the layout above.

## Key flows

| Flow | Entry | Exit |
|------|-------|------|
| **New project** | `ProjectListScreen` → New Project | `CreateProjectScreen` → preload → `EditorScreen(project:)` |
| **Resume project** | Tap `ProjectCardView` on home | `EditorScreen(project:)` |
| **Export** | Export button in `EditorTopBar` | `EditorExportScreen` → Photos + Share |
