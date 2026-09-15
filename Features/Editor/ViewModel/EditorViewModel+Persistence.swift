//
//  EditorViewModel+Persistence.swift
//  Mixtape
//

import SwiftUI
import UIKit
import AVFoundation
import Photos

extension EditorViewModel {
    // MARK: Undo / Redo

    func undo() {
        guard let restored = undoManager.undo(replacing: currentSnapshot()) else { return }
        applySnapshot(restored)
        refreshUndoState()
        scheduleSave()
        Task { await alignPlaybackToTimeline() }
    }

    func redo() {
        guard let restored = undoManager.redo(replacing: currentSnapshot()) else { return }
        applySnapshot(restored)
        refreshUndoState()
        scheduleSave()
        Task { await alignPlaybackToTimeline() }
    }

    func commitProjectTitle() {
        let trimmed = projectTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            projectTitle = "Untitled Project"
        } else {
            projectTitle = trimmed
        }
        scheduleSave()
    }

    func saveNow() {
        guard !isCopilotPreview else { return }
        saveTask?.cancel()
        try? ProjectStore.shared.save(makeProject())
    }

    // MARK: - Private helpers

    func currentSnapshot() -> EditorTimelineSnapshot {
        EditorTimelineSnapshot(
            clips: clips,
            openingTransitionKind: openingTransitionKind,
            openingTransitionDuration: openingTransitionDuration,
            closingTransitionKind: closingTransitionKind,
            closingTransitionDuration: closingTransitionDuration,
            timelinePosition: timelinePosition,
            selectedClipID: selectedClipID,
            selectedTextOverlayID: selectedTextOverlayID,
            selectedGraphicOverlayID: selectedGraphicOverlayID,
            selectedAudioClipID: selectedAudioClipID,
            selectedOverlayClipID: selectedOverlayClipID,
            textOverlays: textOverlays,
            graphicOverlays: graphicOverlays,
            audioClips: audioClips,
            audioTrackSettings: audioTrackSettings,
            masterVolume: masterVolume,
            overlayClips: overlayClips,
            adjustmentLayers: adjustmentLayers,
            canvasSettings: canvasSettings,
            exportInPoint: exportInPoint,
            exportOutPoint: exportOutPoint,
            sequences: sequences,
            markers: markers,
            selectedTimelineItems: selectedTimelineItems,
            selectedSequenceID: selectedSequenceID,
            activeSequenceID: activeSequenceID
        )
    }

    func applySnapshot(_ snapshot: EditorTimelineSnapshot) {
        clips = snapshot.clips
        openingTransitionKind = snapshot.openingTransitionKind
        openingTransitionDuration = snapshot.openingTransitionDuration
        closingTransitionKind = snapshot.closingTransitionKind
        closingTransitionDuration = snapshot.closingTransitionDuration
        timelinePosition = min(snapshot.timelinePosition, totalDuration)
        selectedClipID = snapshot.selectedClipID
        selectedTextOverlayID = snapshot.selectedTextOverlayID
        selectedGraphicOverlayID = snapshot.selectedGraphicOverlayID
        selectedAudioClipID = snapshot.selectedAudioClipID
        selectedOverlayClipID = snapshot.selectedOverlayClipID
        textOverlays = snapshot.textOverlays
        graphicOverlays = snapshot.graphicOverlays
        audioClips = snapshot.audioClips
        audioTrackSettings = snapshot.audioTrackSettings
        masterVolume = snapshot.masterVolume
        overlayClips = snapshot.overlayClips
        adjustmentLayers = snapshot.adjustmentLayers
        canvasSettings = snapshot.canvasSettings
        exportInPoint = snapshot.exportInPoint
        exportOutPoint = snapshot.exportOutPoint
        sequences = snapshot.sequences
        markers = snapshot.markers
        selectedTimelineItems = snapshot.selectedTimelineItems
        selectedSequenceID = snapshot.selectedSequenceID
        activeSequenceID = snapshot.activeSequenceID
        isMultiSelectMode = !selectedTimelineItems.isEmpty
        if isMultiSelectMode {
            selectedTool = .sequence
            selectedClipID = nil
            selectedTextOverlayID = nil
            selectedGraphicOverlayID = nil
            selectedAudioClipID = nil
            selectedOverlayClipID = nil
        } else if selectedTool == .sequence {
            selectedTool = nil
        }
        invalidateComposition()
    }

    func registerUndoIfNeeded() {
        undoManager.pushUndoState(currentSnapshot())
        refreshUndoState()
    }

    func refreshUndoState() {
        canUndo = undoManager.canUndo
        canRedo = undoManager.canRedo
    }

    func makeProject() -> EditorProject {
        EditorProject(
            id: projectID,
            title: projectTitle,
            createdAt: projectCreatedAt,
            modifiedAt: Date(),
            clips: clips.map { SavedEditorClip(from: $0) },
            textOverlays: textOverlays.map { SavedTextOverlay(from: $0) },
            graphicOverlays: graphicOverlays,
            audioClips: audioClips.map { SavedAudioClip(from: $0) },
            overlayClips: overlayClips.map { SavedOverlayClip(from: $0) },
            adjustmentLayers: adjustmentLayers,
            openingTransitionKind: openingTransitionKind,
            openingTransitionDuration: openingTransitionDuration,
            closingTransitionKind: closingTransitionKind,
            closingTransitionDuration: closingTransitionDuration,
            timelinePosition: timelinePosition,
            selectedClipID: selectedClipID,
            selectedTextOverlayID: selectedTextOverlayID,
            selectedGraphicOverlayID: selectedGraphicOverlayID,
            selectedAudioClipID: selectedAudioClipID,
            selectedOverlayClipID: selectedOverlayClipID,
            sequences: sequences,
            markers: markers,
            selectedTimelineItems: Array(selectedTimelineItems).sorted { $0.id < $1.id },
            selectedSequenceID: selectedSequenceID,
            activeSequenceID: activeSequenceID,
            canvasSettings: canvasSettings,
            exportInPoint: exportInPoint,
            exportOutPoint: exportOutPoint,
            audioTrackSettings: audioTrackSettings,
            masterVolume: masterVolume,
            proxySettings: proxySettings
        )
    }

    func scheduleSave() {
        guard !isCopilotPreview else { return }
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            try? await ProjectStore.shared.saveInBackground(makeProject())
        }
    }

    /// Magnetic snapping shared by playhead and movable overlay lanes. The point threshold
    /// is converted to time so it naturally becomes more precise as the timeline zooms in.
}
