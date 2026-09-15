//
//  EditorViewModel+Effects.swift
//  Mixtape
//

import SwiftUI
import UIKit
import AVFoundation
import Photos

extension EditorViewModel {
    // MARK: Effects stack and adjustment layers

    var selectedEffectStack: [EditorVisualEffect] {
        if let id = selectedAdjustmentLayerID {
            return adjustmentLayers.first(where: { $0.id == id })?.effects ?? []
        }
        return selectedOverlayClip?.effects ?? selectedClip?.effects ?? []
    }

    var selectedVisualEffect: EditorVisualEffect? {
        guard let selectedVisualEffectID else { return nil }
        return selectedEffectStack.first { $0.id == selectedVisualEffectID }
    }

    var selectedEffectTargetStartTime: TimeInterval {
        if let id = selectedAdjustmentLayerID,
           let layer = adjustmentLayers.first(where: { $0.id == id }) {
            return layer.startTime
        }
        if let overlay = selectedOverlayClip { return overlay.timelineStart }
        if let id = selectedClipID,
           let index = clips.firstIndex(where: { $0.id == id }) {
            return timelineOffsetForClipIndex(index)
        }
        return 0
    }

    var selectedEffectTargetDuration: TimeInterval {
        if let id = selectedAdjustmentLayerID,
           let layer = adjustmentLayers.first(where: { $0.id == id }) {
            return layer.duration
        }
        return selectedOverlayClip?.duration ?? selectedClip?.duration ?? 0
    }

    var selectedEffectLocalTime: TimeInterval {
        min(
            max(0, timelinePosition - selectedEffectTargetStartTime),
            selectedEffectTargetDuration
        )
    }

    func selectAdjustmentLayer(_ id: UUID?) {
        selectedAdjustmentLayerID = id
        selectedVisualEffectID = selectedEffectStack.first?.id
        if let id, let layer = adjustmentLayers.first(where: { $0.id == id }) {
            timelinePosition = min(max(layer.startTime, 0), totalDuration)
            Task { await alignPlaybackToTimeline() }
        }
    }

    func addAdjustmentLayer() {
        registerUndoIfNeeded()
        let availableEnd = max(totalDuration, videoDuration)
        let start = exportRange?.lowerBound ?? 0
        let end = exportRange?.upperBound ?? availableEnd
        let layer = EditorAdjustmentLayer(
            title: "Adjustment \(adjustmentLayers.count + 1)",
            startTime: start,
            endTime: max(start + 0.1, end),
            zIndex: (adjustmentLayers.map(\.zIndex).max() ?? -1) + 1
        )
        adjustmentLayers.append(layer)
        selectedAdjustmentLayerID = layer.id
        selectedVisualEffectID = nil
        finishEffectsMutation()
    }

    func deleteSelectedAdjustmentLayer() {
        guard let id = selectedAdjustmentLayerID else { return }
        registerUndoIfNeeded()
        adjustmentLayers.removeAll { $0.id == id }
        selectedAdjustmentLayerID = nil
        selectedVisualEffectID = nil
        finishEffectsMutation()
    }

    func updateSelectedAdjustmentRange(start: TimeInterval? = nil, end: TimeInterval? = nil) {
        guard let id = selectedAdjustmentLayerID,
              let index = adjustmentLayers.firstIndex(where: { $0.id == id }) else { return }
        registerUndoIfNeeded()
        let ceiling = max(videoDuration, totalDuration)
        var layer = adjustmentLayers[index]
        if let start {
            layer.startTime = min(max(0, start), layer.endTime - 0.1)
        }
        if let end {
            layer.endTime = min(
                max(layer.startTime + 0.1, end),
                max(ceiling, layer.startTime + 0.1)
            )
        }
        adjustmentLayers[index] = layer
        finishEffectsMutation()
    }

    func toggleSelectedAdjustmentLayer() {
        guard let id = selectedAdjustmentLayerID,
              let index = adjustmentLayers.firstIndex(where: { $0.id == id }) else { return }
        registerUndoIfNeeded()
        adjustmentLayers[index].isEnabled.toggle()
        finishEffectsMutation()
    }

    func addVisualEffect(_ kind: EditorVisualEffectKind) {
        let effect = EditorVisualEffect(kind: kind)
        mutateSelectedEffectStack { stack in
            stack.append(effect)
        }
        selectedVisualEffectID = effect.id
    }

    func applyEffectPreset(_ preset: EditorEffectPreset) {
        let effects = preset.effects.map {
            var copy = $0
            copy.id = UUID()
            return copy
        }
        mutateSelectedEffectStack { stack in
            stack = effects
        }
        selectedVisualEffectID = effects.first?.id
    }

    func toggleVisualEffect(_ id: UUID) {
        mutateSelectedEffectStack { stack in
            guard let index = stack.firstIndex(where: { $0.id == id }) else { return }
            stack[index].isEnabled.toggle()
        }
    }

    func setVisualEffectAmount(_ id: UUID, amount: Double) {
        mutateSelectedEffectStack { stack in
            guard let index = stack.firstIndex(where: { $0.id == id }) else { return }
            stack[index].amount = min(max(amount, 0), 1)
        }
    }

