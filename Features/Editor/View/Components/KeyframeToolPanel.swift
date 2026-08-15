//
//  KeyframeToolPanel.swift
//  Mixtape
//

import SwiftUI

struct KeyframeToolPanel: View {
    let vm: EditorViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var selectedProperty: EditorKeyframeProperty
    @State private var selectedKeyframeID: UUID?
    @State private var draftValue: Double = 0
    @State private var draftTime: TimeInterval = 0
    @State private var draftCurve: EditorKeyframeCurve = .linear

    init(vm: EditorViewModel) {
        self.vm = vm
        _selectedProperty = State(
            initialValue: vm.availableKeyframeProperties.first ?? .positionX
        )
    }

    private var track: EditorKeyframeTrack {
        vm.selectedKeyframeTrack(for: selectedProperty)
    }

    private var selectedPoint: EditorKeyframe? {
        guard let selectedKeyframeID else { return nil }
        return track.keyframes.first { $0.id == selectedKeyframeID }
    }

    private var previousKeyframe: EditorKeyframe? {
        track.keyframes.last { $0.time < vm.keyframeLocalTime - 0.001 }
    }

    private var nextKeyframe: EditorKeyframe? {
        track.keyframes.first { $0.time > vm.keyframeLocalTime + 0.001 }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    propertyPicker

                    KeyframeCurveGraph(
                        track: track,
                        duration: vm.keyframeTargetDuration,
                        selectedID: selectedKeyframeID,
                        playheadTime: vm.keyframeLocalTime,
                        onSelect: select,
                        onScrubChanged: scrub,
                        onScrubEnded: finishScrubbing
                    )
                    .frame(height: 190)

                    HStack(spacing: 12) {
                        Label(
                            String(format: "%.2fs", vm.keyframeLocalTime),
                            systemImage: "playhead.fill"
                        )
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)

                        Button {
                            if let previousKeyframe { select(previousKeyframe) }
                        } label: {
                            Image(systemName: "chevron.left.to.line")
                        }
                        .buttonStyle(.bordered)
                        .disabled(previousKeyframe == nil)
                        .accessibilityLabel("Previous keyframe")

                        Button {
                            if let nextKeyframe { select(nextKeyframe) }
                        } label: {
                            Image(systemName: "chevron.right.to.line")
                        }
                        .buttonStyle(.bordered)
                        .disabled(nextKeyframe == nil)
                        .accessibilityLabel("Next keyframe")

                        Spacer(minLength: 0)

                        Button {
                            let id = vm.upsertSelectedKeyframe(
                                property: selectedProperty,
                                value: vm.selectedKeyframeValue(for: selectedProperty)
                            )
                            selectedKeyframeID = id
                            syncDrafts()
                        } label: {
                            Label("Add at Playhead", systemImage: "diamond.fill")
                                .font(.subheadline.weight(.semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.appColors.primaryColor)
                    }

                    if selectedPoint != nil {
                        pointEditor
                        curveEditor
                    } else {
                        Text("Add a keyframe or select a diamond to edit its time, value, and outgoing curve.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 18)
                    }
                }
                .padding(18)
            }
            .navigationTitle("\(vm.keyframeTargetTitle) Keyframes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button {
                        vm.undo()
                        reconcileSelection()
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .disabled(!vm.canUndo)
                    .accessibilityLabel("Undo keyframe change")

                    Button {
                        vm.redo()
                        reconcileSelection()
                    } label: {
                        Image(systemName: "arrow.uturn.forward")
                    }
                    .disabled(!vm.canRedo)
                    .accessibilityLabel("Redo keyframe change")
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        vm.selectedTool = nil
                        dismiss()
                    }
                }
            }
            .onChange(of: selectedProperty) { _, _ in
                selectedKeyframeID = nil
                syncDrafts()
            }
        }
    }

    private var propertyPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(vm.availableKeyframeProperties) { property in
                    Button {
                        selectedProperty = property
                    } label: {
                        Label(property.title, systemImage: property.systemImage)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(selectedProperty == property ? .black : .white)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 8)
                            .background(
                                Capsule().fill(
                                    selectedProperty == property
                                        ? Color.appColors.primaryColor
                                        : Color.white.opacity(0.08)
                                )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var pointEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("KEYFRAME").font(.caption.bold()).foregroundStyle(.secondary)

            HStack(spacing: 12) {
                VStack(alignment: .leading) {
                    Text("Time").font(.caption2).foregroundStyle(.secondary)
                    TextField("Time", value: $draftTime, format: .number.precision(.fractionLength(2)))
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading) {
                    Text("Value").font(.caption2).foregroundStyle(.secondary)
                    TextField("Value", value: $draftValue, format: .number.precision(.fractionLength(3)))
                        .keyboardType(.numbersAndPunctuation)
                        .textFieldStyle(.roundedBorder)
                }
            }

            Slider(
                value: $draftValue,
                in: selectedProperty.range
            )

            HStack {
                Button(role: .destructive) {
                    guard let id = selectedKeyframeID else { return }
                    vm.deleteSelectedKeyframe(property: selectedProperty, id: id)
                    selectedKeyframeID = nil
                } label: {
                    Label("Delete", systemImage: "trash")
                }

                Spacer()

                Button("Apply Point") {
                    guard let id = selectedKeyframeID else { return }
                    vm.updateSelectedKeyframe(
                        property: selectedProperty,
                        id: id,
                        time: draftTime,
                        value: draftValue
                    )
                    vm.seekToSelectedKeyframe(localTime: draftTime)
                    syncDrafts()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
    }

    private var curveEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("OUTGOING CURVE").font(.caption.bold()).foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(EditorKeyframeCurvePreset.allCases) { preset in
                        Button(preset.title) {
                            draftCurve.applyPreset(preset)
                        }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.bordered)
                        .tint(draftCurve.preset == preset ? Color.appColors.primaryColor : .gray)
                    }
                }
            }

            KeyframeBezierEditor(curve: $draftCurve)
                .frame(height: 150)

            Button("Apply Curve") {
                guard let id = selectedKeyframeID else { return }
                vm.updateSelectedKeyframeCurve(
                    property: selectedProperty,
                    id: id,
                    curve: draftCurve
                )
                syncDrafts()
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
    }

    private func select(_ keyframe: EditorKeyframe) {
        selectedKeyframeID = keyframe.id
        draftValue = keyframe.value
        draftTime = keyframe.time
        draftCurve = keyframe.curve
        vm.seekToSelectedKeyframe(localTime: keyframe.time)
    }

    private func scrub(to time: TimeInterval) {
        vm.scrubSelectedKeyframePlayhead(to: snappedTime(for: time))
    }

    private func finishScrubbing(at time: TimeInterval) {
        let time = snappedTime(for: time)
        vm.scrubSelectedKeyframePlayhead(to: time)
        vm.commitSelectedKeyframePlayhead()
        if let point = track.keyframes.min(by: {
            abs($0.time - time) < abs($1.time - time)
        }), abs(point.time - time) < 0.001 {
            selectedKeyframeID = point.id
            syncDrafts()
        }
    }

    private func snappedTime(for time: TimeInterval) -> TimeInterval {
        guard let nearest = track.keyframes.min(by: {
            abs($0.time - time) < abs($1.time - time)
        }) else { return time }
        let threshold = max(0.12, vm.keyframeTargetDuration * 0.025)
        return abs(nearest.time - time) <= threshold ? nearest.time : time
    }

    private func reconcileSelection() {
        if let selectedKeyframeID,
           !track.keyframes.contains(where: { $0.id == selectedKeyframeID }) {
            self.selectedKeyframeID = nil
        }
        syncDrafts()
    }

    private func syncDrafts() {
        guard let selectedPoint else {
            draftValue = vm.selectedKeyframeValue(for: selectedProperty)
            draftTime = vm.keyframeLocalTime
            draftCurve = .linear
            return
        }
        draftValue = selectedPoint.value
        draftTime = selectedPoint.time
        draftCurve = selectedPoint.curve
    }
}

