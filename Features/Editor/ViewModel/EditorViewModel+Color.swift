//
//  EditorViewModel+Color.swift
//  Mixtape
//

import SwiftUI
import UIKit
import AVFoundation
import Photos

extension EditorViewModel {
    // MARK: Color and filters

    var canPasteColorAdjustment: Bool { copiedColorAdjustment != nil }

    func setSelectedClipFilter(_ preset: EditorFilterPreset) {
        updateSelectedClipColor { $0.preset = preset }
    }

    func setSelectedClipFilterIntensity(_ intensity: Double) {
        updateSelectedClipColor { $0.presetIntensity = min(max(intensity, 0), 1) }
    }

    func setSelectedClipColorValue(
        _ keyPath: WritableKeyPath<EditorColorAdjustment, Double>,
        value: Double
    ) {
        updateSelectedClipColor {
            $0[keyPath: keyPath] = min(max(value, -1), 1)
        }
    }

    func setSelectedClipHSLValue(
        color: EditorHSLColor,
        keyPath: WritableKeyPath<EditorHSLBandAdjustment, Double>,
        value: Double
    ) {
        updateSelectedClipColor { adjustment in
            var band = adjustment.hsl[color]
            band[keyPath: keyPath] = min(max(value, -1), 1)
            adjustment.hsl[color] = band
        }
    }

    func setSelectedClipToneCurve(
        channel: EditorCurveChannel,
        points: [EditorCurvePoint]
    ) {
        updateSelectedClipColor { adjustment in
            adjustment.curves[channel] = points
                .sorted { $0.x < $1.x }
                .map {
                    EditorCurvePoint(
                        x: min(max($0.x, 0), 1),
                        y: min(max($0.y, 0), 1)
                    )
                }
        }
    }

    func setSelectedClipColorWheel(
        range: EditorColorWheelRange,
        value: EditorColorWheelValue
    ) {
        updateSelectedClipColor { adjustment in
            adjustment.wheels[range] = EditorColorWheelValue(
                x: min(max(value.x, -1), 1),
                y: min(max(value.y, -1), 1),
                luminance: min(max(value.luminance, -1), 1)
            )
        }
    }

    @discardableResult
    func addSelectedClipColorMask(_ mask: EditorColorMask) -> UUID? {
        guard (selectedColorAdjustment?.masks.count ?? 0) < 8 else { return nil }
        var sanitized = mask
        sanitizeColorMask(&sanitized)
        updateSelectedClipColor { $0.masks.append(sanitized) }
        selectedColorMaskID = sanitized.id
        return sanitized.id
    }

    func updateSelectedClipColorMask(_ mask: EditorColorMask) {
        var sanitized = mask
        sanitizeColorMask(&sanitized)
        let correctionProgress = selectedColorMaskProgress
        updateSelectedClipColor { adjustment in
            guard let index = adjustment.masks.firstIndex(where: { $0.id == sanitized.id }) else {
                return
            }
            let old = adjustment.masks[index]
            let geometryChanged = old.centerX != sanitized.centerX
                || old.centerY != sanitized.centerY
                || old.width != sanitized.width
                || old.height != sanitized.height
                || old.points != sanitized.points
            if geometryChanged,
               !old.trackingKeyframes.isEmpty,
               let correctionProgress {
                var samples = old.trackingKeyframes.filter {
                    abs($0.progress - correctionProgress) > 0.004
                }
                samples.append(
                    EditorColorMaskTrackingKeyframe(
                        progress: correctionProgress,
                        centerX: sanitized.centerX,
                        centerY: sanitized.centerY,
                        width: sanitized.width,
                        height: sanitized.height,
                        confidence: 1
                    )
                )
                sanitized.trackingKeyframes = deduplicatedTrackingSamples(samples)
            }
            adjustment.masks[index] = sanitized
        }
    }

