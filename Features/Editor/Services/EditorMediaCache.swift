//
//  EditorMediaCache.swift
//  Mixtape
//

import AVFoundation
import Photos
import UIKit

// MARK: - Proxy and preview render cache

struct EditorMediaCacheStats: Equatable, Sendable {
    var proxyBytes: Int64 = 0
    var renderBytes: Int64 = 0
    var proxyCount = 0
    var renderCount = 0

    static let empty = EditorMediaCacheStats()
    var totalBytes: Int64 { proxyBytes + renderBytes }
}

enum EditorMediaCacheError: LocalizedError {
    case sourceUnavailable
    case cannotCreateExporter
    case lowStorage
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .sourceUnavailable: return "The original media is not available from Photos."
        case .cannotCreateExporter: return "This media cannot be encoded on this device."
        case .lowStorage: return "Proxy generation paused because device storage is low."
        case let .exportFailed(message): return message
        }
    }
}

/// Owns disposable performance media. Files are deterministic and versioned by
/// source identity, source metadata, and proxy profile. Project documents retain
/// only Photos identifiers; originals therefore remain authoritative and cache
/// eviction can never make a project unexportable.
actor EditorMediaCache {
    static let shared = EditorMediaCache()

    private static let proxyFolder = "MixtapeProxies-v1"
    private static let renderFolder = "MixtapePreviewRenders-v1"
    private var activeProxyExports: [String: AVAssetExportSession] = [:]
    private var activeRenderExport: AVAssetExportSession?

    static func cachedProxyURL(for asset: PHAsset, quality: EditorProxyQuality) -> URL? {
        let url = directory(named: proxyFolder)
            .appendingPathComponent("\(proxyKey(for: asset, quality: quality)).mp4")
        guard usable(url) else { return nil }
        touch(url)
        return url
    }

    static func cachedRenderURL(for fingerprint: String) -> URL? {
        let url = directory(named: renderFolder)
            .appendingPathComponent("\(stableHash(fingerprint)).mp4")
        guard usable(url) else { return nil }
        touch(url)
        return url
    }

    func generateProxy(
        for asset: PHAsset,
        quality: EditorProxyQuality,
        budgetMB: Int
    ) async throws -> URL {
        if let cached = Self.cachedProxyURL(for: asset, quality: quality) {
            Self.touch(cached)
            return cached
        }
        try Self.requireWorkingStorage()
        let source = try await Self.requestOriginalAsset(for: asset)
        guard let exporter = AVAssetExportSession(asset: source, presetName: quality.exportPreset) else {
            throw EditorMediaCacheError.cannotCreateExporter
        }
        let key = Self.proxyKey(for: asset, quality: quality)
        let output = Self.directory(named: Self.proxyFolder).appendingPathComponent("\(key).mp4")
        let temporary = output.deletingLastPathComponent()
            .appendingPathComponent(".\(key)-\(UUID().uuidString).tmp.mp4")
        try? FileManager.default.removeItem(at: temporary)
        defer { try? FileManager.default.removeItem(at: temporary) }
        exporter.shouldOptimizeForNetworkUse = true
        activeProxyExports[asset.localIdentifier] = exporter
        defer { activeProxyExports[asset.localIdentifier] = nil }

        try await exporter.export(to: temporary, as: .mp4)
        try Task.checkCancellation()
        try? FileManager.default.removeItem(at: output)
        try FileManager.default.moveItem(at: temporary, to: output)
        Self.excludeFromBackup(output)
        await enforceBudget(megabytes: budgetMB, protecting: output)
        return output
    }

    func generateRender(
        built: EditorCompositionBuildResult,
        fingerprint: String,
        budgetMB: Int
    ) async throws -> URL {
        if let cached = Self.cachedRenderURL(for: fingerprint) {
            Self.touch(cached)
            return cached
        }
        try Self.requireWorkingStorage()
        guard let exporter = AVAssetExportSession(
            asset: built.composition,
            presetName: AVAssetExportPreset960x540
        ) else { throw EditorMediaCacheError.cannotCreateExporter }
        exporter.videoComposition = built.videoComposition
        exporter.audioMix = built.audioMix
        exporter.shouldOptimizeForNetworkUse = false
        let key = Self.stableHash(fingerprint)
        let output = Self.directory(named: Self.renderFolder).appendingPathComponent("\(key).mp4")
        let temporary = output.deletingLastPathComponent()
            .appendingPathComponent(".\(key)-\(UUID().uuidString).tmp.mp4")
        try? FileManager.default.removeItem(at: temporary)
        defer { try? FileManager.default.removeItem(at: temporary) }
        activeRenderExport?.cancelExport()
        activeRenderExport = exporter
        defer { if activeRenderExport === exporter { activeRenderExport = nil } }

        try await exporter.export(to: temporary, as: .mp4)
        try Task.checkCancellation()
        try? FileManager.default.removeItem(at: output)
        try FileManager.default.moveItem(at: temporary, to: output)
        Self.excludeFromBackup(output)
        await enforceBudget(megabytes: budgetMB, protecting: output)
        return output
    }

    func cancelWork() {
        activeProxyExports.values.forEach { $0.cancelExport() }
        activeProxyExports.removeAll()
        activeRenderExport?.cancelExport()
        activeRenderExport = nil
    }

    /// Settings only removes regenerable performance files, never project-owned media.
    /// Reject cleanup while an exporter is writing, including across actor suspension points.
    func clearDisposableCache() throws {
        guard activeProxyExports.isEmpty, activeRenderExport == nil else {
            throw NSError(domain: "MixtapeCache", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Preview files are still being generated. Try clearing the cache again in a moment."
            ])
        }
        for name in [Self.proxyFolder, Self.renderFolder] {
            let directory = Self.directory(named: name)
            let files = try FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
            )
            for file in files { try FileManager.default.removeItem(at: file) }
        }
    }

    func clearProxies() { Self.clear(directoryNamed: Self.proxyFolder) }
    func clearRenders() { Self.clear(directoryNamed: Self.renderFolder) }

    func stats() -> EditorMediaCacheStats {
        let proxies = Self.files(in: Self.directory(named: Self.proxyFolder))
        let renders = Self.files(in: Self.directory(named: Self.renderFolder))
        return EditorMediaCacheStats(
            proxyBytes: proxies.reduce(0) { $0 + Self.fileSize($1) },
            renderBytes: renders.reduce(0) { $0 + Self.fileSize($1) },
            proxyCount: proxies.count,
            renderCount: renders.count
        )
    }

    private func enforceBudget(megabytes: Int, protecting protectedURL: URL) async {
        let byteLimit = Int64(min(max(megabytes, 256), 16_384)) * 1_024 * 1_024
        var candidates = Self.files(in: Self.directory(named: Self.proxyFolder))
            + Self.files(in: Self.directory(named: Self.renderFolder))
        var total = candidates.reduce(Int64(0)) { $0 + Self.fileSize($1) }
        candidates.sort { Self.modifiedDate($0) < Self.modifiedDate($1) }
        for url in candidates where total > byteLimit && url != protectedURL {
            let bytes = Self.fileSize(url)
            try? FileManager.default.removeItem(at: url)
            total -= bytes
        }
    }

    private static func requestOriginalAsset(for asset: PHAsset) async throws -> AVAsset {
        let options = PHVideoRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.version = .original
        options.isNetworkAccessAllowed = true
        return try await withCheckedThrowingContinuation { continuation in
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { result, _, info in
                if let result {
                    continuation.resume(returning: result)
                } else {
                    let error = (info?[PHImageErrorKey] as? Error) ?? EditorMediaCacheError.sourceUnavailable
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func proxyKey(for asset: PHAsset, quality: EditorProxyQuality) -> String {
        let modified = asset.modificationDate?.timeIntervalSince1970 ?? 0
        return stableHash(
            "\(asset.localIdentifier)|\(modified)|\(asset.pixelWidth)x\(asset.pixelHeight)|\(asset.duration)|\(quality.rawValue)"
        )
    }

    private static func stableHash(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }

    private static func directory(named name: String) -> URL {
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let directory = root.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func requireWorkingStorage() throws {
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let capacity = try? root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage
        if let capacity, capacity < 512 * 1_024 * 1_024 { throw EditorMediaCacheError.lowStorage }
    }

    private static func files(in directory: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
    }

    private static func fileSize(_ url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }

    private static func modifiedDate(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    private static func usable(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path) && fileSize(url) > 0
    }

    private static func touch(_ url: URL) {
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
    }

    private static func excludeFromBackup(_ url: URL) {
        var mutable = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? mutable.setResourceValues(values)
    }

    private static func clear(directoryNamed name: String) {
        for url in files(in: directory(named: name)) { try? FileManager.default.removeItem(at: url) }
    }
}

