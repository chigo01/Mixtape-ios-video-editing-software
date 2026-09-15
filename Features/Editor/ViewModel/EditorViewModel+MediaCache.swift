//
//  EditorViewModel+MediaCache.swift
//  Mixtape
//

import SwiftUI
import UIKit
import AVFoundation
import Photos

extension EditorViewModel {
    // MARK: Proxy and render cache

    func saveCurrentProjectAsTemplate(named name: String) async throws -> EditorProjectTemplate {
        let template = try await EditorTemplateStore.shared.save(project: makeProject(), name: name)
        templateStatusMessage = "Saved “\(template.name)” with \(template.slots.count) replaceable slots."
        return template
    }

    func applyTemplate(_ template: EditorProjectTemplate) throws {
        registerUndoIfNeeded()
        pausePlaybackForEdit()
        var project = try EditorTemplateStore.shared.materializedProject(
            from: template,
            destinationProjectID: projectID
        )
        let primaryAssets = clips.map(\.asset)
        let overlayAssets = overlayClips.map(\.asset)
        let primarySlots = template.slots.filter { $0.role == .primary }
            .sorted { $0.order < $1.order }
        let overlaySlots = template.slots.filter { $0.role == .overlay }
            .sorted { $0.order < $1.order }

        for index in project.clips.indices where primaryAssets.indices.contains(index) {
            let targetDuration = primarySlots.first {
                $0.itemID == project.clips[index].id
            }?.targetDuration
            rebindTemplatePrimary(
                &project.clips[index],
                to: primaryAssets[index],
                targetDuration: targetDuration
            )
        }
        for index in project.overlayClips.indices where overlayAssets.indices.contains(index) {
            let targetDuration = overlaySlots.first {
                $0.itemID == project.overlayClips[index].id
            }?.targetDuration
            rebindTemplateOverlay(
                &project.overlayClips[index],
                to: overlayAssets[index],
                targetDuration: targetDuration
            )
        }

        clips = EditorProjectResolver.clips(from: project.clips)
        overlayClips = EditorProjectResolver.overlayClips(from: project.overlayClips)
        textOverlays = project.textOverlays.map { $0.toOverlay() }
        graphicOverlays = project.graphicOverlays.filter { overlay in
            if case let .image(path) = overlay.source {
                return FileManager.default.fileExists(atPath: path)
            }
            return true
        }
        audioClips = project.audioClips.compactMap { $0.toAudioClip() }
        adjustmentLayers = project.adjustmentLayers
        openingTransitionKind = project.openingTransitionKind
        openingTransitionDuration = project.openingTransitionDuration
        closingTransitionKind = project.closingTransitionKind
        closingTransitionDuration = project.closingTransitionDuration
        canvasSettings = project.canvasSettings
        exportInPoint = project.exportInPoint
        exportOutPoint = project.exportOutPoint
        audioTrackSettings = project.audioTrackSettings
        masterVolume = project.masterVolume
        sequences = project.sequences
        markers = project.markers
        selectedTimelineItems = []
        selectedSequenceID = nil
        activeSequenceID = nil
        isMultiSelectMode = false
        selectedClipID = clips.first?.id
        selectedTextOverlayID = nil
        selectedGraphicOverlayID = nil
        selectedAudioClipID = nil
        selectedOverlayClipID = nil
        selectedAdjustmentLayerID = nil
        selectedVisualEffectID = nil
        timelinePosition = 0
        selectedTool = nil
        normalizeExportRange()
        pruneSequenceStructure()
        invalidateComposition()
        scheduleSave()
        refreshUndoState()
        templateStatusMessage = "Applied “\(template.name)”. Your media filled slots in timeline order."
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task { await alignPlaybackToTimeline() }
    }

    private func rebindTemplatePrimary(
        _ saved: inout SavedEditorClip,
        to asset: PHAsset,
        targetDuration: TimeInterval?
    ) {
        let oldSourceSpan = max(0.05, saved.trimEnd - saved.trimStart)
        let target = max(0.05, targetDuration ?? oldSourceSpan / TimeInterval(max(saved.speed, 0.01)))
        let rawDuration = asset.mediaType == .video ? asset.duration : EditorClip.photoDefaultDuration
        let sourceSpan = min(rawDuration, oldSourceSpan)
        saved.assetLocalIdentifier = asset.localIdentifier
        saved.originalDuration = rawDuration
        saved.trimStart = 0
        saved.trimEnd = sourceSpan
        if asset.mediaType != .video || sourceSpan + 0.001 < oldSourceSpan {
            saved.speedRamp = nil
            saved.playback = .forward
            saved.speed = Float(max(0.05, sourceSpan / target))
            saved.motionTracks = []
            saved.stabilization = .disabled
        }
    }

