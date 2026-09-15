//
//  ProxyRenderCachePanel.swift
//  Mixtape
//

import SwiftUI
import PhotosUI

struct ProxyRenderCachePanel: View {
    let vm: EditorViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 16) {
                    originalMediaBanner
                    proxyCard
                    renderCard
                    storageCard
                    if let message = vm.cacheStatusMessage {
                        Label(message, systemImage: statusIcon)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                    }
                }
                .padding(18)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
        }
        .background(Color.appColors.backgroundColor)
        .task { await vm.refreshMediaCacheStats() }
    }

    private var header: some View {
        ZStack {
            VStack(spacing: 2) {
                Text("Performance Media").font(.headline)
                Text("Proxy & render cache").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Done") { vm.selectedTool = nil }
                    .font(.subheadline.bold())
                    .foregroundStyle(Color.appColors.primaryColor)
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 58)
    }

    private var originalMediaBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.shield.fill")
                .font(.title3)
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 4) {
                Text("Originals stay authoritative")
                    .font(.subheadline.bold())
                Text("Performance files are used only while editing. Every export reads the full-quality original media.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color.green.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
    }

    private var proxyCard: some View {
        cacheCard(title: "PROXY MEDIA", icon: "bolt.horizontal.circle.fill") {
            Toggle("Use proxies for playback", isOn: Binding(
                get: { vm.proxySettings.isEnabled },
                set: vm.setProxyEnabled
            ))
            .tint(Color.appColors.primaryColor)

            Toggle("Generate automatically", isOn: Binding(
                get: { vm.proxySettings.automaticallyGenerate },
                set: vm.setAutomaticProxyGeneration
            ))
            .tint(Color.appColors.primaryColor)
            .disabled(!vm.proxySettings.isEnabled)

            Picker("Proxy quality", selection: Binding(
                get: { vm.proxySettings.quality },
                set: vm.setProxyQuality
            )) {
                ForEach(EditorProxyQuality.allCases) { quality in
                    Text(quality.title).tag(quality)
                }
            }
            .pickerStyle(.segmented)
            .disabled(!vm.proxySettings.isEnabled)

            if let progress = vm.proxyGenerationProgress {
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text("Generating proxies")
                        Spacer()
                        Text(progress, format: .percent.precision(.fractionLength(0)))
                            .monospacedDigit()
                    }
                    .font(.caption.weight(.semibold))
                    ProgressView(value: progress).tint(Color.appColors.primaryColor)
                }
            }

            Button {
                vm.generateMissingProxies()
            } label: {
                Label("Generate missing proxies", systemImage: "wand.and.rays")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.appColors.primaryColor)
            .disabled(vm.proxyGenerationProgress != nil)
        }
    }

    private var renderCard: some View {
        cacheCard(title: "RENDER CACHE", icon: "film.stack.fill") {
            Toggle("Cache complex playback", isOn: Binding(
                get: { vm.proxySettings.backgroundRenderCache },
                set: vm.setBackgroundRenderCache
            ))
            .tint(Color.appColors.primaryColor)

            Text("After editing pauses, Mixtape renders the exact current cut for smooth playback. Any visual, timing, or audio change gets a new fingerprint.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                vm.buildRenderCacheNow()
            } label: {
                HStack {
                    if vm.isBuildingRenderCache { ProgressView().controlSize(.small) }
                    Label(
                        vm.isBuildingRenderCache ? "Rendering current cut…" : "Render current cut now",
                        systemImage: "play.rectangle.on.rectangle.fill"
                    )
                    Spacer()
                }
            }
            .buttonStyle(.bordered)
            .disabled(!vm.proxySettings.backgroundRenderCache || vm.isBuildingRenderCache)
        }
    }

    private var storageCard: some View {
        cacheCard(title: "STORAGE", icon: "internaldrive.fill") {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(byteString(vm.mediaCacheStats.totalBytes))
                        .font(.title3.bold()).monospacedDigit()
                    Text("\(vm.mediaCacheStats.proxyCount) proxies · \(vm.mediaCacheStats.renderCount) renders")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("Limit \(budgetString)")
                    .font(.caption.bold())
                    .foregroundStyle(Color.appColors.primaryColor)
            }

            Slider(
                value: Binding(
                    get: { Double(vm.proxySettings.cacheBudgetMB) },
                    set: { vm.setMediaCacheBudgetMB(Int($0)) }
                ),
                in: 256...16_384,
                step: 256
            )
            .tint(Color.appColors.primaryColor)

            HStack(spacing: 10) {
                Button("Clear proxies", role: .destructive) { vm.clearProxyCache() }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                Button("Clear renders", role: .destructive) { vm.clearRenderCache() }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func cacheCard<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: icon)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            content()
        }
        .padding(16)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 16))
    }

    private var statusIcon: String {
        vm.isBuildingRenderCache || vm.proxyGenerationProgress != nil
            ? "hourglass"
            : "checkmark.circle"
    }

    private func byteString(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private var budgetString: String {
        ByteCountFormatter.string(
            fromByteCount: Int64(vm.proxySettings.cacheBudgetMB) * 1_024 * 1_024,
            countStyle: .file
        )
    }
}

