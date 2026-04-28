//  VideoProjectLocalDataSource.swift
//  Mixtape  —  Data/DataSources

import Foundation
import Combine

final class VideoProjectLocalDataSource {
    private let fileManager = FileManager.default

    private var projectsURL: URL {
        fileManager
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("projects", isDirectory: true)
    }

    init() {
        try? fileManager.createDirectory(at: projectsURL, withIntermediateDirectories: true)
    }

    func fetchAll() -> AnyPublisher<[VideoProjectDTO], Error> {
        Future { promise in
            do {
                let files = try self.fileManager
                    .contentsOfDirectory(at: self.projectsURL, includingPropertiesForKeys: nil)
                    .filter { $0.pathExtension == "json" }
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let dtos = try files.map { try decoder.decode(VideoProjectDTO.self, from: Data(contentsOf: $0)) }
                promise(.success(dtos))
            } catch {
                promise(.failure(error))
            }
        }.eraseToAnyPublisher()
    }

    func save(_ dto: VideoProjectDTO) -> AnyPublisher<Void, Error> {
        Future { promise in
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = .prettyPrinted
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(dto)
                let url = self.projectsURL.appendingPathComponent("\(dto.id).json")
                try data.write(to: url)
                promise(.success(()))
            } catch {
                promise(.failure(error))
            }
        }.eraseToAnyPublisher()
    }

    func delete(id: UUID) -> AnyPublisher<Void, Error> {
        Future { promise in
            let url = self.projectsURL.appendingPathComponent("\(id.uuidString).json")
            do {
                try self.fileManager.removeItem(at: url)
                promise(.success(()))
            } catch {
                promise(.failure(error))
            }
        }.eraseToAnyPublisher()
    }
}