    private func rebindTemplateOverlay(
        _ saved: inout SavedOverlayClip,
        to asset: PHAsset,
        targetDuration: TimeInterval?
    ) {
        let oldSourceSpan = max(0.05, saved.trimEnd - saved.trimStart)
        let target = max(0.05, targetDuration ?? oldSourceSpan / TimeInterval(max(saved.speed, 0.01)))
        let rawDuration = asset.mediaType == .video ? asset.duration : EditorClip.photoDefaultDuration
        let sourceSpan = min(rawDuration, oldSourceSpan)
        saved.assetLocalIdentifier = asset.localIdentifier
        saved.originalDuration = rawDuration
        saved.trimStart = 0
        saved.trimEnd = sourceSpan
        if asset.mediaType != .video || sourceSpan + 0.001 < oldSourceSpan {
            saved.playback = .forward
            saved.speed = Float(max(0.05, sourceSpan / target))
            saved.motionTracks = []
            saved.stabilization = .disabled
        }
    }

    func setProxyEnabled(_ enabled: Bool) {
        guard proxySettings.isEnabled != enabled else { return }
        proxySettings.isEnabled = enabled
        if !enabled {
            proxyGenerationTask?.cancel()
            Task { await EditorMediaCache.shared.cancelWork() }
        }
        compositionFingerprint = nil
        scheduleSave()
        if enabled && proxySettings.automaticallyGenerate { generateMissingProxies() }
    }

    func setAutomaticProxyGeneration(_ enabled: Bool) {
        proxySettings.automaticallyGenerate = enabled
        scheduleSave()
        if enabled && proxySettings.isEnabled { generateMissingProxies() }
    }

    func setBackgroundRenderCache(_ enabled: Bool) {
        proxySettings.backgroundRenderCache = enabled
        renderCacheTask?.cancel()
        compositionFingerprint = nil
        scheduleSave()
        if enabled { scheduleBackgroundRenderCache(delay: .milliseconds(250)) }
    }

    func setProxyQuality(_ quality: EditorProxyQuality) {
        guard proxySettings.quality != quality else { return }
        proxySettings.quality = quality
        compositionFingerprint = nil
        scheduleSave()
        if proxySettings.isEnabled && proxySettings.automaticallyGenerate { generateMissingProxies() }
    }

    func setMediaCacheBudgetMB(_ megabytes: Int) {
        proxySettings.cacheBudgetMB = min(max(megabytes, 256), 16_384)
        scheduleSave()
    }

    func generateMissingProxies() {
        proxyGenerationTask?.cancel()
        let quality = proxySettings.quality
        let budget = proxySettings.cacheBudgetMB
        var assetsByIdentifier: [String: PHAsset] = [:]
        for clip in clips where clip.isVideo {
            assetsByIdentifier[clip.asset.localIdentifier] = clip.asset
        }
        for overlay in overlayClips where overlay.asset.mediaType == .video {
            assetsByIdentifier[overlay.asset.localIdentifier] = overlay.asset
        }
        let assets = assetsByIdentifier.values.sorted {
            $0.localIdentifier < $1.localIdentifier
        }
        guard !assets.isEmpty else {
            cacheStatusMessage = "No video media needs a proxy."
            return
        }

        proxyGenerationTask = Task {
            proxyGenerationProgress = 0
            cacheStatusMessage = "Preparing performance media…"
            var completed = 0
            var generated = 0
            do {
                for asset in assets {
                    try Task.checkCancellation()
                    if EditorMediaCache.cachedProxyURL(for: asset, quality: quality) == nil {
                        _ = try await EditorMediaCache.shared.generateProxy(
                            for: asset,
                            quality: quality,
                            budgetMB: budget
                        )
                        generated += 1
                    }
                    completed += 1
                    proxyGenerationProgress = Double(completed) / Double(assets.count)
                }
                compositionFingerprint = nil
                cacheStatusMessage = generated == 0
                    ? "Performance media is already ready."
                    : "Generated \(generated) \(generated == 1 ? "proxy" : "proxies")."
                await refreshMediaCacheStats()
                scheduleBackgroundRenderCache(delay: .milliseconds(250))
            } catch is CancellationError {
                cacheStatusMessage = "Proxy generation cancelled."
            } catch {
                cacheStatusMessage = error.localizedDescription
            }
            proxyGenerationProgress = nil
        }
    }

