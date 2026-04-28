//  UseCaseProtocols.swift
//  Mixtape  —  Domain/UseCases

import Foundation
import Combine
import AVFoundation

// MARK: - Fetch

protocol FetchProjectsUseCaseProtocol {
    func execute(input: Void) -> AnyPublisher<[VideoProject], Error>
}

final class FetchProjectsUseCase: FetchProjectsUseCaseProtocol {
    private let repository: VideoProjectRepositoryProtocol
    init(repository: VideoProjectRepositoryProtocol = DIContainer.shared.videoProjectRepository) {
        self.repository = repository
    }
    func execute(input: Void) -> AnyPublisher<[VideoProject], Error> {
        repository.fetchAll()
    }
}

// MARK: - Save

protocol SaveProjectUseCaseProtocol {
    func execute(input: VideoProject) -> AnyPublisher<Void, Error>
}

final class SaveProjectUseCase: SaveProjectUseCaseProtocol {
    private let repository: VideoProjectRepositoryProtocol
    init(repository: VideoProjectRepositoryProtocol = DIContainer.shared.videoProjectRepository) {
        self.repository = repository
    }
    func execute(input: VideoProject) -> AnyPublisher<Void, Error> {
        repository.save(input)
    }
}

// MARK: - Delete

protocol DeleteProjectUseCaseProtocol {
    func execute(input: UUID) -> AnyPublisher<Void, Error>
}

final class DeleteProjectUseCase: DeleteProjectUseCaseProtocol {
    private let repository: VideoProjectRepositoryProtocol
    init(repository: VideoProjectRepositoryProtocol = DIContainer.shared.videoProjectRepository) {
        self.repository = repository
    }
    func execute(input: UUID) -> AnyPublisher<Void, Error> {
        repository.delete(id: input)
    }
}

// MARK: - Export

protocol ExportProjectUseCaseProtocol {
    func execute(input: VideoProject) -> AnyPublisher<URL, Error>
}

final class ExportProjectUseCase: ExportProjectUseCaseProtocol {
    func execute(input: VideoProject) -> AnyPublisher<URL, Error> {
        Future<URL, Error> { promise in
            Task {
                let composition = AVMutableComposition()
                guard let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
                      let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                    promise(.failure(NSError(domain: "ExportError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create tracks"])))
                    return
                }

                var currentTime = CMTime.zero
                
                for clip in input.timeline.videoTracks.flatMap({ $0.clips }) {
                    let asset = AVURLAsset(url: clip.assetURL)
                    let duration = CMTime(seconds: clip.duration, preferredTimescale: 600)
                    let timeRange = CMTimeRange(start: .zero, duration: duration)
                    
                    do {
                        if let assetVideoTrack = try await asset.loadTracks(withMediaType: .video).first {
                            try videoTrack.insertTimeRange(timeRange, of: assetVideoTrack, at: currentTime)
                        }
                        if let assetAudioTrack = try await asset.loadTracks(withMediaType: .audio).first {
                            try audioTrack.insertTimeRange(timeRange, of: assetAudioTrack, at: currentTime)
                        }
                        currentTime = CMTimeAdd(currentTime, duration)
                    } catch {
                        print("Failed to insert track: \(error)")
                    }
                }

                guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
                    promise(.failure(NSError(domain: "ExportError", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to create export session"])))
                    return
                }

                let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
                session.outputURL = outputURL
                session.outputFileType = .mp4

                await session.export()
                
                DispatchQueue.main.async {
                    switch session.status {
                    case .completed:
                        promise(.success(outputURL))
                    case .failed, .cancelled:
                        let err = session.error ?? NSError(domain: "ExportError", code: -3, userInfo: [NSLocalizedDescriptionKey: "Export failed"])
                        promise(.failure(err))
                    default:
                        promise(.failure(NSError(domain: "ExportError", code: -4, userInfo: [NSLocalizedDescriptionKey: "Unknown status"])))
                    }
                }
            }
        }.eraseToAnyPublisher()
    }
}