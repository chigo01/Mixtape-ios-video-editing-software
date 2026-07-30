//
//  ProjectListViewModel.swift
//  Mixtape
//

import SwiftUI

@MainActor
@Observable
final class ProjectListViewModel {
    private(set) var projects: [EditorProject] = []
    private(set) var loadError: String?

    func reload() {
        do {
            projects = try ProjectStore.shared.loadAll()
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    func deleteProject(_ project: EditorProject) {
        try? ProjectStore.shared.delete(id: project.id)
        reload()
    }

    func renameProject(_ project: EditorProject, to proposedTitle: String) {
        let trimmed = proposedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var renamed = project
        renamed.title = trimmed
        do {
            try ProjectStore.shared.save(renamed)
            reload()
        } catch {
            loadError = error.localizedDescription
        }
    }
}
