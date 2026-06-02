# Features — MVVM layout

Each feature module uses the same **Model → ViewModel → View** structure. Shared infrastructure lives under `Core/` and `App/`.

```
Features/
├── Editor/
│   ├── Model/           # EditorClip, EditorTool, …
│   ├── ViewModel/       # EditorViewModel (@Observable)
│   ├── View/
│   │   ├── Screens/     # EditorScreen
│   │   └── Components/  # EditorTimeline, EditorPreviewPlayer, …
│   └── Services/        # EditorCompositionBuilder (AVFoundation)
│
└── ProjectList/
    ├── Model/           # MediaItem, MediaFilter, ProjectMockModel
    ├── ViewModel/       # PhotoLibraryViewModel
    └── View/
        ├── Screens/     # ProjectListScreen, CreateProjectScreen, MediaLibraryPickerScreen
        └── Components/  # MediaGridItemView, SelectionBottomBar, …
```

## MVVM roles

| Layer | Responsibility |
|-------|----------------|
| **Model** | Plain types and enums; no SwiftUI, no PhotoKit/AVFoundation orchestration. |
| **ViewModel** | Observable state and actions (`@MainActor`, `@Observable`). |
| **View** | SwiftUI only; reads ViewModel, forwards user input. |
| **Services** | Feature-specific helpers (e.g. building `AVMutableComposition`). Not part of the UI triangle. |

## Conventions

- Screens own navigation and `@State` ViewModel instances.
- Components receive `let vm: SomeViewModel` (or bindings) from their parent screen.
- Do not add `Domain/`, `Data/`, `Presentation/`, or `Presenter/` folders — use the layout above.
