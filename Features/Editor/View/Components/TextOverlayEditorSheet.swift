//
//  TextOverlayEditorSheet.swift
//  Mixtape
//
//  Bottom sheet for adding and editing text overlays with style controls.
//

import SwiftUI

struct TextOverlayEditorSheet: View {
    let vm: EditorViewModel
    let isEmbedded: Bool

    @State private var overlay: EditorTextOverlay
    @State private var selectedTab = "Styles"
    @FocusState private var isTextFieldFocused: Bool

    init(vm: EditorViewModel, overlay: EditorTextOverlay, isEmbedded: Bool = false) {
        self.vm = vm
        self.isEmbedded = isEmbedded
        _overlay = State(initialValue: overlay)
    }

    var body: some View {
        Group {
            if isEmbedded {
                VStack(spacing: 0) {
                    embeddedHeader
                    Divider().overlay(Color.white.opacity(0.1))
                    editorContent
                }
            } else {
                NavigationStack {
                    editorContent
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar { nativeToolbar }
                        .toolbarBackground(Color(white: 0.11), for: .navigationBar)
                        .toolbarBackground(.visible, for: .navigationBar)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color(white: 0.11))
        .onChange(of: overlay) { _, newValue in
            vm.updateTextOverlay(newValue)
        }
        .onAppear {
            vm.beginTextOverlayEdit()
            isTextFieldFocused = true
        }
        .interactiveDismissDisabled(false)
        .onDisappear {
            vm.dismissTextEditor()
        }
    }

    private var editorContent: some View {
        ZStack {
                Color(white: 0.11).ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        isTextFieldFocused = false
                    }

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        tabRow
                        textInputSection

                        if selectedTab == "Styles" {
                            fontStyleSection
                            colorSection
                            sizeSection
                            opacitySection
                            alignmentSection
                            positionSection
                        } else if selectedTab == "Fonts" {
                            fontFamilySection
                        }

                        deleteButton
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
        }
    }

    @ToolbarContentBuilder
    private var nativeToolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Text("Text")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Done", action: commitAndDismiss)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Color.appColors.primaryColor)
        }
    }

    private var embeddedHeader: some View {
        ZStack {
            Text("Text")
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(.white)
            HStack {
                Spacer()
                Button("Done", action: commitAndDismiss)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color.appColors.primaryColor)
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 48)
    }

    // MARK: - Tab row (Styles active; rest are future placeholders)

    private var tabRow: some View {
        HStack(spacing: 0) {
            ForEach(["Styles", "Fonts", "Effects"], id: \.self) { tab in
                let isActive = tab == selectedTab
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = tab
                    }
                } label: {
                    Text(tab)
                        .font(.system(size: 13, weight: isActive ? .bold : .medium))
                        .foregroundColor(isActive ? .white : Color.white.opacity(0.35))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .overlay(alignment: .bottom) {
                            if isActive {
                                Rectangle()
                                    .fill(Color.appColors.primaryColor)
                                    .frame(height: 2)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    // MARK: - Text input

    private var textInputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Enter text…", text: $overlay.text, axis: .vertical)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(1...4)
                .focused($isTextFieldFocused)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        }
    }

    // MARK: - Font Family Grid

    private var fontFamilySection: some View {
        let columns = [
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10)
        ]

        return LazyVGrid(columns: columns, spacing: 10) {
            ForEach(TextOverlayFontFamily.allCases) { family in
                fontFamilyCell(family)
            }
        }
    }

    private func fontFamilyCell(_ family: TextOverlayFontFamily) -> some View {
        let isSelected = overlay.fontFamily == family
        return Button {
            overlay.fontFamily = family
        } label: {
            Text(family.displayName)
                .font(family == .system ? .system(size: 14, weight: .semibold) : .custom(family.rawValue, size: 14))
                .foregroundColor(isSelected ? Color.appColors.primaryColor : .white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(
                            isSelected ? Color.appColors.primaryColor : Color.white.opacity(0.12),
                            lineWidth: isSelected ? 1.5 : 1
                        )
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Font style presets ("Aa" chips)

    private var fontStyleSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(TextOverlayFontStyle.allCases) { style in
                    fontStyleChip(style)
                }
            }
        }
    }

    private func fontStyleChip(_ style: TextOverlayFontStyle) -> some View {
        let isSelected = overlay.fontStyle == style
        return Button {
            overlay.fontStyle = style
        } label: {
            Text(style.label)
                .font(style.font)
                .foregroundColor(chipForeground(for: style))
                .frame(width: 52, height: 52)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(chipBackground(for: style))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(
                            isSelected ? Color.appColors.primaryColor : Color.white.opacity(0.1),
                            lineWidth: isSelected ? 2 : 1
                        )
                )
        }
        .buttonStyle(.plain)
    }

    private func chipBackground(for style: TextOverlayFontStyle) -> Color {
        switch style {
        case .background: return Color.black
        case .outlined:   return Color.white.opacity(0.04)
        case .shadow:     return Color.white.opacity(0.04)
        default:          return Color.white.opacity(0.06)
        }
    }

    private func chipForeground(for style: TextOverlayFontStyle) -> Color {
        switch style {
        case .background: return .white
        case .outlined:   return .white
        default:          return .white
        }
    }

    // MARK: - Color picker row

    private var colorSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                // Color wheel icon (decorative)
                Image(systemName: "paintpalette.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(
                        .linearGradient(
                            colors: [.red, .orange, .yellow, .green, .blue, .purple, .red],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 36, height: 36)

                ForEach(TextOverlayColor.allCases) { presetColor in
                    colorCircle(presetColor)
                }
            }
        }
    }

    private func colorCircle(_ presetColor: TextOverlayColor) -> some View {
        let isSelected = overlay.textColor == presetColor
        return Button {
            overlay.textColor = presetColor
        } label: {
            Circle()
                .fill(presetColor.color)
                .frame(width: 32, height: 32)
                .overlay(
                    Circle()
                        .stroke(
                            isSelected ? Color.appColors.primaryColor : Color.white.opacity(0.15),
                            lineWidth: isSelected ? 2.5 : 1
                        )
                        .padding(isSelected ? -3 : 0)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Size slider

    private var sizeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Size")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                Spacer()
                Text(String(format: "%.0f", overlay.fontSize))
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundColor(Color.appColors.primaryColor)
            }
            Slider(value: $overlay.fontSize, in: 12...120, step: 1)
                .tint(Color.appColors.primaryColor)
        }
    }

    // MARK: - Opacity slider

    private var opacitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Opacity")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                Spacer()
                Text(String(format: "%.0f%%", overlay.opacity * 100))
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundColor(Color.appColors.primaryColor)
            }
            Slider(value: $overlay.opacity, in: 0...1, step: 0.01)
                .tint(Color.appColors.primaryColor)
        }
    }

    // MARK: - Alignment buttons

    private var alignmentSection: some View {
        HStack(spacing: 12) {
            // Horizontal alignment
            HStack(spacing: 4) {
                ForEach(TextOverlayHAlignment.allCases) { align in
                    alignmentButton(
                        systemImage: align.systemImage,
                        isSelected: overlay.horizontalAlignment == align
                    ) {
                        overlay.horizontalAlignment = align
                    }
                }
            }
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )

            Spacer()

            // Vertical alignment
            HStack(spacing: 4) {
                ForEach(TextOverlayVAlignment.allCases) { align in
                    alignmentButton(
                        systemImage: align.systemImage,
                        isSelected: overlay.verticalAlignment == align
                    ) {
                        overlay.verticalAlignment = align
                    }
                }
            }
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
        }
    }

    private func alignmentButton(
        systemImage: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(isSelected ? Color.appColors.primaryColor : Color.white.opacity(0.55))
                .frame(width: 38, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isSelected ? Color.appColors.primaryColor.opacity(0.15) : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Position sliders

    private var positionSection: some View {
        VStack(spacing: 16) {
            // X Offset
            VStack(spacing: 8) {
                HStack {
                    Text("X Position")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                    Spacer()
                    Text(String(format: "%.0f", overlay.xOffset))
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                        .foregroundColor(Color.appColors.primaryColor)
                }
                Slider(value: $overlay.xOffset, in: -300...300, step: 1)
                    .tint(Color.appColors.primaryColor)
            }

            // Y Offset
            VStack(spacing: 8) {
                HStack {
                    Text("Y Position")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                    Spacer()
                    Text(String(format: "%.0f", overlay.yOffset))
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                        .foregroundColor(Color.appColors.primaryColor)
                }
                Slider(value: $overlay.yOffset, in: -400...400, step: 1)
                    .tint(Color.appColors.primaryColor)
            }
        }
    }

    // MARK: - Delete

    private var deleteButton: some View {
        Button(role: .destructive) {
            vm.deleteTextOverlay(id: overlay.id)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .semibold))
                Text("Delete Text")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundColor(.red)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.red.opacity(0.1))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func commitAndDismiss() {
        vm.updateTextOverlay(overlay)
        vm.dismissTextEditor()
    }
}
