//
//  ColorAdjustmentToolPanel.swift
//  Mixtape
//
//  Professional selected-clip grading workspace inspired by CapCut and DaVinci Resolve.
//

import Photos
import SwiftUI
import UIKit

private enum ColorWorkspaceSection: String, CaseIterable, Identifiable {
    case filters = "Filters"
    case adjust = "Adjust"
    case hsl = "HSL"
    case curves = "Curves"
    case wheels = "Wheels"
    case masks = "Masks"
    case scopes = "Scopes"
    var id: String { rawValue }
}

private enum MaskColorControl: String, CaseIterable, Identifiable {
    case exposure, brightness, contrast, saturation, vibrance
    case temperature, tint, hue, smoothness

    var id: String { rawValue }
    var title: String { self == .temperature ? "Temp" : rawValue.capitalized }
    var keyPath: WritableKeyPath<EditorMaskedColorAdjustment, Double> {
        switch self {
        case .exposure: return \.exposure
        case .brightness: return \.brightness
        case .contrast: return \.contrast
        case .saturation: return \.saturation
        case .vibrance: return \.vibrance
        case .temperature: return \.temperature
        case .tint: return \.tint
        case .hue: return \.hue
        case .smoothness: return \.smoothness
        }
    }
    var isPositiveOnly: Bool { self == .smoothness }
}

private enum PrimaryColorControl: String, CaseIterable, Identifiable {
    case brightness, exposure, contrast, saturation, brilliance
    case vibrance, dehaze
    case highlights, shadows, whites, blacks
    case temperature, tint, hue, fade
    case sharpness, clarity, grain, vignette

    var id: String { rawValue }
    var title: String {
        switch self {
        case .temperature: return "Temp"
        default: return rawValue.capitalized
        }
    }

    var systemImage: String {
        switch self {
        case .brightness: return "sun.max.fill"
        case .exposure: return "plusminus.circle.fill"
        case .contrast: return "circle.lefthalf.filled"
        case .saturation: return "drop.fill"
        case .brilliance: return "sun.max.trianglebadge.exclamationmark"
        case .vibrance: return "camera.filters"
        case .dehaze: return "cloud.fog.fill"
        case .highlights: return "sun.haze.fill"
        case .shadows: return "moon.fill"
        case .whites: return "square.fill"
        case .blacks: return "square.fill"
        case .temperature: return "thermometer.medium"
        case .tint: return "paintpalette.fill"
        case .hue: return "circle.hexagongrid.fill"
        case .fade: return "circle.bottomhalf.filled"
        case .sharpness: return "triangle.fill"
        case .clarity: return "viewfinder"
        case .grain: return "circle.grid.3x3.fill"
        case .vignette: return "circle.dashed.inset.filled"
        }
    }

    var keyPath: WritableKeyPath<EditorColorAdjustment, Double> {
        switch self {
        case .brightness: return \.brightness
        case .exposure: return \.exposure
        case .contrast: return \.contrast
        case .saturation: return \.saturation
        case .brilliance: return \.brilliance
        case .vibrance: return \.vibrance
        case .dehaze: return \.dehaze
        case .highlights: return \.highlights
        case .shadows: return \.shadows
        case .whites: return \.whites
        case .blacks: return \.blacks
        case .temperature: return \.temperature
        case .tint: return \.tint
        case .hue: return \.hue
        case .fade: return \.fade
        case .sharpness: return \.sharpness
        case .clarity: return \.clarity
        case .grain: return \.grain
        case .vignette: return \.vignette
        }
    }

    var isPositiveOnly: Bool {
        switch self {
        case .fade, .sharpness, .clarity, .grain, .vignette: return true
        default: return false
        }
    }
}

struct ColorAdjustmentToolPanel: View {
    let vm: EditorViewModel

    @State private var section: ColorWorkspaceSection = .filters
    @State private var filterCategory: EditorFilterCategory = .featured
    @State private var selectedControl: PrimaryColorControl = .brightness
    @State private var selectedHSLColor: EditorHSLColor = .red
    @State private var selectedCurveChannel: EditorCurveChannel = .master
    @State private var filterPreviewSource: UIImage?
    @State private var scopeMode: EditorColorScopeMode = .waveform
    @State private var scopeSnapshot: EditorColorScopeSnapshot?
    @State private var isScopeLoading = false
    @State private var scopesUseGrade = true
    @State private var selectedMaskControl: MaskColorControl = .exposure
    @State private var isDetectingFaces = false
    @State private var maskMessage: String?

