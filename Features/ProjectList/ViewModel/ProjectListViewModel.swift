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
}