private struct KeyframeCurveGraph: View {
    let track: EditorKeyframeTrack
    let duration: TimeInterval
    let selectedID: UUID?
    let playheadTime: TimeInterval
    let onSelect: (EditorKeyframe) -> Void
    let onScrubChanged: (TimeInterval) -> Void
    let onScrubEnded: (TimeInterval) -> Void

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.25))

                gridPath(size: size)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)

                curvePath(size: size)
                    .stroke(Color.appColors.primaryColor, style: StrokeStyle(lineWidth: 2, lineJoin: .round))

                Rectangle()
                    .fill(Color.white.opacity(0.55))
                    .frame(width: 1)
                    .offset(x: x(for: playheadTime, width: size.width) - size.width / 2)

                ForEach(track.keyframes) { point in
                    DiamondShape()
                        .fill(point.id == selectedID ? Color.white : Color.appColors.primaryColor)
                        .frame(width: 15, height: 15)
                        .position(
                            x: x(for: point.time, width: size.width),
                            y: y(for: point.value, height: size.height)
                        )
                        .contentShape(Rectangle().inset(by: -10))
                        .onTapGesture { onSelect(point) }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .coordinateSpace(name: "keyframeGraph")
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(
                    minimumDistance: 0,
                    coordinateSpace: .named("keyframeGraph")
                )
                .onChanged { gesture in
                    onScrubChanged(time(at: gesture.location.x, width: size.width))
                }
                .onEnded { gesture in
                    onScrubEnded(time(at: gesture.location.x, width: size.width))
                }
            )
        }
    }

    private func x(for time: TimeInterval, width: CGFloat) -> CGFloat {
        width * CGFloat(min(max(time / max(duration, 0.000_001), 0), 1))
    }

    private func time(at x: CGFloat, width: CGFloat) -> TimeInterval {
        Double(min(max(x / max(width, 1), 0), 1)) * max(duration, 0)
    }

    private func y(for value: Double, height: CGFloat) -> CGFloat {
        let range = track.property.range
        let normalized = (value - range.lowerBound) / max(range.upperBound - range.lowerBound, 0.000_001)
        return height * CGFloat(1 - min(max(normalized, 0), 1))
    }

    private func gridPath(size: CGSize) -> Path {
        Path { path in
            for index in 1..<4 {
                let x = size.width * CGFloat(index) / 4
                let y = size.height * CGFloat(index) / 4
                path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height))
                path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y))
            }
        }
    }

    private func curvePath(size: CGSize) -> Path {
        Path { path in
            guard !track.keyframes.isEmpty else { return }
            let sampleCount = max(24, Int(size.width / 4))
            for index in 0...sampleCount {
                let time = duration * Double(index) / Double(sampleCount)
                let value = track.value(at: time, default: track.keyframes[0].value)
                let point = CGPoint(x: x(for: time, width: size.width), y: y(for: value, height: size.height))
                if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
        }
    }
}

