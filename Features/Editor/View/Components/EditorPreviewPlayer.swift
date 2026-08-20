//
//  EditorPreviewPlayer.swift
//  Mixtape
//
//  Created by Favour Baruch on 14/05/2026.
//

import SwiftUI
import AVFoundation
import UIKit
import Photos

struct EditorPreviewPlayer: View {
    let vm: EditorViewModel
    /// When true, the preview stretches to fill a non–9:16 parent frame (fullscreen sheet only).
    var fillsBounds: Bool = false
    var onFullscreen: () -> Void = {}

    @State private var posterImage: UIImage?

    private var previewClip: EditorClip? {
        vm.playbackInfo?.clip ?? vm.selectedClip
    }

    private var showingVideoLayer: Bool {
        // Photo clips are silent video segments in the shared composition. Showing
        // the composition here keeps their grade, masks, transitions, and canvas
        // treatment visible instead of covering them with the raw PhotoKit poster.
        vm.player != nil
    }

    var body: some View {
        Group {
            if fillsBounds {
                previewSurface
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            } else {
                previewSurface
                    .frame(maxWidth: .infinity)
                    .aspectRatio(vm.canvasSettings.aspectRatio, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
        .task { loadPoster() }
        .onChange(of: vm.playbackClipID) { _, _ in loadPoster() }
        .onChange(of: vm.selectedClipID) { _, _ in
            if vm.playbackInfo == nil { loadPoster() }
        }
    }

    private var previewSurface: some View {
        ZStack {
            background

            if let posterImage, !showingVideoLayer {
                Image(uiImage: posterImage)
                    .resizable()
                    .modifier(PreviewMediaScaling(fillsBounds: fillsBounds))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if showingVideoLayer, let player = vm.player {
                PlayerLayerView(
                    player: player,
                    videoGravity: fillsBounds ? .resizeAspectFill : .resizeAspect
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            EditorColorMaskSelectionLayer(vm: vm)
            EditorReframeSelectionLayer(vm: vm)
            EditorOverlaySelectionLayer(vm: vm)
            CompositingMaskSelectionLayer(vm: vm)
            MotionTrackingSelectionLayer(vm: vm)

            // Text overlays rendered on top of video/poster
            textOverlayLayer

            if shouldShowLoading {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
            }

            VStack {
                Spacer(minLength: 0)
                    .allowsHitTesting(false)
                controlsHUD
            }
        }
    }

    private var textOverlayLayer: some View {
        EditorTextOverlayLayerView(vm: vm)
    }

    private var shouldShowLoading: Bool {
        guard let clip = previewClip else { return false }
        if clip.isVideo { return vm.player == nil && posterImage == nil }
        return posterImage == nil
    }

    private var background: some View {
        Group {
            if vm.canvasSettings.backgroundKind == .image,
               let path = vm.canvasSettings.backgroundImagePath,
               let image = UIImage(contentsOfFile: path) {
                Image(uiImage: image).resizable().scaledToFill()
            } else if vm.canvasSettings.backgroundKind == .blur, let posterImage {
                Image(uiImage: posterImage).resizable().scaledToFill().blur(radius: 24).scaleEffect(1.12)
            } else {
                let rgb = vm.canvasSettings.backgroundColorRGB
                Color(
                    red: Double((rgb >> 16) & 0xff) / 255,
                    green: Double((rgb >> 8) & 0xff) / 255,
                    blue: Double(rgb & 0xff) / 255
                )
            }
        }
    }

    private var controlsHUD: some View {
        HStack(spacing: 14) {
            Text(vm.currentTimeString)
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundColor(.white)

            Button(action: { vm.togglePlay() }) {
                Image(systemName: vm.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundColor(.white)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .disabled(vm.totalDuration <= 0)
            .accessibilityLabel(vm.isPlaying ? "Pause" : "Play")

            Button(action: onFullscreen) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Fullscreen")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
        .background(Capsule().fill(Color.black.opacity(0.55)))
        .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
        .padding(.bottom, 14)
    }

    private func loadPoster() {
        posterImage = nil
        guard let clip = previewClip else { return }
        let manager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true
        let target = CGSize(width: 1200, height: 1200)
        manager.requestImage(
            for: clip.asset,
            targetSize: target,
            contentMode: .aspectFit,
            options: options
        ) { image, _ in
            guard let image else { return }
            Task { @MainActor in self.posterImage = image }
        }
    }
}

struct EditorReframeSelectionLayer: View {
    let vm: EditorViewModel

    @State private var scaleAtGestureStart: CGFloat?

    private var activeClip: EditorClip? {
        guard vm.selectedTool == .crop, let selected = vm.selectedReframeClip else { return nil }
        if let overlay = vm.selectedOverlayClip {
            guard vm.timelinePosition >= overlay.timelineStart,
                  vm.timelinePosition <= overlay.timelineEnd else { return nil }
        } else {
            guard vm.playbackInfo?.clip.id == vm.selectedClipID else { return nil }
        }
        return selected
    }

    var body: some View {
        GeometryReader { geometry in
            if let clip = activeClip {
                let frame = cropGuideFrame(for: clip, canvas: geometry.size)
                ZStack {
                    Color.clear
                        .contentShape(Rectangle())

                    Rectangle()
                        .stroke(Color.appColors.primaryColor, lineWidth: 1.5)
                        .frame(width: frame.width, height: frame.height)

                    if vm.showsReframeSafeAreaGuides {
                        safeAreaGuides(in: frame)
                    }
                }
                .gesture(positionGesture(canvasSize: geometry.size))
                .simultaneousGesture(scaleGesture(for: clip))
                .accessibilityLabel("Crop and reframe canvas")
                .accessibilityHint("Drag to position or pinch to zoom the selected clip")
            }
        }
    }

    private func cropGuideFrame(for clip: EditorClip, canvas: CGSize) -> CGSize {
        guard let ratio = clip.cropAspect.ratio else { return canvas }
        let canvasRatio = canvas.width / max(canvas.height, 1)
        if ratio > canvasRatio {
            return CGSize(width: canvas.width, height: canvas.width / ratio)
        }
        return CGSize(width: canvas.height * ratio, height: canvas.height)
    }

    @ViewBuilder
    private func safeAreaGuides(in frame: CGSize) -> some View {
        ZStack {
            Rectangle()
                .stroke(Color.white.opacity(0.65), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                .frame(width: frame.width * 0.9, height: frame.height * 0.9)

            HStack(spacing: 0) {
                Spacer()
                Rectangle().fill(Color.white.opacity(0.35)).frame(width: 0.5)
                Spacer()
                Rectangle().fill(Color.white.opacity(0.35)).frame(width: 0.5)
                Spacer()
            }
            .frame(width: frame.width, height: frame.height)

            VStack(spacing: 0) {
                Spacer()
                Rectangle().fill(Color.white.opacity(0.35)).frame(height: 0.5)
                Spacer()
                Rectangle().fill(Color.white.opacity(0.35)).frame(height: 0.5)
                Spacer()
            }
            .frame(width: frame.width, height: frame.height)
        }
    }

    private func positionGesture(canvasSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                vm.beginSelectedClipReframeDrag()
                vm.updateSelectedClipReframeDrag(
                    translation: value.translation,
                    canvasSize: canvasSize
                )
            }
            .onEnded { _ in vm.commitSelectedClipReframe() }
    }

    private func scaleGesture(for clip: EditorClip) -> some Gesture {
        MagnificationGesture()
            .onChanged { amount in
                if scaleAtGestureStart == nil { scaleAtGestureStart = clip.reframeScale }
                vm.setSelectedClipReframeScale((scaleAtGestureStart ?? clip.reframeScale) * amount)
            }
            .onEnded { _ in
                scaleAtGestureStart = nil
                vm.commitSelectedClipReframe()
            }
    }
}

struct EditorOverlaySelectionLayer: View {
    let vm: EditorViewModel

    @State private var scaleAtGestureStart: CGFloat?
    @State private var handleScaleAtGestureStart: CGFloat?

    private var selectedVisibleOverlay: EditorOverlayClip? {
        guard vm.selectedTool != .crop,
              vm.selectedTool != .track,
              !(vm.selectedTool == .filter && vm.isColorMaskEditing),
              let clip = vm.selectedOverlayClip,
              vm.timelinePosition >= clip.timelineStart,
              vm.timelinePosition < clip.timelineEnd else { return nil }
        return vm.resolvedOverlayClip(clip, at: vm.timelinePosition)
    }

    var body: some View {
        GeometryReader { geometry in
            if let clip = selectedVisibleOverlay {
                let selectionSize = fittedSelectionSize(for: clip, in: geometry.size)
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.clear)
                    .frame(width: selectionSize.width, height: selectionSize.height)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .stroke(Color.appColors.primaryColor, lineWidth: 2)
                    )
                    .overlay(alignment: .topTrailing) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.black)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(Color.appColors.primaryColor))
                            .offset(x: 10, y: -10)
                            .contentShape(Circle().inset(by: -10))
                            .highPriorityGesture(
                                resizeHandleGesture(for: clip, canvasSize: geometry.size)
                            )
                            .accessibilityLabel("Resize overlay")
                            .accessibilityHint("Drag outward to enlarge or inward to shrink")
                    }
                    .contentShape(Rectangle())
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                    .offset(
                        x: clip.xOffset * geometry.size.width,
                        y: clip.yOffset * geometry.size.height
                    )
                    .gesture(positionGesture(for: clip, canvasSize: geometry.size))
                    .simultaneousGesture(scaleGesture(for: clip))
                    .accessibilityLabel("Selected media overlay")
                    .accessibilityHint("Drag to move; pinch or drag the corner handle to resize")
            }
        }
    }

    private func fittedSelectionSize(
        for clip: EditorOverlayClip,
        in canvasSize: CGSize
    ) -> CGSize {
        let sourceWidth = max(CGFloat(clip.asset.pixelWidth), 1)
        let sourceHeight = max(CGFloat(clip.asset.pixelHeight), 1)
        let sourceAspect = sourceWidth / sourceHeight
        let canvasAspect = canvasSize.width / max(canvasSize.height, 1)

        if sourceAspect >= canvasAspect {
            let width = canvasSize.width * clip.scale
            return CGSize(width: width, height: width / sourceAspect)
        }
        let height = canvasSize.height * clip.scale
        return CGSize(width: height * sourceAspect, height: height)
    }

    private func positionGesture(for clip: EditorOverlayClip, canvasSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                vm.beginOverlayPositionDrag(id: clip.id)
                vm.updateOverlayPositionDrag(
                    id: clip.id,
                    translation: value.translation,
                    canvasSize: canvasSize
                )
            }
            .onEnded { _ in vm.commitOverlayTransform() }
    }

    private func scaleGesture(for clip: EditorOverlayClip) -> some Gesture {
        MagnificationGesture()
            .onChanged { amount in
                if scaleAtGestureStart == nil {
                    scaleAtGestureStart = clip.scale
                }
                vm.setOverlayScale(
                    id: clip.id,
                    scale: (scaleAtGestureStart ?? clip.scale) * amount
                )
            }
            .onEnded { _ in
                scaleAtGestureStart = nil
                vm.commitOverlayTransform()
            }
    }

    private func resizeHandleGesture(
        for clip: EditorOverlayClip,
        canvasSize: CGSize
    ) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if handleScaleAtGestureStart == nil {
                    handleScaleAtGestureStart = clip.scale
                }
                let reference = max(min(canvasSize.width, canvasSize.height), 1)
                let diagonalDelta = (value.translation.width - value.translation.height) / reference
                vm.setOverlayScale(
                    id: clip.id,
                    scale: (handleScaleAtGestureStart ?? clip.scale) + diagonalDelta
                )
            }
            .onEnded { _ in
                handleScaleAtGestureStart = nil
                vm.commitOverlayTransform()
            }
    }
}

private struct PreviewMediaScaling: ViewModifier {
    let fillsBounds: Bool

    func body(content: Content) -> some View {
        if fillsBounds {
            content.scaledToFill()
        } else {
            content.scaledToFit()
        }
    }
}

// MARK: - AVPlayerLayer wrapper

struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer
    var videoGravity: AVLayerVideoGravity = .resizeAspect

    func makeUIView(context: Context) -> PlayerHostView {
        let v = PlayerHostView()
        v.playerLayer.player = player
        v.playerLayer.videoGravity = videoGravity
        v.backgroundColor = .black
        // Overlay chrome (text, masks, crop) is SwiftUI on top of this
        // layer. Leaving the UIView hittable eats pans that miss a
        // glyph's layout slot.
        v.isUserInteractionEnabled = false
        return v
    }

    func updateUIView(_ uiView: PlayerHostView, context: Context) {
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
        }
        uiView.playerLayer.videoGravity = videoGravity
        uiView.isUserInteractionEnabled = false
        uiView.setNeedsLayout()
    }
}

final class PlayerHostView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
    }
}
