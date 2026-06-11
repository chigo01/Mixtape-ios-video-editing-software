//
//  CreateProjectScreen.swift
//  Mixtape
//
//  Created by Favour Baruch on 08/05/2026.
//

import SwiftUI

struct CreateProjectScreen: View {
    /// Called after the project is saved; the home screen replaces this
    /// screen with the editor so back navigation skips the media picker.
    let onProjectCreated: (EditorProject) -> Void

    @State private var isPreparingEditor = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        MediaLibraryPickerScreen(
            title: "New Project",
            confirmButtonTitle: "Next",
            isConfirmLoading: isPreparingEditor,
            onCancel: { dismiss() },
            onConfirm: { items in
                Task { @MainActor in
                    guard !isPreparingEditor else { return }
                    isPreparingEditor = true
                    await EditorCompositionBuilder.warmUp(from: items)
                    let project = EditorProject.new(from: items)
                    try? ProjectStore.shared.save(project)
                    isPreparingEditor = false
                    onProjectCreated(project)
                }
            }
        )
    }
}

#Preview {
    NavigationStack {
        CreateProjectScreen { _ in }
    }
}