    private var adjustment: EditorColorAdjustment {
        vm.selectedClip?.colorAdjustment ?? .neutral
    }

    var body: some View {
        VStack(spacing: 13) {
            header
            sectionTabs
            Divider().overlay(Color.white.opacity(0.1))

            Group {
                switch section {
                case .filters: filtersView
                case .adjust: primaryAdjustmentsView
                case .hsl: hslView
                case .curves: curvesView
                case .wheels: wheelsView
                case .masks: masksView
                case .scopes: scopesView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            if section != .masks && section != .scopes {
                footer
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .task(id: vm.selectedClipID) { await loadFilterPreviewSource() }
        .task(id: scopeFingerprint) { await updateScopeIfNeeded() }
        .onChange(of: adjustment.masks.map(\.id)) { _, ids in
            guard let selectedMaskID = vm.selectedColorMaskID, ids.contains(selectedMaskID) else {
                vm.selectedColorMaskID = ids.first
                return
            }
        }
        .onChange(of: section) { _, newSection in
            vm.isColorMaskEditing = newSection == .masks
            if newSection == .masks, vm.selectedColorMaskID == nil {
                vm.selectedColorMaskID = adjustment.masks.first?.id
            }
        }
        .onDisappear {
            vm.cancelColorMaskTracking()
            vm.isColorMaskEditing = false
            vm.selectedColorMaskID = nil
            vm.commitColorAdjustmentEdit()
        }
    }

    private var header: some View {
        HStack {
            Button("Reset") { vm.resetSelectedClipColor() }
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(adjustment.isNeutral ? Color.white.opacity(0.35) : .white)
                .disabled(adjustment.isNeutral)
            Spacer()
            Text("Color Grade")
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(.white)
            Spacer()
            Button("Done") {
                vm.commitColorAdjustmentEdit()
                vm.selectedTool = nil
            }
            .font(.system(size: 13, weight: .bold))
            .foregroundColor(Color.appColors.primaryColor)
        }
    }

    private var sectionTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 24) {
                ForEach(ColorWorkspaceSection.allCases) { item in
                    Button { section = item } label: {
                        VStack(spacing: 8) {
                            Text(item.rawValue)
                                .font(.system(size: 13, weight: section == item ? .bold : .medium))
                                .foregroundColor(section == item ? .white : Color.white.opacity(0.48))
                            Capsule()
                                .fill(section == item ? Color.appColors.primaryColor : .clear)
                                .frame(height: 2)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(section == item ? .isSelected : [])
                }
            }
        }
    }

    private var filtersView: some View {
        VStack(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(EditorFilterCategory.allCases) { category in
                        Button { filterCategory = category } label: {
                            Text(category.rawValue)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(filterCategory == category ? .black : .white)
                                .padding(.horizontal, 13)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule().fill(
                                        filterCategory == category
                                            ? Color.appColors.primaryColor
                                            : Color.white.opacity(0.08)
                                    )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            ScrollView {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3),
                    spacing: 12
                ) {
                    ForEach(filters(in: filterCategory)) { preset in
                        filterCard(preset)
                    }
                }
                .padding(.vertical, 2)
            }

            gradeSlider(
                title: "Intensity",
                value: Binding(
                    get: { adjustment.presetIntensity },
                    set: { vm.setSelectedClipFilterIntensity($0) }
                ),
                range: 0...1,
                isEnabled: adjustment.preset != .original
            )
        }
    }

    private var primaryAdjustmentsView: some View {
        VStack(spacing: 16) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 18) {
                    ForEach(PrimaryColorControl.allCases) { control in
                        primaryControlButton(control)
                    }
                }
                .padding(.horizontal, 2)
            }

            gradeSlider(
                title: selectedControl.title,
                value: Binding(
                    get: { adjustment[keyPath: selectedControl.keyPath] },
                    set: { vm.setSelectedClipColorValue(selectedControl.keyPath, value: $0) }
                ),
                range: selectedControl.isPositiveOnly ? 0...1 : -1...1
            )
        }
    }

