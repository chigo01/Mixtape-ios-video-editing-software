//
//  EditorExportScreen.swift
//  Mixtape
//

import SwiftUI
import Photos
import UIKit

struct EditorExportScreen: View {
    @Bindable var vm: EditorViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var settings = EditorExportSettings()
    @State private var coverImage: UIImage?
    @State private var showShareSheet = false

    var body: some View {
        AppGlobalBackgroundScaffold {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    previewHeader
                    resolutionSection
                    frameRateSection
                    formatAndSizeRow
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, vm.isExporting || vm.exportMessage != nil ? 220 : 100)
            }
            .safeAreaInset(edge: .bottom) {
                if !vm.isExporting && vm.exportedFileURL == nil && vm.exportMessage == nil {
                    startExportButton
                }
            }

            if vm.isExporting || vm.exportMessage != nil || vm.exportedFileURL != nil {
                exportPanel
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top) {
            exportNavBar
        }
        .task { loadCover() }
        .sheet(isPresented: $showShareSheet) {
            if let url = vm.exportedFileURL {
                ShareSheet(items: [url])
            }
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

    private var previewHeader: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let coverImage {
                    Image(uiImage: coverImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.white.opacity(0.06)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 220)
            .clipped()

            LinearGradient(
                colors: [.clear, .black.opacity(0.75)],
                startPoint: .center,
                endPoint: .bottom
            )

            Image(systemName: "play.fill")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.white.opacity(0.9))
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 8) {
                badge(vm.formatDuration(vm.totalDuration))
                badge("MIXTAPE")
            }
            .padding(12)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
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
                Text("~ \(settings.estimatedFileSizeMB(duration: vm.totalDuration)) MB")
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

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold).monospacedDigit())
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.black.opacity(0.55)))
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
