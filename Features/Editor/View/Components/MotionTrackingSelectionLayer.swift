//
//  MotionTrackingSelectionLayer.swift
//  Mixtape
//
//  Direct-preview placement for the CapCut-style tracking circle: a
//  draggable oval with independent width/height handles, an inline
//  "Select an object to track" hint, and a live tracking-progress chip.
//

import SwiftUI

struct MotionTrackingSelectionLayer: View {
    let vm: EditorViewModel

    private var track: EditorMotionTrack? {
        guard vm.selectedTool == .track else { return nil }
        return vm.currentTrackingBox
    }

    var body: some View {
        GeometryReader { geometry in
            let canvasSize = geometry.size
            ZStack {
                if let track {
                    TrackingCircleHandle(
                        track: track,
                        sample: track.resolved(at: vm.currentClipProgressForTracking()),
                        canvasSize: canvasSize,
                        showsHint: !track.isTracked && !vm.isMotionTracking,
                        onMove: { x, y in
                            // Read the progress before entering the mutation
                            // closure below — updateSelectedMotionTrack holds
                            // an exclusive (inout) access to `clips` for the
                            // whole closure, and currentClipProgressForTracking()
                            // reads `clips` again internally, so calling it
                            // from inside trips Swift's exclusivity checker
                            // and crashes.
                            let progress = vm.currentClipProgressForTracking()
                            vm.updateSelectedMotionTrack {
                                if $0.isTracked {
                                    $0.correct(at: progress, x: x, y: y)
                                } else {
                                    $0.translate(dx: x - $0.seedX, dy: y - $0.seedY)
                                }
                            }
                        },
                        onResize: { width, height in
                            vm.updateSelectedMotionTrack { $0.resize(width: width, height: height) }
                        },
                        onCommit: { vm.commitMotionTrackingEdit() },
                        onCancel: { vm.clearSubjectTracking() }
                    )
                    .allowsHitTesting(!vm.isMotionTracking)

                    if vm.isMotionTracking {
                        TrackingProgressChip(
                            progress: vm.stabilizationAnalysisProgress ?? 0,
                            onCancel: { vm.cancelMotionTracking() }
                        )
                        .position(
                            x: track.seedX * canvasSize.width,
                            y: track.seedY * canvasSize.height
                        )
                    }
                }
            }
            .onAppear { vm.activeTrackingCanvasSize = canvasSize }
            .onChange(of: canvasSize) { _, newValue in vm.activeTrackingCanvasSize = newValue }
        }
        .allowsHitTesting(vm.selectedTool == .track)
    }
}

private struct TrackingCircleHandle: View {
    let track: EditorMotionTrack
    let sample: EditorMotionTrackSample
    let canvasSize: CGSize
    let showsHint: Bool
    let onMove: (Double, Double) -> Void
    let onResize: (Double, Double) -> Void
    let onCommit: () -> Void
    let onCancel: () -> Void

    @State private var dragOrigin: CGPoint?
    @State private var heightResizeOrigin: Double?
    @State private var widthResizeOrigin: Double?

    private var ovalWidth: CGFloat {
        max(track.seedWidth * sample.scale * canvasSize.width, 60)
    }
    private var ovalHeight: CGFloat {
        max(track.seedHeight * sample.scale * canvasSize.height, 60)
    }

    var body: some View {
        let color = Color.appColors.primaryColor
        VStack(spacing: 10) {
            ZStack {
                Ellipse()
                    .fill(color.opacity(0.10))
                Ellipse()
                    .stroke(color, lineWidth: 1.8)
                Circle()
                    .fill(color)
                    .frame(width: 10, height: 10)
                    .overlay(Circle().stroke(.white, lineWidth: 1.5))

                handleButton(systemImage: "xmark", position: .init(x: -ovalWidth / 2, y: -ovalHeight / 2 - 4))
                    .onTapGesture { onCancel() }

                resizeHandle(systemImage: "arrow.up.and.down")
                    .offset(y: -ovalHeight / 2)
                    .gesture(heightResizeGesture)

                resizeHandle(systemImage: "arrow.left.and.right")
                    .offset(x: ovalWidth / 2)
                    .gesture(widthResizeGesture)
            }
            .frame(width: ovalWidth, height: ovalHeight)
            .contentShape(Ellipse())
            .gesture(moveGesture)

            if showsHint {
                Text("Select an object to track")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.black.opacity(0.55)))
                    .allowsHitTesting(false)
            }
        }
        .position(x: sample.x * canvasSize.width, y: sample.y * canvasSize.height)
        .accessibilityLabel("Tracking area")
        .accessibilityHint("Drag to move onto the subject. Use the top and right handles to resize.")
    }

    private func handleButton(systemImage: String, position: CGPoint) -> some View {
        Circle()
            .fill(Color.black.opacity(0.7))
            .frame(width: 26, height: 26)
            .overlay(
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
            )
            .offset(x: position.x, y: position.y)
    }

    private func resizeHandle(systemImage: String) -> some View {
        Circle()
            .fill(.white)
            .frame(width: 26, height: 26)
            .overlay(Circle().stroke(Color.appColors.primaryColor, lineWidth: 1.5))
            .overlay(
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Color.appColors.primaryColor)
            )
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if dragOrigin == nil {
                    // A tracked box can be far from its original seed. Start
                    // corrections from the resolved playhead position so the
                    // handle never jumps back to frame zero on first drag.
                    dragOrigin = CGPoint(x: sample.x, y: sample.y)
                }
                guard let origin = dragOrigin, canvasSize.width > 0, canvasSize.height > 0 else {
                    return
                }
                onMove(
                    origin.x + value.translation.width / canvasSize.width,
                    origin.y + value.translation.height / canvasSize.height
                )
            }
            .onEnded { _ in
                dragOrigin = nil
                onCommit()
            }
    }

    /// Both handles resize symmetrically about the center dot — the anchor
    /// Vision tracks — rather than pinning an opposite edge like a rectangle.
    private var heightResizeGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if heightResizeOrigin == nil { heightResizeOrigin = track.seedHeight }
                guard let origin = heightResizeOrigin, canvasSize.height > 0 else { return }
                let dy = value.translation.height / canvasSize.height
                let newHeight = min(max(origin - 2 * dy, 0.06), 0.9)
                onResize(track.seedWidth, newHeight)
            }
            .onEnded { _ in
                heightResizeOrigin = nil
                onCommit()
            }
    }

    private var widthResizeGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if widthResizeOrigin == nil { widthResizeOrigin = track.seedWidth }
                guard let origin = widthResizeOrigin, canvasSize.width > 0 else { return }
                let dx = value.translation.width / canvasSize.width
                let newWidth = min(max(origin + 2 * dx, 0.06), 0.9)
                onResize(newWidth, track.seedHeight)
            }
            .onEnded { _ in
                widthResizeOrigin = nil
                onCommit()
            }
    }
}

private struct TrackingProgressChip: View {
    let progress: Double
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(Color.appColors.primaryColor)
            Text("Tracking… \(Int(progress * 100))%")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
        }
        .padding(14)
        .frame(width: 140)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.black.opacity(0.75)))
    }
}
