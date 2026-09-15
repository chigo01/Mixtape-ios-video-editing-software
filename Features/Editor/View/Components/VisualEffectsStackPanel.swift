//
//  VisualEffectsStackPanel.swift
//  Mixtape
//

import SwiftUI
import PhotosUI

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

