//
//  ProjectListScreen.swift
//  Mixtape
//
//  Created by Favour Baruch on 07/05/2026.
//

import SwiftUI

/// Routes pushed from the home screen. Owning the path here lets the create
/// flow replace itself with the editor, so back from the editor lands on home.
enum ProjectListRoute: Hashable {
    case createProject
    case editor(EditorProject)
}

struct ProjectListScreen: View {
    @State private var listVM = ProjectListViewModel()
    @State private var projectToDelete: EditorProject?
    @State private var projectToRename: EditorProject?
    @State private var renameText = ""
    @State private var path: [ProjectListRoute] = []

    var body: some View {
        AppGlobalBackgroundScaffold {
            NavigationStack(path: $path) {
                GeometryReader { geometry in
                    projectListContent(availableWidth: geometry.size.width)
                        .frame(maxWidth: 1180)
                        .frame(maxWidth: .infinity)
                }
                .navigationDestination(for: ProjectListRoute.self) { route in
                    switch route {
                    case .createProject:
                        CreateProjectScreen { project in
                            // Swap the create screen for the editor so back pops to home.
                            path = [.editor(project)]
                        }
                    case .editor(let project):
                        EditorScreen(project: project)
                            .id(project.id)
                    }
                }
                .confirmationDialog(
                    "Delete this project?",
                    isPresented: Binding(
                        get: { projectToDelete != nil },
                        set: { if !$0 { projectToDelete = nil } }
                    ),
                    titleVisibility: .visible,
                    presenting: projectToDelete
                ) { project in
                    Button("Delete", role: .destructive) {
                        listVM.deleteProject(project)
                    }
                    Button("Cancel", role: .cancel) {}
                } message: { project in
                    Text("“\(project.title)” will be removed. This can’t be undone.")
                }
                .alert(
                    "Rename Project",
                    isPresented: Binding(
                        get: { projectToRename != nil },
                        set: { if !$0 { projectToRename = nil } }
                    ),
                    presenting: projectToRename
                ) { project in
                    TextField("Project name", text: $renameText)
                    Button("Save") {
                        listVM.renameProject(project, to: renameText)
                        projectToRename = nil
                    }
                    .disabled(renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Cancel", role: .cancel) {
                        projectToRename = nil
                    }
                } message: { project in
                    Text("Choose a new name for “\(project.title)”.")
                }
            }
            .background(Color.appColors.backgroundColor)
            .toolbarBackground(Color.appColors.backgroundColor, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .onAppear { listVM.reload() }
            .onChange(of: path) { _, newPath in
                if newPath.isEmpty { listVM.reload() }
            }
        }
    }

    private func projectListContent(availableWidth: CGFloat) -> some View {
        let usesGrid = availableWidth >= 700
        let columnCount = availableWidth >= 1080 ? 3 : 2

        return VStack(spacing: 0) {
            SizedBox(height: usesGrid ? 32 : 20)

            Text("Studio WorkSpace")
                .font(.system(size: usesGrid ? 24 : 18, weight: .semibold))
            SizedBox(height: 8)
            Text("Manage and curate your visual narratives")
                .font(.system(size: usesGrid ? 16 : 15))
                .foregroundStyle(Color.appColors.darkPrimary)

            SizedBox(height: usesGrid ? 20 : 12)

            NavigationLink(value: ProjectListRoute.createProject) {
                Label("New Project", systemImage: "plus.circle.fill")
                    .font(.system(size: usesGrid ? 19 : 18, weight: .medium))
                    .kerning(usesGrid ? 1 : 2)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, usesGrid ? 18 : 16)
                    .background(Color.appColors.primaryColor.opacity(0.8))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            SizedBox(height: 20)

            if let error = listVM.loadError {
                Text(error)
                    .font(.footnote)
                    .foregroundColor(.red.opacity(0.8))
                    .padding(.bottom, 8)
            }

            ScrollView {
                if listVM.projects.isEmpty {
                    Text("No saved projects yet. Tap New Project to start editing.")
                        .font(.subheadline)
                        .foregroundColor(Color.white.opacity(0.55))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 24)
                } else if usesGrid {
                    LazyVGrid(
                        columns: Array(
                            repeating: GridItem(.flexible(), spacing: 16),
                            count: columnCount
                        ),
                        spacing: 16
                    ) {
                        ForEach(listVM.projects) { project in
                            projectLink(project)
                        }
                    }
                } else {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(listVM.projects) { project in
                            projectLink(project)
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal, usesGrid ? 28 : 16)
    }

    private func projectLink(_ project: EditorProject) -> some View {
        NavigationLink(value: ProjectListRoute.editor(project)) {
            ProjectCardView(project: project)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                renameText = project.title
                projectToRename = project
            } label: {
                Label("Rename Project", systemImage: "pencil")
            }

            Button(role: .destructive) {
                projectToDelete = project
            } label: {
                Label("Delete Project", systemImage: "trash")
            }
        }
    }
}

#Preview {
    NavigationStack {
        ProjectListScreen()
    }
}
