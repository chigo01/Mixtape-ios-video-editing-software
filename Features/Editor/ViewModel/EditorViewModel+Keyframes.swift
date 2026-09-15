//
//  EditorViewModel+Keyframes.swift
//  Mixtape
//

import SwiftUI
import UIKit
import AVFoundation
import Photos

extension EditorViewModel {
    // MARK: Keyframes

    var availableKeyframeProperties: [EditorKeyframeProperty] {
        if selectedOverlayClip != nil {
            return [
                .positionX, .positionY, .scale, .rotation, .opacity, .volume,
                .cropX, .cropY, .cropScale, .filterIntensity, .effectAmount
            ]
        }
        if selectedAudioClip != nil { return [.volume] }
        if selectedTextOverlay != nil {
            return [.textPositionX, .textPositionY, .textScale, .textRotation, .opacity, .effectAmount]
        }
        if selectedClip != nil {
            return [
                .positionX, .positionY, .scale, .rotation, .opacity, .volume,
                .cropX, .cropY, .cropScale, .filterIntensity, .effectAmount
            ]
        }
        return []
    }

    var keyframeTargetTitle: String {
        if selectedOverlayClip != nil { return "Media Overlay" }
        if selectedAudioClip != nil { return "Audio" }
        if selectedTextOverlay != nil { return "Text" }
        return "Clip"
    }

    var keyframeTargetDuration: TimeInterval {
        if let overlay = selectedOverlayClip { return overlay.duration }
        if let audio = selectedAudioClip { return audio.duration }
        if let text = selectedTextOverlay { return text.duration }
        return selectedClip?.duration ?? 0
    }

    var keyframeLocalTime: TimeInterval {
        min(
            max(0, timelinePosition - selectedKeyframeTargetStartTime),
            keyframeTargetDuration
        )
    }

    func selectedKeyframeTrack(for property: EditorKeyframeProperty) -> EditorKeyframeTrack {
        selectedKeyframeTracks.track(for: property)
    }

    func selectedKeyframeValue(for property: EditorKeyframeProperty) -> Double {
        selectedKeyframeTracks.value(
            for: property,
            at: keyframeLocalTime,
            default: keyframeBaseValue(for: property)
        )
    }

    @discardableResult
    func upsertSelectedKeyframe(
        property: EditorKeyframeProperty,
        value: Double,
        curve: EditorKeyframeCurve = .linear
    ) -> UUID? {
        guard availableKeyframeProperties.contains(property) else { return nil }
        registerUndoIfNeeded()
        var tracks = selectedKeyframeTracks
        var track = tracks.track(for: property)
        let id = track.upsert(at: keyframeLocalTime, value: value, curve: curve)
        tracks.replace(track)
        setSelectedKeyframeTracks(tracks)
        finishKeyframeMutation()
        return id
    }

    func updateSelectedKeyframe(
        property: EditorKeyframeProperty,
        id: UUID,
        time: TimeInterval? = nil,
        value: Double? = nil
    ) {
        var tracks = selectedKeyframeTracks
        var track = tracks.track(for: property)
        guard track.keyframes.contains(where: { $0.id == id }) else { return }
        registerUndoIfNeeded()
        track.update(
            id: id,
            time: time.map { min(max(0, $0), keyframeTargetDuration) },
            value: value
        )
        tracks.replace(track)
        setSelectedKeyframeTracks(tracks)
        finishKeyframeMutation()
    }

    func updateSelectedKeyframeCurve(
        property: EditorKeyframeProperty,
        id: UUID,
        curve: EditorKeyframeCurve
    ) {
        var tracks = selectedKeyframeTracks
        var track = tracks.track(for: property)
        guard track.keyframes.contains(where: { $0.id == id }) else { return }
        registerUndoIfNeeded()
        track.updateCurve(id: id, curve: curve)
        tracks.replace(track)
        setSelectedKeyframeTracks(tracks)
        finishKeyframeMutation()
    }

    func deleteSelectedKeyframe(property: EditorKeyframeProperty, id: UUID) {
        var tracks = selectedKeyframeTracks
        var track = tracks.track(for: property)
        guard track.keyframes.contains(where: { $0.id == id }) else { return }
        registerUndoIfNeeded()
        track.remove(id: id)
        tracks.replace(track)
        setSelectedKeyframeTracks(tracks)
        finishKeyframeMutation()
    }

