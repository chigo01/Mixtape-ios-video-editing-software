//
//  KeyframeToolPanel.swift
//  Mixtape
//

import SwiftUI

struct KeyframeToolPanel: View {
    let vm: EditorViewModel
    let isEmbedded: Bool

    @State private var selectedProperty: EditorKeyframeProperty
    @State private var selectedKeyframeID: UUID?
    @State private var draftValue: Double = 0
    @State private var draftTime: TimeInterval = 0
    @State private var draftCurve: EditorKeyframeCurve = .linear

    init(vm: EditorViewModel, isEmbedded: Bool = false) {
        self.vm = vm
        self.isEmbedded = isEmbedded
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
        Group {
            if isEmbedded {
                VStack(spacing: 0) {
                    embeddedHeader
                    Divider().overlay(Color.white.opacity(0.1))
                    panelContent
                }
            } else {
                NavigationStack {
                    panelContent
                        .navigationTitle("\(vm.keyframeTargetTitle) Keyframes")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar { nativeToolbar }
                }
            }
        }
        .onChange(of: selectedProperty) { _, _ in
            selectedKeyframeID = nil
            syncDrafts()
        }
        .onChange(of: track.keyframes) { _, _ in
            reconcileSelection()
        }
    }

    private var panelContent: some View {
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
                        onScrubEnded: finishScrubbing,
                        onMoveChanged: { point, time in
                            draftTime = time
                            vm.scrubSelectedKeyframePlayhead(to: time)
                        },
                        onMoveEnded: { point, time in
                            vm.updateSelectedKeyframe(property: selectedProperty, id: point.id, time: time)
                            vm.seekToSelectedKeyframe(localTime: time)
                            syncDrafts()
                        }
                    )
                    .id(selectedProperty)
                    .frame(height: 190)

                    Text("Tap a point to select. Drag it left or right to change timing. Drag the playhead or background to scrub.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

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
    }

