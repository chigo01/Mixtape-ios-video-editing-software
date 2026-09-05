//
//  EditorBottomToolbar.swift
//  Mixtape
//
//  Created by Favour Baruch on 14/05/2026.
//

import SwiftUI
import PhotosUI

struct EditorBottomToolbar: View {
    let vm: EditorViewModel
    var isOverlayMode = false
    var onAddOverlay: () -> Void = {}

    var body: some View {
        GeometryReader { geometry in
            let tools = EditorTool.mainTools
            let itemWidth = max(68, geometry.size.width / CGFloat(max(tools.count, 1)))
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(tools) { tool in
                        ToolButton(
                            tool: tool,
                            isSelected: vm.selectedTool == tool || (tool == .overlay && isOverlayMode)
                        ) {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                if tool == .overlay {
                                    onAddOverlay()
                                } else {
                                    vm.performToolAction(tool)
                                }
                            }
                        }
                        .frame(width: itemWidth)
                    }
                }
                .frame(minWidth: geometry.size.width, alignment: .leading)
            }
        }
        .frame(height: 62)
        .padding(.horizontal, 4)
        .padding(.top, 12)
        .padding(.bottom, 18)
        .background(
            Rectangle()
                .fill(Color.white.opacity(0.02))
                .overlay(
                    Rectangle()
                        .frame(height: 0.5)
                        .foregroundColor(Color.white.opacity(0.06)),
                    alignment: .top
                )
        )
    }
}

struct EditorTemplatesPanel: View {
    let vm: EditorViewModel
    @State private var templates: [EditorProjectTemplate] = []
    @State private var templateName = ""
    @State private var isSaving = false
    @State private var localMessage: String?
    @State private var pendingTemplate: EditorProjectTemplate?

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    creationCard
                    libraryHeader
                    if templates.isEmpty { emptyState }
                    else {
                        LazyVStack(spacing: 14) {
                            ForEach(templates) { template in templateCard(template) }
                        }
                    }
                    if let message = localMessage ?? vm.templateStatusMessage {
                        Label(message, systemImage: "checkmark.circle")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(18)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
        }
        .background(Color.appColors.backgroundColor)
        .task { reload() }
        .alert(
            "Apply template?",
            isPresented: Binding(
                get: { pendingTemplate != nil },
                set: { if !$0 { pendingTemplate = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) { pendingTemplate = nil }
            Button("Apply", role: .destructive) {
                guard let template = pendingTemplate else { return }
                apply(template)
                pendingTemplate = nil
            }
        } message: {
            Text("This replaces the current timeline structure and fills its media slots in order. You can undo the entire application in one step.")
        }
    }

    private var header: some View {
        ZStack {
            VStack(spacing: 2) {
                Text("Templates").font(.headline)
                Text("Reusable, fully editable projects").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Done") { vm.selectedTool = nil }
                    .font(.subheadline.bold())
                    .foregroundStyle(Color.appColors.primaryColor)
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 58)
    }

    private var creationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("SAVE CURRENT EDIT", systemImage: "square.and.arrow.down.fill")
                .font(.caption.bold()).foregroundStyle(.secondary)
            Text("Turn this timeline into a reusable template. Primary clips and video overlays become replaceable slots; timing and creative work stay intact.")
                .font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                TextField("Template name", text: $templateName)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .frame(height: 44)
                    .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 11))
                Button {
                    saveTemplate()
                } label: {
                    if isSaving { ProgressView().controlSize(.small).frame(width: 48) }
                    else { Text("Save").fontWeight(.bold).frame(width: 48) }
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.appColors.primaryColor)
                .disabled(templateName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 16))
    }

    private var libraryHeader: some View {
        HStack {
            Text("MY TEMPLATES").font(.caption.bold()).foregroundStyle(.secondary)
            Spacer()
            Text("\(templates.count)").font(.caption.bold()).foregroundStyle(Color.appColors.primaryColor)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.3.group.bubble.left")
                .font(.system(size: 34)).foregroundStyle(Color.appColors.primaryColor)
            Text("Your template library is empty").font(.subheadline.bold())
            Text("Name the current edit above to save its structure, styling, audio, graphics, and replaceable media slots.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
    }

    private func templateCard(_ template: EditorProjectTemplate) -> some View {
        let validation = EditorTemplateStore.shared.validation(for: template)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                templatePreview(template)
                    .frame(width: 92, height: 92)
                    .clipShape(RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 6) {
                    Text(template.name).font(.headline).lineLimit(1)
                    Label(
                        "\(template.primarySlotCount) media · \(template.overlaySlotCount) overlay slots",
                        systemImage: "rectangle.on.rectangle.angled"
                    )
                    Label(
                        "\(template.project.formattedDuration) · \(template.project.canvasSettings.format.title)",
                        systemImage: "clock"
                    )
                    if !template.requiredFontFamilies.isEmpty {
                        Label("\(template.requiredFontFamilies.count) font styles", systemImage: "textformat")
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }

            if !validation.isReady {
                Label(
                    "\(validation.issueCount) original references unavailable. Current timeline media can still fill matching slots.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption).foregroundStyle(.orange)
            }

            HStack(spacing: 10) {
                Button(role: .destructive) {
                    delete(template)
                } label: {
                    Image(systemName: "trash").frame(width: 36, height: 24)
                }
                .buttonStyle(.bordered)

                Button {
                    pendingTemplate = template
                } label: {
                    Label("Apply to current media", systemImage: "wand.and.stars")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.appColors.primaryColor)
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private func templatePreview(_ template: EditorProjectTemplate) -> some View {
        if let url = EditorTemplateStore.shared.thumbnailURL(for: template),
           let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image).resizable().scaledToFill()
        } else {
            ZStack {
                LinearGradient(
                    colors: [Color.appColors.primaryColor.opacity(0.55), .purple.opacity(0.35)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: "film.stack.fill").font(.title).foregroundStyle(.white.opacity(0.9))
            }
        }
    }

    private func saveTemplate() {
        let name = templateName
        isSaving = true
        localMessage = nil
        Task {
            do {
                _ = try await vm.saveCurrentProjectAsTemplate(named: name)
                templateName = ""
                reload()
            } catch {
                localMessage = error.localizedDescription
            }
            isSaving = false
        }
    }

    private func apply(_ template: EditorProjectTemplate) {
        do {
            try vm.applyTemplate(template)
            localMessage = nil
        } catch {
            localMessage = error.localizedDescription
        }
    }

    private func delete(_ template: EditorProjectTemplate) {
        do {
            try EditorTemplateStore.shared.delete(template)
            localMessage = "Deleted “\(template.name)”. Applied projects keep private copies of its assets."
            reload()
        } catch {
            localMessage = error.localizedDescription
        }
    }

    private func reload() {
        templates = EditorTemplateStore.shared.loadAll()
    }
}

struct ProxyRenderCachePanel: View {
    let vm: EditorViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 16) {
                    originalMediaBanner
                    proxyCard
                    renderCard
                    storageCard
                    if let message = vm.cacheStatusMessage {
                        Label(message, systemImage: statusIcon)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                    }
                }
                .padding(18)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
        }
        .background(Color.appColors.backgroundColor)
        .task { await vm.refreshMediaCacheStats() }
    }

    private var header: some View {
        ZStack {
            VStack(spacing: 2) {
                Text("Performance Media").font(.headline)
                Text("Proxy & render cache").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Done") { vm.selectedTool = nil }
                    .font(.subheadline.bold())
                    .foregroundStyle(Color.appColors.primaryColor)
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 58)
    }

    private var originalMediaBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.shield.fill")
                .font(.title3)
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 4) {
                Text("Originals stay authoritative")
                    .font(.subheadline.bold())
                Text("Performance files are used only while editing. Every export reads the full-quality original media.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color.green.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
    }

    private var proxyCard: some View {
        cacheCard(title: "PROXY MEDIA", icon: "bolt.horizontal.circle.fill") {
            Toggle("Use proxies for playback", isOn: Binding(
                get: { vm.proxySettings.isEnabled },
                set: vm.setProxyEnabled
            ))
            .tint(Color.appColors.primaryColor)

            Toggle("Generate automatically", isOn: Binding(
                get: { vm.proxySettings.automaticallyGenerate },
                set: vm.setAutomaticProxyGeneration
            ))
            .tint(Color.appColors.primaryColor)
            .disabled(!vm.proxySettings.isEnabled)

            Picker("Proxy quality", selection: Binding(
                get: { vm.proxySettings.quality },
                set: vm.setProxyQuality
            )) {
                ForEach(EditorProxyQuality.allCases) { quality in
                    Text(quality.title).tag(quality)
                }
            }
            .pickerStyle(.segmented)
            .disabled(!vm.proxySettings.isEnabled)

            if let progress = vm.proxyGenerationProgress {
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text("Generating proxies")
                        Spacer()
                        Text(progress, format: .percent.precision(.fractionLength(0)))
                            .monospacedDigit()
                    }
                    .font(.caption.weight(.semibold))
                    ProgressView(value: progress).tint(Color.appColors.primaryColor)
                }
            }

            Button {
                vm.generateMissingProxies()
            } label: {
                Label("Generate missing proxies", systemImage: "wand.and.rays")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.appColors.primaryColor)
            .disabled(vm.proxyGenerationProgress != nil)
        }
    }

    private var renderCard: some View {
        cacheCard(title: "RENDER CACHE", icon: "film.stack.fill") {
            Toggle("Cache complex playback", isOn: Binding(
                get: { vm.proxySettings.backgroundRenderCache },
                set: vm.setBackgroundRenderCache
            ))
            .tint(Color.appColors.primaryColor)

            Text("After editing pauses, Mixtape renders the exact current cut for smooth playback. Any visual, timing, or audio change gets a new fingerprint.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                vm.buildRenderCacheNow()
            } label: {
                HStack {
                    if vm.isBuildingRenderCache { ProgressView().controlSize(.small) }
                    Label(
                        vm.isBuildingRenderCache ? "Rendering current cut…" : "Render current cut now",
                        systemImage: "play.rectangle.on.rectangle.fill"
                    )
                    Spacer()
                }
            }
            .buttonStyle(.bordered)
            .disabled(!vm.proxySettings.backgroundRenderCache || vm.isBuildingRenderCache)
        }
    }

    private var storageCard: some View {
        cacheCard(title: "STORAGE", icon: "internaldrive.fill") {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(byteString(vm.mediaCacheStats.totalBytes))
                        .font(.title3.bold()).monospacedDigit()
                    Text("\(vm.mediaCacheStats.proxyCount) proxies · \(vm.mediaCacheStats.renderCount) renders")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("Limit \(budgetString)")
                    .font(.caption.bold())
                    .foregroundStyle(Color.appColors.primaryColor)
            }

            Slider(
                value: Binding(
                    get: { Double(vm.proxySettings.cacheBudgetMB) },
                    set: { vm.setMediaCacheBudgetMB(Int($0)) }
                ),
                in: 256...16_384,
                step: 256
            )
            .tint(Color.appColors.primaryColor)

            HStack(spacing: 10) {
                Button("Clear proxies", role: .destructive) { vm.clearProxyCache() }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                Button("Clear renders", role: .destructive) { vm.clearRenderCache() }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func cacheCard<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: icon)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            content()
        }
        .padding(16)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 16))
    }

    private var statusIcon: String {
        vm.isBuildingRenderCache || vm.proxyGenerationProgress != nil
            ? "hourglass"
            : "checkmark.circle"
    }

    private func byteString(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private var budgetString: String {
        ByteCountFormatter.string(
            fromByteCount: Int64(vm.proxySettings.cacheBudgetMB) * 1_024 * 1_024,
            countStyle: .file
        )
    }
}