    func seekToSelectedKeyframe(localTime: TimeInterval) {
        scrubSelectedKeyframePlayhead(to: localTime)
        commitSelectedKeyframePlayhead()
    }

    func scrubSelectedKeyframePlayhead(to localTime: TimeInterval) {
        if isPlaying {
            stopPlaybackTicking()
            player?.pause()
            isPlaying = false
        }
        timelinePosition = min(
            max(
                0,
                selectedKeyframeTargetStartTime
                    + min(max(0, localTime), keyframeTargetDuration)
            ),
            totalDuration
        )
        if compositionFingerprint != nil {
            player?.seek(
                to: CMTime(seconds: timelinePosition, preferredTimescale: 600),
                toleranceBefore: .zero, toleranceAfter: .zero
            )
        }
    }

    func commitSelectedKeyframePlayhead() {
        commitTimelineAfterScrub()
    }

    private var selectedKeyframeTracks: EditorKeyframeTracks {
        if let overlay = selectedOverlayClip { return overlay.keyframes }
        if let audio = selectedAudioClip { return audio.keyframes }
        if let text = selectedTextOverlay { return text.keyframes }
        return selectedClip?.keyframes ?? .empty
    }

    private var selectedKeyframeTargetStartTime: TimeInterval {
        if let overlay = selectedOverlayClip { return overlay.timelineStart }
        if let audio = selectedAudioClip { return audio.timelineStart }
        if let text = selectedTextOverlay { return text.startTime }
        if let id = selectedClipID,
           let index = clips.firstIndex(where: { $0.id == id }) {
            return timelineOffsetForClipIndex(index)
        }
        return 0
    }

    private func setSelectedKeyframeTracks(_ tracks: EditorKeyframeTracks) {
        if let id = selectedOverlayClipID,
           let index = overlayClips.firstIndex(where: { $0.id == id }) {
            overlayClips[index].keyframes = tracks
        } else if let id = selectedAudioClipID,
                  let index = audioClips.firstIndex(where: { $0.id == id }) {
            audioClips[index].keyframes = tracks
        } else if let id = selectedTextOverlayID,
                  let index = textOverlays.firstIndex(where: { $0.id == id }) {
            textOverlays[index].keyframes = tracks
        } else if let id = selectedClipID,
                  let index = clips.firstIndex(where: { $0.id == id }) {
            clips[index].keyframes = tracks
        }
    }

    private func keyframeBaseValue(for property: EditorKeyframeProperty) -> Double {
        if let overlay = selectedOverlayClip {
            switch property {
            case .positionX: return Double(overlay.xOffset)
            case .positionY: return Double(overlay.yOffset)
            case .scale: return Double(overlay.scale)
            case .rotation: return overlay.straightenDegrees
            case .opacity: return overlay.opacity
            case .volume: return Double(overlay.volume)
            case .cropX: return Double(overlay.reframeXOffset)
            case .cropY: return Double(overlay.reframeYOffset)
            case .cropScale: return Double(overlay.reframeScale)
            case .filterIntensity: return overlay.colorAdjustment.presetIntensity
            default: return property.neutralValue
            }
        }
        if let audio = selectedAudioClip {
            return property == .volume ? Double(audio.volume) : property.neutralValue
        }
        if let text = selectedTextOverlay {
            switch property {
            case .textPositionX: return Double(text.xOffset)
            case .textPositionY: return Double(text.yOffset)
            case .opacity: return text.opacity
            default: return property.neutralValue
            }
        }
        if let clip = selectedClip {
            switch property {
            case .positionX: return Double(clip.reframeXOffset)
            case .positionY: return Double(clip.reframeYOffset)
            case .scale: return Double(clip.reframeScale)
            case .rotation: return clip.straightenDegrees
            case .volume: return Double(clip.volume)
            case .cropX: return Double(clip.reframeXOffset)
            case .cropY: return Double(clip.reframeYOffset)
            case .cropScale: return Double(clip.reframeScale)
            case .filterIntensity: return clip.colorAdjustment.presetIntensity
            default: return property.neutralValue
            }
        }
        return property.neutralValue
    }

    private func finishKeyframeMutation() {
        invalidateComposition()
        scheduleSave()
        Task { await alignPlaybackToTimeline() }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}
