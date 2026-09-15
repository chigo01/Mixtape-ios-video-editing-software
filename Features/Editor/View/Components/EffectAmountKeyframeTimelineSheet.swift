//
//  EffectAmountKeyframeTimelineSheet.swift
//  Mixtape
//

import SwiftUI
import PhotosUI

struct EffectAmountKeyframeTimelineSheet: View {
    let vm: EditorViewModel
    let effectID: UUID
    let onDone: () -> Void

    @State private var selectedKeyframeID: UUID?

    private let displayFrameRate = 30

    private var effect: EditorVisualEffect? {
        vm.selectedEffectStack.first { $0.id == effectID }
    }

    private var keyframes: [EditorKeyframe] {
        effect?.amountKeyframes.keyframes ?? []
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    timelineSummary
                    EffectKeyframeTimeRuler(
                        keyframes: keyframes,
                        duration: vm.selectedEffectTargetDuration,
                        playheadTime: vm.selectedEffectLocalTime,
                        selectedID: selectedKeyframeID,
                        onSelect: { point in
                            selectedKeyframeID = point.id
                            vm.scrubVisualEffectPlayhead(to: point.time)
                        },
                        onScrub: { vm.scrubVisualEffectPlayhead(to: $0) },
                        onScrubEnd: { vm.commitTimelineAfterScrub() },
                        onMove: { point, time in
                            vm.updateVisualEffectAmountKeyframe(
                                effectID: effectID, keyframeID: point.id, time: time
                            )
                        }
                    )
                    .frame(height: 150)

                    HStack {
                        Label(
                            timecode(vm.timelinePosition),
                            systemImage: "playhead.fill"
                        )
                        .font(.caption.monospacedDigit())
                        Spacer()
                        Button {
                            vm.keyframeVisualEffectAmount(effectID)
                            selectedKeyframeID = keyframes.min(by: {
                                abs($0.time - vm.selectedEffectLocalTime)
                                    < abs($1.time - vm.selectedEffectLocalTime)
                            })?.id
                        } label: {
                            Label("Add at Playhead", systemImage: "diamond.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.appColors.primaryColor)
                    }

                    keyframeList
                }
                .padding(18)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("\(effect?.kind.title ?? "Effect") Keyframes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDone)
                }
            }
        }
    }

    private var timelineSummary: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("EFFECT VALUES · PROJECT TIMECODE · 30 FPS")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Text("Tap a diamond to select. Drag it to change timing, or drag the playhead to scrub.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(keyframes.count) keyframe\(keyframes.count == 1 ? "" : "s")")
                .font(.caption.monospacedDigit())
        }
    }

    @ViewBuilder
    private var keyframeList: some View {
        if keyframes.isEmpty {
            ContentUnavailableView(
                "No Amount Keyframes",
                systemImage: "diamond",
                description: Text("Move the playhead and add the first keyframe.")
            )
            .frame(maxWidth: .infinity, minHeight: 150)
        } else {
            VStack(spacing: 8) {
                ForEach(Array(keyframes.enumerated()), id: \.element.id) { index, point in
                    let globalTime = vm.selectedEffectTargetStartTime + point.time
                    EffectKeyframeListRow(
                        index: index,
                        point: point,
                        secondaryTitle: effect?.kind.secondaryControlTitle,
                        secondaryValue: effect?.resolvedSecondaryAmount(at: point.time) ?? 0.5,
                        projectTimecode: timecode(globalTime),
                        projectFrame: frameNumber(globalTime),
                        isSelected: selectedKeyframeID == point.id,
                        onSelect: { select(point) },
                        onValueCommit: { value in
                            vm.updateVisualEffectAmountKeyframe(
                                effectID: effectID, keyframeID: point.id, value: value
                            )
                        },
                        onSecondaryCommit: { value in
                            vm.updateVisualEffectAmountKeyframe(
                                effectID: effectID, keyframeID: point.id, secondaryValue: value
                            )
                        },
                        onDelete: {
                            vm.deleteVisualEffectAmountKeyframe(
                                effectID: effectID,
                                keyframeID: point.id
                            )
                            if selectedKeyframeID == point.id { selectedKeyframeID = nil }
                        }
                    )
                }
            }
        }
    }

    private func select(_ point: EditorKeyframe) {
        selectedKeyframeID = point.id
        vm.seekToVisualEffectKeyframe(localTime: point.time)
    }

    private func frameNumber(_ seconds: TimeInterval) -> Int {
        Int((max(0, seconds) * Double(displayFrameRate)).rounded())
    }

    private func timecode(_ seconds: TimeInterval) -> String {
        let frames = frameNumber(seconds)
        let frame = frames % displayFrameRate
        let totalSeconds = frames / displayFrameRate
        let second = totalSeconds % 60
        let minute = (totalSeconds / 60) % 60
        let hour = totalSeconds / 3_600
        return String(format: "%02d:%02d:%02d:%02d", hour, minute, second, frame)
    }
}