struct VisualEffectsStackPanel: View {
    let vm: EditorViewModel
    let isEmbedded: Bool
    @State private var keyframeEditorEffectID: UUID?
    @State private var selectedCatalogCategory: EditorEffectCategory = .featured
    @State private var effectSearch = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    targetStrip
                    if let layer = selectedLayer { adjustmentControls(layer) }
                    presetStrip
                    effectStack
                    addEffectMenu
                }
                .padding(18)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
        }
        .background(Color.appColors.backgroundColor)
        .sheet(
            isPresented: Binding(
                get: { keyframeEditorEffectID != nil },
                set: { if !$0 { keyframeEditorEffectID = nil } }
            )
        ) {
            if let effectID = keyframeEditorEffectID {
                EffectAmountKeyframeTimelineSheet(
                    vm: vm,
                    effectID: effectID,
                    onDone: { keyframeEditorEffectID = nil }
                )
                .presentationDetents([.fraction(0.72), .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Color.appColors.backgroundColor)
            }
        }
    }

    private var selectedLayer: EditorAdjustmentLayer? {
        guard let id = vm.selectedAdjustmentLayerID else { return nil }
        return vm.adjustmentLayers.first { $0.id == id }
    }

    private var header: some View {
        ZStack {
            Text("Effects Stack").font(.headline)
            HStack {
                Spacer()
                Button("Done") { vm.selectedTool = nil }
                    .font(.subheadline.bold())
                    .foregroundStyle(Color.appColors.primaryColor)
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 48)
    }

    private var targetStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TARGET").font(.caption.bold()).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if vm.selectedClip != nil || vm.selectedOverlayClip != nil {
                        targetButton(
                            vm.selectedOverlayClip == nil ? "Selected Clip" : "Selected Overlay",
                            selected: vm.selectedAdjustmentLayerID == nil
                        ) { vm.selectAdjustmentLayer(nil) }
                    }
                    ForEach(vm.adjustmentLayers.sorted(by: { $0.zIndex < $1.zIndex })) { layer in
                        targetButton(
                            layer.title,
                            selected: vm.selectedAdjustmentLayerID == layer.id
                        ) { vm.selectAdjustmentLayer(layer.id) }
                    }
                    Button { vm.addAdjustmentLayer() } label: {
                        Label("Adjustment", systemImage: "plus.rectangle.on.rectangle")
                            .font(.caption.bold())
                            .padding(.horizontal, 12).padding(.vertical, 9)
                            .background(Color.white.opacity(0.08), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func targetButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.caption.bold())
                .foregroundStyle(selected ? .black : .white)
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(selected ? Color.appColors.primaryColor : Color.white.opacity(0.08), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func adjustmentControls(_ layer: EditorAdjustmentLayer) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("PROGRAM ADJUSTMENT", systemImage: "square.3.layers.3d.top.filled")
                    .font(.caption.bold()).foregroundStyle(.secondary)
                Spacer()
                Button { vm.editSelectedAdjustmentColor() } label: {
                    Label("Color", systemImage: "slider.horizontal.3")
                        .font(.caption.bold())
                }
                Button { vm.toggleSelectedAdjustmentLayer() } label: {
                    Image(systemName: layer.isEnabled ? "eye.fill" : "eye.slash")
                }
                Button(role: .destructive) { vm.deleteSelectedAdjustmentLayer() } label: {
                    Image(systemName: "trash")
                }
            }
            HStack {
                Text("Start \(layer.startTime, format: .number.precision(.fractionLength(1)))s")
                    .font(.caption).frame(width: 72, alignment: .leading)
                Slider(
                    value: Binding(
                        get: { layer.startTime },
                        set: { vm.updateSelectedAdjustmentRange(start: $0) }
                    ),
                    in: 0...max(0.1, layer.endTime - 0.1)
                )
            }
            HStack {
                Text("End \(layer.endTime, format: .number.precision(.fractionLength(1)))s")
                    .font(.caption).frame(width: 72, alignment: .leading)
                Slider(
                    value: Binding(
                        get: { layer.endTime },
                        set: { vm.updateSelectedAdjustmentRange(end: $0) }
                    ),
                    in: min(layer.startTime + 0.1, max(vm.totalDuration, 0.1))...max(vm.totalDuration, layer.startTime + 0.1)
                )
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
    }

    private var presetStrip: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("EFFECT LIBRARY").font(.caption.bold()).foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search effects", text: $effectSearch)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if !effectSearch.isEmpty {
                    Button { effectSearch = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 42)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(EditorEffectCategory.allCases) { category in
                        Button {
                            selectedCatalogCategory = category
                        } label: {
                            Label(category.title, systemImage: category.systemImage)
                                .font(.caption.bold())
                                .foregroundStyle(selectedCatalogCategory == category ? .black : .white)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 8)
                                .background(
                                    selectedCatalogCategory == category
                                        ? Color.appColors.primaryColor
                                        : Color.white.opacity(0.08),
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if filteredPresets.isEmpty {
                ContentUnavailableView.search(text: effectSearch)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 138), spacing: 10)],
                    spacing: 10
                ) {
                    ForEach(filteredPresets) { preset in
                        presetCard(preset)
                    }
                }
            }
        }
    }

    private var filteredPresets: [EditorEffectPreset] {
        let query = effectSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        return EditorEffectPreset.builtIn.filter { preset in
            let matchesCategory = query.isEmpty
                ? preset.category == selectedCatalogCategory
                : true
            let searchable = ([preset.title, preset.category.title]
                + preset.effects.map(\.kind.title))
                .joined(separator: " ")
            let matchesSearch = query.isEmpty
                || searchable.localizedCaseInsensitiveContains(query)
            return matchesCategory && matchesSearch
        }
    }

    private func presetCard(_ preset: EditorEffectPreset) -> some View {
        Button { vm.applyEffectPreset(preset) } label: {
            ZStack(alignment: .bottomLeading) {
                LinearGradient(
                    colors: catalogColors(for: preset.category),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Image(systemName: preset.category.systemImage)
                            .font(.title3.bold())
                        Spacer()
                        if preset.effects.contains(where: \.kind.isTemporal) {
                            Label("Motion", systemImage: "waveform.path")
                                .font(.system(size: 9, weight: .bold))
                        }
                    }
                    Spacer()
                    Text(preset.title)
                        .font(.subheadline.bold())
                        .lineLimit(1)
                    Text("\(preset.effects.count) layer\(preset.effects.count == 1 ? "" : "s")")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.72))
                }
                .padding(12)
            }
            .foregroundStyle(.white)
            .frame(height: 104)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Apply \(preset.title) effect")
    }

    private func catalogColors(for category: EditorEffectCategory) -> [Color] {
        switch category {
        case .featured: return [Color.orange.opacity(0.9), Color.purple.opacity(0.8)]
        case .motion: return [Color.blue.opacity(0.85), Color.cyan.opacity(0.65)]
        case .light: return [Color.orange.opacity(0.9), Color.pink.opacity(0.72)]
        case .glitch: return [Color.purple.opacity(0.9), Color.cyan.opacity(0.72)]
        case .pixel: return [Color.indigo.opacity(0.9), Color.blue.opacity(0.68)]
        case .retro: return [Color.brown.opacity(0.9), Color.orange.opacity(0.58)]
        case .stylize: return [Color.pink.opacity(0.82), Color.purple.opacity(0.82)]
        case .blur: return [Color.teal.opacity(0.82), Color.indigo.opacity(0.72)]
        }
    }

    private var effectStack: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("STACK · TOP RUNS FIRST")
                .font(.caption.bold()).foregroundStyle(.secondary)
            if vm.selectedEffectStack.isEmpty {
                ContentUnavailableView(
                    "No Effects",
                    systemImage: "wand.and.stars",
                    description: Text("Add an effect or choose a preset. Effects render in this order.")
                )
                .frame(maxWidth: .infinity, minHeight: 130)
            } else {
                ForEach(Array(vm.selectedEffectStack.enumerated()), id: \.element.id) { index, effect in
                    effectRow(effect, index: index)
                }
            }
        }
    }

    private func effectRow(_ effect: EditorVisualEffect, index: Int) -> some View {
        VStack(spacing: 10) {
            HStack {
                Image(systemName: effect.kind.systemImage).frame(width: 24)
                Text(effect.kind.title).font(.subheadline.bold())
                Spacer()
                Button { vm.moveVisualEffect(effect.id, by: -1) } label: {
                    Image(systemName: "arrow.up")
                }.disabled(index == 0)
                Button { vm.moveVisualEffect(effect.id, by: 1) } label: {
                    Image(systemName: "arrow.down")
                }.disabled(index == vm.selectedEffectStack.count - 1)
                Button { vm.toggleVisualEffect(effect.id) } label: {
                    Image(systemName: effect.isEnabled ? "eye.fill" : "eye.slash")
                }
                Button(role: .destructive) { vm.deleteVisualEffect(effect.id) } label: {
                    Image(systemName: "trash")
                }
            }
            HStack {
                Text("Amount").font(.caption).foregroundStyle(.secondary)
                Slider(
                    value: Binding(
                        get: { vm.selectedEffectStack.first(where: { $0.id == effect.id })?.amount ?? 0 },
                        set: { vm.setVisualEffectAmount(effect.id, amount: $0) }
                    ),
                    in: 0...1
                )
                Button { vm.keyframeVisualEffectAmount(effect.id) } label: {
                    Image(systemName: effect.amountKeyframes.isEmpty ? "diamond" : "diamond.fill")
                        .foregroundStyle(Color.appColors.primaryColor)
                }
                .accessibilityLabel("Add amount keyframe")
                Button {
                    vm.selectedVisualEffectID = effect.id
                    keyframeEditorEffectID = effect.id
                } label: {
                    Image(systemName: "chart.xyaxis.line")
                        .foregroundStyle(
                            effect.amountKeyframes.isEmpty
                                ? Color.secondary
                                : Color.appColors.primaryColor
                        )
                }
                .accessibilityLabel("Open effect keyframe timeline")
            }
            if let secondaryTitle = effect.kind.secondaryControlTitle {
                HStack {
                    Text(secondaryTitle)
                        .font(.caption).foregroundStyle(.secondary)
                    Slider(
                        value: Binding(
                            get: {
                                vm.selectedEffectStack.first(where: { $0.id == effect.id })?
                                    .secondaryAmount ?? 0.5
                            },
                            set: { vm.setVisualEffectSecondaryAmount(effect.id, amount: $0) }
                        ),
                        in: 0...1
                    )
                }
            }
        }
        .opacity(effect.isEnabled ? 1 : 0.5)
        .padding(12)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }

    private var addEffectMenu: some View {
        Menu {
            ForEach(EditorEffectCategory.allCases.filter { $0 != .featured }) { category in
                Section(category.title) {
                    ForEach(EditorVisualEffectKind.allCases.filter { $0.category == category }) { kind in
                        Button { vm.addVisualEffect(kind) } label: {
                            Label(kind.title, systemImage: kind.systemImage)
                        }
                    }
                }
            }
        } label: {
            Label("Add Effect", systemImage: "plus")
                .font(.body.bold())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.appColors.primaryColor, in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(.black)
        }
        .disabled(vm.selectedAdjustmentLayerID == nil && vm.selectedClip == nil && vm.selectedOverlayClip == nil)
    }
}

