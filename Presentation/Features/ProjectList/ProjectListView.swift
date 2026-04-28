//  ProjectListView.swift
//  Mixtape  —  Presentation/Features/ProjectList

import SwiftUI

struct ProjectListView: View {
    @StateObject private var viewModel = ProjectListViewModel()
    @State private var showingNewProject = false

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView()
                } else if viewModel.projects.isEmpty {
                    emptyState
                } else {
                    projectGrid
                }
            }
            .navigationTitle("Mixtape")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingNewProject = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingNewProject) {
                NewProjectView()
            }
            .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
        .onAppear { viewModel.loadProjects() }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "film.stack")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text("No Projects")
                .font(.title2.bold())
            Text("Tap + to create your first project")
                .foregroundStyle(.secondary)
            Button("New Project") { showingNewProject = true }
                .buttonStyle(.borderedProminent)
        }
    }

    private var projectGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160))], spacing: 16) {
                ForEach(viewModel.projects) { project in
                    NavigationLink(destination: EditorView(project: project)) {
                        ProjectThumbnailView(project: project)
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            viewModel.deleteProject(id: project.id)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .padding()
        }
    }
}

#Preview { ProjectListView() }