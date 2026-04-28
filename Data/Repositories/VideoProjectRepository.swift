//  VideoProjectRepository.swift
//  Mixtape  —  Data/Repositories

import Foundation
import Combine

final class VideoProjectRepository: VideoProjectRepositoryProtocol {
    private let localDataSource: VideoProjectLocalDataSource

    init(localDataSource: VideoProjectLocalDataSource = VideoProjectLocalDataSource()) {
        self.localDataSource = localDataSource
    }

    func fetchAll() -> AnyPublisher<[VideoProject], Error> {
        localDataSource.fetchAll()
            .map { $0.map { $0.toDomain() } }
            .eraseToAnyPublisher()
    }

    func fetch(id: UUID) -> AnyPublisher<VideoProject, Error> {
        localDataSource.fetchAll()
            .tryMap {
                guard let dto = $0.first(where: { $0.id == id.uuidString }) else {
                    throw RepositoryError.notFound
                }
                return dto.toDomain()
            }
            .eraseToAnyPublisher()
    }

    func save(_ project: VideoProject) -> AnyPublisher<Void, Error> {
        localDataSource.save(VideoProjectDTO.fromDomain(project))
    }

    func delete(id: UUID) -> AnyPublisher<Void, Error> {
        localDataSource.delete(id: id)
    }
}

enum RepositoryError: LocalizedError {
    case notFound
    case saveFailed(Error)

    var errorDescription: String? {
        switch self {
        case .notFound:          return "Record not found"
        case .saveFailed(let e): return "Save failed: \(e.localizedDescription)"
        }
    }
}