// MARK: - Stickers and reusable graphics

struct EditorGraphicsPanel: View {
    let vm: EditorViewModel
    @State private var category: GraphicLibraryCategory = .emoji
    @State private var query = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var favoriteIDs = EditorGraphicFavoritesStore.ids
    @State private var importError: String?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 5)

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let graphic = vm.selectedGraphicOverlay { inspector(graphic) }
                    searchField
                    categoryStrip
                    libraryGrid
                }
                .padding(18)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
        }
        .background(Color.appColors.backgroundColor)
        .alert("Couldn’t Import Graphic", isPresented: Binding(
            get: { importError != nil }, set: { if !$0 { importError = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(importError ?? "Unknown error") }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else {
                        throw CocoaError(.fileReadUnknown)
                    }
                    try vm.importGraphicImageData(data)
                } catch { importError = error.localizedDescription }
                photoItem = nil
            }
        }
    }

    private var header: some View {
        ZStack {
            VStack(spacing: 1) {
                Text("Stickers & Graphics").font(.headline)
                Text("Reusable visual layers").font(.caption2).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Done") { vm.commitGraphicEdit(); vm.selectedTool = nil }
                    .font(.subheadline.bold()).foregroundStyle(Color.appColors.primaryColor)
            }
        }
        .padding(.horizontal, 18).frame(height: 52)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search symbols", text: $query)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 13).frame(height: 42)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.07)))
    }

    private var categoryStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 9) {
                ForEach(GraphicLibraryCategory.allCases) { item in
                    Button { category = item } label: {
                        Label(item.title, systemImage: item.icon)
                            .font(.caption.bold()).padding(.horizontal, 13).frame(height: 36)
                            .foregroundStyle(category == item ? .black : .white)
                            .background(Capsule().fill(category == item ? Color.appColors.primaryColor : Color.white.opacity(0.08)))
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var libraryGrid: some View {
        if category == .imported {
            VStack(spacing: 12) {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label("Import PNG, photo or artwork", systemImage: "photo.badge.plus")
                        .font(.subheadline.bold()).frame(maxWidth: .infinity).frame(height: 52)
                        .foregroundStyle(.black)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.appColors.primaryColor))
                }
                Text("Mixtape copies the graphic into project-safe storage. Transparent PNGs stay transparent.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        } else if filteredSources.isEmpty {
            ContentUnavailableView(
                category == .favorites ? "No Favorites Yet" : "No Results",
                systemImage: category == .favorites ? "heart" : "magnifyingglass",
                description: Text(category == .favorites ? "Long-press the heart on any graphic to keep it reusable." : "Try another search.")
            )
        } else {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(filteredSources, id: \.catalogID) { source in graphicCell(source) }
            }
        }
    }

    private func graphicCell(_ source: EditorGraphicSource) -> some View {
        Button { vm.addGraphic(source: source) } label: {
            ZStack(alignment: .topTrailing) {
                graphicPreview(source)
                    .frame(maxWidth: .infinity).aspectRatio(1, contentMode: .fit)
                    .background(RoundedRectangle(cornerRadius: 13).fill(Color.white.opacity(0.07)))
                if favoriteIDs.contains(source.catalogID) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.appColors.primaryColor)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(.black.opacity(0.55)))
                        .padding(4)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                EditorGraphicFavoritesStore.toggle(source)
                favoriteIDs = EditorGraphicFavoritesStore.ids
            } label: {
                Label(
                    favoriteIDs.contains(source.catalogID) ? "Remove from Favorites" : "Add to Favorites",
                    systemImage: favoriteIDs.contains(source.catalogID) ? "heart.slash" : "heart"
                )
            }
        }
        .accessibilityLabel("Add \(source.displayName)")
        .accessibilityHint("Double tap to place on the preview. Long press for favorites.")
    }

    @ViewBuilder
    private func graphicPreview(_ source: EditorGraphicSource) -> some View {
        switch source {
        case let .emoji(value): Text(value).font(.system(size: 34))
        case let .symbol(name): Image(systemName: name).resizable().scaledToFit().padding(20).foregroundStyle(.white)
        case let .image(path):
            if let image = UIImage(contentsOfFile: path) { Image(uiImage: image).resizable().scaledToFit().padding(7) }
        }
    }

    private func inspector(_ graphic: EditorGraphicOverlay) -> some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                graphicPreview(graphic.source).frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(graphic.title).font(.subheadline.bold()).lineLimit(1)
                    Text("\(format(graphic.startTime)) – \(format(graphic.endTime))")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                Spacer()
                inspectorButton(
                    favoriteIDs.contains(graphic.source.catalogID) ? "heart.fill" : "heart",
                    "Favorite"
                ) {
                    EditorGraphicFavoritesStore.toggle(graphic.source)
                    favoriteIDs = EditorGraphicFavoritesStore.ids
                }
                inspectorButton("doc.on.doc", "Duplicate") { vm.duplicateSelectedGraphic() }
                inspectorButton("trash", "Delete", destructive: true) { vm.deleteSelectedGraphic() }
            }
            control("Size", value: Double(graphic.size), range: 40...320) { value in
                vm.updateSelectedGraphic { $0.size = CGFloat(value) }
            }
            control("Scale", value: Double(graphic.scale), range: 0.25...3) { value in
                vm.updateSelectedGraphic { $0.scale = CGFloat(value) }
            }
            control("Rotate", value: graphic.rotationDegrees, range: -180...180) { value in
                vm.updateSelectedGraphic { $0.rotationDegrees = value }
            }
            control("Opacity", value: graphic.opacity, range: 0...1) { value in
                vm.updateSelectedGraphic { $0.opacity = value }
            }
            HStack(spacing: 10) {
                Menu {
                    ForEach(EditorGraphicAnimation.allCases) { value in
                        Button(value.title) { vm.updateSelectedGraphic { $0.animation = value }; vm.commitGraphicEdit() }
                    }
                } label: { inspectorMenu("Animation", graphic.animation.title, "waveform.path") }
                Menu {
                    ForEach(EditorGraphicBlendMode.allCases) { value in
                        Button(value.title) { vm.updateSelectedGraphic { $0.blendMode = value }; vm.commitGraphicEdit() }
                    }
                } label: { inspectorMenu("Blend", graphic.blendMode.title, "circle.hexagongrid") }
                Button {
                    vm.updateSelectedGraphic { $0.isFlippedHorizontally.toggle() }; vm.commitGraphicEdit()
                } label: { inspectorMenu("Transform", "Flip", "arrow.left.and.right.righttriangle.left.righttriangle.right") }
                    .buttonStyle(.plain)
            }
        }
        .padding(14).background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.055)))
    }

    private func control(_ title: String, value: Double, range: ClosedRange<Double>, update: @escaping (Double) -> Void) -> some View {
        HStack(spacing: 12) {
            Text(title).font(.caption).foregroundStyle(.secondary).frame(width: 52, alignment: .leading)
            Slider(value: Binding(get: { value }, set: update), in: range, onEditingChanged: { if !$0 { vm.commitGraphicEdit() } })
                .tint(Color.appColors.primaryColor)
            Text(value.formatted(.number.precision(.fractionLength(title == "Opacity" ? 2 : 0))))
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 38, alignment: .trailing)
        }
    }

    private func inspectorButton(_ icon: String, _ label: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).frame(width: 34, height: 34) }
            .buttonStyle(.plain).foregroundStyle(destructive ? .red : Color.appColors.primaryColor)
            .background(Circle().fill(Color.white.opacity(0.07))).accessibilityLabel(label)
    }

    private func inspectorMenu(_ label: String, _ value: String, _ icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.body.bold())
            Text(value).font(.caption2.bold()).lineLimit(1)
        }.frame(maxWidth: .infinity).frame(height: 52)
            .foregroundStyle(.white).background(RoundedRectangle(cornerRadius: 11).fill(Color.white.opacity(0.07)))
            .accessibilityLabel("\(label): \(value)")
    }

    private var filteredSources: [EditorGraphicSource] {
        let all: [EditorGraphicSource]
        switch category {
        case .emoji: all = EditorGraphicCatalog.emojis.map(EditorGraphicSource.emoji)
        case .symbols: all = EditorGraphicCatalog.symbols.map(EditorGraphicSource.symbol)
        case .favorites:
            all = favoriteIDs.compactMap(EditorGraphicSource.init(catalogID:))
            return all.filter(matches)
        case .imported: return []
        }
        return all.filter(matches)
    }

    private func matches(_ source: EditorGraphicSource) -> Bool {
        query.isEmpty || source.displayName.localizedCaseInsensitiveContains(query)
    }

    private func format(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(seconds.rounded()))
        return String(format: "%02d:%02d", value / 60, value % 60)
    }
}

