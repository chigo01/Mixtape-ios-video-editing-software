import SwiftUI

struct EditorCopilotPanel: View {
    @Bindable var vm: EditorViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var prompt = ""
    @State private var target = 45
    @State private var captions = true
    @State private var locale = ""
    @State private var availability: String?
    @FocusState private var isBriefFocused: Bool

    private let suggestions: [(label: String, prompt: String)] = [
        ("Highlights", "Extract the most useful highlights."),
        ("2 min", "Extract a 2-minute excerpt of the most useful moments."),
        ("5 min", "Extract a 5-minute excerpt of the most useful moments."),
        ("10 min", "Extract a 10-minute excerpt of the most useful moments."),
        ("Fade here", "Apply a fade transition at this playhead."),
        ("Split here", "Split the clip at this playhead."),
        ("Slow-mo", "Slow motion at the playhead."),
        ("Vignette here", "Add a vignette at the playhead and keyframe it."),
        ("Fade in", "Fade in from black at the start."),
        ("Zoom here", "Zoom in at the playhead and keyframe it."),
        ("Add title", "Add a title that says Mixtape at the playhead."),
        ("Captions", "Add captions to the current timeline.")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Label("ON-DEVICE MIXPILOT", systemImage: "sparkles")
                        .font(.caption.weight(.bold)).tracking(1.5)
                        .foregroundStyle(Color.appColors.primaryColor)
                    Text("Describe the edit.")
                        .font(.title2.bold())
                    Text("MixPilot speeds up ordinary editing — cuts, effects, keyframes, text, or captions. Analysis stays on this device. Review every change before applying. After Apply, the playhead stays on the edit.")
                        .font(.subheadline).foregroundStyle(.secondary)

                    if let reason = availability ?? vm.copilotRestriction {
                        Label(reason, systemImage: "info.circle")
                            .font(.subheadline).padding()
                            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Your brief").font(.headline)
                        TextField("Add a vignette at the playhead and keyframe it…", text: $prompt, axis: .vertical)
                            .lineLimit(3...6).padding(12)
                            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                            .focused($isBriefFocused)
                            .accessibilityLabel("Editing request")

                        Text("Playhead \(timecode(vm.timelinePosition)) · Timeline \(timecode(vm.videoDuration))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        if vm.videoDuration > 8 * 60 {
                            Text("Long clips are sampled for speech instead of transcribing every minute. Ask for 45 seconds, 5 minutes, 10 minutes, or any length up to 30 minutes.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(suggestions, id: \.label) { item in
                                    Button(item.label) {
                                        prompt = item.prompt
                                        if let duration = EditorCopilotPlan.parsedHighlightDuration(from: item.prompt) {
                                            target = min(duration, maxTarget)
                                        }
                                    }
                                        .font(.caption.weight(.semibold))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(
                                            Capsule().fill(
                                                prompt == item.prompt
                                                    ? Color.appColors.primaryColor.opacity(0.22)
                                                    : Color.white.opacity(0.06)
                                            )
                                        )
                                        .foregroundStyle(
                                            prompt == item.prompt
                                                ? Color.appColors.primaryColor
                                                : Color.white.opacity(0.86)
                                        )
                                        .disabled(vm.isCopilotWorking)
                                }
                            }
                        }
                        .accessibilityLabel("Suggested requests")

                        if EditorCopilotService.usesExcerptControls(prompt) {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Excerpt length").font(.headline)
                                Stepper(
                                    "Target: \(durationLabel(target))",
                                    value: $target,
                                    in: 10...min(EditorCopilotPlan.maximumExcerptSeconds, maxTarget),
                                    step: target >= 300 ? 30 : (target >= 120 ? 15 : 5)
                                )
                                Toggle("Add captions", isOn: $captions)
                                HStack {
                                    Text("Spoken language")
                                    Spacer()
                                    Picker("Spoken language", selection: $locale) {
                                        Text("Automatic").tag("")
                                        ForEach(EditorCaptionService.supportedLanguageOptions(), id: \.identifier) { option in
                                            Text(option.title).tag(option.identifier)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .labelsHidden()
                                    .accessibilityLabel("Spoken language")
                                }
                                Text("Works on any spoken clip, not just webinars. Name a length in your brief — 5 minutes, 10 minutes, and so on — or use this control. The brief wins if it includes a duration.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .disabled(vm.isCopilotWorking)

                    if vm.isCopilotWorking {
                        HStack(spacing: 12) {
                            ProgressView().tint(Color.appColors.primaryColor)
                            Text(vm.copilotStatus ?? "Analyzing…").font(.subheadline)
                            Spacer()
                            Button("Cancel") { vm.cancelCopilot() }
                        }
                    } else {
                        Button {
                            availability = EditorCopilotService.unavailableReason
                            vm.generateCopilot(
                                prompt: prompt, target: target, captions: captions,
                                locale: locale.isEmpty ? nil : locale
                            )
                        } label: {
                            Label(
                                vm.hasCopilotDraft ? "Regenerate from original" : "Create draft",
                                systemImage: "sparkles"
                            )
                            .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 7)
                        }
                        .buttonStyle(.borderedProminent).tint(Color.appColors.primaryColor)
                        .foregroundStyle(.black)
                        .disabled(
                            availability != nil
                                || vm.copilotRestriction != nil
                                || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                || prompt.count > 800
                        )
                    }

                    if let error = vm.copilotError {
                        Label(error, systemImage: "exclamationmark.circle")
                            .font(.subheadline).foregroundStyle(.orange)
                            .accessibilityLabel("MixPilot error: \(error)")
                    }

                    if let preview = vm.copilotPreview, !vm.isCopilotWorking {
                        if let plan = vm.copilotPlan {
                            highlightReview(plan: plan, preview: preview)
                        } else if let plan = vm.copilotEditPlan {
                            editReview(plan: plan, preview: preview)
                        }
                    }
                }.padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .simultaneousGesture(TapGesture().onEnded { isBriefFocused = false })
            }
            .scrollDismissesKeyboard(.immediately)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if vm.copilotPreview != nil, !vm.isCopilotWorking {
                    applyBar()
                }
            }
            .background(Color.appColors.backgroundColor)
            .navigationTitle(EditorCopilotService.productName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Close") { dismiss() } }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { isBriefFocused = false }
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            availability = EditorCopilotService.unavailableReason
            target = min(max(target, 10), maxTarget)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { availability = EditorCopilotService.unavailableReason }
        }
        .onDisappear { vm.cancelCopilot() }
    }

