//
//  CanvasToolPanel.swift
//  Mixtape
//

import SwiftUI
import PhotosUI

struct CanvasToolPanel: View {
    let vm: EditorViewModel
    let isEmbedded: Bool
    @State private var draft: EditorCanvasSettings

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

                    Text("Use the Background tool for color, image, and blur fills.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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

/// Project-wide canvas fill, modeled after the quick background workflow in
/// mobile editors. Changes are applied immediately so the player and exported
/// composition always show the same result.