    func setVisualEffectSecondaryAmount(_ id: UUID, amount: Double) {
        mutateSelectedEffectStack { stack in
            guard let index = stack.firstIndex(where: { $0.id == id }) else { return }
            stack[index].secondaryAmount = min(max(amount, 0), 1)
        }
    }

    func keyframeVisualEffectAmount(_ id: UUID) {
        let localTime = selectedEffectLocalTime
        mutateSelectedEffectStack { stack in
            guard let index = stack.firstIndex(where: { $0.id == id }) else { return }
            var track = stack[index].amountKeyframes
            _ = track.upsert(
                at: localTime,
                value: stack[index].amount,
                curve: .init(preset: .easeInOut)
            )
            stack[index].amountKeyframes = track
            if stack[index].kind.secondaryControlTitle != nil {
                stack[index].secondaryKeyframes = stack[index].alignedSecondaryKeyframes()
            }
        }
    }

    func seekToVisualEffectKeyframe(localTime: TimeInterval) {
        scrubVisualEffectPlayhead(to: localTime)
        commitTimelineAfterScrub()
    }

    func scrubVisualEffectPlayhead(to localTime: TimeInterval) {
        pausePlaybackForEdit()
        timelinePosition = min(
            max(0, selectedEffectTargetStartTime + min(max(0, localTime), selectedEffectTargetDuration)),
            totalDuration
        )
        if compositionFingerprint != nil {
            player?.seek(
                to: CMTime(seconds: timelinePosition, preferredTimescale: 600),
                toleranceBefore: .zero,
                toleranceAfter: .zero
            )
        }
    }

    func updateVisualEffectAmountKeyframe(
        effectID: UUID,
        keyframeID: UUID,
        time: TimeInterval? = nil,
        value: Double? = nil,
        secondaryValue: Double? = nil
    ) {
        guard let effect = selectedEffectStack.first(where: { $0.id == effectID }),
              let point = effect.amountKeyframes.keyframes.first(where: { $0.id == keyframeID }) else { return }
        let resolvedTime = min(max(0, time ?? point.time), selectedEffectTargetDuration)
        let resolvedValue = min(max(0, value ?? point.value), 1)
        let resolvedSecondary = min(max(secondaryValue ?? effect.resolvedSecondaryAmount(at: point.time), 0), 1)
        guard resolvedTime != point.time || resolvedValue != point.value
                || resolvedSecondary != effect.resolvedSecondaryAmount(at: point.time) else { return }
        pausePlaybackForEdit()
        // A gesture commits once, so dragging creates a single undo step.
        mutateSelectedEffectStack { stack in
            guard let index = stack.firstIndex(where: { $0.id == effectID }) else { return }
            if stack[index].kind.secondaryControlTitle != nil {
                var secondaryTrack = stack[index].alignedSecondaryKeyframes()
                secondaryTrack.update(id: keyframeID, time: resolvedTime, value: resolvedSecondary)
                stack[index].secondaryKeyframes = secondaryTrack
            }
            stack[index].amountKeyframes.update(id: keyframeID, time: resolvedTime, value: resolvedValue)
        }
        scrubVisualEffectPlayhead(to: resolvedTime)
    }

    func deleteVisualEffectAmountKeyframe(effectID: UUID, keyframeID: UUID) {
        mutateSelectedEffectStack { stack in
            guard let index = stack.firstIndex(where: { $0.id == effectID }) else { return }
            var track = stack[index].amountKeyframes
            track.remove(id: keyframeID)
            stack[index].amountKeyframes = track
            stack[index].secondaryKeyframes?.remove(id: keyframeID)
        }
    }

    func moveVisualEffect(_ id: UUID, by offset: Int) {
        mutateSelectedEffectStack { stack in
            guard let index = stack.firstIndex(where: { $0.id == id }) else { return }
            let destination = min(max(0, index + offset), stack.count - 1)
            guard destination != index else { return }
            stack.swapAt(index, destination)
        }
    }

    func deleteVisualEffect(_ id: UUID) {
        mutateSelectedEffectStack { stack in
            stack.removeAll { $0.id == id }
        }
        selectedVisualEffectID = selectedEffectStack.first?.id
    }

    func editSelectedAdjustmentColor() {
        guard selectedAdjustmentLayerID != nil else { return }
        selectedTool = .filter
        colorUndoSnapshot = currentSnapshot()
        pausePlaybackForEdit()
    }

    private func mutateSelectedEffectStack(_ mutation: (inout [EditorVisualEffect]) -> Void) {
        registerUndoIfNeeded()
        if let id = selectedAdjustmentLayerID,
           let index = adjustmentLayers.firstIndex(where: { $0.id == id }) {
            mutation(&adjustmentLayers[index].effects)
        } else if let id = selectedOverlayClipID,
                  let index = overlayClips.firstIndex(where: { $0.id == id }) {
            mutation(&overlayClips[index].effects)
        } else if let id = selectedClipID,
                  let index = clips.firstIndex(where: { $0.id == id }) {
            mutation(&clips[index].effects)
        } else {
            return
        }
        finishEffectsMutation()
    }

    private func finishEffectsMutation() {
        invalidateComposition()
        scheduleSave()
        scheduleColorPreviewRefresh()
    }
}