    @ToolbarContentBuilder
    private var nativeToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarLeading) {
            historyButton("arrow.uturn.backward", enabled: vm.canUndo, action: undo)
            historyButton("arrow.uturn.forward", enabled: vm.canRedo, action: redo)
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Done") { vm.selectedTool = nil }
        }
    }

    private var embeddedHeader: some View {
        ZStack {
            Text("\(vm.keyframeTargetTitle) Keyframes")
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(.white)
            HStack(spacing: 8) {
                historyButton("arrow.uturn.backward", enabled: vm.canUndo, action: undo)
                historyButton("arrow.uturn.forward", enabled: vm.canRedo, action: redo)
                Spacer()
                Button("Done") { vm.selectedTool = nil }
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color.appColors.primaryColor)
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 48)
    }

    private func historyButton(
        _ systemImage: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) { Image(systemName: systemImage) }
            .disabled(!enabled)
    }

    private func undo() { vm.undo(); reconcileSelection() }
    private func redo() { vm.redo(); reconcileSelection() }

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
        vm.scrubSelectedKeyframePlayhead(to: time)
    }

    private func finishScrubbing(at time: TimeInterval) {
        vm.scrubSelectedKeyframePlayhead(to: time)
        vm.commitSelectedKeyframePlayhead()
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
    let onMoveChanged: (EditorKeyframe, TimeInterval) -> Void
    let onMoveEnded: (EditorKeyframe, TimeInterval) -> Void

    @State private var interacting = false
    @State private var draggedPoint: EditorKeyframe?
    @State private var movedTime: TimeInterval?
    private let inset: CGFloat = 24

    private var displayedTrack: EditorKeyframeTrack {
        var result = track
        if let draggedPoint, let movedTime { result.update(id: draggedPoint.id, time: movedTime) }
        return result
    }

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
                    .frame(width: 2, height: max(1, size.height - 24))
                    .position(x: x(for: movedTime ?? playheadTime, width: size.width), y: size.height / 2 + 12)

                Image(systemName: "arrowtriangle.down.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .position(x: x(for: movedTime ?? playheadTime, width: size.width), y: 10)

                ForEach(displayedTrack.keyframes) { point in
                    DiamondShape()
                        .fill(point.id == selectedID ? Color.white : Color.appColors.primaryColor)
                        .frame(width: 20, height: 20)
                        .position(
                            x: x(for: point.time, width: size.width),
                            y: y(for: point.value, height: size.height)
                        )
                        .accessibilityLabel("Keyframe at \(String(format: "%.2f", point.time)) seconds")
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { onSelect(point) }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .coordinateSpace(name: "keyframeGraph")
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("keyframeGraph"))
                    .onChanged { gesture in
                        if !interacting {
                            interacting = true
                            let nearest = track.keyframes.min {
                                distance(to: $0, from: gesture.startLocation, size: size)
                                    < distance(to: $1, from: gesture.startLocation, size: size)
                            }
                            if let nearest, gesture.startLocation.y > 20,
                               distance(to: nearest, from: gesture.startLocation, size: size) <= 26 {
                                draggedPoint = nearest
                                onSelect(nearest)
                            }
                        }
                        if let point = draggedPoint {
                            guard movedTime != nil || abs(gesture.translation.width) >= 3 else { return }
                            let requested = point.time
                                + Double(gesture.translation.width / max(1, size.width - inset * 2)) * duration
                            let time = constrainedTime(requested, point: point)
                            movedTime = time
                            onMoveChanged(point, time)
                        } else {
                            onScrubChanged(time(at: gesture.location.x, width: size.width))
                        }
                    }
                    .onEnded { gesture in
                        if let point = draggedPoint {
                            if let movedTime, abs(movedTime - point.time) > 0.000001 {
                                onMoveEnded(point, movedTime)
                            }
                        } else {
                            onScrubEnded(time(at: gesture.location.x, width: size.width))
                        }
                        interacting = false
                        draggedPoint = nil
                        movedTime = nil
                    }
            )
        }
    }

    private func distance(to point: EditorKeyframe, from location: CGPoint, size: CGSize) -> CGFloat {
        hypot(x(for: point.time, width: size.width) - location.x,
              y(for: point.value, height: size.height) - location.y)
    }

    private func constrainedTime(_ time: TimeInterval, point: EditorKeyframe) -> TimeInterval {
        let previous = track.keyframes.last { $0.time < point.time }?.time
        let next = track.keyframes.first { $0.time > point.time }?.time
        let lower = previous.map { $0 + min(1.0 / 30, (point.time - $0) / 2) } ?? 0
        let upper = next.map { $0 - min(1.0 / 30, ($0 - point.time) / 2) } ?? duration
        return min(max(time, lower), max(lower, upper))
    }

    private func x(for time: TimeInterval, width: CGFloat) -> CGFloat {
        inset + max(1, width - inset * 2) * CGFloat(min(max(time / max(duration, 0.000_001), 0), 1))
    }

    private func time(at x: CGFloat, width: CGFloat) -> TimeInterval {
        Double(min(max((x - inset) / max(width - inset * 2, 1), 0), 1)) * max(duration, 0)
    }

    private func y(for value: Double, height: CGFloat) -> CGFloat {
        let range = track.property.range
        let normalized = (value - range.lowerBound) / max(range.upperBound - range.lowerBound, 0.000_001)
        return inset + max(1, height - inset * 2) * CGFloat(1 - min(max(normalized, 0), 1))
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
                let value = displayedTrack.value(at: time, default: track.keyframes[0].value)
                let point = CGPoint(x: x(for: time, width: size.width), y: y(for: value, height: size.height))
                if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
        }
    }
}

private struct KeyframeBezierEditor: View {
    @Binding var curve: EditorKeyframeCurve
    @State private var handleOrigins: [Int: CGPoint] = [:]

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

                handle(curve.controlPoint1, index: 1, size: size) { point in
                    curve.preset = .custom
                    curve.controlPoint1 = point
                }
                handle(curve.controlPoint2, index: 2, size: size) { point in
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
        index: Int,
        size: CGSize,
        update: @escaping (CGPoint) -> Void
    ) -> some View {
        Circle()
            .fill(Color.white)
            .frame(width: 16, height: 16)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .position(x: size.width * point.x, y: size.height * (1 - point.y))
            .gesture(
                DragGesture(
                    minimumDistance: 0,
                    coordinateSpace: .named("bezierEditor")
                )
                    .onChanged { gesture in
                        if handleOrigins[index] == nil { handleOrigins[index] = point }
                        let origin = handleOrigins[index] ?? point
                        update(CGPoint(
                            x: min(max(origin.x + gesture.translation.width / max(size.width, 1), 0), 1),
                            y: min(max(origin.y - gesture.translation.height / max(size.height, 1), 0), 1)
                        ))
                    }
                    .onEnded { _ in handleOrigins[index] = nil }
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