private enum GraphicLibraryCategory: String, CaseIterable, Identifiable {
    case emoji, symbols, favorites, imported
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var icon: String {
        switch self {
        case .emoji: return "face.smiling"
        case .symbols: return "sparkles"
        case .favorites: return "heart.fill"
        case .imported: return "photo.badge.plus"
        }
    }
}

private struct EffectAmountKeyframeTimelineSheet: View {
    let vm: EditorViewModel
    let effectID: UUID
    let onDone: () -> Void

    @State private var selectedKeyframeID: UUID?

    private let displayFrameRate = 30

    private var effect: EditorVisualEffect? {
        vm.selectedEffectStack.first { $0.id == effectID }
    }

    private var keyframes: [EditorKeyframe] {
        effect?.amountKeyframes.keyframes ?? []
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    timelineSummary
                    EffectKeyframeTimeRuler(
                        keyframes: keyframes,
                        duration: vm.selectedEffectTargetDuration,
                        playheadTime: vm.selectedEffectLocalTime,
                        selectedID: selectedKeyframeID,
                        onSelect: select
                    )
                    .frame(height: 150)

                    HStack {
                        Label(
                            timecode(vm.timelinePosition),
                            systemImage: "playhead.fill"
                        )
                        .font(.caption.monospacedDigit())
                        Spacer()
                        Button {
                            vm.keyframeVisualEffectAmount(effectID)
                            selectedKeyframeID = keyframes.min(by: {
                                abs($0.time - vm.selectedEffectLocalTime)
                                    < abs($1.time - vm.selectedEffectLocalTime)
                            })?.id
                        } label: {
                            Label("Add at Playhead", systemImage: "diamond.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.appColors.primaryColor)
                    }

                    keyframeList
                }
                .padding(18)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("\(effect?.kind.title ?? "Effect") Keyframes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDone)
                }
            }
        }
    }

    private var timelineSummary: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("AMOUNT · PROJECT TIMECODE · 30 FPS")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Text("Tap a diamond to jump to its exact project time.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(keyframes.count) keyframe\(keyframes.count == 1 ? "" : "s")")
                .font(.caption.monospacedDigit())
        }
    }

    @ViewBuilder
    private var keyframeList: some View {
        if keyframes.isEmpty {
            ContentUnavailableView(
                "No Amount Keyframes",
                systemImage: "diamond",
                description: Text("Move the playhead and add the first keyframe.")
            )
            .frame(maxWidth: .infinity, minHeight: 150)
        } else {
            VStack(spacing: 8) {
                ForEach(Array(keyframes.enumerated()), id: \.element.id) { index, point in
                    let globalTime = vm.selectedEffectTargetStartTime + point.time
                    EffectKeyframeListRow(
                        index: index,
                        point: point,
                        projectTimecode: timecode(globalTime),
                        projectFrame: frameNumber(globalTime),
                        isSelected: selectedKeyframeID == point.id,
                        onSelect: { select(point) },
                        onDelete: {
                            vm.deleteVisualEffectAmountKeyframe(
                                effectID: effectID,
                                keyframeID: point.id
                            )
                            if selectedKeyframeID == point.id { selectedKeyframeID = nil }
                        }
                    )
                }
            }
        }
    }

    private func select(_ point: EditorKeyframe) {
        selectedKeyframeID = point.id
        vm.seekToVisualEffectKeyframe(localTime: point.time)
    }

    private func frameNumber(_ seconds: TimeInterval) -> Int {
        Int((max(0, seconds) * Double(displayFrameRate)).rounded())
    }

    private func timecode(_ seconds: TimeInterval) -> String {
        let frames = frameNumber(seconds)
        let frame = frames % displayFrameRate
        let totalSeconds = frames / displayFrameRate
        let second = totalSeconds % 60
        let minute = (totalSeconds / 60) % 60
        let hour = totalSeconds / 3_600
        return String(format: "%02d:%02d:%02d:%02d", hour, minute, second, frame)
    }
}

