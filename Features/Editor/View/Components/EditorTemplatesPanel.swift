//
//  EditorTemplatesPanel.swift
//  Mixtape
//

import SwiftUI
import PhotosUI

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

