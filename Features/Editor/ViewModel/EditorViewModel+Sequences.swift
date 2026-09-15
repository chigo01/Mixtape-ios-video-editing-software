//
//  EditorViewModel+Sequences.swift
//  Mixtape
//

import SwiftUI
import UIKit
import AVFoundation
import Photos

extension EditorViewModel {
    // MARK: Selection and sequence structure

    var selectionCount: Int { expandedSelection.count }
    var hasSelectionRange: Bool { exportRange != nil }
    var canCreateSequence: Bool { selectedTimelineItems.count >= 2 }

    var activeSequence: EditorSequence? {
        guard let activeSequenceID else { return nil }
        return sequences.first { $0.id == activeSequenceID }
    }

    var selectedSequence: EditorSequence? {
        guard let selectedSequenceID else { return nil }
        return sequences.first { $0.id == selectedSequenceID }
    }

    var visibleSequences: [EditorSequence] {
        sequences.filter { $0.parentSequenceID == activeSequenceID }
    }

    func beginMultiSelection() {
        finalizeSelectionToolEdits()
        isMultiSelectMode = true
        selectedTool = .sequence
        selectedClipID = nil
        selectedTextOverlayID = nil
        selectedAudioClipID = nil
        selectedOverlayClipID = nil
        isTextEditorPresented = false
    }

    func endMultiSelection(clearSelection: Bool = true) {
        isMultiSelectMode = false
        if clearSelection {
            selectedTimelineItems.removeAll()
            selectedSequenceID = nil
        }
        if selectedTool == .sequence { selectedTool = nil }
        scheduleSave()
    }

    private func finalizeSelectionToolEdits() {
        if selectedTool == .speed { finalizeSpeedEditUndo() }
        if selectedTool == .duration { finalizePhotoDurationEditUndo() }
        if selectedTool == .crop { finalizeReframeEditUndo() }
        if selectedTool == .filter { finalizeColorAdjustmentUndo() }
        if selectedTool == .compositing { finalizeOverlayCompositingUndo() }
        if selectedTool == .track || selectedTool == .stabilize { finalizeMotionTrackingUndo() }
        finalizeAudioVolumeEditUndo()
        finalizeOverlayTransform()
        cancelMotionTracking()
    }

    @discardableResult
    func handleMultiSelection(_ reference: EditorTimelineItemReference) -> Bool {
        guard isMultiSelectMode else {
            selectedTimelineItems.removeAll()
            selectedSequenceID = nil
            return false
        }
        guard isItemInActiveSequence(reference) else { return true }
        if selectedTimelineItems.contains(reference) {
            selectedTimelineItems.remove(reference)
        } else {
            selectedTimelineItems.insert(reference)
        }
        selectedSequenceID = reference.kind == .sequence ? reference.itemID : nil
        UISelectionFeedbackGenerator().selectionChanged()
        scheduleSave()
        return true
    }

    func isItemSelected(_ reference: EditorTimelineItemReference) -> Bool {
        selectedTimelineItems.contains(reference) || expandedSelection.contains(reference)
    }

    func isItemInActiveSequence(_ reference: EditorTimelineItemReference) -> Bool {
        guard let activeSequenceID else { return true }
        return leafReferences(in: activeSequenceID).contains(reference)
    }

    func selectAllInActiveSequence() {
        beginMultiSelection()
        if let activeSequenceID {
            selectedTimelineItems = leafReferences(in: activeSequenceID)
        } else {
            selectedTimelineItems = allLeafReferences
        }
        selectedSequenceID = nil
        scheduleSave()
    }

    func selectItemsInExportRange() {
        guard let range = exportRange else { return }
        beginMultiSelection()
        let candidates = activeSequenceID.map { leafReferences(in: $0) } ?? allLeafReferences
        selectedTimelineItems = Set(candidates.filter { reference in
            guard let itemRange = timeRange(for: reference) else { return false }
            return itemRange.upperBound > range.lowerBound && itemRange.lowerBound < range.upperBound
        })
        selectedSequenceID = nil
        scheduleSave()
    }

    func selectSequence(_ id: UUID) {
        guard sequences.contains(where: { $0.id == id }) else { return }
        beginMultiSelection()
        selectedTimelineItems = [.sequence(id)]
        selectedSequenceID = id
        scheduleSave()
    }

    func groupSelectedItems() { createSequence(kind: .group) }
    func createCompoundClip() { createSequence(kind: .compound) }

