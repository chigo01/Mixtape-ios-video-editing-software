//
//  CreateProjectScreen.swift
//  Mixtape
//
//  Created by Favour Baruch on 08/05/2026.
//

import SwiftUI

struct CreateProjectScreen: View {
    @State private var pickedMedia: [MediaItem] = []
    @State private var goToEditor = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        MediaLibraryPickerScreen(
            title: "New Project",
            confirmButtonTitle: "Next",
            onCancel: { dismiss() },
            onConfirm: { items in
                pickedMedia = items
                goToEditor = true
            }
        )
        .navigationDestination(isPresented: $goToEditor) {
            EditorScreen(media: pickedMedia)
        }
    }
}

#Preview {
    NavigationStack {
        CreateProjectScreen()
    }
}