private struct EffectKeyframeListRow: View {
    let index: Int
    let point: EditorKeyframe
    let secondaryTitle: String?
    let secondaryValue: Double
    let projectTimecode: String
    let projectFrame: Int
    let isSelected: Bool
    let onSelect: () -> Void
    let onValueCommit: (Double) -> Void
    let onSecondaryCommit: (Double) -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Button(action: onSelect) {
                    HStack(spacing: 12) {
                        Image(systemName: "diamond.fill")
                            .foregroundStyle(isSelected ? Color.white : Color.appColors.primaryColor)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Keyframe \(index + 1)  ·  \(projectTimecode)")
                                .font(.subheadline.bold().monospacedDigit())
                            Text("Project frame \(projectFrame)  ·  Local \(localTimeText)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 3) {
                            Text("\(Int((point.value * 100).rounded()))%")
                                .font(.subheadline.bold().monospacedDigit())
                            Text(point.curve.preset.title)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
            }

            EffectKeyframeValueSlider(
                title: "Amount", value: point.value,
                onSelect: onSelect, onCommit: onValueCommit
            )
            if let secondaryTitle {
                EffectKeyframeValueSlider(
                    title: secondaryTitle, value: secondaryValue,
                    onSelect: onSelect, onCommit: onSecondaryCommit
                )
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12).fill(
                isSelected
                    ? Color.appColors.primaryColor.opacity(0.18)
                    : Color.white.opacity(0.05)
            )
        )
    }

    private var localTimeText: String {
        String(format: "%.3fs", point.time)
    }
}

private struct EffectKeyframeValueSlider: View {
    let title: String
    let value: Double
    let onSelect: () -> Void
    let onCommit: (Double) -> Void

    @State private var draft: Double?

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int(((draft ?? value) * 100).rounded()))%")
                    .monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Slider(
                value: Binding(get: { draft ?? value }, set: { draft = $0 }),
                in: 0...1,
                step: 0.01,
                onEditingChanged: { editing in
                    if editing {
                        onSelect()
                    } else {
                        if let draft { onCommit(draft) }
                        draft = nil
                    }
                }
            )
            .tint(Color.appColors.primaryColor)
            .accessibilityLabel("Keyframe \(title)")
        }
    }
}

private struct EffectKeyframeTimeRuler: View {
    let keyframes: [EditorKeyframe]
    let duration: TimeInterval
    let playheadTime: TimeInterval
    let selectedID: UUID?
    let onSelect: (EditorKeyframe) -> Void
    let onScrub: (TimeInterval) -> Void
    let onScrubEnd: () -> Void
    let onMove: (EditorKeyframe, TimeInterval) -> Void

    @State private var isInteracting = false
    @State private var draggedPoint: EditorKeyframe?
    @State private var draftTime: TimeInterval?
    @State private var didMove = false