    func buildRenderCacheNow() {
        scheduleBackgroundRenderCache(delay: .zero, userInitiated: true)
    }

    func clearProxyCache() {
        proxyGenerationTask?.cancel()
        Task {
            await EditorMediaCache.shared.clearProxies()
            compositionFingerprint = nil
            cacheStatusMessage = "Proxy cache cleared. Originals are untouched."
            await refreshMediaCacheStats()
        }
    }

    func clearRenderCache() {
        renderCacheTask?.cancel()
        Task {
            await EditorMediaCache.shared.clearRenders()
            compositionFingerprint = nil
            isBuildingRenderCache = false
            cacheStatusMessage = "Preview render cache cleared."
            await refreshMediaCacheStats()
        }
    }

    func refreshMediaCacheStats() async {
        mediaCacheStats = await EditorMediaCache.shared.stats()
    }

    func scheduleBackgroundRenderCache(
        delay: Duration = .seconds(3),
        userInitiated: Bool = false
    ) {
        guard !isCopilotPreview else { return }
        renderCacheTask?.cancel()
        guard proxySettings.backgroundRenderCache, !clips.isEmpty else { return }
        let fingerprint = renderCacheFingerprint()
        if EditorMediaCache.cachedRenderURL(for: fingerprint) != nil {
            Task { await refreshMediaCacheStats() }
            return
        }
        let settings = proxySettings
        let clipsSnapshot = clips
        let graphicOverlaysSnapshot = graphicOverlays
        let audioClipsSnapshot = audioClips
        let overlayClipsSnapshot = overlayClips
        let adjustmentLayersSnapshot = adjustmentLayers
        let openingKindSnapshot = openingTransitionKind
        let openingDurationSnapshot = openingTransitionDuration
        let closingKindSnapshot = closingTransitionKind
        let closingDurationSnapshot = closingTransitionDuration
        let canvasSnapshot = canvasSettings
        let audioTrackSettingsSnapshot = audioTrackSettings
        let masterVolumeSnapshot = masterVolume

        renderCacheTask = Task(priority: userInitiated ? .userInitiated : .utility) {
            do {
                try await Task.sleep(for: delay)
                try Task.checkCancellation()
                guard fingerprint == renderCacheFingerprint() else { return }
                isBuildingRenderCache = true
                cacheStatusMessage = "Rendering smooth playback cache…"
                guard let built = await EditorCompositionBuilder.build(
                    from: clipsSnapshot,
                    graphicOverlays: graphicOverlaysSnapshot,
                    audioClips: audioClipsSnapshot,
                    overlayClips: overlayClipsSnapshot,
                    adjustmentLayers: adjustmentLayersSnapshot,
                    openingTransitionKind: openingKindSnapshot,
                    openingTransitionDuration: openingDurationSnapshot,
                    closingTransitionKind: closingKindSnapshot,
                    closingTransitionDuration: closingDurationSnapshot,
                    canvasSettings: canvasSnapshot,
                    canvasSize: canvasSnapshot.renderSize(longEdge: 960),
                    proxySettings: settings,
                    audioTrackSettings: audioTrackSettingsSnapshot,
                    masterVolume: masterVolumeSnapshot
                ) else { throw EditorMediaCacheError.cannotCreateExporter }
                _ = try await EditorMediaCache.shared.generateRender(
                    built: built,
                    fingerprint: fingerprint,
                    budgetMB: settings.cacheBudgetMB
                )
                guard fingerprint == renderCacheFingerprint() else { return }
                compositionFingerprint = nil
                cacheStatusMessage = "Smooth playback cache is ready."
                await refreshMediaCacheStats()
            } catch is CancellationError {
                // Normal while edits are still arriving; the latest edit schedules a replacement.
            } catch {
                cacheStatusMessage = error.localizedDescription
            }
            isBuildingRenderCache = false
        }
    }
}
