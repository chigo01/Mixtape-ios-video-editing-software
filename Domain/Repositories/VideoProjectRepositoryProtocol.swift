//  VideoProjectRepositoryProtocol.swift
//  Mixtape  —  Domain/Repositories

import Foundation
import Combine

protocol VideoProjectRepositoryProtocol {
    func fetchAll() -> AnyPublisher<[VideoProject], Error>
    func fetch(id: UUID) -> AnyPublisher<VideoProject, Error>
    func save(_ project: VideoProject) -> AnyPublisher<Void, Error>
    func delete(id: UUID) -> AnyPublisher<Void, Error>
}