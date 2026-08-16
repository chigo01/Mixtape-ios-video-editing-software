//
//  EditorExportScreen.swift
//  Mixtape
//

import SwiftUI
import Photos
import UIKit
import AVFoundation

struct EditorExportScreen: View {
    @Bindable var vm: EditorViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var settings = EditorExportSettings()
    @State private var showShareSheet = false

    var body: some View {
        AppGlobalBackgroundScaffold {
            GeometryReader { geometry in
                exportContent(availableWidth: geometry.size.width)
                    .safeAreaInset(edge: .bottom) {
                        if !vm.isExporting && vm.exportedFileURL == nil && vm.exportMessage == nil {
                            startExportButton
                                .frame(maxWidth: 720)
                                .frame(maxWidth: .infinity)
                        }
                    }

                if vm.isExporting || vm.exportMessage != nil || vm.exportedFileURL != nil {
                    exportPanel
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top) {
            exportNavBar
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = vm.exportedFileURL {
                ShareSheet(items: [url])
            }
        }
        .onDisappear { vm.commitProjectTitle() }
    }

    private func exportContent(availableWidth: CGFloat) -> some View {
        let usesTwoColumns = UIDevice.current.userInterfaceIdiom == .pad && availableWidth >= 920

        return ScrollView {
            Group {
                if usesTwoColumns {
                    HStack(alignment: .top, spacing: 28) {
                        VStack(alignment: .leading, spacing: 22) {
                            EditorExportPreviewSection(vm: vm)
                            rangeSection
                        }
                        .frame(maxWidth: 540)

                        VStack(alignment: .leading, spacing: 22) {
                            resolutionSection
                            frameRateSection
                            qualitySection
                            hdrToggle
                            formatAndSizeRow
                        }
                        .frame(maxWidth: 540)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 22) {
                        EditorExportPreviewSection(vm: vm)
                        rangeSection
                        resolutionSection
                        frameRateSection
                        qualitySection
                        hdrToggle
                        formatAndSizeRow
                    }
                    .frame(maxWidth: 760)
                }
            }
            .frame(maxWidth: 1120)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, usesTwoColumns ? 28 : 16)
            .padding(.top, usesTwoColumns ? 20 : 8)
            .padding(.bottom, vm.isExporting || vm.exportMessage != nil ? 220 : 100)
        }
    }

    private var exportNavBar: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .disabled(vm.isExporting)

            Spacer()

            Text("Export")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)

            Spacer()

