# On-device Copilot verification

Run deterministic plan validation from the repository root:

```sh
swiftc -module-cache-path /tmp/mixtape-swift-cache Features/Editor/Model/EditorCopilotPlan.swift Tests/Copilot/PlanValidationTests.swift -o /tmp/mixtape-copilot-plan-tests
/tmp/mixtape-copilot-plan-tests
```

Build with Xcode 26 or newer:

```sh
xcodebuild -project Mixtape.xcodeproj -scheme Mixtape -destination 'generic/platform=iOS Simulator' -configuration Debug -derivedDataPath /tmp/mixtape-copilot-build CODE_SIGNING_ALLOWED=NO build
```

Physical-device acceptance (requires iOS 26+, Apple Intelligence enabled and downloaded, and on-device speech resources for the selected language):

- Start with locally downloaded spoken video clips, no extra lanes, transitions, or unlinked dialogue. Open Copilot in the editor header.
- On a long recording (30+ minutes, ideally 2–3 hours), ask for 2, 5, or 10 minutes — or type a custom length. Confirm Copilot samples speech instead of transcribing the whole file. Intro music or silent stretches must not abort the job. The draft length should follow the request (capped to the source clip) and remain undoable.
- In airplane mode, request a 45-second highlight reel with captions. Confirm transcription and ranking complete without a network fallback. Missing local speech resources must produce an explicit error.
- Review source ranges, captions, and draft playback. Confirm the main timeline has not changed, including after closing the sheet or terminating/reopening the app before Apply.
- Apply. Confirm every clip/caption is editable. One Undo restores the original timeline and captions, and Redo restores the draft. Save/reopen and export: check duration, speech boundaries, caption timing, framing, grading, and sound against preview.
- Change the duration, caption toggle, language, and brief; regenerate. Identical source/language reuses only the in-memory transcript. Changed source/language must trigger transcription again.
- Cancel during transcription, ranking, and preview preparation; immediately start another job. The old job must not publish results or start playback. Dismiss while preview plays and verify silence.
- Ask for unsupported music, reframing, tracking, or generated media and confirm an explicit explanation, not a success claim.
- Ask for a timed effect or keyframe (for example “add a vignette at the playhead and keyframe it”). Confirm Copilot plans an adjustment-layer effect with amount keyframes, previews it without changing the main timeline, and Apply/Undo uses one transaction. Highlight-reel options stay unused for this path.
- Confirm the built-in Highlights suggestion still produces a spoken highlight draft with duration, captions, and language controls. Existing extra lanes still block highlight reels but must not block effect/keyframe/text drafts.
- Check an older iOS/device, Apple Intelligence disabled/model downloading, unavailable speech language, denied Speech permission, missing/iCloud media, quiet/no-speech footage, and a long recording with multiple analysis batches.

The executable tests validate the model-output trust boundary. They do not establish highlight quality, Foundation Models runtime availability, hardware performance, or preview/export parity; those require the device checks above.

Regression checks for the first phone report:

- A device locale absent from Speech's locale list must still display **Automatic** in a labelled language picker. Choose the actual spoken language when testing recognition accuracy.
- The built-in brief must honor the caption switch and duration without an unnecessary intent-generation call. Custom briefs still use guided intent parsing.
- Transcript excerpt selection uses Apple's documented content-transformation mode and a strict JSON ID decoder. Refusals, prose, and unknown IDs never become edits. JSON fences and recognized ID wrappers are accepted; repeated IDs are removed and excess valid IDs are capped in ranking order. Batch-local section numbers map back to the original transcript IDs. A machine-readable out-of-range selection gets one corrective retry; refusals and prose do not.
- A model refusal must identify whether it occurred while reading the brief, analyzing a transcript section, or comparing final highlights. It must leave the project unchanged.

This addresses the configuration and UI issues visible in the phone screenshot; reproducing that exact model refusal still requires the original recording on a supported phone.

Draft application UI: after generation, a fixed bottom bar must show the original
and draft durations, state that the timeline is unchanged, and expose Apply even
when scrolled to the top. Close dismisses the draft without applying. Apply must
close the sheet and replace the main timeline with the displayed draft duration;
Undo/Redo must restore the original/draft respectively. An apply failure remains
visible in the fixed bar.