    private let inset: CGFloat = 22
    private let pointY: CGFloat = 88

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.3))

                ForEach(0...4, id: \.self) { index in
                    let time = duration * Double(index) / 4
                    let tickX = x(for: time, width: width)
                    Rectangle()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 1, height: 126)
                        .position(x: tickX, y: 87)
                    Text(shortTime(time))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .position(x: tickX, y: 12)
                }

                Capsule()
                    .fill(Color.white.opacity(0.16))
                    .frame(width: max(1, width - inset * 2), height: 3)
                    .position(x: width / 2, y: pointY)

                Rectangle()
                    .fill(Color.white.opacity(0.8))
                    .frame(width: 2, height: 96)
                    .position(x: x(for: draftTime ?? playheadTime, width: width), y: 94)
                Image(systemName: "arrowtriangle.down.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .position(x: x(for: draftTime ?? playheadTime, width: width), y: 40)

                ForEach(keyframes) { point in
                    EffectKeyframeDiamondShape()
                        .fill(point.id == selectedID ? Color.white : Color.appColors.primaryColor)
                        .frame(width: point.id == selectedID ? 24 : 20,
                               height: point.id == selectedID ? 24 : 20)
                        .position(
                            x: x(for: draggedPoint?.id == point.id ? (draftTime ?? point.time) : point.time, width: width),
                            y: pointY
                        )
                        .accessibilityLabel("Keyframe at \(shortTime(point.time))")
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction {
                            onSelect(point)
                            onScrubEnd()
                        }
                }
            }
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        if !isInteracting {
                            isInteracting = true
                            let nearest = keyframes.min {
                                abs(x(for: $0.time, width: width) - gesture.startLocation.x)
                                    < abs(x(for: $1.time, width: width) - gesture.startLocation.x)
                            }
                            // The upper handle always scrubs, even above a selected diamond.
                            if let nearest,
                               abs(gesture.startLocation.y - pointY) <= 24,
                               abs(x(for: nearest.time, width: width) - gesture.startLocation.x) <= 24 {
                                draggedPoint = nearest
                                onSelect(nearest)
                            }
                        }
                        if let point = draggedPoint {
                            guard didMove || abs(gesture.translation.width) >= 3 else { return }
                            didMove = true
                            let requested = point.time
                                + Double(gesture.translation.width / max(1, width - inset * 2)) * duration
                            let time = constrainedTime(requested, for: point)
                            draftTime = time
                            onScrub(time)
                        } else {
                            onScrub(time(at: gesture.location.x, width: width))
                        }
                    }
                    .onEnded { _ in
                        if let point = draggedPoint, let draftTime, didMove {
                            onMove(point, draftTime)
                        } else {
                            onScrubEnd()
                        }
                        isInteracting = false
                        draggedPoint = nil
                        draftTime = nil
                        didMove = false
                    }
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func constrainedTime(_ time: TimeInterval, for point: EditorKeyframe) -> TimeInterval {
        let previous = keyframes.last { $0.time < point.time }?.time
        let next = keyframes.first { $0.time > point.time }?.time
        let lower = previous.map { $0 + min(1.0 / 30, (point.time - $0) / 2) } ?? 0
        let upper = next.map { $0 - min(1.0 / 30, ($0 - point.time) / 2) } ?? duration
        return min(max(time, lower), max(lower, upper))
    }

    private func x(for time: TimeInterval, width: CGFloat) -> CGFloat {
        let progress = min(max(time / max(duration, 0.000_001), 0), 1)
        return inset + max(1, width - inset * 2) * CGFloat(progress)
    }

    private func time(at x: CGFloat, width: CGFloat) -> TimeInterval {
        Double(min(max((x - inset) / max(1, width - inset * 2), 0), 1)) * max(0, duration)
    }

    private func shortTime(_ time: TimeInterval) -> String {
        String(format: "%.2fs", max(0, time))
    }
}

private struct EffectKeyframeDiamondShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
            path.closeSubpath()
        }
    }
}