    private var hslView: some View {
        let band = adjustment.hsl[selectedHSLColor]
        return VStack(spacing: 18) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 18) {
                    ForEach(EditorHSLColor.allCases) { color in
                        Button { selectedHSLColor = color } label: {
                            VStack(spacing: 7) {
                                Circle()
                                    .fill(hslColor(color))
                                    .frame(width: 42, height: 42)
                                    .overlay(
                                        Circle().stroke(
                                            selectedHSLColor == color ? Color.white : .clear,
                                            lineWidth: 3
                                        )
                                    )
                                Text(color.title)
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(selectedHSLColor == color ? .white : Color.white.opacity(0.55))
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 3)
            }

            hslSlider("Hue", value: band.hue, keyPath: \.hue)
            hslSlider("Saturation", value: band.saturation, keyPath: \.saturation)
            hslSlider("Lightness", value: band.lightness, keyPath: \.lightness)

            Button("Reset \(selectedHSLColor.title)") {
                vm.setSelectedClipHSLValue(color: selectedHSLColor, keyPath: \.hue, value: 0)
                vm.setSelectedClipHSLValue(color: selectedHSLColor, keyPath: \.saturation, value: 0)
                vm.setSelectedClipHSLValue(color: selectedHSLColor, keyPath: \.lightness, value: 0)
                vm.commitColorAdjustmentEdit()
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(Color.white.opacity(0.7))
        }
    }

    private var curvesView: some View {
        VStack(spacing: 14) {
            HStack(spacing: 24) {
                ForEach(EditorCurveChannel.allCases) { channel in
                    Button { selectedCurveChannel = channel } label: {
                        Circle()
                            .fill(curveColor(channel))
                            .frame(width: 34, height: 34)
                            .overlay(
                                Circle().stroke(
                                    selectedCurveChannel == channel ? Color.white : Color.white.opacity(0.18),
                                    lineWidth: selectedCurveChannel == channel ? 3 : 1
                                )
                            )
                            .overlay {
                                if channel == .master {
                                    Circle().stroke(Color.black.opacity(0.75), lineWidth: 2).padding(5)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(channel.title) curve")
                }
            }

            ToneCurveGraph(
                points: Binding(
                    get: { adjustment.curves[selectedCurveChannel] },
                    set: { vm.setSelectedClipToneCurve(channel: selectedCurveChannel, points: $0) }
                ),
                color: curveColor(selectedCurveChannel),
                onCommit: { vm.commitColorAdjustmentEdit() }
            )
            .frame(height: 210)

            HStack {
                Text("Tap to add points; drag freely to shape the curve")
                    .font(.system(size: 10))
                    .foregroundColor(Color.white.opacity(0.45))
                Spacer()
                Button("Reset curve") {
                    vm.setSelectedClipToneCurve(
                        channel: selectedCurveChannel,
                        points: EditorToneCurves.linearPoints
                    )
                    vm.commitColorAdjustmentEdit()
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color.appColors.primaryColor)
            }
        }
    }

    private var wheelsView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(EditorColorWheelRange.allCases) { range in
                    ColorWheelEditor(
                        title: range.title,
                        value: Binding(
                            get: { adjustment.wheels[range] },
                            set: { vm.setSelectedClipColorWheel(range: range, value: $0) }
                        ),
                        onCommit: { vm.commitColorAdjustmentEdit() },
                        onReset: {
                            vm.setSelectedClipColorWheel(range: range, value: .init())
                            vm.commitColorAdjustmentEdit()
                        }
                    )
                    .frame(width: 122)
                }
            }
        }
    }

    private var selectedMask: EditorColorMask? {
        guard let selectedMaskID = vm.selectedColorMaskID else { return nil }
        return adjustment.masks.first { $0.id == selectedMaskID }
    }

    private var masksView: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                maskCreationToolbar

                if !adjustment.masks.isEmpty {
                    maskSelector
                }

                if let mask = selectedMask {
                    HStack(spacing: 6) {
                        Image(systemName: "hand.draw.fill")
                        Text(mask.shape == .polygon
                            ? "Drag points directly on the preview"
                            : "Drag or pinch the window directly on the preview")
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Color.appColors.primaryColor)
                    maskActions(mask)
                    maskTrackingControls(mask)
                    maskGeometryControls(mask)
                    maskGradeControls(mask)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "circle.dashed")
                            .font(.system(size: 34, weight: .light))
                        Text("Add a face or shape mask")
                            .font(.system(size: 14, weight: .bold))
                        Text("Local corrections affect only the selected area and render identically in preview and export.")
                            .font(.system(size: 10))
                            .multilineTextAlignment(.center)
                    }
                    .foregroundColor(Color.white.opacity(0.55))
                    .padding(.vertical, 28)
                }

                if let message = vm.colorMaskTrackingMessage ?? maskMessage {
                    Text(message)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.55))
                }
            }
            .padding(.bottom, 4)
        }
    }

    private var maskCreationToolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button {
                    Task { await detectFaceMasks() }
                } label: {
                    Label(isDetectingFaces ? "Detecting…" : "Detect faces", systemImage: "face.smiling")
                        .padding(.horizontal, 11)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color.appColors.primaryColor.opacity(0.9)))
                        .foregroundColor(.black)
                }
                .disabled(isDetectingFaces || vm.player == nil)

                maskAddButton("Ellipse", systemImage: "circle.dashed", shape: .ellipse)
                maskAddButton("Rectangle", systemImage: "rectangle.dashed", shape: .rectangle)
                maskAddButton("Gradient", systemImage: "square.lefthalf.filled", shape: .linear)
                maskAddButton("Polygon", systemImage: "point.3.connected.trianglepath.dotted", shape: .polygon)
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.white)
            .buttonStyle(.plain)
        }
    }

    private func maskAddButton(
        _ title: String,
        systemImage: String,
        shape: EditorColorMaskShape
    ) -> some View {
        Button {
            addMask(shape: shape)
        } label: {
            Label(title, systemImage: systemImage)
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color.white.opacity(0.08)))
        }
    }

    private var maskSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(Array(adjustment.masks.enumerated()), id: \.element.id) { index, mask in
                    Button { vm.selectedColorMaskID = mask.id } label: {
                        HStack(spacing: 5) {
                            Image(systemName: maskIcon(mask.shape))
                            Text(mask.name.isEmpty ? "Mask \(index + 1)" : mask.name)
                        }
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(vm.selectedColorMaskID == mask.id ? .black : .white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            Capsule().fill(
                                vm.selectedColorMaskID == mask.id
                                    ? Color.appColors.primaryColor
                                    : Color.white.opacity(0.07)
                            )
                        )
                        .opacity(mask.isEnabled ? 1 : 0.45)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func maskActions(_ mask: EditorColorMask) -> some View {
        VStack(spacing: 7) {
            HStack(spacing: 7) {
                compactMaskButton(
                    vm.showsColorMaskOverlay ? "Hide overlay" : "Show overlay",
                    systemImage: vm.showsColorMaskOverlay ? "eye.slash.fill" : "eye.fill",
                    isActive: !vm.showsColorMaskOverlay
                ) {
                    vm.showsColorMaskOverlay.toggle()
                }
                compactMaskButton(mask.isEnabled ? "Enabled" : "Disabled", systemImage: mask.isEnabled ? "checkmark.circle.fill" : "circle") {
                    var updated = mask
                    updated.isEnabled.toggle()
                    vm.updateSelectedClipColorMask(updated)
                    vm.commitColorAdjustmentEdit()
                }
                compactMaskButton("Invert", systemImage: "circle.lefthalf.filled", isActive: mask.isInverted) {
                    var updated = mask
                    updated.isInverted.toggle()
                    vm.updateSelectedClipColorMask(updated)
                    vm.commitColorAdjustmentEdit()
                }
            }
            HStack(spacing: 7) {
                compactMaskButton("Reset local grade", systemImage: "arrow.counterclockwise") {
                    vm.resetSelectedClipColorMask(id: mask.id)
                }
                compactMaskButton("Delete mask", systemImage: "trash", roleColor: .red) {
                    vm.removeSelectedClipColorMask(id: mask.id)
                }
            }
        }
    }

    private func maskTrackingControls(_ mask: EditorColorMask) -> some View {
        VStack(spacing: 7) {
            HStack {
                Text("Tracking")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                if mask.isTracked {
                    Label("Tracked", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(Color.appColors.primaryColor)
                }
            }
            HStack(spacing: 7) {
                compactMaskButton("Track back", systemImage: "backward.end.fill") {
                    vm.trackSelectedColorMask(.backward)
                }
                compactMaskButton("Track forward", systemImage: "forward.end.fill") {
                    vm.trackSelectedColorMask(.forward)
                }
                if vm.isColorMaskTracking {
                    compactMaskButton("Cancel", systemImage: "xmark.circle", roleColor: .red) {
                        vm.cancelColorMaskTracking()
                    }
                } else if mask.isTracked {
                    compactMaskButton("Clear", systemImage: "arrow.uturn.backward", roleColor: .red) {
                        vm.clearSelectedColorMaskTracking()
                    }
                }
            }
            if vm.isColorMaskTracking {
                ProgressView()
                    .tint(Color.appColors.primaryColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func compactMaskButton(
        _ title: String,
        systemImage: String,
        isActive: Bool = false,
        roleColor: Color = .white,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(isActive ? .black : roleColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(isActive ? Color.appColors.primaryColor : Color.white.opacity(0.07))
                )
        }
        .buttonStyle(.plain)
    }

    private func maskGeometryControls(_ mask: EditorColorMask) -> some View {
        VStack(spacing: 9) {
            HStack {
                Text("Geometry")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                Text(mask.shape == .polygon ? "Drag preview points" : "Direct preview controls")
                    .font(.system(size: 9))
                    .foregroundColor(Color.white.opacity(0.4))
            }
            HStack(spacing: 12) {
                compactMaskSlider("Feather", value: mask.feather) { value in
                    var updated = mask
                    updated.feather = value
                    vm.updateSelectedClipColorMask(updated)
                }
                compactMaskSlider("Opacity", value: mask.opacity) { value in
                    var updated = mask
                    updated.opacity = value
                    vm.updateSelectedClipColorMask(updated)
                }
                if mask.shape != .polygon {
                    compactMaskSlider("Rotate", value: (mask.rotation + 1) / 2) { value in
                        var updated = mask
                        updated.rotation = value * 2 - 1
                        vm.updateSelectedClipColorMask(updated)
                    }
                }
            }
            if mask.shape == .polygon {
                HStack(spacing: 8) {
                    Button {
                        addPolygonPoint(to: mask)
                    } label: {
                        Label("Add point", systemImage: "plus.circle")
                    }
                    .disabled(mask.points.count >= 12)
                    Button {
                        removePolygonPoint(from: mask)
                    } label: {
                        Label("Remove point", systemImage: "minus.circle")
                    }
                    .disabled(mask.points.count <= 3)
                }
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Color.appColors.primaryColor)
                .buttonStyle(.plain)
            }
        }
    }

    private func compactMaskSlider(
        _ title: String,
        value: Double,
        onChange: @escaping (Double) -> Void
    ) -> some View {
        VStack(spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int(value * 100))")
                    .monospacedDigit()
            }
            .font(.system(size: 8, weight: .semibold))
            .foregroundColor(Color.white.opacity(0.58))
            Slider(
                value: Binding(get: { value }, set: onChange),
                in: 0...1,
                step: 0.01,
                onEditingChanged: { if !$0 { vm.commitColorAdjustmentEdit() } }
            )
            .tint(Color.appColors.primaryColor)
        }
    }

    private func maskGradeControls(_ mask: EditorColorMask) -> some View {
        VStack(spacing: 9) {
            HStack {
                Text("Local grade")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                Text(mask.shape == .face ? "Skin correction" : "Inside mask")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(Color.appColors.primaryColor)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(MaskColorControl.allCases) { control in
                        let active = selectedMaskControl == control
                        Button { selectedMaskControl = control } label: {
                            VStack(spacing: 4) {
                                Text(control.title)
                                    .font(.system(size: 9, weight: .semibold))
                                Circle()
                                    .fill(abs(mask.adjustment[keyPath: control.keyPath]) > 0.001 ? Color.appColors.primaryColor : .clear)
                                    .frame(width: 4, height: 4)
                            }
                            .foregroundColor(active ? .black : .white)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(active ? Color.appColors.primaryColor : Color.white.opacity(0.07))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            gradeSlider(
                title: selectedMaskControl.title,
                value: Binding(
                    get: { selectedMask?.adjustment[keyPath: selectedMaskControl.keyPath] ?? 0 },
                    set: { value in
                        guard var updated = selectedMask else { return }
                        updated.adjustment[keyPath: selectedMaskControl.keyPath] = value
                        vm.updateSelectedClipColorMask(updated)
                    }
                ),
                range: selectedMaskControl.isPositiveOnly ? 0...1 : -1...1,
                tint: Color.appColors.primaryColor
            )
        }
    }

    private var scopesView: some View {
        VStack(spacing: 12) {
            HStack(spacing: 7) {
                ForEach(EditorColorScopeMode.allCases) { mode in
                    Button { scopeMode = mode } label: {
                        Text(mode.rawValue)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(scopeMode == mode ? .black : .white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(scopeMode == mode ? Color.appColors.primaryColor : Color.white.opacity(0.07))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            ZStack {
                if let scopeSnapshot {
                    EditorVideoScopesView(snapshot: scopeSnapshot, mode: scopeMode)
                } else {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.black.opacity(0.72))
                    Text(filterPreviewSource == nil ? "Frame unavailable" : "Building scope…")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.5))
                }
                if isScopeLoading {
                    ProgressView()
                        .tint(.white)
                        .padding(8)
                        .background(Circle().fill(Color.black.opacity(0.6)))
                }
            }
            .frame(height: 218)

            HStack(spacing: 8) {
                scopeSourceButton("Source", usesGrade: false)
                scopeSourceButton("Graded", usesGrade: true)
                Spacer()
                Image(systemName: "info.circle")
                Text("Scope uses a downsampled selected-clip frame")
            }
            .font(.system(size: 9, weight: .medium))
            .foregroundColor(Color.white.opacity(0.43))
        }
    }

    private func scopeSourceButton(_ title: String, usesGrade: Bool) -> some View {
        Button {
            scopesUseGrade = usesGrade
        } label: {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(scopesUseGrade == usesGrade ? .black : .white)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    Capsule().fill(
                        scopesUseGrade == usesGrade
                            ? Color.appColors.primaryColor
                            : Color.white.opacity(0.08)
                    )
                )
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            footerButton("Copy", systemImage: "doc.on.doc") { vm.copySelectedClipColor() }
            footerButton(
                "Paste",
                systemImage: "doc.on.clipboard",
                isEnabled: vm.canPasteColorAdjustment
            ) { vm.pasteColorToSelectedClip() }
            footerButton("Apply all", systemImage: "square.stack.3d.up.fill") {
                vm.applySelectedColorToAllClips()
            }
        }
    }

    private func filters(in category: EditorFilterCategory) -> [EditorFilterPreset] {
        var result = EditorFilterPreset.allCases.filter { $0.category == category }
        if category != .featured { result.insert(.original, at: 0) }
        return result
    }

    private func filterCard(_ preset: EditorFilterPreset) -> some View {
        let selected = adjustment.preset == preset
        let colors = preset.swatchRGB.map(Color.init(rgb:))
        return Button {
            vm.setSelectedClipFilter(preset)
            vm.commitColorAdjustmentEdit()
        } label: {
            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(height: 62)
                    .overlay {
                        FilterThumbnailPreview(
                            preset: preset,
                            source: filterPreviewSource
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .overlay {
                        if preset == .original {
                            Image(systemName: "circle.slash")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white)
                        }
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(selected ? Color.appColors.primaryColor : Color.white.opacity(0.1), lineWidth: selected ? 2 : 1)
                    )
                Text(preset.title)
                    .font(.system(size: 10, weight: selected ? .bold : .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .foregroundColor(selected ? Color.appColors.primaryColor : Color.white.opacity(0.72))
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func primaryControlButton(_ control: PrimaryColorControl) -> some View {
        let selected = selectedControl == control
        let value = adjustment[keyPath: control.keyPath]
        return Button { selectedControl = control } label: {
            VStack(spacing: 7) {
                ZStack {
                    Circle()
                        .fill(selected ? Color.appColors.primaryColor : Color.white.opacity(0.07))
                        .frame(width: 43, height: 43)
                    Image(systemName: control.systemImage)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(selected ? .black : .white)
                }
                Text(control.title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(selected ? Color.appColors.primaryColor : Color.white.opacity(0.66))
                Circle()
                    .fill(abs(value) > 0.001 ? Color.appColors.primaryColor : Color.white.opacity(0.2))
                    .frame(width: 4, height: 4)
            }
        }
        .buttonStyle(.plain)
        .accessibilityValue("\(Int(value * 100))")
    }

    private func hslSlider(
        _ title: String,
        value: Double,
        keyPath: WritableKeyPath<EditorHSLBandAdjustment, Double>
    ) -> some View {
        gradeSlider(
            title: title,
            value: Binding(
                get: { adjustment.hsl[selectedHSLColor][keyPath: keyPath] },
                set: {
                    vm.setSelectedClipHSLValue(
                        color: selectedHSLColor,
                        keyPath: keyPath,
                        value: $0
                    )
                }
            ),
            range: -1...1,
            tint: hslColor(selectedHSLColor)
        )
    }

    private func gradeSlider(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        isEnabled: Bool = true,
        tint: Color = Color.appColors.primaryColor
    ) -> some View {
        VStack(spacing: 7) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                Text("\(Int(value.wrappedValue * 100))")
                    .font(.system(size: 12, weight: .bold).monospacedDigit())
                    .foregroundColor(tint)
                    .frame(width: 38, alignment: .trailing)
            }
            Slider(
                value: value,
                in: range,
                step: 0.01,
                onEditingChanged: { if !$0 { vm.commitColorAdjustmentEdit() } }
            )
            .tint(tint)
            .disabled(!isEnabled)
            .opacity(isEnabled ? 1 : 0.35)
        }
    }

    private func footerButton(
        _ title: String,
        systemImage: String,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(isEnabled ? .white : Color.white.opacity(0.28))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(isEnabled ? 0.08 : 0.035)))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    private func hslColor(_ color: EditorHSLColor) -> Color {
        switch color {
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .cyan: return .cyan
        case .blue: return .blue
        case .purple: return .purple
        case .magenta: return .pink
        }
    }

    private func curveColor(_ channel: EditorCurveChannel) -> Color {
        switch channel {
        case .master: return .white
        case .red: return .red
        case .green: return .green
        case .blue: return .blue
        }
    }

    private func maskIcon(_ shape: EditorColorMaskShape) -> String {
        switch shape {
        case .face: return "face.smiling"
        case .ellipse: return "circle.dashed"
        case .rectangle: return "rectangle.dashed"
        case .linear: return "square.lefthalf.filled"
        case .polygon: return "point.3.connected.trianglepath.dotted"
        }
    }

    private func addMask(shape: EditorColorMaskShape) {
        let number = adjustment.masks.filter { $0.shape == shape }.count + 1
        var mask = EditorColorMask(name: "\(shape.title) \(number)", shape: shape)
        if shape == .linear {
            mask.width = 1
            mask.height = 1
            mask.feather = 0.35
        }
        guard let id = vm.addSelectedClipColorMask(mask) else {
            maskMessage = "A clip can contain up to eight color masks."
            return
        }
        vm.selectedColorMaskID = id
        maskMessage = nil
    }

    private func addPolygonPoint(to mask: EditorColorMask) {
        guard mask.points.count >= 2, mask.points.count < 12 else { return }
        var updated = mask
        let pairs = updated.points.indices.map { index -> (Int, Double) in
            let next = (index + 1) % updated.points.count
            let dx = updated.points[index].x - updated.points[next].x
            let dy = updated.points[index].y - updated.points[next].y
            return (index, dx * dx + dy * dy)
        }
        guard let longest = pairs.max(by: { $0.1 < $1.1 })?.0 else { return }
        let next = (longest + 1) % updated.points.count
        let midpoint = EditorColorMaskPoint(
            x: (updated.points[longest].x + updated.points[next].x) / 2,
            y: (updated.points[longest].y + updated.points[next].y) / 2
        )
        updated.points.insert(midpoint, at: longest + 1)
        vm.updateSelectedClipColorMask(updated)
        vm.commitColorAdjustmentEdit()
    }

    private func removePolygonPoint(from mask: EditorColorMask) {
        guard mask.points.count > 3 else { return }
        var updated = mask
        updated.points.removeLast()
        vm.updateSelectedClipColorMask(updated)
        vm.commitColorAdjustmentEdit()
    }

    @MainActor
    private func detectFaceMasks() async {
        isDetectingFaces = true
        maskMessage = nil
        guard let source = await vm.currentProgramFrameForMaskDetection() else {
            isDetectingFaces = false
            maskMessage = "The current preview frame is not available yet."
            return
        }
        let suggestions = await Task.detached(priority: .userInitiated) {
            (try? EditorFaceMaskDetector.detectFaces(in: source)) ?? []
        }.value
        guard !Task.isCancelled else { return }
        isDetectingFaces = false
        guard !suggestions.isEmpty else {
            maskMessage = "No clear faces were found in this frame. Try an ellipse mask."
            return
        }

        let availableSlots = max(0, 8 - adjustment.masks.count)
        var firstAddedID: UUID?
        let firstFaceNumber = adjustment.masks.filter { $0.shape == .face }.count + 1
        for (index, suggestion) in suggestions.prefix(availableSlots).enumerated() {
            var mask = EditorColorMask(name: "Face \(firstFaceNumber + index)", shape: .face)
            mask.centerX = suggestion.centerX
            mask.centerY = suggestion.centerY
            mask.width = suggestion.width
            mask.height = suggestion.height
            mask.feather = 0.32
            let id = vm.addSelectedClipColorMask(mask)
            if firstAddedID == nil { firstAddedID = id }
        }
        if let firstAddedID {
            vm.selectedColorMaskID = firstAddedID
            vm.commitColorAdjustmentEdit()
            maskMessage = suggestions.count == 1
                ? "Face mask added. Use Track back/forward to follow the subject."
                : "\(min(suggestions.count, availableSlots)) face masks added. Select one, then track it from this frame."
        } else {
            maskMessage = "A clip can contain up to eight color masks."
        }
    }

    @MainActor
    private func loadFilterPreviewSource() async {
        if let selectedMaskID = vm.selectedColorMaskID,
           !adjustment.masks.contains(where: { $0.id == selectedMaskID }) {
            vm.selectedColorMaskID = adjustment.masks.first?.id
        } else if vm.selectedColorMaskID == nil {
            vm.selectedColorMaskID = adjustment.masks.first?.id
        }
        guard let asset = vm.selectedClip?.asset else {
            filterPreviewSource = nil
            return
        }
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .exact
        options.isNetworkAccessAllowed = true
        filterPreviewSource = await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 512, height: 512),
                contentMode: .aspectFit,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    private var scopeFingerprint: String {
        "\(section.rawValue)|\(vm.selectedClipID?.uuidString ?? "none")|\(adjustment.hashValue)|\(filterPreviewSource?.hash ?? 0)|\(scopesUseGrade)"
    }

    @MainActor
    private func updateScopeIfNeeded() async {
        guard section == .scopes, let source = filterPreviewSource else { return }
        isScopeLoading = true
        // Slider drags can publish dozens of values per second. Debounce scope
        // work so playback and the grade renderer always win the GPU budget.
        try? await Task.sleep(for: .milliseconds(140))
        guard !Task.isCancelled else { return }
        let grade = scopesUseGrade ? adjustment : .neutral
        let result = await Task.detached(priority: .utility) {
            EditorColorScopeAnalyzer.analyze(source: source, grade: grade)
        }.value
        guard !Task.isCancelled else { return }
        scopeSnapshot = result
        isScopeLoading = false
    }
}

private struct FilterThumbnailPreview: View {
    let preset: EditorFilterPreset
    let source: UIImage?
    @State private var rendered: UIImage?

    var body: some View {
        Group {
            if let rendered {
                Image(uiImage: rendered)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.clear
            }
        }
        .task(id: "\(preset.rawValue)|\(source?.hash ?? 0)") {
            guard let source else {
                rendered = nil
                return
            }
            await Task.yield()
            rendered = EditorColorGradeRenderer.filterThumbnail(
                preset: preset,
                source: source
            )
        }
        .accessibilityHidden(true)
    }
}