    private func createSequence(kind: EditorSequenceKind) {
        let roots = Array(selectedTimelineItems).sorted { $0.id < $1.id }
        guard roots.count >= 2 else { return }
        registerUndoIfNeeded()
        let title = kind == .compound
            ? "Compound \(sequences.filter { $0.kind == .compound }.count + 1)"
            : "Group \(sequences.filter { $0.kind == .group }.count + 1)"
        let sequence = EditorSequence(
            title: title,
            kind: kind,
            members: roots,
            parentSequenceID: activeSequenceID
        )
        if kind == .compound {
            let rootsSet = Set(roots)
            for index in sequences.indices
            where sequences[index].kind == .compound
                && sequences[index].id != activeSequenceID
                && sequences[index].parentSequenceID == activeSequenceID {
                sequences[index].members.removeAll { rootsSet.contains($0) }
            }
        }
        if let activeSequenceID,
           let parentIndex = sequences.firstIndex(where: { $0.id == activeSequenceID }) {
            let rootsSet = Set(roots)
            sequences[parentIndex].members.removeAll { rootsSet.contains($0) }
            sequences[parentIndex].members.append(.sequence(sequence.id))
        }
        for reference in roots where reference.kind == .sequence {
            if let childIndex = sequences.firstIndex(where: { $0.id == reference.itemID }) {
                sequences[childIndex].parentSequenceID = sequence.id
            }
        }
        sequences.append(sequence)
        pruneSequenceStructure()
        selectedTimelineItems = [.sequence(sequence.id)]
        selectedSequenceID = sequence.id
        scheduleSave()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    func dissolveSelectedSequence() {
        guard let sequence = selectedSequence,
              let index = sequences.firstIndex(where: { $0.id == sequence.id }) else { return }
        registerUndoIfNeeded()
        if let parentID = sequence.parentSequenceID,
           let parentIndex = sequences.firstIndex(where: { $0.id == parentID }) {
            let insertionIndex = sequences[parentIndex].members.firstIndex(of: .sequence(sequence.id))
                ?? sequences[parentIndex].members.endIndex
            sequences[parentIndex].members.removeAll { $0 == .sequence(sequence.id) }
            sequences[parentIndex].members.insert(contentsOf: sequence.members, at: insertionIndex)
        }
        for member in sequence.members where member.kind == .sequence {
            if let childIndex = sequences.firstIndex(where: { $0.id == member.itemID }) {
                sequences[childIndex].parentSequenceID = sequence.parentSequenceID
            }
        }
        sequences.remove(at: index)
        if activeSequenceID == sequence.id { activeSequenceID = sequence.parentSequenceID }
        selectedTimelineItems = Set(sequence.members)
        selectedSequenceID = nil
        scheduleSave()
    }

    func enterSelectedSequence() {
        guard let selectedSequence else { return }
        activeSequenceID = selectedSequence.id
        selectedTimelineItems.removeAll()
        selectedSequenceID = nil
        scheduleSave()
    }

    func exitActiveSequence() {
        guard let activeSequence else { return }
        activeSequenceID = activeSequence.parentSequenceID
        selectedTimelineItems = [.sequence(activeSequence.id)]
        selectedSequenceID = activeSequence.id
        isMultiSelectMode = true
        selectedTool = .sequence
        selectedClipID = nil
        selectedTextOverlayID = nil
        selectedAudioClipID = nil
        selectedOverlayClipID = nil
        scheduleSave()
    }

    func renameSequence(id: UUID, title: String) {
        guard let index = sequences.firstIndex(where: { $0.id == id }) else { return }
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, normalized != sequences[index].title else { return }
        registerUndoIfNeeded()
        sequences[index].title = normalized
        scheduleSave()
    }

    func addMarkerAtPlayhead() {
        registerUndoIfNeeded()
        var number = 1
        let existingNames = Set(markers.map(\.name))
        while existingNames.contains("Marker \(number)") { number += 1 }
        let marker = EditorTimelineMarker(
            name: "Marker \(number)",
            time: min(max(0, timelinePosition), totalDuration)
        )
        markers.append(marker)
        markers.sort { $0.time < $1.time }
        scheduleSave()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func renameMarker(id: UUID, name: String) {
        guard let index = markers.firstIndex(where: { $0.id == id }) else { return }
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, normalized != markers[index].name else { return }
        registerUndoIfNeeded()
        markers[index].name = normalized
        scheduleSave()
    }

    func deleteMarker(id: UUID) {
        guard markers.contains(where: { $0.id == id }) else { return }
        registerUndoIfNeeded()
        markers.removeAll { $0.id == id }
        scheduleSave()
    }

    func moveSelectionEarlier() { moveSelection(direction: -1) }
    func moveSelectionLater() { moveSelection(direction: 1) }

    private func moveSelection(direction: Int) {
        let references = expandedSelection
        guard !references.isEmpty, direction != 0 else { return }
        registerUndoIfNeeded()
        let primaryIDs = Set(references.filter { $0.kind == .primaryClip }.map(\.itemID))
        let anchorID = clips.first(where: { primaryIDs.contains($0.id) })?.id
        let oldAnchorStart = anchorID.flatMap { id in
            clips.firstIndex(where: { $0.id == id }).map { timelineOffsetForClipIndex($0) }
        }
        if !primaryIDs.isEmpty, primaryIDs.count < clips.count {
            if direction < 0 {
                for index in clips.indices.dropFirst() where primaryIDs.contains(clips[index].id)
                    && !primaryIDs.contains(clips[index - 1].id) {
                    clips.swapAt(index, index - 1)
                }
            } else if clips.count > 1 {
                for index in clips.indices.dropLast().reversed() where primaryIDs.contains(clips[index].id)
                    && !primaryIDs.contains(clips[index + 1].id) {
                    clips.swapAt(index, index + 1)
                }
            }
        }

        let primaryTimelineDelta: TimeInterval? = anchorID.flatMap { id in
            guard let oldAnchorStart,
                  let index = clips.firstIndex(where: { $0.id == id }) else { return nil }
            return timelineOffsetForClipIndex(index) - oldAnchorStart
        }

        let timed = references.filter { $0.kind != .primaryClip && $0.kind != .sequence }
        let proposed = primaryTimelineDelta ?? (TimeInterval(direction) * 0.10)
        let earliest = timed.compactMap { timeRange(for: $0)?.lowerBound }.min() ?? 0
        let delta = proposed < 0 ? max(proposed, -earliest) : proposed
        let textIDs = Set(timed.filter { $0.kind == .textOverlay }.map(\.itemID))
        let audioIDs = Set(timed.filter { $0.kind == .audioClip }.map(\.itemID))
        let overlayIDs = Set(timed.filter { $0.kind == .overlayClip }.map(\.itemID))
        for index in textOverlays.indices where textIDs.contains(textOverlays[index].id) {
            textOverlays[index].startTime += delta
            textOverlays[index].endTime += delta
            for wordIndex in textOverlays[index].captionWords.indices {
                textOverlays[index].captionWords[wordIndex].startTime += delta
                textOverlays[index].captionWords[wordIndex].endTime += delta
            }
        }
        for index in audioClips.indices where audioIDs.contains(audioClips[index].id) {
            audioClips[index].timelineStart += delta
        }
        for index in overlayClips.indices where overlayIDs.contains(overlayClips[index].id) {
            overlayClips[index].timelineStart += delta
        }
        finishSequenceMutation(rebuildComposition: !primaryIDs.isEmpty || !audioIDs.isEmpty || !overlayIDs.isEmpty)
    }

    func deleteSelectedTimelineItems() {
        let references = expandedSelection
        guard !references.isEmpty else { return }
        let requestedPrimaryIDs = Set(references.filter { $0.kind == .primaryClip }.map(\.itemID))
        var primaryIDs = requestedPrimaryIDs
        if primaryIDs.count >= clips.count, let retained = clips.last?.id { primaryIDs.remove(retained) }
        let textIDs = Set(references.filter { $0.kind == .textOverlay }.map(\.itemID))
        let audioIDs = Set(references.filter { $0.kind == .audioClip }.map(\.itemID))
        let overlayIDs = Set(references.filter { $0.kind == .overlayClip }.map(\.itemID))
        guard !primaryIDs.isEmpty || !textIDs.isEmpty || !audioIDs.isEmpty || !overlayIDs.isEmpty else { return }
        registerUndoIfNeeded()

        var cursor: TimeInterval = 0
        var removedRanges: [ClosedRange<TimeInterval>] = []
        for clip in clips {
            let range = cursor...(cursor + clip.duration)
            if primaryIDs.contains(clip.id) { removedRanges.append(range) }
            cursor = range.upperBound
        }
        let removedAudioURLs = audioClips.filter { audioIDs.contains($0.id) }.map(\.fileURL)
        textOverlays.removeAll { textIDs.contains($0.id) }
        audioClips.removeAll { audioIDs.contains($0.id) }
        overlayClips.removeAll { overlayIDs.contains($0.id) }
        clips.removeAll { primaryIDs.contains($0.id) }
        for range in removedRanges.sorted(by: { $0.lowerBound > $1.lowerBound }) {
            rippleDeleteTimedItems(from: range.lowerBound, to: range.upperBound)
        }
        removedAudioURLs.forEach(releaseAudioFileIfUnused)
        selectedTimelineItems.removeAll()
        selectedSequenceID = nil
        pruneSequenceStructure()
        finishSequenceMutation(rebuildComposition: true)
    }

    func duplicateSelectedTimelineItems() {
        let references = expandedSelection
        guard !references.isEmpty else { return }
        let ranges = references.compactMap { timeRange(for: $0) }
        let selectionStart = ranges.map(\.lowerBound).min() ?? 0
        let selectionEnd = ranges.map(\.upperBound).max() ?? selectionStart
        let duplicateOffset = max(0.10, selectionEnd - selectionStart)
        let selectedTextSources = textOverlays.filter { references.contains(.text($0.id)) }
        let selectedAudioSources = audioClips.filter { references.contains(.audio($0.id)) }
        let selectedOverlaySources = overlayClips.filter { references.contains(.overlay($0.id)) }
        registerUndoIfNeeded()
        var copiedReferences = Set<EditorTimelineItemReference>()
        var itemCopyMap: [EditorTimelineItemReference: EditorTimelineItemReference] = [:]
        var hostIDMap: [UUID: UUID] = [:]
        var trackIDMap: [UUID: UUID] = [:]
        var copiedTextIDs = Set<UUID>()
        var copiedOverlayIDs = Set<UUID>()

        let primaryIDs = Set(references.filter { $0.kind == .primaryClip }.map(\.itemID))
        for index in clips.indices.reversed() where primaryIDs.contains(clips[index].id) {
            let source = clips[index]
            let boundary = timelineOffsetForClipIndex(index) + source.duration
            let copy = duplicatedPrimaryClip(source)
            clips.insert(copy, at: index + 1)
            rippleInsertTimedItems(at: boundary, duration: copy.duration)
            copiedReferences.insert(.primary(copy.id))
            itemCopyMap[.primary(source.id)] = .primary(copy.id)
            hostIDMap[source.id] = copy.id
            for (oldTrack, newTrack) in zip(source.motionTracks, copy.motionTracks) {
                trackIDMap[oldTrack.id] = newTrack.id
            }
        }
        for source in selectedTextSources {
            let copy = duplicatedTextOverlay(source, timelineOffset: duplicateOffset)
            textOverlays.append(copy)
            copiedReferences.insert(.text(copy.id))
            itemCopyMap[.text(source.id)] = .text(copy.id)
            copiedTextIDs.insert(copy.id)
        }
        for source in selectedAudioSources {
            let copy = EditorAudioClip(
                title: source.title + " Copy", fileURL: source.fileURL,
                originalDuration: source.originalDuration, trimStart: source.trimStart,
                trimEnd: source.trimEnd, timelineStart: source.timelineStart + duplicateOffset,
                laneIndex: source.laneIndex, volume: source.volume,
                fadeInDuration: source.fadeInDuration, fadeOutDuration: source.fadeOutDuration,
                keyframes: source.keyframes, attribution: source.attribution, effect: source.effect
            )
            audioClips.append(copy)
            copiedReferences.insert(.audio(copy.id))
            itemCopyMap[.audio(source.id)] = .audio(copy.id)
        }
        for source in selectedOverlaySources {
            let copy = duplicatedOverlayClip(source, timelineOffset: duplicateOffset)
            overlayClips.append(copy)
            copiedReferences.insert(.overlay(copy.id))
            itemCopyMap[.overlay(source.id)] = .overlay(copy.id)
            copiedOverlayIDs.insert(copy.id)
            hostIDMap[source.id] = copy.id
            for (oldTrack, newTrack) in zip(source.motionTracks, copy.motionTracks) {
                trackIDMap[oldTrack.id] = newTrack.id
            }
        }
        for index in textOverlays.indices where copiedTextIDs.contains(textOverlays[index].id) {
            if let oldHost = textOverlays[index].attachedClipID {
                textOverlays[index].attachedClipID = hostIDMap[oldHost] ?? oldHost
            }
            if let oldTrack = textOverlays[index].attachedTrackID {
                textOverlays[index].attachedTrackID = trackIDMap[oldTrack] ?? oldTrack
            }
        }
        for index in overlayClips.indices where copiedOverlayIDs.contains(overlayClips[index].id) {
            if let oldHost = overlayClips[index].attachedClipID {
                overlayClips[index].attachedClipID = hostIDMap[oldHost] ?? oldHost
            }
            if let oldTrack = overlayClips[index].attachedTrackID {
                overlayClips[index].attachedTrackID = trackIDMap[oldTrack] ?? oldTrack
            }
        }
        let selectedSequenceRoots = selectedTimelineItems.filter { $0.kind == .sequence }
        let copiedSequenceRoots = selectedSequenceRoots.compactMap {
            duplicateSequenceTree(
                sourceID: $0.itemID,
                parentID: activeSequenceID,
                itemCopyMap: itemCopyMap
            )
        }
        if !copiedSequenceRoots.isEmpty {
            if let activeSequenceID,
               let parentIndex = sequences.firstIndex(where: { $0.id == activeSequenceID }) {
                sequences[parentIndex].members.append(
                    contentsOf: copiedSequenceRoots.map(EditorTimelineItemReference.sequence)
                )
            }
            selectedTimelineItems = Set(copiedSequenceRoots.map(EditorTimelineItemReference.sequence))
            selectedSequenceID = copiedSequenceRoots.count == 1 ? copiedSequenceRoots[0] : nil
        } else if copiedReferences.count >= 2 {
            let sourceKind = selectedSequence?.kind ?? .group
            let copySequence = EditorSequence(
                title: "\(selectedSequence?.title ?? "Selection") Copy",
                kind: sourceKind,
                members: Array(copiedReferences).sorted { $0.id < $1.id },
                parentSequenceID: activeSequenceID
            )
            sequences.append(copySequence)
            if let activeSequenceID,
               let parentIndex = sequences.firstIndex(where: { $0.id == activeSequenceID }) {
                sequences[parentIndex].members.append(.sequence(copySequence.id))
            }
            selectedTimelineItems = [.sequence(copySequence.id)]
            selectedSequenceID = copySequence.id
        } else {
            selectedTimelineItems = copiedReferences
            selectedSequenceID = nil
        }
        finishSequenceMutation(rebuildComposition: true)
    }

    private func duplicateSequenceTree(
        sourceID: UUID,
        parentID: UUID?,
        itemCopyMap: [EditorTimelineItemReference: EditorTimelineItemReference],
        visited: Set<UUID> = []
    ) -> UUID? {
        guard !visited.contains(sourceID),
              let source = sequences.first(where: { $0.id == sourceID }) else { return nil }
        var visited = visited
        visited.insert(sourceID)
        let newID = UUID()
        var copiedMembers: [EditorTimelineItemReference] = []
        for member in source.members {
            if member.kind == .sequence,
               let childID = duplicateSequenceTree(
                   sourceID: member.itemID,
                   parentID: newID,
                   itemCopyMap: itemCopyMap,
                   visited: visited
               ) {
                copiedMembers.append(.sequence(childID))
            } else if let copied = itemCopyMap[member] {
                copiedMembers.append(copied)
            }
        }
        guard !copiedMembers.isEmpty else { return nil }
        sequences.append(EditorSequence(
            id: newID,
            title: source.title + " Copy",
            kind: source.kind,
            members: copiedMembers,
            parentSequenceID: parentID
        ))
        return newID
    }

    func timeRange(for reference: EditorTimelineItemReference) -> ClosedRange<TimeInterval>? {
        switch reference.kind {
        case .primaryClip:
            guard let index = clips.firstIndex(where: { $0.id == reference.itemID }) else { return nil }
            let start = timelineOffsetForClipIndex(index)
            return start...(start + clips[index].duration)
        case .textOverlay:
            guard let item = textOverlays.first(where: { $0.id == reference.itemID }) else { return nil }
            return item.startTime...item.endTime
        case .audioClip:
            guard let item = audioClips.first(where: { $0.id == reference.itemID }) else { return nil }
            return item.timelineStart...item.timelineEnd
        case .overlayClip:
            guard let item = overlayClips.first(where: { $0.id == reference.itemID }) else { return nil }
            return item.timelineStart...item.timelineEnd
        case .sequence:
            return sequenceTimeRange(id: reference.itemID)
        }
    }

    func sequenceTimeRange(id: UUID) -> ClosedRange<TimeInterval>? {
        let ranges = leafReferences(in: id).compactMap { timeRange(for: $0) }
        guard let start = ranges.map(\.lowerBound).min(), let end = ranges.map(\.upperBound).max() else { return nil }
        return start...end
    }

    var allLeafReferences: Set<EditorTimelineItemReference> {
        Set(clips.map { EditorTimelineItemReference.primary($0.id) }
            + textOverlays.map { EditorTimelineItemReference.text($0.id) }
            + audioClips.map { EditorTimelineItemReference.audio($0.id) }
            + overlayClips.map { EditorTimelineItemReference.overlay($0.id) })
    }

    private var expandedSelection: Set<EditorTimelineItemReference> {
        var result = Set<EditorTimelineItemReference>()
        for reference in selectedTimelineItems {
            if reference.kind == .sequence {
                result.formUnion(leafReferences(in: reference.itemID))
            } else {
                result.insert(reference)
            }
        }
        return result
    }

    private func leafReferences(in sequenceID: UUID, visited: Set<UUID> = []) -> Set<EditorTimelineItemReference> {
        guard !visited.contains(sequenceID),
              let sequence = sequences.first(where: { $0.id == sequenceID }) else { return [] }
        var visited = visited
        visited.insert(sequenceID)
        var result = Set<EditorTimelineItemReference>()
        for member in sequence.members {
            if member.kind == .sequence {
                result.formUnion(leafReferences(in: member.itemID, visited: visited))
            } else if allLeafReferences.contains(member) {
                result.insert(member)
            }
        }
        return result
    }

    func pruneSequenceStructure() {
        let leaves = allLeafReferences
        var didChange = true
        while didChange {
            didChange = false
            let validIDs = Set(sequences.map(\.id))
            for index in sequences.indices {
                let oldCount = sequences[index].members.count
                sequences[index].members.removeAll {
                    $0.kind == .sequence ? !validIDs.contains($0.itemID) : !leaves.contains($0)
                }
                didChange = didChange || sequences[index].members.count != oldCount
            }
            let oldSequenceCount = sequences.count
            sequences.removeAll { $0.members.isEmpty }
            didChange = didChange || sequences.count != oldSequenceCount
        }
        let validSequenceIDs = Set(sequences.map(\.id))
        for index in sequences.indices where sequences[index].parentSequenceID.map({ !validSequenceIDs.contains($0) }) == true {
            sequences[index].parentSequenceID = nil
        }
        if let activeSequenceID, !validSequenceIDs.contains(activeSequenceID) { self.activeSequenceID = nil }
        if let selectedSequenceID, !validSequenceIDs.contains(selectedSequenceID) {
            self.selectedSequenceID = nil
            selectedTimelineItems.remove(.sequence(selectedSequenceID))
        }
    }

    func remapSequenceMembershipAfterSplit(
        original: EditorTimelineItemReference,
        right: EditorTimelineItemReference
    ) {
        for index in sequences.indices {
            guard let memberIndex = sequences[index].members.firstIndex(of: original),
                  !sequences[index].members.contains(right) else { continue }
            sequences[index].members.insert(right, at: memberIndex + 1)
        }
        if selectedTimelineItems.contains(original) { selectedTimelineItems.insert(right) }
    }

    func remapSequenceMembershipForFreeze(
        originalID: UUID,
        displayedIDs: [UUID]
    ) {
        remapSequenceMembershipForFreeze(
            original: .primary(originalID),
            replacements: displayedIDs.map(EditorTimelineItemReference.primary)
        )
    }

    func remapSequenceMembershipForFreeze(
        original: EditorTimelineItemReference,
        replacements: [EditorTimelineItemReference]
    ) {
        for index in sequences.indices {
            guard let memberIndex = sequences[index].members.firstIndex(of: original) else { continue }
            sequences[index].members.remove(at: memberIndex)
            var insertionIndex = memberIndex
            for replacement in replacements where !sequences[index].members.contains(replacement) {
                sequences[index].members.insert(replacement, at: insertionIndex)
                insertionIndex += 1
            }
        }
        if selectedTimelineItems.contains(original) {
            selectedTimelineItems.formUnion(replacements)
        }
    }

    private func finishSequenceMutation(rebuildComposition: Bool) {
        timelinePosition = min(max(0, timelinePosition), totalDuration)
        normalizeExportRange()
        if rebuildComposition { invalidateComposition() }
        scheduleSave()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if rebuildComposition { Task { await alignPlaybackToTimeline() } }
    }

    private func duplicatedPrimaryClip(_ source: EditorClip) -> EditorClip {
        EditorClip(
            asset: source.asset, originalDuration: source.originalDuration,
            trimStart: source.trimStart, trimEnd: source.trimEnd, speed: source.speed,
            speedRamp: source.speedRamp, playback: source.playback, volume: source.volume,
            audioTrimStart: source.audioTrimStart, audioTrimEnd: source.audioTrimEnd,
            isAudioLinked: source.isAudioLinked, cropAspect: source.cropAspect,
            reframeMode: source.reframeMode, rotationQuarterTurns: source.rotationQuarterTurns,
            straightenDegrees: source.straightenDegrees,
            isFlippedHorizontally: source.isFlippedHorizontally,
            isFlippedVertically: source.isFlippedVertically,
            reframeScale: source.reframeScale, reframeXOffset: source.reframeXOffset,
            reframeYOffset: source.reframeYOffset, colorAdjustment: source.colorAdjustment,
            effects: source.effects,
            compositing: source.compositing, keyframes: source.keyframes,
            motionTracks: source.motionTracks.map { track in var copy = track; copy.id = UUID(); return copy },
            stabilization: source.stabilization, transitionKind: source.transitionKind,
            transitionDuration: source.transitionDuration
        )
    }

    private func duplicatedTextOverlay(
        _ source: EditorTextOverlay,
        timelineOffset offset: TimeInterval
    ) -> EditorTextOverlay {
        return EditorTextOverlay(
            text: source.text, startTime: source.startTime + offset, endTime: source.endTime + offset,
            fontSize: source.fontSize, fontFamily: source.fontFamily, fontStyle: source.fontStyle,
            textColor: source.textColor, opacity: source.opacity,
            horizontalAlignment: source.horizontalAlignment, verticalAlignment: source.verticalAlignment,
            xOffset: source.xOffset, yOffset: source.yOffset, keyframes: source.keyframes,
            animation: source.animation, attachedClipID: source.attachedClipID,
            attachedTrackID: source.attachedTrackID, attachRotation: source.attachRotation,
            attachScale: source.attachScale,
            captionWords: source.captionWords.map {
                EditorCaptionWord(text: $0.text, startTime: $0.startTime + offset,
                                  endTime: $0.endTime + offset, confidence: $0.confidence)
            },
            captionHighlightColor: source.captionHighlightColor,
            captionLocaleIdentifier: source.captionLocaleIdentifier,
            trackedRotationDegrees: source.trackedRotationDegrees
        )
    }

    private func duplicatedOverlayClip(
        _ source: EditorOverlayClip,
        timelineOffset: TimeInterval
    ) -> EditorOverlayClip {
        EditorOverlayClip(
            asset: source.asset, originalDuration: source.originalDuration,
            trimStart: source.trimStart, trimEnd: source.trimEnd,
            timelineStart: source.timelineStart + timelineOffset,
            laneIndex: source.laneIndex, zIndex: source.zIndex,
            speed: source.speed, playback: source.playback,
            scale: source.scale, xOffset: source.xOffset,
            yOffset: source.yOffset, opacity: source.opacity, volume: source.volume,
            cropAspect: source.cropAspect, reframeMode: source.reframeMode,
            rotationQuarterTurns: source.rotationQuarterTurns,
            straightenDegrees: source.straightenDegrees,
            isFlippedHorizontally: source.isFlippedHorizontally,
            isFlippedVertically: source.isFlippedVertically,
            reframeScale: source.reframeScale, reframeXOffset: source.reframeXOffset,
            reframeYOffset: source.reframeYOffset, colorAdjustment: source.colorAdjustment,
            effects: source.effects,
            compositing: source.compositing, keyframes: source.keyframes,
            motionTracks: source.motionTracks.map { track in var copy = track; copy.id = UUID(); return copy },
            stabilization: source.stabilization, attachedClipID: source.attachedClipID,
            attachedTrackID: source.attachedTrackID, attachRotation: source.attachRotation,
            attachScale: source.attachScale
        )
    }
}
