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
                SizedBox(height: 20)

                Text("Studio WorkSpace").font(.custom("", size: 18))
                SizedBox(height: 12)
                Text("Manage and curate your visual narratives")
                    .font(.custom("", size: 15))
                    .foregroundStyle(Color.appColors.darkPrimary)

                SizedBox(height: 12)

                NavigationLink(value: ProjectListRoute.createProject) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.black)

                        Text("New Project")
                            .font(.title2)
                            .kerning(2)
                            .fontWeight(.regular)
                            .foregroundColor(.black)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.appColors.primaryColor.opacity(0.8))
                    .cornerRadius(8)
                }
                SizedBox(height: 20)

                if let error = listVM.loadError {
                    Text(error)
                        .font(.footnote)
                        .foregroundColor(.red.opacity(0.8))
                        .padding(.bottom, 8)
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if listVM.projects.isEmpty {
                            Text("No saved projects yet. Tap New Project to start editing.")
                                .font(.subheadline)
                                .foregroundColor(Color.white.opacity(0.55))
                                .padding(.top, 24)
                        } else {
                            ForEach(listVM.projects) { project in
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
                    }
                }
                .scrollIndicators(.hidden)
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
            .padding(.horizontal)
            .onAppear { listVM.reload() }
            .onChange(of: path) { _, newPath in
                if newPath.isEmpty { listVM.reload() }
            }
        }
    }
}

#Preview {
    NavigationStack {
        ProjectListScreen()
    }
}