private struct EffectKeyframeListRow: View {
    let index: Int
    let point: EditorKeyframe
    let projectTimecode: String
    let projectFrame: Int
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onSelect) {
                HStack(spacing: 12) {
                    Image(systemName: "diamond.fill")
                        .foregroundStyle(isSelected ? Color.white : Color.appColors.primaryColor)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Keyframe \(index + 1)  ·  \(projectTimecode)")
                            .font(.subheadline.bold().monospacedDigit())
                        Text("Project frame \(projectFrame)  ·  Local \(localTimeText)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("\(Int((point.value * 100).rounded()))%")
                            .font(.subheadline.bold().monospacedDigit())
                        Text(point.curve.preset.title)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12).fill(
                isSelected
                    ? Color.appColors.primaryColor.opacity(0.18)
                    : Color.white.opacity(0.05)
            )
        )
    }

    private var localTimeText: String {
        String(format: "%.3fs", point.time)
    }
}

private struct EffectKeyframeTimeRuler: View {
    let keyframes: [EditorKeyframe]
    let duration: TimeInterval
    let playheadTime: TimeInterval
    let selectedID: UUID?
    let onSelect: (EditorKeyframe) -> Void

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.3))

                ForEach(0...4, id: \.self) { index in
                    let progress = Double(index) / 4
                    let x = width * CGFloat(progress)
                    Rectangle()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 1)
                        .offset(x: min(x, max(0, width - 1)), y: 24)
                    Text(shortTime(duration * progress))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .offset(x: min(max(4, x - 18), max(4, width - 42)), y: 5)
                }

                Capsule()
                    .fill(Color.white.opacity(0.16))
                    .frame(height: 3)
                    .offset(y: 86)

                Rectangle()
                    .fill(Color.white.opacity(0.7))
                    .frame(width: 1, height: 82)
                    .offset(x: x(for: playheadTime, width: width), y: 48)

                ForEach(keyframes) { point in
                    EffectKeyframeDiamondShape()
                        .fill(
                            point.id == selectedID
                                ? Color.white
                                : Color.appColors.primaryColor
                        )
                        .frame(width: 20, height: 20)
                        .position(x: x(for: point.time, width: width), y: 88)
                        .contentShape(Rectangle().inset(by: -10))
                        .onTapGesture { onSelect(point) }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func x(for time: TimeInterval, width: CGFloat) -> CGFloat {
        let inset: CGFloat = 12
        let progress = min(max(time / max(duration, 0.000_001), 0), 1)
        return inset + (width - inset * 2) * CGFloat(progress)
    }

    private func shortTime(_ time: TimeInterval) -> String {
        String(format: "%.2fs", max(0, time))
    }
}

private struct EffectKeyframeDiamondShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
            path.closeSubpath()
        }
    }
}

struct CanvasToolPanel: View {
    let vm: EditorViewModel
    let isEmbedded: Bool
    @State private var draft: EditorCanvasSettings
    @State private var selectedPhoto: PhotosPickerItem?

    private let colors: [UInt32] = [0x000000, 0xFFFFFF, 0x1D1D1F, 0x273043, 0x6C4AB6, 0xD95D39, 0xE3B505, 0x2A9D8F]

    init(vm: EditorViewModel, isEmbedded: Bool = false) {
        self.vm = vm
        self.isEmbedded = isEmbedded
        _draft = State(initialValue: vm.canvasSettings)
    }

    var body: some View {
        Group {
            if isEmbedded {
                VStack(spacing: 0) {
                    embeddedHeader
                    Divider().overlay(Color.white.opacity(0.1))
                    panelContent
                }
            } else {
                NavigationStack {
                    panelContent
                        .navigationTitle("Canvas")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done", action: applyAndClose)
                            }
                        }
                }
            }
        }
        .task(id: selectedPhoto) {
            guard let data = try? await selectedPhoto?.loadTransferable(type: Data.self) else { return }
            let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("MixtapeCanvas", isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("\(UUID().uuidString).jpg")
            if (try? data.write(to: url, options: .atomic)) != nil { draft.backgroundImagePath = url.path }
        }
    }

    private var panelContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                    section("FORMAT") {
                        HStack(spacing: 8) {
                            ForEach(EditorCanvasFormat.allCases) { format in
                                chip(format.title, selected: draft.format == format) {
                                    draft.format = format
                                }
                            }
                        }
                    }

                    if draft.format == .custom {
                        HStack(spacing: 12) {
                            dimensionField("Width", value: $draft.customWidth)
                            Image(systemName: "multiply").foregroundStyle(.secondary)
                            dimensionField("Height", value: $draft.customHeight)
                        }
                    }

                    section("BACKGROUND") {
                        HStack(spacing: 8) {
                            ForEach(EditorCanvasBackgroundKind.allCases) { kind in
                                chip(kind.title, selected: draft.backgroundKind == kind) {
                                    draft.backgroundKind = kind
                                }
                            }
                        }
                    }

                    if draft.backgroundKind == .color {
                        HStack(spacing: 12) {
                            ForEach(colors, id: \.self) { rgb in
                                Button {
                                    draft.backgroundColorRGB = rgb
                                } label: {
                                    Circle()
                                        .fill(Color(rgb: rgb))
                                        .frame(width: 32, height: 32)
                                        .overlay(Circle().stroke(.white, lineWidth: draft.backgroundColorRGB == rgb ? 3 : 0))
                                }
                            }
                        }
                    } else if draft.backgroundKind == .image {
                        PhotosPicker(selection: $selectedPhoto, matching: .images) {
                            Label(draft.backgroundImagePath == nil ? "Choose Image" : "Replace Image", systemImage: "photo")
                                .font(.system(size: 14, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.08)))
                        }
                    } else {
                        Text("A softly blurred, edge-to-edge copy of the current clip fills the canvas.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
            }
            .padding(20)
        }
    }

    private var embeddedHeader: some View {
        ZStack {
            Text("Canvas").font(.system(size: 17, weight: .bold)).foregroundColor(.white)
            HStack {
                Spacer()
                Button("Done", action: applyAndClose)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color.appColors.primaryColor)
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 48)
    }

    private func applyAndClose() {
        vm.updateCanvasSettings(draft)
        vm.selectedTool = nil
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.caption.bold()).foregroundStyle(.secondary)
            content()
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 13, weight: .semibold))
                .foregroundStyle(selected ? .black : .white)
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 9).fill(selected ? Color.appColors.primaryColor : Color.white.opacity(0.08)))
        }.buttonStyle(.plain)
    }

    private func dimensionField(_ title: String, value: Binding<Int>) -> some View {
        TextField(title, value: value, format: .number)
            .keyboardType(.numberPad).textFieldStyle(.roundedBorder)
    }
}

