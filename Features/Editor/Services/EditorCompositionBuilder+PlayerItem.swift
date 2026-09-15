//
//  EditorCompositionBuilder+PlayerItem.swift
//  Mixtape
//

import AVFoundation
import Photos
import UIKit

extension EditorCompositionBuilder {
    static func makePlayerItem(
        from clips: [EditorClip],
        graphicOverlays: [EditorGraphicOverlay] = [],
        audioClips: [EditorAudioClip] = [],
        overlayClips: [EditorOverlayClip] = [],
        adjustmentLayers: [EditorAdjustmentLayer] = [],
        openingTransitionKind: EditorTransitionKind = .none,
        openingTransitionDuration: TimeInterval = 0,
        closingTransitionKind: EditorTransitionKind = .none,
        closingTransitionDuration: TimeInterval = 0,
        canvasSettings: EditorCanvasSettings = .default,
        audioTrackSettings: [Int: EditorAudioTrackSettings] = [:],
        masterVolume: Float = 1.0,
        proxySettings: EditorProxySettings = .default,
        renderCacheFingerprint: String? = nil
    ) async -> AVPlayerItem? {
        if proxySettings.backgroundRenderCache,
           let renderCacheFingerprint,
           let cached = EditorMediaCache.cachedRenderURL(for: renderCacheFingerprint) {
            let item = AVPlayerItem(url: cached)
            item.audioTimePitchAlgorithm = .spectral
            return item
        }
        guard let built = await build(
            from: clips,
            graphicOverlays: graphicOverlays,
            audioClips: audioClips,
            overlayClips: overlayClips,
            adjustmentLayers: adjustmentLayers,
            openingTransitionKind: openingTransitionKind,
            openingTransitionDuration: openingTransitionDuration,
            closingTransitionKind: closingTransitionKind,
            closingTransitionDuration: closingTransitionDuration,
            canvasSettings: canvasSettings,
            canvasSize: canvasSettings.renderSize(longEdge: 1920),
            proxySettings: proxySettings,
            audioTrackSettings: audioTrackSettings,
            masterVolume: masterVolume
        ) else { return nil }

        let item = await AVPlayerItem(asset: built.composition)
        await MainActor.run {
            item.audioTimePitchAlgorithm = .spectral
            item.videoComposition = built.videoComposition
            item.audioMix = built.audioMix
        }
        return item
    }
}
