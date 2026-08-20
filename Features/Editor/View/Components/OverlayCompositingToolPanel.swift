//
//  OverlayCompositingToolPanel.swift
//  Mixtape
//

import SwiftUI

struct OverlayCompositingToolPanel: View {
    let vm: EditorViewModel
    let isEmbedded: Bool
    let onDone: () -> Void

    private enum Section: String, CaseIterable, Identifiable {
        case blend = "Blend"
        case mask = "Mask"
        case chroma = "Chroma"
        case shadow = "Shadow"
        var id: String { rawValue }
    }

    @State private var section: Section = .blend

    private var settings: EditorOverlayCompositing {
        vm.selectedCompositing ?? .standard
    }

    var body: some View {
        Group {
            if isEmbedded {
                VStack(spacing: 0) {
                    embeddedHeader
                    Divider().overlay(Color.white.opacity(0.10))
                    panelContent
                }
            } else {
                NavigationStack {
                    panelContent
                        .navigationTitle("Compositing")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Reset") { vm.resetSelectedCompositing() }
                                    .foregroundColor(.white.opacity(0.7))
                            }
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done", action: finish)
                                    .fontWeight(.bold)
                                    .foregroundColor(Color.appColors.primaryColor)
                            }
                        }
                }
            }
        }
        .background(Color.appColors.backgroundColor)
    }

    private var embeddedHeader: some View {
        ZStack {
            Text("Compositing")
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(.white)
            HStack {
                Button("Reset") { vm.resetSelectedCompositing() }
                    .foregroundColor(.white.opacity(0.65))
                Spacer()
                Button("Done", action: finish)
                    .fontWeight(.bold)
                    .foregroundColor(Color.appColors.primaryColor)
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 48)
    }

    private var panelContent: some View {
        VStack(spacing: 0) {
            Picker("Compositing section", selection: $section) {
                ForEach(Section.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider().overlay(Color.white.opacity(0.10))

            ScrollView {
                Group {
                    switch section {
                    case .blend: blendControls
                    case .mask: maskControls
                    case .chroma: chromaControls
                    case .shadow: shadowControls
                    }
                }
                .frame(maxWidth: 920)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
            }
        }
    }

    private var blendControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Blend mode", detail: "Controls how this layer mixes with everything below it.")
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 96, maximum: 150), spacing: 10)],
                spacing: 10
            ) {
                ForEach(EditorOverlayBlendMode.allCases) { mode in
                    let selected = settings.blendMode == mode
                    Button {
                        mutate { $0.blendMode = mode }
                    } label: {
                        Text(mode.title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(selected ? .black : .white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 42)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(selected
                                        ? Color.appColors.primaryColor
                                        : Color.white.opacity(0.08))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var maskControls: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("Visibility mask", detail: "Reveal only part of the overlay with feathered, invertible geometry.")

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 10)], spacing: 10) {
                ForEach(EditorOverlayMaskShape.allCases) { shape in
                    let selected = settings.mask.shape == shape
                    Button {
                        mutate { $0.mask.shape = shape }
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: shape.systemImage)
                                .font(.system(size: 18, weight: .semibold))
                            Text(shape.title)
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundColor(selected ? .black : .white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 62)
                        .background(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(selected
                                    ? Color.appColors.primaryColor
                                    : Color.white.opacity(0.08))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            if settings.mask.isEnabled {
                Toggle("Invert mask", isOn: binding(
                    get: { settings.mask.isInverted },
                    set: { value in mutate { $0.mask.isInverted = value } }
                ))
                .font(.system(size: 13, weight: .semibold))
                .tint(Color.appColors.primaryColor)

                if settings.mask.shape != .polygon {
                    slider("Horizontal position", value: settings.mask.centerX, range: 0...1) {
                        value in mutate { $0.mask.centerX = value }
                    }
                    slider("Vertical position", value: settings.mask.centerY, range: 0...1) {
                        value in mutate { $0.mask.centerY = value }
                    }
                    if settings.mask.shape != .linear {
                        slider("Width", value: settings.mask.width, range: 0.05...1.5) {
                            value in mutate { $0.mask.width = value }
                        }
                        slider("Height", value: settings.mask.height, range: 0.05...1.5) {
                            value in mutate { $0.mask.height = value }
                        }
                    }
                    slider("Rotation", value: settings.mask.rotation, range: -1...1) {
                        value in mutate { $0.mask.rotation = value }
                    }
                }
                slider("Feather", value: settings.mask.feather, range: 0...1) {
                    value in mutate { $0.mask.feather = value }
                }
                slider("Expand / contract", value: settings.mask.expansion, range: -1...1) {
                    value in mutate { $0.mask.expansion = value }
                }
                slider("Mask opacity", value: settings.mask.opacity, range: 0...1) {
                    value in mutate { $0.mask.opacity = value }
                }
                if settings.mask.shape == .polygon {
                    HStack {
                        Text("Drag polygon points directly on the preview.")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.5))
                        Spacer()
                        Button("+ Point") { addPolygonPoint() }
                            .buttonStyle(.bordered)
                            .tint(Color.appColors.primaryColor)
                        Button("− Point") { removePolygonPoint() }
                            .buttonStyle(.bordered)
                            .disabled(settings.mask.points.count <= 3)
                    }
                }
            }
        }
    }

    private var chromaControls: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                sectionTitle("Chroma key", detail: "Remove a keyed background while retaining natural edges.")
                Spacer()
                Toggle("", isOn: binding(
                    get: { settings.chromaKey.isEnabled },
                    set: { value in mutate { $0.chromaKey.isEnabled = value } }
                ))
                .labelsHidden()
                .tint(Color.appColors.primaryColor)
            }

            if settings.chromaKey.isEnabled {
                HStack(spacing: 10) {
                    keyPreset("Green", red: 0, green: 1, blue: 0)
                    keyPreset("Blue", red: 0, green: 0.25, blue: 1)
                    keyPreset("Magenta", red: 1, green: 0, blue: 0.65)
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color(
                            red: settings.chromaKey.red,
                            green: settings.chromaKey.green,
                            blue: settings.chromaKey.blue
                        ))
                        .frame(width: 48, height: 40)
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .stroke(Color.white.opacity(0.3), lineWidth: 1)
                        )
                        .accessibilityLabel("Current key color")
                }

                slider("Key red", value: settings.chromaKey.red, range: 0...1) {
                    value in mutate { $0.chromaKey.red = value }
                }
                slider("Key green", value: settings.chromaKey.green, range: 0...1) {
                    value in mutate { $0.chromaKey.green = value }
                }
                slider("Key blue", value: settings.chromaKey.blue, range: 0...1) {
                    value in mutate { $0.chromaKey.blue = value }
                }
                slider("Tolerance", value: settings.chromaKey.threshold, range: 0.01...0.75) {
                    value in mutate { $0.chromaKey.threshold = value }
                }
                slider("Edge softness", value: settings.chromaKey.softness, range: 0.001...0.5) {
                    value in mutate { $0.chromaKey.softness = value }
                }
                slider("Spill suppression", value: settings.chromaKey.spillSuppression, range: 0...1) {
                    value in mutate { $0.chromaKey.spillSuppression = value }
                }
                slider("Edge desaturation", value: settings.chromaKey.edgeDesaturation, range: 0...1) {
                    value in mutate { $0.chromaKey.edgeDesaturation = value }
                }
            }

            Divider().overlay(Color.white.opacity(0.10))
            Toggle("Luma key", isOn: binding(
                get: { settings.lumaKey.isEnabled },
                set: { value in mutate { $0.lumaKey.isEnabled = value } }
            ))
            .font(.system(size: 13, weight: .semibold))
            .tint(Color.appColors.primaryColor)
            if settings.lumaKey.isEnabled {
                Toggle("Keep shadows instead", isOn: binding(
                    get: { settings.lumaKey.isInverted },
                    set: { value in mutate { $0.lumaKey.isInverted = value } }
                ))
                .font(.system(size: 12, weight: .semibold))
                .tint(Color.appColors.primaryColor)
                slider("Luma threshold", value: settings.lumaKey.threshold, range: 0...1) {
                    value in mutate { $0.lumaKey.threshold = value }
                }
                slider("Luma softness", value: settings.lumaKey.softness, range: 0.01...0.5) {
                    value in mutate { $0.lumaKey.softness = value }
                }
            }
        }
    }

    private var shadowControls: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                sectionTitle("Layer shadow", detail: "Separate cutouts and overlays from the background.")
                Spacer()
                Toggle("", isOn: binding(
                    get: { settings.shadow.isEnabled },
                    set: { value in mutate { $0.shadow.isEnabled = value } }
                ))
                .labelsHidden()
                .tint(Color.appColors.primaryColor)
            }
            if settings.shadow.isEnabled {
                slider("Opacity", value: settings.shadow.opacity, range: 0...1) {
                    value in mutate { $0.shadow.opacity = value }
                }
                slider("Blur", value: settings.shadow.blur, range: 0...1) {
                    value in mutate { $0.shadow.blur = value }
                }
                slider("Distance", value: settings.shadow.distance, range: 0...0.35) {
                    value in mutate { $0.shadow.distance = value }
                }
                slider("Direction", value: settings.shadow.angle, range: -1...1) {
                    value in mutate { $0.shadow.angle = value }
                }
            }
        }
    }

    private func sectionTitle(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.white)
            Text(detail)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.48))
        }
    }

    private func slider(
        _ title: String,
        value: Double,
        range: ClosedRange<Double>,
        update: @escaping (Double) -> Void
    ) -> some View {
        VStack(spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
                Spacer()
                Text(String(format: "%.2f", value))
                    .font(.system(size: 11, weight: .bold).monospacedDigit())
                    .foregroundColor(Color.appColors.primaryColor)
            }
            Slider(
                value: binding(get: { value }, set: update),
                in: range
            )
            .tint(Color.appColors.primaryColor)
        }
    }

    private func keyPreset(
        _ title: String,
        red: Double,
        green: Double,
        blue: Double
    ) -> some View {
        Button {
            mutate {
                $0.chromaKey.red = red
                $0.chromaKey.green = green
                $0.chromaKey.blue = blue
            }
        } label: {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
    }

    private func binding<Value>(
        get: @escaping () -> Value,
        set: @escaping (Value) -> Void
    ) -> Binding<Value> {
        Binding(get: get, set: set)
    }

    private func mutate(_ update: (inout EditorOverlayCompositing) -> Void) {
        vm.updateSelectedCompositing(update)
    }

    private func addPolygonPoint() {
        mutate { settings in
            guard settings.mask.points.count < 24,
                  let first = settings.mask.points.first,
                  let last = settings.mask.points.last else { return }
            settings.mask.points.append(.init(x: (first.x + last.x) / 2, y: (first.y + last.y) / 2))
        }
    }

    private func removePolygonPoint() {
        mutate { settings in
            guard settings.mask.points.count > 3 else { return }
            settings.mask.points.removeLast()
        }
    }

    private func finish() {
        vm.commitOverlayCompositing()
        onDone()
    }
}
