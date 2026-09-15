//
//  EditorViewModel+Export.swift
//  Mixtape
//

import SwiftUI
import UIKit
import AVFoundation
import Photos

extension EditorViewModel {
    // MARK: Export

    func formatDuration(_ duration: TimeInterval) -> String {
        let total = Int(duration.rounded())
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    func startExport(settings: EditorExportSettings) {
        guard !clips.isEmpty, !isExporting else { return }
        commitProjectTitle()
        exportTask?.cancel()
        exportedFileURL = nil
        exportMessage = nil

        exportTask = Task {
            isExporting = true
            exportProgress = 0
            exportMessage = "Rendering clips…"

            do {
                let clipsSnapshot = clips
                let textOverlaysSnapshot = textOverlays
                let graphicOverlaysSnapshot = graphicOverlays
                let audioClipsSnapshot = audioClips
                let overlayClipsSnapshot = overlayClips
                let adjustmentLayersSnapshot = adjustmentLayers
                let openingKindSnapshot = openingTransitionKind
                let openingDurationSnapshot = openingTransitionDuration
                let closingKindSnapshot = closingTransitionKind
                let closingDurationSnapshot = closingTransitionDuration
                let projectTitleSnapshot = projectTitle
                let canvasSnapshot = canvasSettings
                let exportRangeSnapshot = exportRange
                let audioTrackSettingsSnapshot = audioTrackSettings
                let masterVolumeSnapshot = masterVolume
                let url = try await EditorExportService.export(
                    clips: clipsSnapshot,
                    textOverlays: textOverlaysSnapshot,
                    graphicOverlays: graphicOverlaysSnapshot,
                    audioClips: audioClipsSnapshot,
                    overlayClips: overlayClipsSnapshot,
                    adjustmentLayers: adjustmentLayersSnapshot,
                    openingTransitionKind: openingKindSnapshot,
                    openingTransitionDuration: openingDurationSnapshot,
                    closingTransitionKind: closingKindSnapshot,
                    closingTransitionDuration: closingDurationSnapshot,
                    canvasSettings: canvasSnapshot,
                    timeRange: exportRangeSnapshot,
                    settings: settings,
                    projectTitle: projectTitleSnapshot,
                    audioTrackSettings: audioTrackSettingsSnapshot,
                    masterVolume: masterVolumeSnapshot
                ) { progress in
                    Task { @MainActor in
                        self.exportProgress = progress
                    }
                }

                guard !Task.isCancelled else { return }

                exportMessage = "Saving to Photos…"
                try await EditorExportService.saveVideoToPhotoLibrary(url: url)
                exportedFileURL = url
                exportMessage = "Saved to Photos"
                exportProgress = 1
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch is CancellationError {
                exportMessage = nil
            } catch EditorExportError.exportCancelled {
                exportMessage = nil
            } catch {
                exportMessage = error.localizedDescription
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }

            isExporting = false
        }
    }

    func cancelExport() {
        exportTask?.cancel()
        EditorExportService.cancelCurrentExport()
        isExporting = false
        exportProgress = 0
        exportMessage = nil
    }

    func clearExportState() {
        if let url = exportedFileURL {
            try? FileManager.default.removeItem(at: url)
        }
        exportedFileURL = nil
        exportMessage = nil
        exportProgress = 0
    }
}