            Color.clear.frame(width: 36, height: 36)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.appColors.backgroundColor.opacity(0.95))
    }

    private var resolutionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("RESOLUTION")
            HStack(spacing: 0) {
                ForEach(EditorExportResolution.allCases) { option in
                    settingsChip(
                        title: option.rawValue,
                        isSelected: settings.resolution == option
                    ) {
                        settings.resolution = option
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(4)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
        }
    }

    private var rangeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionTitle("EXPORT RANGE")
                Spacer()
                Text(vm.exportRange == nil ? "Entire project" : vm.formatDuration(vm.exportDuration))
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Color.appColors.primaryColor)
            }
            HStack(spacing: 8) {
                rangeButton("SET IN", systemImage: "arrow.right.to.line") { vm.setExportInPoint() }
                rangeButton("SET OUT", systemImage: "arrow.left.to.line") { vm.setExportOutPoint() }
                if vm.exportInPoint != nil || vm.exportOutPoint != nil {
                    rangeButton("CLEAR", systemImage: "xmark") { vm.clearExportRange() }
                }
            }
            Text("Move the preview playhead, then set In and Out. A complete pair exports only that section.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
    }

    private func rangeButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 11, weight: .bold))
                .frame(maxWidth: .infinity).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.08)))
        }
        .buttonStyle(.plain).disabled(vm.isExporting)
    }

    private var frameRateSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("FRAME RATE")
            HStack(spacing: 0) {
                ForEach(EditorExportFrameRate.allCases) { option in
                    settingsChip(
                        title: option.label,
                        isSelected: settings.frameRate == option
                    ) {
                        settings.frameRate = option
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(4)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
        }
    }

    private var qualitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionTitle("QUALITY")
                Spacer()
                Text(settings.targetVideoMbpsLabel)
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundColor(Color.appColors.primaryColor)
            }
            HStack(spacing: 0) {
                ForEach(EditorExportQuality.allCases) { option in
                    settingsChip(
                        title: option.title,
                        isSelected: settings.quality == option
                    ) {
                        settings.quality = option
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(4)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
        }
    }

    private var hdrToggle: some View {
        Toggle(isOn: $settings.includeHDR) {
            VStack(alignment: .leading, spacing: 2) {
                Text("HDR export")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                Text("HEVC 10-bit — best for HDR source clips")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.45))
            }
        }
        .tint(Color.appColors.primaryColor)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
        .disabled(vm.isExporting)
    }

    private var formatAndSizeRow: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("FORMAT")
                HStack(spacing: 8) {
                    ForEach(EditorExportFormat.allCases) { option in
                        settingsChip(
                            title: option.rawValue,
                            isSelected: settings.format == option
                        ) {
                            settings.format = option
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("FILE SIZE")
                Text("~ \(settings.estimatedFileSizeMB(duration: vm.exportDuration)) MB")
                    .font(.system(size: 22, weight: .bold).monospacedDigit())
                    .foregroundColor(Color.appColors.primaryColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
            }
            .frame(width: 140)
        }
    }

    private var exportPanel: some View {
        VStack {
            Spacer()
            VStack(alignment: .leading, spacing: 14) {
                if vm.isExporting {
                    Text("EXPORTING PROJECT")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.2)
                        .foregroundColor(Color.white.opacity(0.45))

                    HStack {
                        Text(vm.exportMessage ?? "Rendering clips…")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.white)
                        Spacer()
                        Text("\(Int(vm.exportProgress * 100))%")
                            .font(.system(size: 34, weight: .bold).monospacedDigit())
                            .foregroundColor(Color.appColors.primaryColor)
                    }

                    ProgressView(value: vm.exportProgress)
                        .progressViewStyle(.linear)
                        .tint(Color.appColors.primaryColor)

                    Button(action: { vm.cancelExport() }) {
                        Text("CANCEL")
                            .font(.system(size: 14, weight: .bold))
                            .tracking(0.6)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.1)))
                    }
                    .buttonStyle(.plain)
                } else if vm.exportedFileURL != nil {
                    Text("EXPORT COMPLETE")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.2)
                        .foregroundColor(Color.white.opacity(0.45))

                    Text(vm.exportMessage ?? "Saved to Photos")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)

                    HStack(spacing: 12) {
                        Button(action: { vm.clearExportState(); dismiss() }) {
                            Text("DONE")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.1)))
                        }
                        .buttonStyle(.plain)

                        Button(action: { showShareSheet = true }) {
                            HStack(spacing: 8) {
                                Image(systemName: "square.and.arrow.up")
                                Text("SHARE")
                            }
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.appColors.primaryColor))
                        }
                        .buttonStyle(.plain)
                    }
                } else if let message = vm.exportMessage {
                    Text(message)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                        .onTapGesture { vm.clearExportState() }
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(white: 0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(
            LinearGradient(
                colors: [.clear, Color.black.opacity(0.55)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
        )
    }

    private var startExportButton: some View {
        Button {
            vm.startExport(settings: settings)
        } label: {
            Text("EXPORT PROJECT")
                .font(.system(size: 14, weight: .bold))
                .tracking(0.8)
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.appColors.primaryColor))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .background(Color.appColors.backgroundColor.opacity(0.95))
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .tracking(1)
            .foregroundColor(Color.white.opacity(0.45))
    }

    private func settingsChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(isSelected ? .black : .white.opacity(0.75))
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isSelected ? Color.appColors.primaryColor : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .disabled(vm.isExporting)
    }
}

