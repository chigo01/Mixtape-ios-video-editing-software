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
