# On-device Copilot verification

Natural-language planning acceptance checks:

- “Make it quieter”, “speed to 1.5x”, “flip vertically”, and “rotate 90 degrees
  counterclockwise” should each produce exactly one matching edit. Whole-clip
  changes use the selected primary clip; adding “here” uses the playhead instead.
  New markers, titles, effects, transitions, and splits default to the playhead.
- “Add title \"Slow fade, mute the highlights\" here” adds only that exact text.
  It must not mute, slow down, add a transition, or open highlight controls.
- On an Apple Intelligence device, try “slow it down without muting”, “blur from
  5 to 8 seconds”, and a compound request. Review the full draft for negation,
  explicit times, values, and the selected target. These requests must go through
  semantic planning rather than returning edits for the first recognized word.
- Requests to modify a music track, existing title, or an unsupported target must
  explain the limitation rather than silently modifying the primary video. A
  partially supported or ambiguous request must not force a partial draft.
- Without Apple Intelligence, complete supported short commands still work;
  complex wording must report that semantic planning is unavailable.

The standalone suite tests shortcut eligibility and deterministic operations. It
does not test the on-device language model's interpretation quality; the checks
above require an Apple Intelligence device.

Fade intent regression (phone): move inside a clip and request “Add fade in at
this playhead”, then compare with “Add fade in transition at the is playhead”.
Both drafts should contain one fade transition at that time, without an opacity
keyframe operation. Also try “fade-in here”, “blend these clips”, and “soften this
cut”. Apply, play before and after the cut, Undo/Redo, save/reopen, and export.
Undo any earlier incorrect opacity edit before testing the corrected request;
the fix does not remove existing project edits automatically.

Explicit “fade in opacity here” remains an opacity animation. Check that footage
before the requested time stays visible and that visibility returns after the
fade. “Fade in the vignette here” must animate the effect without adding a video
opacity fade. The standalone plan and keyframe tests cover these distinctions;
phone preview/export still needs this acceptance check.

Run deterministic plan validation from the repository root:

```sh
swiftc -module-cache-path /tmp/mixtape-swift-cache Features/Editor/Model/EditorCopilotPlan.swift Tests/Copilot/PlanValidationTests.swift -o /tmp/mixtape-copilot-plan-tests
/tmp/mixtape-copilot-plan-tests
```

Build with Xcode 26 or newer:

```sh
xcodebuild -project Mixtape.xcodeproj -scheme Mixtape -destination 'generic/platform=iOS Simulator' -configuration Debug -derivedDataPath /tmp/mixtape-copilot-build CODE_SIGNING_ALLOWED=NO build
```

Physical-device acceptance should cover both an Apple Intelligence device and an older supported device:

- Start with locally downloaded spoken video clips, no extra lanes, transitions, or unlinked dialogue. Open Copilot in the editor header.
- On a long recording (30+ minutes, ideally 2–3 hours), ask for 2, 5, or 10 minutes — or type a custom length. Confirm Copilot samples speech instead of transcribing the whole file. Intro music or silent stretches must not abort the job. The draft length should follow the request (capped to the source clip) and remain undoable.
- In airplane mode on an Apple Intelligence device, request a 45-second highlight reel with captions. Confirm transcription and semantic ranking complete without a network fallback.
- On a device without Apple Intelligence, request 45-second and 2-minute highlights. Confirm the offline mode notice appears and the draft is assembled locally. With local speech resources, confirm keyword ranking and captions work. Without speech permission/resources, confirm audio-activity ranking still creates a draft, reports the fallback, and omits captions.
- Review source ranges, captions, and draft playback. Confirm the main timeline has not changed, including after closing the sheet or terminating/reopening the app before Apply.
- Apply. Confirm every clip/caption is editable. One Undo restores the original timeline and captions, and Redo restores the draft. Save/reopen and export: check duration, speech boundaries, caption timing, framing, grading, and sound against preview.
- Change the duration, caption toggle, language, and brief; regenerate. Identical source/language reuses only the in-memory transcript. Changed source/language must trigger transcription again.
- Cancel during transcription, ranking, and preview preparation; immediately start another job. The old job must not publish results or start playback. Dismiss while preview plays and verify silence.
- Ask for unsupported music, reframing, tracking, or generated media and confirm an explicit explanation, not a success claim.
- Ask for a timed effect or keyframe (for example “add a vignette at the playhead and keyframe it”). Confirm Copilot plans an adjustment-layer effect with amount keyframes, previews it without changing the main timeline, and Apply/Undo uses one transaction. Highlight-reel options stay unused for this path.
- Confirm the built-in Highlights suggestion still produces a spoken highlight draft with duration, captions, and language controls. Existing extra lanes still block highlight reels but must not block effect/keyframe/text drafts.
- Check Apple Intelligence disabled/model downloading, unavailable speech language, denied Speech permission, missing/iCloud media, quiet/no-speech footage, and a long recording with multiple sampled windows. Preset and explicitly supported commands must continue through offline compatibility mode.

The executable tests validate the model-output trust boundary and deterministic offline ranking. They do not establish highlight quality, Foundation Models runtime availability, hardware performance, or preview/export parity; those require the device checks above.

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
