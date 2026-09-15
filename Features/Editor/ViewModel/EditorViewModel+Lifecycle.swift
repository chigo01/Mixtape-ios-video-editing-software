//
//  EditorViewModel+Lifecycle.swift
//  Mixtape
//

import SwiftUI
import UIKit
import AVFoundation
import Photos

extension EditorViewModel {
    // MARK: Lifecycle

    func setupPlayer() async {
        await refreshMediaCacheStats()
        await alignPlaybackToTimeline()
        if proxySettings.isEnabled && proxySettings.automaticallyGenerate {
            generateMissingProxies()
        }
    }

    func teardownPlayer() {
        previewRequestID = UUID()
        previewBuilds.cancel()
        cancelCopilot()
        stopPlaybackTicking()
        removeEndObserver()
        player?.pause()
        player = nil
        compositionFingerprint = nil
        saveTask?.cancel()
        exportTask?.cancel()
        proxyGenerationTask?.cancel()
        renderCacheTask?.cancel()
        Task { await EditorMediaCache.shared.cancelWork() }
        cancelReverseGeneration()
        cancelCaptionTranscription()
        cancelMotionTracking()
        cancelColorMaskTracking()
        EditorExportService.cancelCurrentExport()
        EditorCompositionBuilder.clearCaches()
        isPlaying = false
    }
}