    @ViewBuilder
    private func highlightReview(plan: EditorCopilotPlan, preview: EditorViewModel) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Review your draft").font(.title3.bold())
            Text("\(plan.segments.count) sections · \(plan.duration, specifier: "%.1f")s of \(plan.targetDuration, specifier: "%.0f")s target · \(plan.addsCaptions ? "Captions on" : "No captions")")
                .font(.subheadline).foregroundStyle(.secondary)
            Text("Sections stay in source order. The cut aims for your target length; it may be slightly shorter to keep spoken sections intact. Check transcription and cut boundaries before applying.")
                .font(.caption).foregroundStyle(.secondary)
            draftPlayer(preview, duration: plan.duration)
            ForEach(plan.segments) { segment in
                VStack(alignment: .leading, spacing: 4) {
                    Text("Source \(segment.start, specifier: "%.1f")–\(segment.end, specifier: "%.1f")s")
                        .font(.caption.monospacedDigit()).foregroundStyle(Color.appColors.primaryColor)
                    Text(segment.text).font(.subheadline)
                }.frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    @ViewBuilder
    private func editReview(plan: EditorCopilotEditPlan, preview: EditorViewModel) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Review your draft").font(.title3.bold())
            Text("\(plan.operations.count) change\(plan.operations.count == 1 ? "" : "s") · \(plan.summary)")
                .font(.subheadline).foregroundStyle(.secondary)
            Text("These operations use existing editor tools. The current timeline is unchanged until you apply. MixPilot keeps the playhead on the edit. One Undo restores everything.")
                .font(.caption).foregroundStyle(.secondary)
            draftPlayer(preview, duration: preview.totalDuration)
            ForEach(plan.operations) { operation in
                VStack(alignment: .leading, spacing: 4) {
                    Text(operation.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.appColors.primaryColor)
                    Text(operation.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    @ViewBuilder
    private func draftPlayer(_ preview: EditorViewModel, duration: Double) -> some View {
        EditorPreviewPlayer(vm: preview)
            .frame(maxHeight: 300).allowsHitTesting(false)
        HStack {
            Button { preview.togglePlay() } label: {
                Label(
                    preview.isPlaying ? "Pause" : "Play draft",
                    systemImage: preview.isPlaying ? "pause.fill" : "play.fill"
                )
            }
            Spacer()
            Text("\(preview.timelinePosition, specifier: "%.1f") / \(duration, specifier: "%.1f")s")
                .font(.caption.monospacedDigit())
        }
    }

    @ViewBuilder
    private func applyBar() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Draft only — timeline unchanged")
                .font(.subheadline.weight(.semibold))
            if let plan = vm.copilotPlan {
                Text("Apply to replace the \(vm.videoDuration, specifier: "%.1f")s timeline with this \(plan.duration, specifier: "%.1f")s cut. One Undo restores the original.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if let plan = vm.copilotEditPlan {
                Text("Apply \(plan.operations.count) MixPilot change\(plan.operations.count == 1 ? "" : "s") on the current \(vm.videoDuration, specifier: "%.1f")s timeline. The playhead stays put. One Undo restores the original.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let error = vm.copilotError {
                Text(error).font(.caption).foregroundStyle(.orange)
            }
            Button {
                if vm.applyCopilotDraft() { dismiss() }
            } label: {
                Text(applyTitle)
                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 7)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.appColors.primaryColor).foregroundStyle(.black)
            .accessibilityHint("Applies the reviewed MixPilot draft. Can be undone.")
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
    }

    private var applyTitle: String {
        if let plan = vm.copilotPlan {
            return String(format: "Apply %.1fs to timeline", plan.duration)
        }
        if let plan = vm.copilotEditPlan {
            let count = plan.operations.count
            return "Apply \(count) change\(count == 1 ? "" : "s") to timeline"
        }
        return "Apply to timeline"
    }

    private var maxTarget: Int {
        let duration = Int(vm.videoDuration.rounded(.down))
        guard duration >= 10 else { return EditorCopilotPlan.maximumExcerptSeconds }
        return min(EditorCopilotPlan.maximumExcerptSeconds, duration)
    }

    private func durationLabel(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds) seconds" }
        let minutes = seconds / 60
        let remainder = seconds % 60
        if remainder == 0 {
            return minutes == 1 ? "1 minute" : "\(minutes) minutes"
        }
        return "\(minutes) min \(remainder) s"
    }

    private func timecode(_ time: Double) -> String {
        let clamped = max(0, time)
        let hours = Int(clamped) / 3600
        let minutes = (Int(clamped) % 3600) / 60
        let seconds = clamped.truncatingRemainder(dividingBy: 60)
        if hours > 0 {
            return String(format: "%d:%02d:%04.1f", hours, minutes, seconds)
        }
        return String(format: "%d:%04.1f", minutes, seconds)
    }
}
