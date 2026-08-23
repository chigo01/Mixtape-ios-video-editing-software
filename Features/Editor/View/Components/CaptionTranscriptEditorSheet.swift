import SwiftUI
import UniformTypeIdentifiers

struct CaptionTranscriptEditorSheet: View {
    let vm: EditorViewModel
    let isEmbedded: Bool

    @State private var query = ""
    @State private var localeIdentifier = "auto"
    @State private var audioSource: EditorCaptionAudioSource = .video
    @State private var isImporterPresented = false
    @State private var isExporterPresented = false
    @State private var exportDocument = CaptionSRTDocument()
    @State private var isClearConfirmationPresented = false

    private var supportedLocales: [(identifier: String, title: String)] {
        [("auto", "Automatic (device language + English fallback)")]
            + EditorCaptionService.supportedLanguageOptions()
    }

    private var filteredCaptions: [EditorTextOverlay] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return vm.captionOverlays
        }
        return vm.captionOverlays.filter {
            $0.text.localizedCaseInsensitiveContains(query)
        }
    }

    private var fillerSuggestions: [CaptionWordSuggestion] {
        let fillers: Set<String> = [
            "ah", "eh", "erm", "hmm", "huh", "like", "mm", "mhm", "uh", "um"
        ]
        return vm.captionOverlays.flatMap { caption in
            caption.captionWords.compactMap { word in
                let normalized = word.text.lowercased().filter(\.isLetter)
                guard fillers.contains(normalized) else { return nil }
                return CaptionWordSuggestion(captionID: caption.id, word: word)
            }
        }
    }

    private var lowConfidenceSuggestions: [CaptionWordSuggestion] {
        vm.captionOverlays.flatMap { caption in
            caption.captionWords.compactMap { word in
                word.confidence < 0.55
                    ? CaptionWordSuggestion(captionID: caption.id, word: word)
                    : nil
            }
        }
    }

    private var silenceSuggestions: [CaptionSilenceSuggestion] {
        let words = vm.captionOverlays.flatMap(\.captionWords)
            .sorted { $0.startTime < $1.startTime }
        return zip(words, words.dropFirst()).compactMap { first, second in
            let duration = second.startTime - first.endTime
            guard duration >= 0.65 else { return nil }
            return CaptionSilenceSuggestion(
                id: second.id,
                startTime: first.endTime,
                endTime: second.startTime
            )
        }
    }

    var body: some View {
        Group {
            if isEmbedded {
                VStack(spacing: 0) {
                    header
                    Divider().overlay(Color.white.opacity(0.1))
                    content
                }
            } else {
                NavigationStack {
                    content
                        .navigationTitle("Captions & Transcript")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { vm.selectedTool = nil }
                            }
                        }
                }
            }
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [UTType(filenameExtension: "srt") ?? .plainText]
        ) { result in
            do {
                let url = try result.get()
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                try vm.importCaptions(from: Data(contentsOf: url))
            } catch {
                vm.captionErrorMessage = error.localizedDescription
            }
        }
        .fileExporter(
            isPresented: $isExporterPresented,
            document: exportDocument,
            contentType: UTType(filenameExtension: "srt") ?? .plainText,
            defaultFilename: "\(vm.projectTitle)-captions.srt"
        ) { result in
            if case .failure(let error) = result {
                vm.captionErrorMessage = error.localizedDescription
            }
        }
        .alert("Caption Error", isPresented: Binding(
            get: { vm.captionErrorMessage != nil },
            set: { if !$0 { vm.captionErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { vm.captionErrorMessage = nil }
        } message: {
            Text(vm.captionErrorMessage ?? "Unknown caption error")
        }
        .confirmationDialog(
            "Delete every caption?",
            isPresented: $isClearConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Delete All Captions", role: .destructive) { vm.deleteAllCaptions() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the caption track. The action can be undone in the editor.")
        }
    }

    private var header: some View {
        ZStack {
            Text("Captions & Transcript")
                .font(.system(size: 17, weight: .bold))
            HStack {
                Spacer()
                Button("Done") { vm.selectedTool = nil }
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.appColors.primaryColor)
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 48)
    }

    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                creationCard

                if !vm.captionOverlays.isEmpty {
                    styleCard
                    reviewCard
                    transcriptSection
                } else if !vm.isTranscribingCaptions {
                    ContentUnavailableView(
                        "No Captions Yet",
                        systemImage: "captions.bubble",
                        description: Text("Generate timed captions from the edited mix or import an SRT file.")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
                }
            }
            .padding(18)
            .frame(maxWidth: 920)
            .frame(maxWidth: .infinity)
        }
        .background(Color.appColors.backgroundColor)
    }

    private var creationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TRANSCRIBE THE EDITED TIMELINE")
                .font(.caption.bold()).foregroundStyle(.secondary)
            Text("Caption timing follows the edited video, including trims and speed changes. Choose where Mixtape should listen for dialogue.")
                .font(.footnote).foregroundStyle(.secondary)
            Text("Processing stays on device when the selected language supports it; otherwise Apple Speech Recognition may require a network connection.")
                .font(.caption).foregroundStyle(.secondary)

            Picker("Generate from", selection: $audioSource) {
                ForEach(EditorCaptionAudioSource.allCases) { source in
                    Text(source.title).tag(source)
                }
            }
            .pickerStyle(.segmented)

            Text(audioSource.explanation)
                .font(.caption).foregroundStyle(.secondary)

            Picker("Language", selection: $localeIdentifier) {
                ForEach(supportedLocales, id: \.identifier) { identifier, title in
                    Text(title).tag(identifier)
                }
            }
            .pickerStyle(.menu)

            if vm.isTranscribingCaptions {
                HStack(spacing: 10) {
                    ProgressView().tint(Color.appColors.primaryColor)
                    Text(vm.captionStatusMessage ?? "Creating captions…")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Button("Cancel", role: .cancel) { vm.cancelCaptionTranscription() }
                }
            } else {
                HStack(spacing: 10) {
                    Button {
                        vm.transcribeCaptions(
                            localeIdentifier: localeIdentifier == "auto" ? nil : localeIdentifier,
                            source: audioSource
                        )
                    } label: {
                        Label(vm.captionOverlays.isEmpty ? "Generate Captions" : "Regenerate", systemImage: "waveform.and.mic")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(CaptionPrimaryButtonStyle())

                    Button { isImporterPresented = true } label: {
                        Label("Import SRT", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(CaptionSecondaryButtonStyle())
                }
            }

            if !vm.captionOverlays.isEmpty {
                Button {
                    exportDocument = CaptionSRTDocument(text: EditorSRTCodec.encode(vm.captionOverlays))
                    isExporterPresented = true
                } label: {
                    Label("Export SRT", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(CaptionSecondaryButtonStyle())
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.055)))
    }

    private var styleCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CAPTION STYLE & SAFE ZONE")
                .font(.caption.bold()).foregroundStyle(.secondary)
            if var first = vm.captionOverlays.first {
                HStack(spacing: 10) {
                    ForEach([TextOverlayFontStyle.background, .outlined, .bold], id: \.self) { style in
                        Button(styleName(style)) {
                            first.fontStyle = style
                            vm.applyCaptionStyle(first, toAll: true)
                        }
                        .buttonStyle(CaptionChipButtonStyle(isSelected: first.fontStyle == style))
                    }
                }

                HStack {
                    Text("Highlight").font(.subheadline)
                    Spacer()
                    ForEach([TextOverlayColor.yellow, .green, .blue, .pink], id: \.self) { color in
                        Button {
                            first.captionHighlightColor = color
                            vm.applyCaptionStyle(first, toAll: true)
                        } label: {
                            Circle().fill(color.color).frame(width: 28, height: 28)
                                .overlay(Circle().stroke(.white, lineWidth: first.captionHighlightColor == color ? 2 : 0))
                        }
                    }
                }

                HStack {
                    Text("Text color").font(.subheadline)
                    Spacer()
                    ForEach([TextOverlayColor.white, .yellow, .green, .blue, .pink], id: \.self) { color in
                        Button {
                            first.textColor = color
                            vm.applyCaptionStyle(first, toAll: true)
                        } label: {
                            Circle().fill(color.color).frame(width: 28, height: 28)
                                .overlay(Circle().stroke(.white, lineWidth: first.textColor == color ? 2 : 0))
                        }
                    }
                }

                HStack {
                    Text("Size").font(.subheadline)
                    Slider(value: Binding(
                        get: { Double(first.fontSize) },
                        set: { value in
                            first.fontSize = CGFloat(value)
                            vm.applyCaptionStyle(first, toAll: true)
                        }
                    ), in: 18...64, step: 1)
                    Text("\(Int(first.fontSize))")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        .frame(width: 24)
                }

                HStack {
                    Text("Vertical safe area").font(.subheadline)
                    Slider(value: Binding(
                        get: { Double(first.yOffset) },
                        set: { value in
                            first.verticalAlignment = .bottom
                            first.yOffset = CGFloat(value)
                            vm.applyCaptionStyle(first, toAll: true)
                        }
                    ), in: -100...0)
                    Text("\(Int(abs(first.yOffset)))")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }


                Button(role: .destructive) { isClearConfirmationPresented = true } label: {
                    Label("Delete all captions", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(CaptionSecondaryButtonStyle())
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.055)))
    }

    @ViewBuilder
    private var reviewCard: some View {
        if !fillerSuggestions.isEmpty || !lowConfidenceSuggestions.isEmpty || !silenceSuggestions.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("SMART REVIEW")
                        .font(.caption.bold()).foregroundStyle(.secondary)
                    Spacer()
                    if !fillerSuggestions.isEmpty {
                        Button("Hide all in captions") {
                            vm.removeCaptionWords(Set(fillerSuggestions.map(\.word.id)))
                        }
                        .font(.caption.bold())
                        .foregroundStyle(Color.appColors.primaryColor)
                    }
                }

                if !fillerSuggestions.isEmpty {
                    suggestionStrip(
                        title: "Filler words",
                        suggestions: fillerSuggestions,
                        systemImage: "text.badge.minus"
                    )
                }

                if !lowConfidenceSuggestions.isEmpty {
                    suggestionStrip(
                        title: "Check recognition",
                        suggestions: lowConfidenceSuggestions,
                        systemImage: "exclamationmark.bubble"
                    )
                }

                if !silenceSuggestions.isEmpty {
                    VStack(alignment: .leading, spacing: 7) {
                        Label("Pauses to review", systemImage: "waveform.path")
                            .font(.subheadline.bold())
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(silenceSuggestions) { silence in
                                    Button {
                                        vm.seekTimeline(to: silence.startTime)
                                    } label: {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(timecode(silence.startTime))
                                                .font(.caption.monospacedDigit().bold())
                                            Text(String(format: "%.1fs pause", silence.duration))
                                                .font(.caption2)
                                        }
                                        .padding(.horizontal, 10).padding(.vertical, 7)
                                        .background(Capsule().fill(Color.white.opacity(0.07)))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        Text("Pauses are suggestions only. Media is never cut without an approved ripple edit.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.055)))
        }
    }

    private func suggestionStrip(
        title: String,
        suggestions: [CaptionWordSuggestion],
        systemImage: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("\(title) · \(suggestions.count)", systemImage: systemImage)
                .font(.subheadline.bold())
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(suggestions) { suggestion in
                        HStack(spacing: 6) {
                            Button {
                                vm.seekToCaption(suggestion.captionID)
                            } label: {
                                Text(suggestion.word.text)
                                    .font(.caption.bold())
                            }
                            Button(role: .destructive) {
                                vm.removeCaptionWord(
                                    captionID: suggestion.captionID,
                                    wordID: suggestion.word.id
                                )
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .accessibilityLabel("Remove \(suggestion.word.text)")
                        }
                        .padding(.leading, 10).padding(.trailing, 6).padding(.vertical, 7)
                        .background(Capsule().fill(Color.white.opacity(0.07)))
                    }
                }
            }
        }
    }

    private var transcriptSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("TRANSCRIPT · \(vm.captionOverlays.count) SEGMENTS")
                    .font(.caption.bold()).foregroundStyle(.secondary)
                Spacer()
                TextField("Search transcript", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 250)
            }

            ForEach(filteredCaptions) { caption in
                CaptionTranscriptRow(vm: vm, caption: caption)
            }
        }
    }

    private func styleName(_ style: TextOverlayFontStyle) -> String {
        switch style {
        case .background: return "Background"
        case .outlined: return "Outline"
        case .bold: return "Bold"
        default: return style.rawValue.capitalized
        }
    }

    private func timecode(_ time: TimeInterval) -> String {
        let seconds = max(0, Int(time))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

private struct CaptionTranscriptRow: View {
    let vm: EditorViewModel
    let caption: EditorTextOverlay
    @State private var draft: String
    @State private var isWordEditorExpanded = false
    @FocusState private var isTextFocused: Bool

    init(vm: EditorViewModel, caption: EditorTextOverlay) {
        self.vm = vm
        self.caption = caption
        _draft = State(initialValue: caption.text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Button { vm.seekToCaption(caption.id) } label: {
                    Text(timecode(caption.startTime))
                        .font(.caption.monospacedDigit().bold())
                        .foregroundStyle(Color.appColors.primaryColor)
                        .padding(.horizontal, 8).padding(.vertical, 6)
                        .background(Capsule().fill(Color.appColors.primaryColor.opacity(0.12)))
                }

                TextField("Caption text", text: $draft, axis: .vertical)
                    .lineLimit(1...3)
                    .textFieldStyle(.plain)
                    .focused($isTextFocused)
                    .onSubmit { commit() }
                    .onChange(of: isTextFocused) { wasFocused, isFocused in
                        if wasFocused && !isFocused { commit() }
                    }

                Button(role: .destructive) { vm.deleteTextOverlay(id: caption.id) } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("Delete caption at \(timecode(caption.startTime))")
            }

            HStack(spacing: 14) {
                Button {
                    vm.splitCaption(id: caption.id)
                } label: {
                    Label("Split", systemImage: "scissors")
                }
                .disabled(caption.captionWords.count < 2)

                Button {
                    vm.mergeCaptionWithNext(id: caption.id)
                } label: {
                    Label("Merge next", systemImage: "rectangle.2.swap")
                }
                .disabled(vm.captionOverlays.last?.id == caption.id)

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isWordEditorExpanded.toggle()
                    }
                } label: {
                    Label("Words", systemImage: isWordEditorExpanded ? "chevron.up" : "chevron.down")
                }
            }
            .font(.caption.bold())
            .foregroundStyle(Color.appColors.primaryColor)

            if isWordEditorExpanded {
                VStack(spacing: 6) {
                    ForEach(Array(caption.captionWords.enumerated()), id: \.element.id) { index, word in
                        CaptionWordEditorRow(
                            vm: vm,
                            captionID: caption.id,
                            word: word,
                            allowsBoundaryAdjustment: index + 1 < caption.captionWords.count
                        )
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(
            vm.selectedTextOverlayID == caption.id
                ? Color.appColors.primaryColor.opacity(0.11)
                : Color.white.opacity(0.045)
        ))
        .onDisappear { commit() }
        .onChange(of: caption.text) { _, value in
            if !isTextFocused { draft = value }
        }
    }

    private func commit() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != caption.text else { return }
        vm.updateCaptionText(id: caption.id, text: trimmed)
    }

    private func timecode(_ time: TimeInterval) -> String {
        let seconds = max(0, Int(time))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

private struct CaptionWordEditorRow: View {
    let vm: EditorViewModel
    let captionID: UUID
    let word: EditorCaptionWord
    let allowsBoundaryAdjustment: Bool

    @State private var draft: String
    @FocusState private var isFocused: Bool

    init(
        vm: EditorViewModel,
        captionID: UUID,
        word: EditorCaptionWord,
        allowsBoundaryAdjustment: Bool
    ) {
        self.vm = vm
        self.captionID = captionID
        self.word = word
        self.allowsBoundaryAdjustment = allowsBoundaryAdjustment
        _draft = State(initialValue: word.text)
    }

    var body: some View {
        HStack(spacing: 8) {
            TextField("Word", text: $draft)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onSubmit { commit() }
                .onChange(of: isFocused) { wasFocused, focused in
                    if wasFocused && !focused { commit() }
                }

            Text(String(format: "%.2f", word.startTime))
                .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)

            if allowsBoundaryAdjustment {
                Button {
                    vm.nudgeCaptionWordBoundary(captionID: captionID, afterWordID: word.id, by: -0.05)
                } label: { Image(systemName: "minus") }
                .accessibilityLabel("Move word boundary earlier")
                Button {
                    vm.nudgeCaptionWordBoundary(captionID: captionID, afterWordID: word.id, by: 0.05)
                } label: { Image(systemName: "plus") }
                .accessibilityLabel("Move word boundary later")
            }

            Button(role: .destructive) {
                vm.removeCaptionWord(captionID: captionID, wordID: word.id)
            } label: { Image(systemName: "xmark") }
        }
        .font(.caption)
        .onChange(of: word.text) { _, value in
            if !isFocused { draft = value }
        }
    }

    private func commit() {
        vm.updateCaptionWordText(captionID: captionID, wordID: word.id, text: draft)
    }
}

private struct CaptionWordSuggestion: Identifiable {
    let captionID: UUID
    let word: EditorCaptionWord
    var id: UUID { word.id }
}

private struct CaptionSilenceSuggestion: Identifiable {
    let id: UUID
    let startTime: TimeInterval
    let endTime: TimeInterval
    var duration: TimeInterval { max(0, endTime - startTime) }
}

private struct CaptionPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.bold()).foregroundStyle(.black)
            .padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.appColors.primaryColor.opacity(configuration.isPressed ? 0.75 : 1)))
    }
}

private struct CaptionSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.bold()).foregroundStyle(.white)
            .padding(.horizontal, 12).padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(configuration.isPressed ? 0.13 : 0.08)))
    }
}

private struct CaptionChipButtonStyle: ButtonStyle {
    let isSelected: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.bold()).foregroundStyle(isSelected ? .black : .white)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Capsule().fill(isSelected ? Color.appColors.primaryColor : Color.white.opacity(0.08)))
    }
}
