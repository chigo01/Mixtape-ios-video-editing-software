//  EditorViewModel.swift
//  Mixtape  —  Presentation/Features/Editor

import Foundation
import Combine
import AVFoundation

@MainActor
final class EditorViewModel: ObservableObject {
    @Published var project: VideoProject
    @Published var selectedClipId: UUID? = nil
    @Published var currentTime: TimeInterval = 0
    @Published var isPlaying: Bool = false
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil

    private let saveProjectUseCase: SaveProjectUseCaseProtocol
    private let exportProjectUseCase: ExportProjectUseCaseProtocol
    private var cancellables = Set<AnyCancellable>()

    var selectedClip: VideoClip? {
        guard let id = selectedClipId else { return nil }
        return project.timeline.videoTracks.flatMap(\.clips).first { $0.id == id }
    }

    init(
        project: VideoProject,
        saveProjectUseCase: SaveProjectUseCaseProtocol = DIContainer.shared.saveProjectUseCase,
        exportProjectUseCase: ExportProjectUseCaseProtocol = DIContainer.shared.exportProjectUseCase
    ) {
        self.project = project
        self.saveProjectUseCase = saveProjectUseCase
        self.exportProjectUseCase = exportProjectUseCase
    }

    func addClip(url: URL) {
        Task {
            let asset = AVURLAsset(url: url)
            let duration = try? await asset.load(.duration)
            let clip = VideoClip(assetURL: url, duration: duration?.seconds ?? 0)
            project.timeline.addClip(clip)
            saveProject()
        }
    }

    func removeClip(id: UUID) {
        project.timeline.removeClip(id: id)
        if selectedClipId == id { selectedClipId = nil }
        saveProject()
    }

    func selectClip(id: UUID) {
        selectedClipId = (selectedClipId == id) ? nil : id
    }

    func exportProject() {
        isLoading = true
        exportProjectUseCase.execute(input: project)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    if case .failure(let error) = completion {
                        self?.errorMessage = error.localizedDescription
                    }
                },
                receiveValue: { _ in }
            )
            .store(in: &cancellables)
    }

    private func saveProject() {
        saveProjectUseCase.execute(input: project)
            .sink(receiveCompletion: { _ in }, receiveValue: { _ in })
            .store(in: &cancellables)
    }
}