//
//  BackgroundToolPanel.swift
//  Mixtape
//

import SwiftUI
import PhotosUI

struct BackgroundToolPanel: View {
    let vm: EditorViewModel
    let isEmbedded: Bool

    @State private var draft: EditorCanvasSettings
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var customColor: Color

    private let colors: [UInt32] = [
        0xFFFFFF, 0xD1D1D1, 0x8E8E93, 0x3A3A3C, 0x000000,
        0xFFCC00, 0xFF7A00, 0xFF453A, 0xAF52DE, 0x5856D6,
        0x0A84FF, 0x32D74B
    ]

    init(vm: EditorViewModel, isEmbedded: Bool = false) {
        self.vm = vm
        self.isEmbedded = isEmbedded
        let settings = vm.canvasSettings
        _draft = State(initialValue: settings)
        _customColor = State(initialValue: Color(rgb: settings.backgroundColorRGB))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Color.white.opacity(0.1))

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    modePicker
                    activeControls

                    Label("Background applies to the entire project", systemImage: "square.3.layers.3d")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .padding(20)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
        }
        .background(Color.appColors.backgroundColor)
        .task(id: selectedPhoto) {
            guard let data = try? await selectedPhoto?.loadTransferable(type: Data.self) else { return }
            let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("MixtapeCanvas", isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("\(UUID().uuidString).jpg")
            guard (try? data.write(to: url, options: .atomic)) != nil else { return }
            draft.backgroundImagePath = url.path
            draft.backgroundKind = .image
            applyDraft()
            // Image import is a durability boundary. Persist immediately instead
            // of relying only on the debounced autosave, which can be cancelled
            // when Xcode terminates the app to install a new build.
            vm.saveNow()
        }
    }

    private var header: some View {
        ZStack {
            Text("Background")
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(.white)
            HStack {
                Button("Reset", action: resetBackground)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isDefaultBackground ? Color.white.opacity(0.3) : Color.white.opacity(0.82))
                    .disabled(isDefaultBackground)
                    .accessibilityHint("Removes the current background and restores black")

                Spacer()
                Button {
                    vm.selectedTool = nil
                } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Color.appColors.primaryColor)
                        .frame(width: 38, height: 38)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Done")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: isEmbedded ? 48 : 52)
    }

    private var modePicker: some View {
        HStack(spacing: 8) {
            backgroundModeButton(.color, icon: "paintpalette")
            backgroundModeButton(.image, icon: "photo")
            backgroundModeButton(.blur, icon: "drop.halffull")
        }
    }

    @ViewBuilder
    private var activeControls: some View {
        switch draft.backgroundKind {
        case .color:
            colorControls
        case .image:
            imageControls
        case .blur:
            blurControls
        }
    }

    private var colorControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("COLOR").font(.caption.bold()).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ColorPicker("Custom background color", selection: $customColor, supportsOpacity: false)
                        .labelsHidden()
                        .frame(width: 40, height: 40)
                        .onChange(of: customColor) { _, color in
                            setCustomColor(color)
                        }

                    ForEach(colors, id: \.self) { rgb in
                        Button {
                            customColor = Color(rgb: rgb)
                            draft.backgroundColorRGB = rgb
                            applyDraft()
                        } label: {
                            Circle()
                                .fill(Color(rgb: rgb))
                                .frame(width: 40, height: 40)
                                .overlay(
                                    Circle().stroke(
                                        draft.backgroundColorRGB == rgb ? Color.appColors.primaryColor : .white.opacity(0.16),
                                        lineWidth: draft.backgroundColorRGB == rgb ? 3 : 1
                                    )
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(String(format: "Color %06X", rgb))
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var imageControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("IMAGE").font(.caption.bold()).foregroundStyle(.secondary)
            HStack(spacing: 14) {
                if let path = draft.backgroundImagePath,
                   let image = UIImage(contentsOfFile: path) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 82, height: 82)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.appColors.primaryColor, lineWidth: 2))
                }

                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    VStack(spacing: 8) {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 24, weight: .medium))
                        Text(draft.backgroundImagePath == nil ? "Choose image" : "Replace image")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 82)
                    .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
                }
            }

            Text("The image fills the canvas behind fitted video and photos.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if draft.backgroundImagePath != nil {
                Button(action: resetBackground) {
                    Label("Remove background image", systemImage: "trash")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 11))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var blurControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("BLUR").font(.caption.bold()).foregroundStyle(.secondary)
                Spacer()
                Text("\(Int((draft.backgroundBlurIntensity * 100).rounded()))")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(Color.appColors.primaryColor)
            }

            HStack(spacing: 12) {
                Image(systemName: "circle.dotted")
                    .foregroundStyle(.secondary)
                Slider(
                    value: Binding(
                        get: { draft.backgroundBlurIntensity },
                        set: {
                            draft.backgroundBlurIntensity = $0
                            applyDraft()
                        }
                    ),
                    in: 0...1
                )
                .tint(Color.appColors.primaryColor)
                Image(systemName: "circle.hexagongrid.fill")
                    .foregroundStyle(.secondary)
            }

            Text("Uses a softened, edge-to-edge copy of the current clip.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func backgroundModeButton(_ kind: EditorCanvasBackgroundKind, icon: String) -> some View {
        Button {
            draft.backgroundKind = kind
            applyDraft()
        } label: {
            VStack(spacing: 7) {
                Image(systemName: icon).font(.system(size: 19, weight: .semibold))
                Text(kind.title).font(.caption.weight(.semibold))
            }
            .foregroundStyle(draft.backgroundKind == kind ? Color.black : Color.white)
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(draft.backgroundKind == kind ? Color.appColors.primaryColor : Color.white.opacity(0.07))
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(draft.backgroundKind == kind ? .isSelected : [])
    }

    private func setCustomColor(_ color: Color) {
        let uiColor = UIColor(color)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return }
        draft.backgroundColorRGB = UInt32((red * 255).rounded()) << 16
            | UInt32((green * 255).rounded()) << 8
            | UInt32((blue * 255).rounded())
        applyDraft()
    }

    private func applyDraft() {
        vm.updateCanvasSettings(draft)
    }

    private var isDefaultBackground: Bool {
        draft.backgroundKind == .color
            && draft.backgroundColorRGB == 0x000000
            && draft.backgroundImagePath == nil
            && draft.backgroundBlurIntensity == 0.55
    }

    private func resetBackground() {
        draft.backgroundKind = .color
        draft.backgroundColorRGB = 0x000000
        draft.backgroundImagePath = nil
        draft.backgroundBlurIntensity = 0.55
        customColor = .black
        selectedPhoto = nil
        applyDraft()
    }
}