enum EditorPrecisionMode: String, CaseIterable, Identifiable {
    case ripple = "Ripple"
    case roll = "Roll"
    case slip = "Slip"
    case slide = "Slide"
    case audio = "J/L Cuts"
    var id: String { rawValue }
}

struct PrecisionEditToolPanel: View {
    let vm: EditorViewModel
    @State private var mode: EditorPrecisionMode = .ripple
    @State private var step: TimeInterval = 0.10

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Picker("Edit type", selection: $mode) {
                        ForEach(EditorPrecisionMode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    if let message = vm.precisionEditMessage {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .font(.footnote).foregroundStyle(.orange)
                    }

                    if mode == .audio {
                        audioControls
                    } else {
                        editControls
                    }
                }
                .padding(18)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
        }
        .background(Color.appColors.backgroundColor)
    }

    private var header: some View {
        ZStack {
            Text("Timeline Precision").font(.headline)
            HStack {
                Spacer()
                Button("Done") { vm.selectedTool = nil }
                    .font(.subheadline.bold()).foregroundStyle(Color.appColors.primaryColor)
            }
        }
        .padding(.horizontal, 18).frame(height: 48)
    }

    private var editControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(explanation).font(.footnote).foregroundStyle(.secondary)

            Picker("Adjustment", selection: $step) {
                Text("1 frame").tag(TimeInterval(1.0 / 30.0))
                Text("0.10s").tag(TimeInterval(0.10))
                Text("0.50s").tag(TimeInterval(0.50))
            }
            .pickerStyle(.segmented)

            HStack(spacing: 12) {
                adjustmentButton(title: "Earlier", image: "minus", delta: -step)
                adjustmentButton(title: "Later", image: "plus", delta: step)
            }

            if mode == .ripple {
                Button(role: .destructive) { vm.deleteSelectedClip() } label: {
                    Label("Ripple delete selected clip", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!vm.canDeleteSelectedClip)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.055)))
    }

    private var audioControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let clip = vm.selectedClip, clip.isVideo {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(clip.isAudioLinked ? "Linked A/V" : "Independent audio handles")
                            .font(.subheadline.bold())
                        Text("J starts audio before picture; L keeps audio after picture.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(clip.isAudioLinked ? "Unlink" : "Relink") {
                        vm.toggleSelectedClipAudioLink()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.appColors.primaryColor)
                    .foregroundStyle(.black)
                }

                precisionBoundaryRow(
                    title: "J cut · audio start",
                    value: clip.effectiveAudioTrimStart,
                    earlier: { vm.adjustSelectedClipAudioStart(by: -step) },
                    later: { vm.adjustSelectedClipAudioStart(by: step) }
                )
                precisionBoundaryRow(
                    title: "L cut · audio end",
                    value: clip.effectiveAudioTrimEnd,
                    earlier: { vm.adjustSelectedClipAudioEnd(by: -step) },
                    later: { vm.adjustSelectedClipAudioEnd(by: step) }
                )
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.055)))
    }

    private func adjustmentButton(title: String, image: String, delta: TimeInterval) -> some View {
        Button {
            switch mode {
            case .ripple: vm.rippleTrimSelectedClipOut(by: delta)
            case .roll: vm.rollSelectedCut(by: delta)
            case .slip: vm.slipSelectedClip(by: delta)
            case .slide: vm.slideSelectedClip(by: delta)
            case .audio: break
            }
        } label: {
            Label("\(title) \(formatted(step))", systemImage: image)
                .frame(maxWidth: .infinity).padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .tint(Color.appColors.primaryColor)
        .foregroundStyle(.black)
        .disabled(
            vm.precisionEditMessage != nil
                || (mode == .roll && !vm.canRollSelectedCut)
                || (mode == .slide && !vm.canSlideSelectedClip)
        )
    }

    private func precisionBoundaryRow(
        title: String,
        value: TimeInterval,
        earlier: @escaping () -> Void,
        later: @escaping () -> Void
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline)
                Text(String(format: "Source %.2fs", value))
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: earlier) { Image(systemName: "minus") }.buttonStyle(.bordered)
            Button(action: later) { Image(systemName: "plus") }.buttonStyle(.bordered)
        }
    }

    private var explanation: String {
        switch mode {
        case .ripple: return "Trim the selected out-point and move every downstream timed item by the exact duration change."
        case .roll: return "Move the cut between the selected clip and the next clip without changing total duration."
        case .slip: return "Change source content while preserving the selected clip's timeline position and duration."
        case .slide: return "Move the selected middle clip while compensating the neighboring edit points."
        case .audio: return "Adjust linked picture and embedded-audio boundaries independently."
        }
    }

    private func formatted(_ value: TimeInterval) -> String {
        value < 0.05 ? "1f" : String(format: "%.2fs", value)
    }
}


