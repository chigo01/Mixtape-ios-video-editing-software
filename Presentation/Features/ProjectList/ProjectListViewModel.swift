//  ProjectListViewModel.swift
//  Mixtape  —  Presentation/Features/ProjectList

import Foundation
import Combine

@MainActor
final class ProjectListViewModel: ObservableObject {
    @Published var projects: [VideoProject] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil

    private let fetchProjectsUseCase: FetchProjectsUseCaseProtocol
    private let deleteProjectUseCase: DeleteProjectUseCaseProtocol
    private var cancellables = Set<AnyCancellable>()

    init(
        fetchProjectsUseCase: FetchProjectsUseCaseProtocol = DIContainer.shared.fetchProjectsUseCase,
        deleteProjectUseCase: DeleteProjectUseCaseProtocol = DIContainer.shared.deleteProjectUseCase
    ) {
        self.fetchProjectsUseCase = fetchProjectsUseCase
        self.deleteProjectUseCase = deleteProjectUseCase
    }

    func loadProjects() {
        isLoading = true
        fetchProjectsUseCase.execute(input: ())
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    if case .failure(let error) = completion {
                        self?.errorMessage = error.localizedDescription
                    }
                },
                receiveValue: { [weak self] in self?.projects = $0 }
            )
            .store(in: &cancellables)
    }

    func deleteProject(id: UUID) {
        deleteProjectUseCase.execute(input: id)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case .failure(let error) = completion {
                        self?.errorMessage = error.localizedDescription
                    }
                },
                receiveValue: { [weak self] _ in
                    self?.projects.removeAll { $0.id == id }
                }
            )
            .store(in: &cancellables)
    }
}