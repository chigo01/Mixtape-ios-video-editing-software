//
//  ClipTrimHandleView.swift
//  Mixtape
//

import SwiftUI
import UIKit

// MARK: - SwiftUI bridge

struct ClipTrimHandleRepresentable: UIViewRepresentable {
    let clipID: UUID
    let trimStart: TimeInterval
    let trimEnd: TimeInterval
    let originalDuration: TimeInterval
    let allowsDurationExtension: Bool
    let speed: Float
    let pixelsPerSecond: CGFloat
    let onTrimChanged: (UUID, TimeInterval, TimeInterval) -> Void
    let onTrimEnded: () -> Void

    func makeUIView(context: Context) -> ClipTrimHandleContainerView {
        let view = ClipTrimHandleContainerView()
        view.onTrimChanged = onTrimChanged
        view.onTrimEnded = onTrimEnded
        view.configure(
            clipID: clipID,
            trimStart: trimStart,
            trimEnd: trimEnd,
            originalDuration: originalDuration,
            allowsDurationExtension: allowsDurationExtension,
            speed: speed,
            pixelsPerSecond: pixelsPerSecond
        )
        return view
    }

    func updateUIView(_ uiView: ClipTrimHandleContainerView, context: Context) {
        uiView.onTrimChanged = onTrimChanged
        uiView.onTrimEnded = onTrimEnded
        uiView.configure(
            clipID: clipID,
            trimStart: trimStart,
            trimEnd: trimEnd,
            originalDuration: originalDuration,
            allowsDurationExtension: allowsDurationExtension,
            speed: speed,
            pixelsPerSecond: pixelsPerSecond
        )
    }
}

// MARK: - Container

final class ClipTrimHandleContainerView: UIView {
    var onTrimChanged: ((UUID, TimeInterval, TimeInterval) -> Void)?
    var onTrimEnded: (() -> Void)?

    private let leftHandle = TrimHandleView(edge: .start)
    private let rightHandle = TrimHandleView(edge: .end)

    private var clipID: UUID?
    private var baselineTrimStart: TimeInterval = 0
    private var baselineTrimEnd: TimeInterval = 0
    private var trimStart: TimeInterval = 0
    private var trimEnd: TimeInterval = 0
    private var originalDuration: TimeInterval = 0
    private var allowsDurationExtension = false
    private var speed: Float = 1
    private var pixelsPerSecond: CGFloat = 18

    private let handleWidth: CGFloat = 22
    private weak var scrollViewWhilePanning: UIScrollView?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = true
        backgroundColor = .clear

        [leftHandle, rightHandle].forEach { handle in
            addSubview(handle)
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            pan.maximumNumberOfTouches = 1
            handle.addGestureRecognizer(pan)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// Only the handle bars receive touches; the clip body passes taps through to SwiftUI.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, alpha > 0.01, bounds.contains(point) else { return nil }
        for handle in [leftHandle, rightHandle] {
            let local = convert(point, to: handle)
            if handle.point(inside: local, with: event) {
                return handle
            }
        }
        return nil
    }

    func configure(
        clipID: UUID,
        trimStart: TimeInterval,
        trimEnd: TimeInterval,
        originalDuration: TimeInterval,
        allowsDurationExtension: Bool,
        speed: Float,
        pixelsPerSecond: CGFloat
    ) {
        self.clipID = clipID
        self.trimStart = trimStart
        self.trimEnd = trimEnd
        self.originalDuration = originalDuration
        self.allowsDurationExtension = allowsDurationExtension
        self.speed = speed
        self.pixelsPerSecond = pixelsPerSecond
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let h = bounds.height
        leftHandle.frame = CGRect(x: 0, y: 0, width: handleWidth, height: h)
        rightHandle.frame = CGRect(x: bounds.width - handleWidth, y: 0, width: handleWidth, height: h)
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let handle = gesture.view as? TrimHandleView,
              let clipID else { return }

        switch gesture.state {
        case .began:
            baselineTrimStart = trimStart
            baselineTrimEnd = trimEnd
            scrollViewWhilePanning = enclosingScrollView()
            scrollViewWhilePanning?.isScrollEnabled = false
        case .changed:
            let deltaX = gesture.translation(in: self).x
            let deltaTimeline = TimeInterval(deltaX / pixelsPerSecond)
            let deltaSource = deltaTimeline * TimeInterval(max(speed, 0.001))
            let minSpan = EditorClip.minimumSourceSpan(speed: speed)

            var newStart = baselineTrimStart
            var newEnd = baselineTrimEnd

            switch handle.edge {
            case .start:
                newStart = baselineTrimStart + deltaSource
                newStart = min(max(0, newStart), baselineTrimEnd - minSpan)
            case .end:
                newEnd = baselineTrimEnd + deltaSource
                if allowsDurationExtension {
                    newEnd = max(newEnd, baselineTrimStart + minSpan)
                } else {
                    newEnd = max(min(originalDuration, newEnd), baselineTrimStart + minSpan)
                }
            }

            trimStart = newStart
            trimEnd = newEnd
            onTrimChanged?(clipID, newStart, newEnd)
        case .ended, .cancelled:
            scrollViewWhilePanning?.isScrollEnabled = true
            scrollViewWhilePanning = nil
            onTrimEnded?()
            gesture.setTranslation(.zero, in: self)
        default:
            break
        }
    }

    private func enclosingScrollView() -> UIScrollView? {
        var view: UIView? = superview
        while let current = view {
            if let scroll = current as? UIScrollView { return scroll }
            view = current.superview
        }
        return nil
    }
}

// MARK: - Handle chrome

private final class TrimHandleView: UIView {
    enum Edge { case start, end }

    let edge: Edge

    init(edge: Edge) {
        self.edge = edge
        super.init(frame: .zero)
        isUserInteractionEnabled = true
        backgroundColor = UIColor(Color.appColors.primaryColor).withAlphaComponent(0.92)

        let grip = UIView()
        grip.backgroundColor = UIColor.white.withAlphaComponent(0.85)
        grip.layer.cornerRadius = 1
        grip.translatesAutoresizingMaskIntoConstraints = false
        grip.isUserInteractionEnabled = false
        addSubview(grip)

        NSLayoutConstraint.activate([
            grip.centerXAnchor.constraint(equalTo: centerXAnchor),
            grip.centerYAnchor.constraint(equalTo: centerYAnchor),
            grip.widthAnchor.constraint(equalToConstant: 2),
            grip.heightAnchor.constraint(equalToConstant: 20)
        ])

        if edge == .start {
            layer.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner]
        } else {
            layer.maskedCorners = [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]
        }
        layer.cornerRadius = 4
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        let hit = bounds.insetBy(dx: -10, dy: -6)
        return hit.contains(point)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }
}