private struct KeyframeBezierEditor: View {
    @Binding var curve: EditorKeyframeCurve

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.25))
                Path { path in
                    path.move(to: CGPoint(x: 0, y: size.height))
                    for index in 1...48 {
                        let progress = Double(index) / 48
                        path.addLine(to: CGPoint(
                            x: size.width * CGFloat(progress),
                            y: size.height * CGFloat(1 - curve.solve(progress))
                        ))
                    }
                }
                .stroke(Color.appColors.primaryColor, lineWidth: 2)

                handle(curve.controlPoint1, size: size) { point in
                    curve.preset = .custom
                    curve.controlPoint1 = point
                }
                handle(curve.controlPoint2, size: size) { point in
                    curve.preset = .custom
                    curve.controlPoint2 = point
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .coordinateSpace(name: "bezierEditor")
        }
    }

    private func handle(
        _ point: CGPoint,
        size: CGSize,
        update: @escaping (CGPoint) -> Void
    ) -> some View {
        Circle()
            .fill(Color.white)
            .frame(width: 16, height: 16)
            .position(x: size.width * point.x, y: size.height * (1 - point.y))
            .gesture(
                DragGesture(
                    minimumDistance: 0,
                    coordinateSpace: .named("bezierEditor")
                )
                    .onChanged { gesture in
                        update(CGPoint(
                            x: min(max(gesture.location.x / max(size.width, 1), 0), 1),
                            y: 1 - min(max(gesture.location.y / max(size.height, 1), 0), 1)
                        ))
                    }
            )
    }
}

private struct DiamondShape: Shape {
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
