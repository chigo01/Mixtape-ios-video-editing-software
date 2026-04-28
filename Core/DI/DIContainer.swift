//  DIContainer.swift
//  Mixtape  —  Core/DI

import Foundation

final class DIContainer {
    static let shared = DIContainer()
    private init() {}

    // Data Sources
    lazy var videoProjectLocalDataSource = VideoProjectLocalDataSource()

    // Repositories
    lazy var videoProjectRepository: VideoProjectRepositoryProtocol =
        VideoProjectRepository(localDataSource: videoProjectLocalDataSource)

    // Use Cases
    lazy var fetchProjectsUseCase: FetchProjectsUseCaseProtocol =
        FetchProjectsUseCase(repository: videoProjectRepository)

    lazy var saveProjectUseCase: SaveProjectUseCaseProtocol =
        SaveProjectUseCase(repository: videoProjectRepository)

    lazy var deleteProjectUseCase: DeleteProjectUseCaseProtocol =
        DeleteProjectUseCase(repository: videoProjectRepository)

    lazy var exportProjectUseCase: ExportProjectUseCaseProtocol =
        ExportProjectUseCase()
}