// MARK: - Export preview

private struct EditorExportPreviewSection: View {
    @Bindable var vm: EditorViewModel

    @State private var coverImage: UIImage?
    @State private var exportedPlayer: AVPlayer?
    @State private var isExportedPlaying = false
    @State private var exportedDuration: TimeInterval = 0
    @State private var exportedPosition: TimeInterval = 0
    @State private var isScrubbing = false
    @State private var scrubPosition: TimeInterval = 0
    @State private var exportedTickTimer: Timer?

    private var isShowingExportedFile: Bool {
        vm.exportedFileURL != nil && !vm.isExporting
    }

    private var previewClip: EditorClip? {
        vm.playbackInfo?.clip ?? vm.clips.first
    }

    private var showingCompositionVideo: Bool {
        !isShowingExportedFile && vm.player != nil
    }

    private var isPreviewPlaying: Bool {
        isShowingExportedFile ? isExportedPlaying : vm.isPlaying
    }

    private var playbackDuration: TimeInterval {
        max(isShowingExportedFile ? exportedDuration : vm.totalDuration, 0.01)
    }

    private var displayedPosition: TimeInterval {
        if isShowingExportedFile {
            exportedPosition
        } else if isScrubbing {
            scrubPosition
        } else {
            vm.timelinePosition
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            videoPreview
            playbackControls
            projectNameField
        }
        .task {
            await vm.setupPlayer()
            loadCover()
        }
        .onDisappear { stopPreview() }
        .onChange(of: vm.exportedFileURL) { _, url in
            Task { await configureExportedPlayer(url: url) }
        }
        .onChange(of: vm.isExporting) { _, exporting in
            if exporting { stopPreview() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { notification in
            guard let item = exportedPlayer?.currentItem,
                  notification.object as? AVPlayerItem === item else { return }
            isExportedPlaying = false
            exportedPosition = exportedDuration
            stopExportedTicking()
        }
    }

    private var videoPreview: some View {
        ZStack {
            previewSurface
                .frame(maxWidth: .infinity)
                .frame(height: 220)
                .clipped()

            LinearGradient(
                colors: [.clear, .black.opacity(0.55)],
                startPoint: .center,
                endPoint: .bottom
            )
            .allowsHitTesting(false)

            if !vm.isExporting {
                Button(action: togglePlayback) {
                    Image(systemName: isPreviewPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white.opacity(0.9))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isPreviewPlaying ? "Pause preview" : "Play preview")
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .opacity(vm.isExporting ? 0.45 : 1)
    }

    private var playbackControls: some View {
        HStack(spacing: 10) {
            Text(vm.formatPlaybackTime(displayedPosition))
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundColor(.white.opacity(0.75))
                .frame(width: 72, alignment: .leading)

            Slider(
                value: sliderBinding,
                in: 0...playbackDuration,
                onEditingChanged: handleScrubEditingChanged
            )
            .tint(Color.appColors.primaryColor)
            .disabled(vm.isExporting || playbackDuration <= 0)

            Text(vm.formatDuration(playbackDuration))
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundColor(.white.opacity(0.75))
                .frame(width: 44, alignment: .trailing)
        }
    }

    private var projectNameField: some View {
        VStack(alignment: .leading, spacing: 10) {
            exportSectionTitle("PROJECT NAME")
            TextField(
                "",
                text: $vm.projectTitle,
                prompt: Text("Enter project name")
                    .foregroundColor(Color.white.opacity(0.45))
            )
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(.white)
            .textFieldStyle(.plain)
            .submitLabel(.done)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
            .disabled(vm.isExporting)
            .onSubmit { vm.commitProjectTitle() }
        }
    }

    private var sliderBinding: Binding<Double> {
        Binding(
            get: { displayedPosition },
            set: { newValue in
                let time = min(max(0, newValue), playbackDuration)
                if isShowingExportedFile {
                    seekExported(to: time)
                } else {
                    scrubPosition = time
                    vm.setTimelinePositionForScrub(time)
                }
            }
        )
    }

    @ViewBuilder
    private var previewSurface: some View {
        ZStack {
            Color.black

            if isShowingExportedFile, let exportedPlayer {
                PlayerLayerView(player: exportedPlayer, videoGravity: .resizeAspectFill)
            } else {
                if let coverImage, !showingCompositionVideo {
                    Image(uiImage: coverImage)
                        .resizable()
                        .scaledToFill()
                }

                if showingCompositionVideo, let player = vm.player {
                    PlayerLayerView(player: player, videoGravity: .resizeAspectFill)
                }

                EditorTextOverlayLayerView(vm: vm)
                    .allowsHitTesting(false)
            }
        }
    }

    private func handleScrubEditingChanged(_ editing: Bool) {
        isScrubbing = editing
        if editing {
            if isShowingExportedFile {
                if isExportedPlaying {
                    exportedPlayer?.pause()
                    isExportedPlaying = false
                    stopExportedTicking()
                }
                exportedPosition = displayedPosition
            } else {
                scrubPosition = vm.timelinePosition
            }
        } else if isShowingExportedFile {
            seekExported(to: exportedPosition)
        } else {
            vm.commitTimelineAfterScrub()
        }
    }

    private func togglePlayback() {
        if isShowingExportedFile {
            toggleExportedPlayback()
        } else {
            vm.togglePlay()
        }
    }

    private func toggleExportedPlayback() {
        guard let player = exportedPlayer else { return }
        if isExportedPlaying {
            player.pause()
            isExportedPlaying = false
            stopExportedTicking()
        } else {
            if exportedPosition >= exportedDuration - 0.05 {
                seekExported(to: 0)
            }
            player.play()
            isExportedPlaying = true
            startExportedTicking()
        }
    }

    private func configureExportedPlayer(url: URL?) async {
        stopExportedTicking()
        exportedPlayer?.pause()
        exportedPlayer = nil
        isExportedPlaying = false
        exportedDuration = 0
        exportedPosition = 0

        guard let url else { return }
        if vm.isPlaying { vm.togglePlay() }

        let asset = AVURLAsset(url: url)
        let duration = (try? await asset.load(.duration))?.seconds ?? vm.totalDuration
        exportedDuration = max(duration, 0.01)
        exportedPlayer = AVPlayer(url: url)
    }

    private func seekExported(to time: TimeInterval) {
        let clamped = min(max(0, time), exportedDuration)
        exportedPosition = clamped
        let target = CMTime(seconds: clamped, preferredTimescale: 600)
        exportedPlayer?.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func startExportedTicking() {
        stopExportedTicking()
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { _ in
            Task { @MainActor in
                guard isExportedPlaying, let player = exportedPlayer else { return }
                let current = player.currentTime().seconds
                if current.isFinite {
                    exportedPosition = min(current, exportedDuration)
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        exportedTickTimer = timer
    }

    private func stopExportedTicking() {
        exportedTickTimer?.invalidate()
        exportedTickTimer = nil
    }

    private func stopPreview() {
        if vm.isPlaying { vm.togglePlay() }
        exportedPlayer?.pause()
        isExportedPlaying = false
        stopExportedTicking()
    }

    private func exportSectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .tracking(1)
            .foregroundColor(Color.white.opacity(0.45))
    }

    private func loadCover() {
        guard let clip = vm.clips.first else { return }
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true
        PHImageManager.default().requestImage(
            for: clip.asset,
            targetSize: CGSize(width: 600, height: 600),
            contentMode: .aspectFill,
            options: options
        ) { result, _ in
            guard let result else { return }
            Task { @MainActor in coverImage = result }
        }
    }
}

// MARK: - Share sheet

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
