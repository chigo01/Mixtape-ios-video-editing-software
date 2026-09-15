//
//  EditorViewModel+GraphicsAndText.swift
//  Mixtape
//

import SwiftUI
import UIKit
import AVFoundation
import Photos

extension EditorViewModel {
    // MARK: Stickers and reusable graphics

    func addGraphic(source: EditorGraphicSource, title: String? = nil) {
        let start = min(max(0, timelinePosition), max(0, totalDuration - 0.12))
        let end = min(totalDuration, start + 3)
        guard end - start >= 0.1 else { return }
        registerUndoIfNeeded()
        let overlay = EditorGraphicOverlay(
            source: source,
            title: title ?? source.displayName,
            startTime: start,
            endTime: end
        )
        graphicOverlays.append(overlay)
        selectedGraphicOverlayID = overlay.id
        selectedTextOverlayID = nil
        selectedClipID = nil
        selectedAudioClipID = nil
        selectedOverlayClipID = nil
        selectedAdjustmentLayerID = nil
        scheduleSave()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func importGraphicImageData(_ data: Data) throws {
        guard let image = UIImage(data: data), image.size.width > 0, image.size.height > 0 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Mixtape/Graphics", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let url = base.appendingPathComponent("graphic-\(UUID().uuidString).png")
        guard let normalized = image.pngData() else { throw CocoaError(.fileWriteUnknown) }
        try normalized.write(to: url, options: .atomic)
        addGraphic(source: .image(path: url.path), title: "Imported Graphic")
    }

    func selectGraphicOverlay(_ id: UUID) {
        selectedGraphicOverlayID = id
        selectedTextOverlayID = nil
        selectedClipID = nil
        selectedAudioClipID = nil
        selectedOverlayClipID = nil
        selectedAdjustmentLayerID = nil
        isTextEditorPresented = false
        selectedTool = .graphics
    }

    func beginGraphicEdit() {
        if graphicEditUndoSnapshot == nil { graphicEditUndoSnapshot = currentSnapshot() }
    }

    func updateSelectedGraphic(_ mutation: (inout EditorGraphicOverlay) -> Void) {
        guard let id = selectedGraphicOverlayID,
              let index = graphicOverlays.firstIndex(where: { $0.id == id }) else { return }
        beginGraphicEdit()
        mutation(&graphicOverlays[index])
        graphicOverlays[index].size = min(max(graphicOverlays[index].size, 32), 420)
        graphicOverlays[index].scale = min(max(graphicOverlays[index].scale, 0.15), 6)
        graphicOverlays[index].opacity = min(max(graphicOverlays[index].opacity, 0), 1)
    }

    func commitGraphicEdit() {
        guard let before = graphicEditUndoSnapshot else { return }
        graphicEditUndoSnapshot = nil
        graphicDragOrigin = nil
        if before != currentSnapshot() {
            undoManager.pushUndoState(before)
            refreshUndoState()
            scheduleSave()
        }
    }

    func beginGraphicPositionDrag(id: UUID) {
        guard let graphic = graphicOverlays.first(where: { $0.id == id }) else { return }
        beginGraphicEdit()
        graphicDragOrigin = (graphic.xOffset, graphic.yOffset)
    }

    func updateGraphicPositionDrag(id: UUID, translation: CGSize, canvasScale: CGFloat) {
        guard canvasScale > 0, let origin = graphicDragOrigin,
              let index = graphicOverlays.firstIndex(where: { $0.id == id }) else { return }
        graphicOverlays[index].xOffset = origin.x + translation.width / canvasScale
        graphicOverlays[index].yOffset = origin.y + translation.height / canvasScale
    }

    func duplicateSelectedGraphic() {
        guard var copy = selectedGraphicOverlay else { return }
        registerUndoIfNeeded()
        copy.id = UUID()
        copy.title += " Copy"
        copy.xOffset += 18
        copy.yOffset += 18
        graphicOverlays.append(copy)
        selectedGraphicOverlayID = copy.id
        scheduleSave()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    func deleteSelectedGraphic() {
        guard let id = selectedGraphicOverlayID else { return }
        registerUndoIfNeeded()
        let removed = graphicOverlays.first { $0.id == id }
        graphicOverlays.removeAll { $0.id == id }
        selectedGraphicOverlayID = nil
        if case let .image(path)? = removed?.source,
           !graphicOverlays.contains(where: { $0.source == .image(path: path) }),
           !EditorGraphicFavoritesStore.ids.contains(EditorGraphicSource.image(path: path).catalogID) {
            try? FileManager.default.removeItem(atPath: path)
        }
        scheduleSave()
    }

    func updateGraphicTimeRange(id: UUID, start: TimeInterval, end: TimeInterval) {
        guard let index = graphicOverlays.firstIndex(where: { $0.id == id }) else { return }
        beginGraphicEdit()
        let minimum = 0.1
        graphicOverlays[index].startTime = min(max(0, start), max(0, end - minimum))
        graphicOverlays[index].endTime = min(totalDuration, max(end, start + minimum))
    }

    func moveGraphicOnTimeline(id: UUID, startTime: TimeInterval) {
        guard let index = graphicOverlays.firstIndex(where: { $0.id == id }) else { return }
        beginGraphicEdit()
        let duration = graphicOverlays[index].duration
        let start = min(max(0, startTime), max(0, totalDuration - duration))
        graphicOverlays[index].startTime = start
        graphicOverlays[index].endTime = start + duration
    }

    func updateTextOverlay(_ overlay: EditorTextOverlay) {
        guard let idx = textOverlays.firstIndex(where: { $0.id == overlay.id }) else { return }
        let current = textOverlays[idx]
        var updated = overlay

        // Captions render and export from their timed words, while the regular
        // text editor edits `text`. Keep both representations in lockstep so a
        // correction is immediately visible everywhere. Preserve the old words
        // during a transient empty edit; dismissing the editor still deletes it.
        let normalizedText = overlay.text
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .joined(separator: " ")
        let renderedCaptionText = overlay.captionWords.map(\.text).joined(separator: " ")
        if current.isCaption, !normalizedText.isEmpty,
           normalizedText != renderedCaptionText {
            updated.captionWords = retimedCaptionWords(
                for: overlay.text,
                in: overlay,
                preserving: current.captionWords
            )
        }

        textOverlays[idx] = updated
        scheduleSave()
    }

    func retimedCaptionWords(
        for text: String,
        in overlay: EditorTextOverlay,
        preserving existingWords: [EditorCaptionWord]
    ) -> [EditorCaptionWord] {
        let tokens = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !tokens.isEmpty else { return [] }

        // A normal spelling correction does not change the word count. Retain
        // the recognizer's word-level timing (and stable IDs used by karaoke
        // highlighting) instead of needlessly redistributing the whole line.
        if tokens.count == existingWords.count {
            return zip(tokens, existingWords).map { token, existing in
                EditorCaptionWord(
                    id: existing.id,
                    text: token,
                    startTime: existing.startTime,
                    endTime: existing.endTime,
                    confidence: existing.confidence
                )
            }
        }

        let start = overlay.startTime
        let end = max(start, overlay.endTime)
        let step = (end - start) / Double(tokens.count)
        return tokens.enumerated().map { offset, token in
            EditorCaptionWord(
                text: token,
                startTime: start + Double(offset) * step,
                endTime: offset == tokens.count - 1
                    ? end
                    : start + Double(offset + 1) * step,
                confidence: offset < existingWords.count
                    ? existingWords[offset].confidence
                    : 1
            )
        }
    }

    func captionOverlay(
        basedOn source: EditorTextOverlay,
        id: UUID = UUID(),
        words: [EditorCaptionWord],
        start: TimeInterval,
        end: TimeInterval
    ) -> EditorTextOverlay {
        EditorTextOverlay(
            id: id,
            text: words.map(\.text).joined(separator: " "),
            startTime: start,
            endTime: end,
            fontSize: source.fontSize,
            fontFamily: source.fontFamily,
            fontStyle: source.fontStyle,
            textColor: source.textColor,
            opacity: source.opacity,
            horizontalAlignment: source.horizontalAlignment,
            verticalAlignment: source.verticalAlignment,
            xOffset: source.xOffset,
            yOffset: source.yOffset,
            keyframes: source.keyframes,
            animation: source.animation,
            attachedClipID: source.attachedClipID,
            attachedTrackID: source.attachedTrackID,
            attachRotation: source.attachRotation,
            attachScale: source.attachScale,
            captionWords: words,
            captionHighlightColor: source.captionHighlightColor,
            captionLocaleIdentifier: source.captionLocaleIdentifier,
            trackedRotationDegrees: source.trackedRotationDegrees
        )
    }

    func beginTextOverlayEdit() {
        if textEditUndoSnapshot == nil {
            textEditUndoSnapshot = currentSnapshot()
        }
    }

    func finalizeTextOverlayEdit() {
        guard let before = textEditUndoSnapshot else { return }
        textEditUndoSnapshot = nil
        textEditDragOrigin = nil
        if before != currentSnapshot() {
            undoManager.pushUndoState(before)
            refreshUndoState()
            scheduleSave()
        }
    }

    func beginTextOverlayPositionDrag(id: UUID) {
        beginTextOverlayEdit()
        guard let overlay = textOverlays.first(where: { $0.id == id }) else { return }
        let resolved = overlay.resolved(at: timelinePosition)
        textEditDragOrigin = (resolved.xOffset, resolved.yOffset)
    }

    func updateTextOverlayPositionDrag(
        id: UUID,
        translation: CGSize,
        canvasScale: CGFloat
    ) {
        guard let origin = textEditDragOrigin,
              canvasScale > 0,
              let idx = textOverlays.firstIndex(where: { $0.id == id }) else { return }
        let x = origin.x + translation.width / canvasScale
        let y = origin.y + translation.height / canvasScale
        textOverlays[idx].xOffset = x
        textOverlays[idx].yOffset = y

        // `resolved()` reads keyframed X/Y when those tracks exist, ignoring
        // the base offset. Write through at the playhead so the glyph actually
        // follows the finger instead of appearing stuck.
        let localTime = min(
            max(0, timelinePosition - textOverlays[idx].startTime),
            textOverlays[idx].duration
        )
        var tracks = textOverlays[idx].keyframes
        var wroteKeyframe = false
        if !tracks.track(for: .textPositionX).isEmpty {
            var track = tracks.track(for: .textPositionX)
            _ = track.upsert(at: localTime, value: Double(x))
            tracks.replace(track)
            wroteKeyframe = true
        }
        if !tracks.track(for: .textPositionY).isEmpty {
            var track = tracks.track(for: .textPositionY)
            _ = track.upsert(at: localTime, value: Double(y))
            tracks.replace(track)
            wroteKeyframe = true
        }
        if wroteKeyframe {
            textOverlays[idx].keyframes = tracks
        }
    }

    func commitTextOverlayPositionDrag() {
        textEditDragOrigin = nil
        finalizeTextOverlayEdit()
    }

    func deleteTextOverlay(id: UUID) {
        clearTextOverlayEditUndo()
        registerUndoIfNeeded()
        textOverlays.removeAll { $0.id == id }
        selectedTimelineItems.remove(.text(id))
        pruneSequenceStructure()
        if selectedTextOverlayID == id {
            selectedTextOverlayID = nil
            isTextEditorPresented = false
        }
        scheduleSave()
    }

    func duplicateSelectedTextOverlay() {
        guard let source = selectedTextOverlay else { return }
        let start = min(source.endTime, totalDuration)
        let duration = source.duration
        let captionTimeOffset = start - source.startTime
        let copiedCaptionWords = source.captionWords.map { word in
            EditorCaptionWord(
                text: word.text,
                startTime: word.startTime + captionTimeOffset,
                endTime: word.endTime + captionTimeOffset,
                confidence: word.confidence
            )
        }
        let copy = EditorTextOverlay(
            text: source.text, startTime: start,
            endTime: min(totalDuration, start + duration), fontSize: source.fontSize,
            fontFamily: source.fontFamily, fontStyle: source.fontStyle,
            textColor: source.textColor, opacity: source.opacity,
            horizontalAlignment: source.horizontalAlignment,
            verticalAlignment: source.verticalAlignment, xOffset: source.xOffset,
            yOffset: source.yOffset, keyframes: source.keyframes,
            animation: source.animation,
            attachedClipID: source.attachedClipID,
            attachedTrackID: source.attachedTrackID,
            attachRotation: source.attachRotation,
            attachScale: source.attachScale,
            captionWords: copiedCaptionWords,
            captionHighlightColor: source.captionHighlightColor,
            captionLocaleIdentifier: source.captionLocaleIdentifier
        )
        guard copy.duration > 0.1 else { return }
        registerUndoIfNeeded()
        textOverlays.append(copy)
        selectedTextOverlayID = copy.id
        scheduleSave()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    func selectTextOverlay(_ id: UUID) {
        if handleMultiSelection(.text(id)) { return }
        if selectedTextOverlayID == id {
            selectedTextOverlayID = nil
        } else {
            if selectedTool == .track || selectedTool == .stabilize {
                finalizeMotionTrackingUndo()
            }
            selectedTextOverlayID = id
            selectedAdjustmentLayerID = nil
            selectedClipID = nil
            selectedAudioClipID = nil
            selectedOverlayClipID = nil
            isTextEditorPresented = false
            selectedTool = nil
        }
    }

    func dismissTextEditor() {
        finalizeTextOverlayEdit()

        // If the text is empty, delete the overlay.
        if let id = selectedTextOverlayID,
           let overlay = textOverlays.first(where: { $0.id == id }),
           overlay.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            deleteTextOverlay(id: id)
        }
        // Notice we do NOT clear selectedTextOverlayID here, so it remains selected on the timeline
        isTextEditorPresented = false
    }

    func updateTextOverlayTimeRange(id: UUID, start: TimeInterval, end: TimeInterval) {
        if textTimeRangeUndoSnapshot == nil {
            textTimeRangeUndoSnapshot = currentSnapshot()
        }

        guard let idx = textOverlays.firstIndex(where: { $0.id == id }),
              let baseline = textTimeRangeUndoSnapshot?.textOverlays.first(where: { $0.id == id }) else { return }
        let minimumSpan = min(EditorClip.minimumSourceSpan(speed: 1), baseline.duration)
        var newStart = baseline.startTime
        var newEnd = baseline.endTime
        // Snap only the dragged edge; never move the opposite edge or collapse the range.
        if start != baseline.startTime {
            newStart = min(max(0, snappedTime(start, excluding: id)), newEnd - minimumSpan)
        } else if end != baseline.endTime {
            // Text has no source-media limit and may extend the timeline.
            let snappedEnd = end > totalDuration ? end : snappedTime(end, excluding: id)
            newEnd = max(newStart + minimumSpan, snappedEnd)
        }
        textOverlays[idx].startTime = newStart
        textOverlays[idx].endTime = newEnd
    }

    func commitTextOverlayTimeRange() {
        normalizeCaptionWordsForCurrentRanges()
        if let before = textTimeRangeUndoSnapshot {
            if before != currentSnapshot() {
                undoManager.pushUndoState(before)
                refreshUndoState()
            }
            textTimeRangeUndoSnapshot = nil
        }
        clearSnapGuide()
        scheduleSave()
    }

    func moveTextOverlayOnTimeline(id: UUID, startTime: TimeInterval) {
        if textMoveUndoSnapshot == nil {
            textMoveUndoSnapshot = currentSnapshot()
        }
        guard let idx = textOverlays.firstIndex(where: { $0.id == id }) else { return }
        let duration = textOverlays[idx].duration
        let clampedStart = snappedTime(startTime, excluding: id)
        let delta = clampedStart - textOverlays[idx].startTime
        if textOverlays[idx].isCaption, abs(delta) > 0.000_001 {
            for wordIndex in textOverlays[idx].captionWords.indices {
                textOverlays[idx].captionWords[wordIndex].startTime += delta
                textOverlays[idx].captionWords[wordIndex].endTime += delta
            }
        }
        textOverlays[idx].startTime = clampedStart
        textOverlays[idx].endTime = clampedStart + duration
    }

    func commitTextOverlayMove() {
        if let before = textMoveUndoSnapshot {
            if before != currentSnapshot() {
                undoManager.pushUndoState(before)
                refreshUndoState()
                scheduleSave()
            }
            textMoveUndoSnapshot = nil
        }
        clearSnapGuide()
    }

    private func clearTextOverlayEditUndo() {
        textEditUndoSnapshot = nil
        textEditDragOrigin = nil
        textTimeRangeUndoSnapshot = nil
        textMoveUndoSnapshot = nil
    }

    private func normalizeCaptionWordsForCurrentRanges() {
        for index in textOverlays.indices where textOverlays[index].isCaption {
            let start = textOverlays[index].startTime
            let end = textOverlays[index].endTime
            var words = textOverlays[index].captionWords.filter {
                $0.endTime > start && $0.startTime < end
            }
            guard !words.isEmpty else { continue }
            words[0].startTime = max(words[0].startTime, start)
            words[words.count - 1].endTime = min(words[words.count - 1].endTime, end)
            textOverlays[index].captionWords = words
            textOverlays[index].text = words.map(\.text).joined(separator: " ")
        }
    }
}