    private var selectedColorMaskProgress: Double? {
        if let id = selectedAdjustmentLayerID,
           let layer = adjustmentLayers.first(where: { $0.id == id }) {
            guard timelinePosition >= layer.startTime,
                  timelinePosition <= layer.endTime else { return nil }
            return min(max(
                (timelinePosition - layer.startTime) / max(layer.duration, 0.001),
                0
            ), 1)
        }
        if let overlay = selectedOverlayClip {
            guard timelinePosition >= overlay.timelineStart,
                  timelinePosition <= overlay.timelineEnd else { return nil }
            return min(max(
                (timelinePosition - overlay.timelineStart) / max(overlay.duration, 0.001),
                0
            ), 1)
        }
        guard let id = selectedClipID,
              let index = clips.firstIndex(where: { $0.id == id }) else { return nil }
        let clip = clips[index]
        let local = timelinePosition - timelineOffsetForClipIndex(index)
        return min(max(local / max(clip.duration, 0.001), 0), 1)
    }

    func removeSelectedClipColorMask(id: UUID) {
        updateSelectedClipColor { adjustment in
            adjustment.masks.removeAll { $0.id == id }
        }
        if selectedColorMaskID == id {
            selectedColorMaskID = selectedColorAdjustment?.masks.first?.id
        }
        commitColorAdjustmentEdit()
    }

    func resetSelectedClipColorMask(id: UUID) {
        updateSelectedClipColor { adjustment in
            guard let index = adjustment.masks.firstIndex(where: { $0.id == id }) else { return }
            adjustment.masks[index].adjustment = .init()
        }
        commitColorAdjustmentEdit()
    }

    private func sanitizeColorMask(_ mask: inout EditorColorMask) {
        mask.centerX = min(max(mask.centerX, 0), 1)
        mask.centerY = min(max(mask.centerY, 0), 1)
        mask.width = min(max(mask.width, 0.04), 1.5)
        mask.height = min(max(mask.height, 0.04), 1.5)
        mask.rotation = min(max(mask.rotation, -1), 1)
        mask.feather = min(max(mask.feather, 0), 1)
        mask.opacity = min(max(mask.opacity, 0), 1)
        mask.points = Array(mask.points.prefix(12)).map { point in
            var point = point
            point.x = min(max(point.x, 0), 1)
            point.y = min(max(point.y, 0), 1)
            return point
        }
        mask.trackingKeyframes = Array(mask.trackingKeyframes.prefix(720))
            .map { keyframe in
                var keyframe = keyframe
                keyframe.progress = min(max(keyframe.progress, 0), 1)
                keyframe.centerX = min(max(keyframe.centerX, 0), 1)
                keyframe.centerY = min(max(keyframe.centerY, 0), 1)
                keyframe.width = min(max(keyframe.width, 0.02), 1.5)
                keyframe.height = min(max(keyframe.height, 0.02), 1.5)
                keyframe.confidence = min(max(keyframe.confidence, 0), 1)
                return keyframe
            }
            .sorted { $0.progress < $1.progress }
        mask.adjustment.exposure = min(max(mask.adjustment.exposure, -1), 1)
        mask.adjustment.brightness = min(max(mask.adjustment.brightness, -1), 1)
        mask.adjustment.contrast = min(max(mask.adjustment.contrast, -1), 1)
        mask.adjustment.saturation = min(max(mask.adjustment.saturation, -1), 1)
        mask.adjustment.vibrance = min(max(mask.adjustment.vibrance, -1), 1)
        mask.adjustment.temperature = min(max(mask.adjustment.temperature, -1), 1)
        mask.adjustment.tint = min(max(mask.adjustment.tint, -1), 1)
        mask.adjustment.hue = min(max(mask.adjustment.hue, -1), 1)
        mask.adjustment.smoothness = min(max(mask.adjustment.smoothness, 0), 1)
    }

