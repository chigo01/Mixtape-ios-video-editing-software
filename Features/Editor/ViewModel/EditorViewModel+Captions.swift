//
//  EditorViewModel+Captions.swift
//  Mixtape
//

import SwiftUI
import UIKit
import AVFoundation
import Photos

extension EditorViewModel {
    // MARK: Text Overlays

    func transcribeCaptions(
        localeIdentifier: String? = nil,
        source: EditorCaptionAudioSource = .video
    ) {
        guard !isTranscribingCaptions else { return }
        captionTask?.cancel()
        let jobID = UUID()
        captionJobID = jobID
        isTranscribingCaptions = true
        captionErrorMessage = nil
        captionStatusMessage = source == .video
            ? "Preparing video dialogue…"
            : "Preparing the edited audio mix…"
        let clipsSnapshot = clips
        let audioSnapshot = audioClips
        let overlaysSnapshot = overlayClips
        let trackSettingsSnapshot = audioTrackSettings
        let masterSnapshot = masterVolume

        captionTask = Task {
            defer {
                if captionJobID == jobID {
                    isTranscribingCaptions = false
                    captionStatusMessage = nil
                    captionJobID = nil
                    captionTask = nil
                }
            }
            do {
                let result = try await EditorCaptionService.transcribe(
                    clips: clipsSnapshot,
                    audioClips: audioSnapshot,
                    overlayClips: overlaysSnapshot,
                    audioTrackSettings: trackSettingsSnapshot,
                    masterVolume: masterSnapshot,
                    requestedLocaleIdentifier: localeIdentifier,
                    source: source,
                    onProgress: { [weak self] message in
                        guard self?.captionJobID == jobID else { return }
                        self?.captionStatusMessage = message
                    }
                )
                try Task.checkCancellation()
                guard captionJobID == jobID else { return }
                let captions = EditorCaptionService.makeCaptionOverlays(from: result)
                replaceAllCaptions(with: captions)
                captionStatusMessage = "Created \(captions.count) caption segments"
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch is CancellationError {
                return
            } catch {
                guard captionJobID == jobID, !Task.isCancelled else { return }
                captionErrorMessage = error.localizedDescription
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }

    func cancelCaptionTranscription() {
        captionTask?.cancel()
        captionJobID = nil
        captionTask = nil
        isTranscribingCaptions = false
        captionStatusMessage = nil
    }

    func importCaptions(from data: Data) throws {
        replaceAllCaptions(with: try EditorSRTCodec.decode(data))
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    func replaceAllCaptions(with captions: [EditorTextOverlay]) {
        registerUndoIfNeeded()
        let captionIDs = Set(textOverlays.filter(\.isCaption).map(\.id))
        textOverlays.removeAll { captionIDs.contains($0.id) }
        textOverlays.append(contentsOf: captions)
        selectedTextOverlayID = nil
        scheduleSave()
    }

    func updateCaptionText(id: UUID, text: String) {
        guard let index = textOverlays.firstIndex(where: { $0.id == id && $0.isCaption }) else { return }
        registerUndoIfNeeded()
        textOverlays[index].text = text
        textOverlays[index].captionWords = retimedCaptionWords(
            for: text,
            in: textOverlays[index],
            preserving: textOverlays[index].captionWords
        )
        scheduleSave()
    }

    func updateCaptionWordText(captionID: UUID, wordID: UUID, text: String) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty,
              let captionIndex = textOverlays.firstIndex(where: { $0.id == captionID && $0.isCaption }),
              let wordIndex = textOverlays[captionIndex].captionWords.firstIndex(where: { $0.id == wordID }),
              textOverlays[captionIndex].captionWords[wordIndex].text != value else { return }
        registerUndoIfNeeded()
        textOverlays[captionIndex].captionWords[wordIndex].text = value
        textOverlays[captionIndex].text = textOverlays[captionIndex].captionWords
            .map(\.text).joined(separator: " ")
        scheduleSave()
    }

    /// Moves the boundary after one word while maintaining a valid, contiguous
    /// pair. This provides precise timing correction without allowing inverted
    /// or zero-length words.
    func nudgeCaptionWordBoundary(
        captionID: UUID,
        afterWordID wordID: UUID,
        by delta: TimeInterval
    ) {
        guard let captionIndex = textOverlays.firstIndex(where: { $0.id == captionID && $0.isCaption }),
              let wordIndex = textOverlays[captionIndex].captionWords.firstIndex(where: { $0.id == wordID }),
              wordIndex + 1 < textOverlays[captionIndex].captionWords.count else { return }
        let words = textOverlays[captionIndex].captionWords
        let minimumWordDuration: TimeInterval = 0.03
        let currentBoundary = words[wordIndex].endTime
        let lower = words[wordIndex].startTime + minimumWordDuration
        let upper = words[wordIndex + 1].endTime - minimumWordDuration
        let boundary = min(max(currentBoundary + delta, lower), upper)
        guard abs(boundary - currentBoundary) > 0.000_001 else { return }
        registerUndoIfNeeded()
        textOverlays[captionIndex].captionWords[wordIndex].endTime = boundary
        textOverlays[captionIndex].captionWords[wordIndex + 1].startTime = boundary
        scheduleSave()
    }

    func removeCaptionWord(captionID: UUID, wordID: UUID) {
        guard let captionIndex = textOverlays.firstIndex(where: { $0.id == captionID && $0.isCaption }),
              let wordIndex = textOverlays[captionIndex].captionWords.firstIndex(where: { $0.id == wordID }) else { return }
        guard textOverlays[captionIndex].captionWords.count > 1 else {
            deleteTextOverlay(id: captionID)
            return
        }
        registerUndoIfNeeded()
        textOverlays[captionIndex].captionWords.remove(at: wordIndex)
        let words = textOverlays[captionIndex].captionWords
        textOverlays[captionIndex].startTime = words.first?.startTime ?? textOverlays[captionIndex].startTime
        textOverlays[captionIndex].endTime = words.last?.endTime ?? textOverlays[captionIndex].endTime
        textOverlays[captionIndex].text = words.map(\.text).joined(separator: " ")
        scheduleSave()
    }

    func removeCaptionWords(_ wordIDs: Set<UUID>) {
        guard !wordIDs.isEmpty,
              textOverlays.contains(where: { overlay in
                  overlay.isCaption && overlay.captionWords.contains { wordIDs.contains($0.id) }
              }) else { return }
        registerUndoIfNeeded()
        let captionIDs = Set(textOverlays.filter(\.isCaption).map(\.id))
        for index in textOverlays.indices where textOverlays[index].isCaption {
            textOverlays[index].captionWords.removeAll { wordIDs.contains($0.id) }
            let words = textOverlays[index].captionWords
            if let first = words.first, let last = words.last {
                textOverlays[index].startTime = first.startTime
                textOverlays[index].endTime = last.endTime
                textOverlays[index].text = words.map(\.text).joined(separator: " ")
            }
        }
        let emptiedCaptionIDs = Set(textOverlays.filter {
            captionIDs.contains($0.id) && $0.captionWords.isEmpty
        }.map(\.id))
        textOverlays.removeAll { emptiedCaptionIDs.contains($0.id) }
        if let selectedTextOverlayID, emptiedCaptionIDs.contains(selectedTextOverlayID) {
            self.selectedTextOverlayID = nil
        }
        scheduleSave()
    }

    func splitCaption(id: UUID, near timelineTime: TimeInterval? = nil) {
        guard let index = textOverlays.firstIndex(where: { $0.id == id && $0.isCaption }) else { return }
        let source = textOverlays[index]
        guard source.captionWords.count >= 2 else { return }
        let target = timelineTime ?? timelinePosition
        let possibleBreaks = Array(1..<source.captionWords.count)
        let splitIndex: Int
        if target > source.startTime, target < source.endTime {
            splitIndex = possibleBreaks.min {
                abs(source.captionWords[$0].startTime - target)
                    < abs(source.captionWords[$1].startTime - target)
            } ?? source.captionWords.count / 2
        } else {
            splitIndex = source.captionWords.count / 2
        }
        let leftWords = Array(source.captionWords[..<splitIndex])
        let rightWords = Array(source.captionWords[splitIndex...])
        guard let leftEnd = leftWords.last?.endTime,
              let rightStart = rightWords.first?.startTime else { return }

        registerUndoIfNeeded()
        let left = captionOverlay(
            basedOn: source,
            id: source.id,
            words: leftWords,
            start: source.startTime,
            end: max(leftEnd, source.startTime + 0.03)
        )
        let right = captionOverlay(
            basedOn: source,
            words: rightWords,
            start: min(rightStart, source.endTime - 0.03),
            end: source.endTime
        )
        textOverlays.replaceSubrange(index...index, with: [left, right])
        remapSequenceMembershipAfterSplit(original: .text(left.id), right: .text(right.id))
        selectedTextOverlayID = right.id
        scheduleSave()
    }

    func mergeCaptionWithNext(id: UUID) {
        let orderedIDs = captionOverlays.map(\.id)
        guard let orderedIndex = orderedIDs.firstIndex(of: id),
              orderedIndex + 1 < orderedIDs.count,
              let firstIndex = textOverlays.firstIndex(where: { $0.id == id }),
              let secondIndex = textOverlays.firstIndex(where: { $0.id == orderedIDs[orderedIndex + 1] }) else { return }
        let first = textOverlays[firstIndex]
        let second = textOverlays[secondIndex]
        let words = first.captionWords + second.captionWords
        registerUndoIfNeeded()
        textOverlays[firstIndex] = captionOverlay(
            basedOn: first,
            id: first.id,
            words: words,
            start: first.startTime,
            end: max(first.endTime, second.endTime)
        )
        textOverlays.remove(at: secondIndex)
        selectedTimelineItems.remove(.text(second.id))
        pruneSequenceStructure()
        selectedTextOverlayID = first.id
        scheduleSave()
    }

    func deleteAllCaptions() {
        guard textOverlays.contains(where: \.isCaption) else { return }
        registerUndoIfNeeded()
        let captionIDs = Set(textOverlays.filter(\.isCaption).map(\.id))
        textOverlays.removeAll { captionIDs.contains($0.id) }
        if let selectedTextOverlayID, captionIDs.contains(selectedTextOverlayID) {
            self.selectedTextOverlayID = nil
            isTextEditorPresented = false
        }
        scheduleSave()
    }

    func applyCaptionStyle(_ source: EditorTextOverlay, toAll: Bool) {
        registerUndoIfNeeded()
        for index in textOverlays.indices where textOverlays[index].isCaption
            && (toAll || textOverlays[index].id == source.id) {
            textOverlays[index].fontSize = source.fontSize
            textOverlays[index].fontFamily = source.fontFamily
            textOverlays[index].fontStyle = source.fontStyle
            textOverlays[index].textColor = source.textColor
            textOverlays[index].captionHighlightColor = source.captionHighlightColor
            textOverlays[index].opacity = source.opacity
            textOverlays[index].horizontalAlignment = source.horizontalAlignment
            textOverlays[index].verticalAlignment = source.verticalAlignment
            textOverlays[index].xOffset = source.xOffset
            textOverlays[index].yOffset = source.yOffset
        }
        scheduleSave()
    }

    func applyCaptionAnimation(_ animation: EditorTextAnimation, toAll: Bool = true) {
        guard textOverlays.contains(where: \.isCaption) else { return }
        if textEditUndoSnapshot == nil { registerUndoIfNeeded() }
        for index in textOverlays.indices where textOverlays[index].isCaption
            && (toAll || textOverlays[index].id == selectedTextOverlayID) {
            textOverlays[index].animation = animation
        }
        scheduleSave()
    }

    func seekToCaption(_ id: UUID) {
        guard let caption = textOverlays.first(where: { $0.id == id && $0.isCaption }) else { return }
        selectedTextOverlayID = id
        seekTimeline(to: caption.startTime)
    }

    func addTextOverlay() {
        let defaultDuration: TimeInterval = 3.0
        let start = max(0, timelinePosition)
        let end = min(start + defaultDuration, totalDuration)

        guard end > start + 0.1 else { return } // not enough room

        registerUndoIfNeeded()
        let overlay = EditorTextOverlay(
            text: "Text",
            startTime: start,
            endTime: end
        )
        textOverlays.append(overlay)
        selectedClipID = nil
        selectedAudioClipID = nil
        selectedOverlayClipID = nil
        selectedGraphicOverlayID = nil
        selectedAdjustmentLayerID = nil
        selectedTextOverlayID = overlay.id
        isTextEditorPresented = true
        scheduleSave()

        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}
