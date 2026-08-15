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
        HStack(spacing: 0) {
            ForEach(EditorTool.mainTools) { tool in
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
                .frame(maxWidth: .infinity)
            }
        }
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
    @State private var draft: EditorCanvasSettings
    @State private var selectedPhoto: PhotosPickerItem?

    private let colors: [UInt32] = [0x000000, 0xFFFFFF, 0x1D1D1F, 0x273043, 0x6C4AB6, 0xD95D39, 0xE3B505, 0x2A9D8F]

    init(vm: EditorViewModel) {
        self.vm = vm
        _draft = State(initialValue: vm.canvasSettings)
    }

    var body: some View {
        NavigationStack {
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
            .navigationTitle("Canvas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { vm.updateCanvasSettings(draft); vm.selectedTool = nil }
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
                    .foregroundColor(isSelected ? Color.appColors.primaryColor : Color.white.opacity(0.75))
            }
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tool.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