    func resetSelectedClipColor() {
        updateSelectedClipColor { $0 = .neutral }
        selectedColorMaskID = nil
        commitColorAdjustmentEdit()
    }

    func currentProgramFrameForMaskDetection() async -> UIImage? {
        guard let item = player?.currentItem else { return nil }
        let generator = AVAssetImageGenerator(asset: item.asset)
        generator.videoComposition = item.videoComposition
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 720, height: 1280)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let time = player?.currentTime() ?? CMTime(seconds: timelinePosition, preferredTimescale: 600)
        guard let result = try? await generator.image(at: time) else { return nil }
        return UIImage(cgImage: result.image)
    }

    var isColorMaskTracking: Bool { colorMaskTrackingDirection != nil }
    var canTrackSelectedColorMask: Bool { selectedAdjustmentLayerID == nil }

    func trackSelectedColorMask(_ direction: EditorColorMaskTrackingDirection) {
        guard canTrackSelectedColorMask,
              colorMaskTrackingTask == nil,
              let mask = selectedColorMask,
              let item = player?.currentItem else { return }

        let target: (id: UUID, start: TimeInterval, duration: TimeInterval)
        if let overlay = selectedOverlayClip {
            guard timelinePosition >= overlay.timelineStart,
                  timelinePosition <= overlay.timelineEnd else { return }
            target = (overlay.id, overlay.timelineStart, max(overlay.duration, 0.001))
        } else if let info = playbackInfo, info.clip.id == selectedClipID {
            target = (
                info.clip.id,
                timelineOffsetForClipIndex(info.index),
                max(info.clip.duration, 0.001)
            )
        } else {
            return
        }

        let clipStart = target.start
        let clipDuration = target.duration
        let startProgress = min(max((timelinePosition - clipStart) / clipDuration, 0), 1)
        let maskID = mask.id
        let clipID = target.id
        let sessionID = UUID()
        colorMaskTrackingSessionID = sessionID
        colorMaskTrackingDirection = direction
        switch direction {
        case .forward: colorMaskTrackingMessage = "Tracking mask forward…"
        case .backward: colorMaskTrackingMessage = "Tracking mask backward…"
        }
        player?.pause()
        isPlaying = false

        colorMaskTrackingTask = Task { [weak self] in
            guard let self else { return }
            do {
                let samples = try await EditorColorMaskTracker.track(
                    mask: mask.resolved(at: startProgress),
                    asset: item.asset,
                    videoComposition: item.videoComposition,
                    clipStart: clipStart,
                    clipDuration: clipDuration,
                    startProgress: startProgress,
                    direction: direction
                )
                try Task.checkCancellation()
                guard self.colorMaskTrackingSessionID == sessionID,
                      self.selectedColorTargetID == clipID else { return }
                self.updateSelectedClipColor { adjustment in
                    guard let index = adjustment.masks.firstIndex(where: { $0.id == maskID }) else {
                        return
                    }
                    var trackedMask = adjustment.masks[index]
                    let retained = trackedMask.trackingKeyframes.filter { keyframe in
                        switch direction {
                        case .forward: return keyframe.progress < startProgress
                        case .backward: return keyframe.progress > startProgress
                        }
                    }
                    trackedMask.trackingKeyframes = self.deduplicatedTrackingSamples(retained + samples)
                    adjustment.masks[index] = trackedMask
                }
                self.commitColorAdjustmentEdit()
                self.colorMaskTrackingMessage = "Tracking complete · \(samples.count) motion samples"
            } catch is CancellationError {
                if self.colorMaskTrackingSessionID == sessionID {
                    self.colorMaskTrackingMessage = "Tracking cancelled"
                }
            } catch {
                if self.colorMaskTrackingSessionID == sessionID {
                    self.colorMaskTrackingMessage = error.localizedDescription
                }
            }
            guard self.colorMaskTrackingSessionID == sessionID else { return }
            self.colorMaskTrackingSessionID = nil
            self.colorMaskTrackingDirection = nil
            self.colorMaskTrackingTask = nil
        }
    }

    func cancelColorMaskTracking() {
        guard colorMaskTrackingTask != nil else { return }
        colorMaskTrackingTask?.cancel()
        colorMaskTrackingTask = nil
        colorMaskTrackingSessionID = nil
        colorMaskTrackingDirection = nil
        colorMaskTrackingMessage = "Tracking cancelled"
    }

    func clearSelectedColorMaskTracking() {
        guard let id = selectedColorMaskID else { return }
        updateSelectedClipColor { adjustment in
            guard let index = adjustment.masks.firstIndex(where: { $0.id == id }) else { return }
            adjustment.masks[index].trackingKeyframes = []
        }
        commitColorAdjustmentEdit()
        colorMaskTrackingMessage = "Mask tracking cleared"
    }

    private func deduplicatedTrackingSamples(
        _ samples: [EditorColorMaskTrackingKeyframe]
    ) -> [EditorColorMaskTrackingKeyframe] {
        var result: [EditorColorMaskTrackingKeyframe] = []
        for sample in samples.sorted(by: { $0.progress < $1.progress }) {
            if let last = result.last, abs(last.progress - sample.progress) < 0.000_01 {
                result[result.count - 1] = sample
            } else {
                result.append(sample)
            }
        }
        return result
    }

    func copySelectedClipColor() {
        copiedColorAdjustment = selectedColorAdjustment
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    func pasteColorToSelectedClip() {
        guard let copiedColorAdjustment else { return }
        updateSelectedClipColor { $0 = copiedColorAdjustment }
        commitColorAdjustmentEdit()
    }

    func applySelectedColorToAllClips() {
        guard selectedAdjustmentLayerID == nil,
              let adjustment = selectedColorAdjustment else { return }
        beginColorAdjustmentEditIfNeeded()
        for index in clips.indices {
            clips[index].colorAdjustment = adjustment
        }
        for index in overlayClips.indices {
            overlayClips[index].colorAdjustment = adjustment
        }
        invalidateComposition()
        commitColorAdjustmentEdit()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func commitColorAdjustmentEdit() {
        colorPreviewTask?.cancel()
        colorPreviewTask = nil
        finalizeColorAdjustmentUndo()
        Task { await alignPlaybackToTimeline() }
    }

    private func updateSelectedClipColor(_ update: (inout EditorColorAdjustment) -> Void) {
        beginColorAdjustmentEditIfNeeded()
        if let id = selectedAdjustmentLayerID,
           let index = adjustmentLayers.firstIndex(where: { $0.id == id }) {
            update(&adjustmentLayers[index].colorAdjustment)
        } else if let id = selectedOverlayClipID,
           let index = overlayClips.firstIndex(where: { $0.id == id }) {
            update(&overlayClips[index].colorAdjustment)
        } else if let id = selectedClipID,
                  let index = clips.firstIndex(where: { $0.id == id }) {
            update(&clips[index].colorAdjustment)
        } else {
            return
        }
        invalidateComposition()
        scheduleColorPreviewRefresh()
    }

    private func beginColorAdjustmentEditIfNeeded() {
        if colorUndoSnapshot == nil {
            colorUndoSnapshot = currentSnapshot()
        }
    }

    func finalizeColorAdjustmentUndo() {
        colorPreviewTask?.cancel()
        colorPreviewTask = nil
        guard let before = colorUndoSnapshot else { return }
        colorUndoSnapshot = nil
        if before != currentSnapshot() {
            undoManager.pushUndoState(before)
            refreshUndoState()
            scheduleSave()
        }
    }

    func scheduleColorPreviewRefresh() {
        colorPreviewTask?.cancel()
        colorPreviewTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(90))
            guard !Task.isCancelled, let self else { return }
            await self.alignPlaybackToTimeline()
        }
    }
}