struct SequenceSelectionActionBar: View {
    let vm: EditorViewModel
    let onStructure: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button { vm.endMultiSelection() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 56)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Finish selecting")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    sequenceAction("GROUP", image: "rectangle.3.group") { vm.groupSelectedItems() }
                        .disabled(!vm.canCreateSequence)
                    sequenceAction("COMPOUND", image: "square.stack.3d.up.fill") { vm.createCompoundClip() }
                        .disabled(!vm.canCreateSequence)
                    sequenceAction("EARLIER", image: "arrow.left") { vm.moveSelectionEarlier() }
                        .disabled(vm.selectionCount == 0)
                    sequenceAction("LATER", image: "arrow.right") { vm.moveSelectionLater() }
                        .disabled(vm.selectionCount == 0)
                    sequenceAction("DUPLICATE", image: "plus.square.on.square") {
                        vm.duplicateSelectedTimelineItems()
                    }
                    .disabled(vm.selectionCount == 0)
                    sequenceAction("STRUCTURE", image: "list.bullet.indent") { onStructure() }
                    sequenceAction("DELETE", image: "trash", destructive: true) {
                        vm.deleteSelectedTimelineItems()
                    }
                    .disabled(vm.selectionCount == 0)
                }
                .padding(.trailing, 8)
            }
        }
        .padding(.leading, 4)
        .padding(.top, 10)
        .padding(.bottom, 18)
        .background(
            Rectangle().fill(Color.white.opacity(0.02))
                .overlay(Rectangle().fill(Color.white.opacity(0.06)).frame(height: 0.5), alignment: .top)
        )
    }

    private func sequenceAction(
        _ title: String,
        image: String,
        destructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: image).font(.system(size: 18, weight: .semibold))
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.5).lineLimit(1).minimumScaleFactor(0.72)
            }
            .foregroundStyle(destructive ? Color.red.opacity(0.9) : .white)
            .frame(width: 82).frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title.capitalized)
    }
}

struct SequenceStructurePanel: View {
    let vm: EditorViewModel
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text("Sequence Structure").font(.headline)
                HStack {
                    if vm.activeSequence != nil {
                        Button { vm.exitActiveSequence() } label: {
                            Label("Up", systemImage: "arrow.turn.up.left")
                        }
                        .font(.subheadline.bold())
                        .foregroundStyle(Color.appColors.primaryColor)
                    }
                    Spacer()
                    Button("Done", action: onDone)
                        .font(.subheadline.bold()).foregroundStyle(Color.appColors.primaryColor)
                }
            }
            .padding(.horizontal, 18).frame(height: 48)

            Divider().overlay(Color.white.opacity(0.1))

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let active = vm.activeSequence {
                        Label("Editing inside \(active.title)", systemImage: "square.stack.3d.up.fill")
                            .font(.subheadline.bold()).foregroundStyle(Color.appColors.primaryColor)
                    }

                    section("SELECTION") {
                        HStack(spacing: 10) {
                            Button("Select All") { vm.selectAllInActiveSequence() }
                                .buttonStyle(.bordered)
                            Button("Select In/Out Range") { vm.selectItemsInExportRange() }
                                .buttonStyle(.bordered)
                                .disabled(!vm.hasSelectionRange)
                            Spacer()
                            Text("\(vm.selectionCount) selected")
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }

                    section("GROUPS & COMPOUNDS") {
                        if vm.visibleSequences.isEmpty {
                            Text("Select at least two timeline items, then create a group or compound clip.")
                                .font(.footnote).foregroundStyle(.secondary)
                        } else {
                            ForEach(vm.visibleSequences) { sequence in
                                SequenceRenameRow(
                                    sequence: sequence,
                                    range: vm.sequenceTimeRange(id: sequence.id),
                                    isSelected: vm.selectedSequenceID == sequence.id,
                                    onSelect: { vm.selectSequence(sequence.id) },
                                    onEnter: {
                                        vm.selectSequence(sequence.id)
                                        vm.enterSelectedSequence()
                                    },
                                    onRename: { vm.renameSequence(id: sequence.id, title: $0) }
                                )
                            }
                        }

                        if vm.selectedSequence != nil {
                            HStack {
                                Button { vm.enterSelectedSequence() } label: {
                                    Label("Enter", systemImage: "arrow.down.right.and.arrow.up.left")
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(Color.appColors.primaryColor).foregroundStyle(.black)
                                Button(role: .destructive) { vm.dissolveSelectedSequence() } label: {
                                    Label("Dissolve", systemImage: "rectangle.3.group")
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }

                    section("MARKERS") {
                        Button { vm.addMarkerAtPlayhead() } label: {
                            Label("Add marker at playhead", systemImage: "bookmark.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.appColors.primaryColor).foregroundStyle(.black)

                        ForEach(vm.markers) { marker in
                            MarkerRenameRow(
                                marker: marker,
                                onSeek: { vm.seekTimeline(to: marker.time) },
                                onRename: { vm.renameMarker(id: marker.id, name: $0) },
                                onDelete: { vm.deleteMarker(id: marker.id) }
                            )
                        }
                    }
                }
                .padding(18).frame(maxWidth: 820).frame(maxWidth: .infinity)
            }
        }
        .background(Color.appColors.backgroundColor)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.caption.bold()).foregroundStyle(.secondary)
            content()
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.055)))
    }
}

private struct SequenceRenameRow: View {
    let sequence: EditorSequence
    let range: ClosedRange<TimeInterval>?
    let isSelected: Bool
    let onSelect: () -> Void
    let onEnter: () -> Void
    let onRename: (String) -> Void
    @State private var title: String

    init(
        sequence: EditorSequence,
        range: ClosedRange<TimeInterval>?,
        isSelected: Bool,
        onSelect: @escaping () -> Void,
        onEnter: @escaping () -> Void,
        onRename: @escaping (String) -> Void
    ) {
        self.sequence = sequence
        self.range = range
        self.isSelected = isSelected
        self.onSelect = onSelect
        self.onEnter = onEnter
        self.onRename = onRename
        _title = State(initialValue: sequence.title)
    }

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onSelect) {
                Image(systemName: sequence.kind == .compound ? "square.stack.3d.up.fill" : "rectangle.3.group")
                    .foregroundStyle(isSelected ? Color.appColors.primaryColor : .white)
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            TextField("Name", text: $title)
                .textFieldStyle(.roundedBorder)
                .onSubmit { onRename(title) }
                .onDisappear { onRename(title) }
            if let range {
                Text(String(format: "%.1f–%.1fs", range.lowerBound, range.upperBound))
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Button(action: onEnter) { Image(systemName: "chevron.right") }
                .buttonStyle(.plain).foregroundStyle(.secondary)
        }
    }
}

private struct MarkerRenameRow: View {
    let marker: EditorTimelineMarker
    let onSeek: () -> Void
    let onRename: (String) -> Void
    let onDelete: () -> Void
    @State private var name: String

    init(
        marker: EditorTimelineMarker,
        onSeek: @escaping () -> Void,
        onRename: @escaping (String) -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.marker = marker
        self.onSeek = onSeek
        self.onRename = onRename
        self.onDelete = onDelete
        _name = State(initialValue: marker.name)
    }

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onSeek) {
                Text(String(format: "%.2fs", marker.time))
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(Color.appColors.primaryColor)
            }
            .buttonStyle(.plain)
            TextField("Marker name", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit { onRename(name) }
                .onDisappear { onRename(name) }
            Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }
                .buttonStyle(.plain)
        }
    }
}

private struct ToolButton: View {
    let tool: EditorTool
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: tool.systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(isSelected ? Color.appColors.primaryColor : .white)
                Text(tool.title)
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.5)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .foregroundColor(isSelected ? Color.appColors.primaryColor : Color.white.opacity(0.75))
            }
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .center)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tool.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
