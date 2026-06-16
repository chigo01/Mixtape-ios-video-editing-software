//
//  ClipReorderGestureView.swift
//  Mixtape
//
//  UIKit long-press + pan reorder. Updates layer transform during drag so SwiftUI
//  does not re-render the timeline on every frame.
//

import SwiftUI
import UIKit

struct TimelineClipMetrics {
    let clipWidths: [CGFloat]
    let insertSlotWidth: CGFloat

    /// Each clip cell occupies its own width + one insert-slot. This returns the
    /// leading edge of the clip at `index` within the HStack.
    func leadingEdge(ofClipAt index: Int) -> CGFloat {
        guard index >= 0, index < clipWidths.count else { return 0 }
        var x: CGFloat = 0
        for i in 0..<index {
            x += clipWidths[i] + insertSlotWidth
        }
        return x
    }

    /// Center-X of the clip at `index`.
    func centerX(ofClipAt index: Int) -> CGFloat {
        leadingEdge(ofClipAt: index) + clipWidths[index] / 2
    }

    func targetIndex(forSource source: Int, dragTranslation: CGFloat) -> Int {
        guard source >= 0, source < clipWidths.count else { return source }

        let draggedCenter = centerX(ofClipAt: source) + dragTranslation

        // Walk through each slot and find where the dragged center falls.
        for i in 0..<clipWidths.count {
            let slotCenter = centerX(ofClipAt: i)
            if draggedCenter < slotCenter { return i }
        }
        return clipWidths.count - 1
    }

    /// The horizontal translation needed to snap the clip from `sourceIndex`
    /// to the position at `destIndex` (accounting for clip widths).
    func snapTranslation(from sourceIndex: Int, to destIndex: Int) -> CGFloat {
        centerX(ofClipAt: destIndex) - centerX(ofClipAt: sourceIndex)
    }
}

// MARK: - Reorder state communicated back to SwiftUI

/// Shared object that the UIKit gesture view writes to, and the SwiftUI timeline
/// reads from, so clips can animate out of the way during a drag.
@MainActor
@Observable
final class ClipReorderState {
    /// The index of the clip currently being dragged, or nil if idle.
    var draggingSourceIndex: Int?
    /// Where the dragged clip would land if released now.
    var proposedDestinationIndex: Int?
    /// Raw horizontal translation of the drag (for the dragged clip's offset).
    var dragTranslationX: CGFloat = 0
    /// Whether the drag is actively in progress (for scaling/opacity effects).
    var isDragging: Bool = false
}

// MARK: - UIViewRepresentable bridge

struct ClipReorderGestureRepresentable: UIViewRepresentable {
    let clipIndex: Int
    let metrics: TimelineClipMetrics
    let reorderState: ClipReorderState
    let onMove: (Int, Int) -> Void

    func makeUIView(context: Context) -> ClipReorderGestureView {
        let view = ClipReorderGestureView()
        view.clipIndex = clipIndex
        view.metrics = metrics
        view.reorderState = reorderState
        view.onMove = onMove
        return view
    }

    func updateUIView(_ uiView: ClipReorderGestureView, context: Context) {
        uiView.clipIndex = clipIndex
        uiView.metrics = metrics
        uiView.reorderState = reorderState
        uiView.onMove = onMove
    }
}

// MARK: - UIKit gesture view

final class ClipReorderGestureView: UIView, UIGestureRecognizerDelegate {
    var clipIndex: Int = 0
    var metrics = TimelineClipMetrics(clipWidths: [], insertSlotWidth: 28)
    var reorderState: ClipReorderState?
    var onMove: ((Int, Int) -> Void)?

    /// Touch location when the long-press fires `.began`, used to compute translation.
    private var dragOrigin: CGPoint = .zero
    private var isDragging = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = true

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.minimumPressDuration = 0.35
        longPress.delegate = self
        addGestureRecognizer(longPress)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard bounds.contains(point) else { return nil }
        return self
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        false
    }

    /// The reference coordinate space for tracking drag translation.
    private var dragCoordinateView: UIView? {
        // Walk up to the scroll-view content so the translation is in timeline-content space.
        var v: UIView? = self
        while let parent = v?.superview {
            v = parent
            // The HStack hosting clips lives inside a UIHostingView inside the ScrollView.
            // Going 3–4 levels up is enough to reach a stable frame.
            if parent.bounds.width > self.bounds.width * 2 { return parent }
        }
        return superview
    }

    // MARK: - Long press handles the ENTIRE drag lifecycle

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        let refView = dragCoordinateView

        switch gesture.state {
        case .began:
            isDragging = true
            dragOrigin = gesture.location(in: refView)

            UIImpactFeedbackGenerator(style: .medium).impactOccurred()

            Task { @MainActor in
                self.reorderState?.draggingSourceIndex = self.clipIndex
                self.reorderState?.proposedDestinationIndex = self.clipIndex
                self.reorderState?.dragTranslationX = 0
                self.reorderState?.isDragging = true
            }

        case .changed:
            guard isDragging else { return }
            let current = gesture.location(in: refView)
            let tx = current.x - dragOrigin.x
            let target = metrics.targetIndex(forSource: clipIndex, dragTranslation: tx)

            Task { @MainActor in
                self.reorderState?.dragTranslationX = tx
                if self.reorderState?.proposedDestinationIndex != target {
                    self.reorderState?.proposedDestinationIndex = target
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            }

        case .ended, .cancelled, .failed:
            commitDragAndReset()

        default:
            break
        }
    }

    // MARK: - Commit

    private func commitDragAndReset() {
        guard isDragging else { return }
        isDragging = false

        let source = clipIndex
        let dest = reorderState?.proposedDestinationIndex ?? clipIndex

        // Reset SwiftUI state so clips animate back.
        Task { @MainActor in
            self.reorderState?.isDragging = false
            self.reorderState?.draggingSourceIndex = nil
            self.reorderState?.proposedDestinationIndex = nil
            self.reorderState?.dragTranslationX = 0
        }

        if dest != source {
            onMove?(source, dest)
        }
    }
}
