//
//  EditorExportService.swift
//  Mixtape
//

import AVFoundation
import Photos

enum EditorExportError: LocalizedError {
    case compositionFailed
    case exportSessionFailed
    case exportFailed(String)
    case exportCancelled
    case photoLibraryDenied

    var errorDescription: String? {
        switch self {
        case .compositionFailed: return "Could not build the export timeline."
        case .exportSessionFailed: return "Could not start the export session."
        case .exportFailed(let detail): return "Export failed: \(detail)"
        case .exportCancelled: return "Export cancelled."
        case .photoLibraryDenied: return "Photo library access is required to save your video."
        }
    }
}

enum EditorExportService {

    private static var activeSession: AVAssetExportSession?

    static func cancelCurrentExport() {
        activeSession?.cancelExport()
        activeSession = nil
    }

    /// Renders the current timeline to a temporary file using the chosen export settings.
    static func export(
        clips: [EditorClip],
        settings: EditorExportSettings,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        guard let built = await EditorCompositionBuilder.build(
            from: clips,
            frameRate: Int32(settings.frameRate.rawValue)
        ) else {
            throw EditorExportError.compositionFailed
        }

        guard let session = AVAssetExportSession(
            asset: built.composition,
            presetName: settings.resolution.avPreset
        ) else {
            throw EditorExportError.exportSessionFailed
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mixtape-export-\(UUID().uuidString).\(settings.format.fileExtension)")

        session.outputURL = outputURL
        session.outputFileType = settings.format.fileType
        session.videoComposition = built.videoComposition
        session.audioTimePitchAlgorithm = .spectral
        session.shouldOptimizeForNetworkUse = true
        activeSession = session

        let progressTask = Task {
            while !Task.isCancelled {
                progress(Double(session.progress))
                if session.progress >= 1 { break }
                try? await Task.sleep(for: .milliseconds(120))
            }
        }

        defer {
            progressTask.cancel()
            activeSession = nil
        }

        do {
            try await session.export(to: outputURL, as: settings.format.fileType)
            progress(1)
            return outputURL
        } catch {
            if session.status == .cancelled {
                throw EditorExportError.exportCancelled
            }
            throw EditorExportError.exportFailed(error.localizedDescription)
        }
    }

    static func saveVideoToPhotoLibrary(url: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw EditorExportError.photoLibraryDenied
        }

        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        }
    }
}
