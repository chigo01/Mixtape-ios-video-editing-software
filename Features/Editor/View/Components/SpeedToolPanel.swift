//
//  SpeedToolPanel.swift
//  Mixtape
//

import SwiftUI

struct SpeedToolPanel: View {
    let vm: EditorViewModel

    private enum Mode: String, CaseIterable, Identifiable {
        case normal
        case curve
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }

    @State private var mode: Mode = .normal
    @State private var selectedPointIndex = 1

    private let presets: [(label: String, value: Float)] = [
        ("0.5×", 0.5),
        ("0.75×", 0.75),
        ("1×", 1.0),
        ("1.5×", 1.5),
        ("2×", 2.0)
    ]

    private var activeSpeed: Float? {
        vm.selectedOverlayClip?.speed ?? vm.selectedClip?.speed
    }

    private var hasSelection: Bool {
        vm.selectedOverlayClipID != nil || vm.selectedClipID != nil
    }

    private var primaryClip: EditorClip? { vm.selectedClip }
    private var activeRamp: EditorSpeedRamp? { primaryClip?.speedRamp }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Speed")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                if let clip = primaryClip, mode == .curve, clip.speedRamp != nil {
                    Text(String(format: "%.2f s", clip.duration))
                        .font(.system(size: 12, weight: .bold).monospacedDigit())
                        .foregroundColor(Color.appColors.primaryColor)
                } else if let activeSpeed {
                    Text(String(format: "%.2g×", activeSpeed))
                        .font(.system(size: 13, weight: .bold).monospacedDigit())
                        .foregroundColor(Color.appColors.primaryColor)
                }
            }

            if !hasSelection {
                Text("Select a clip to change speed.")
                    .font(.system(size: 12))
                    .foregroundColor(Color.white.opacity(0.55))
            } else {
                Picker("Speed mode", selection: $mode) {
                    ForEach(Mode.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: mode) { _, newMode in
                    guard let clip = primaryClip else { return }
                    if newMode == .curve, clip.isVideo, clip.speedRamp == nil {
                        vm.enableSpeedRamp(clipID: clip.id)
                    } else if newMode == .normal, clip.speedRamp != nil {
                        vm.clearSpeedRamp(clipID: clip.id)
                    }
                }

                if mode == .normal {
                    normalControls
                } else if vm.selectedOverlayClipID != nil {
                    Text("Speed curves currently apply to primary video clips. Overlay clips support normal speed.")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.55))
                } else if primaryClip?.isPhoto == true {
                    Text("Use Photo Duration for still images. Speed curves require a video clip.")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.55))
                } else if let clip = primaryClip, let ramp = activeRamp {
                    curveControls(clip: clip, ramp: ramp)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .onAppear {
            mode = activeRamp == nil ? .normal : .curve
        }
        .onChange(of: vm.selectedClipID) { _, _ in
            mode = activeRamp == nil ? .normal : .curve
            selectedPointIndex = min(1, max(0, (activeRamp?.points.count ?? 1) - 1))
        }
    }

    private var normalControls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                ForEach(presets, id: \.label) { preset in
                    speedChip(preset)
                }
            }

            Slider(
                value: Binding(
                    get: { Double(activeSpeed ?? 1) },
                    set: { setSpeed(Float($0), commit: false) }
                ),
                in: 0.25...3.0,
                step: 0.05
            ) {
                Text("Speed")
            } minimumValueLabel: {
                Text("0.25×").font(.system(size: 10)).foregroundColor(.white.opacity(0.5))
            } maximumValueLabel: {
                Text("3×").font(.system(size: 10)).foregroundColor(.white.opacity(0.5))
            } onEditingChanged: { editing in
                if !editing, let activeSpeed { setSpeed(activeSpeed, commit: true) }
            }
            .tint(Color.appColors.primaryColor)
        }
    }

    @ViewBuilder
    private func curveControls(clip: EditorClip, ramp: EditorSpeedRamp) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(EditorSpeedRampPreset.allCases) { preset in
                        Button {
                            vm.applySpeedRampPreset(preset, clipID: clip.id)
                            selectedPointIndex = min(1, preset.ramp.points.count - 1)
                        } label: {
                            VStack(spacing: 5) {
                                Image(systemName: preset.systemImage)
                                    .font(.system(size: 13, weight: .semibold))
                                Text(preset.title)
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .frame(width: 68, height: 48)
                            .background(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(Color.white.opacity(0.08))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            SpeedRampCurveEditor(
                ramp: ramp,
                playheadProgress: vm.selectedClipSourceProgress,
                selectedPointIndex: $selectedPointIndex,
                onChange: { index, position, speed in
                    vm.setSpeedRampPoint(
                        clipID: clip.id,
                        index: index,
                        position: position,
                        speed: speed
                    )
                },
                onCommit: { vm.commitSpeedRampEdit() }
            )
            .frame(height: 142)

            HStack(spacing: 10) {
                Picker(
                    "Curve interpolation",
                    selection: Binding(
                        get: { ramp.interpolation },
                        set: { vm.setSpeedRampInterpolation($0, clipID: clip.id) }
                    )
                ) {
                    ForEach(EditorSpeedRampInterpolation.allCases) { interpolation in
                        Text(interpolation.title).tag(interpolation)
                    }
                }
                .pickerStyle(.segmented)

                Button {
                    addPoint(
                        to: ramp,
                        clipID: clip.id,
                        preferredPosition: vm.selectedClipSourceProgress
                    )
                } label: {
                    Label("Point", systemImage: "plus")
                        .font(.system(size: 11, weight: .bold))
                }
                .buttonStyle(.bordered)
                .tint(Color.appColors.primaryColor)

                Button(role: .destructive) {
                    vm.removeSpeedRampPoint(clipID: clip.id, index: selectedPointIndex)
                    selectedPointIndex = max(0, selectedPointIndex - 1)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.bordered)
                .disabled(
                    selectedPointIndex == 0
                        || selectedPointIndex >= ramp.points.count - 1
                        || ramp.points.count <= 2
                )

                Button("Reset") {
                    vm.clearSpeedRamp(clipID: clip.id)
                    mode = .normal
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.75))
            }

            if ramp.points.indices.contains(selectedPointIndex) {
                let point = ramp.points[selectedPointIndex]
                HStack {
                    Text(String(format: "Point %d  •  %.2f×", selectedPointIndex + 1, point.speed))
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundColor(.white.opacity(0.7))
                    Spacer()
                    Text("Drag points vertically for speed, horizontally for timing")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
        }
    }

    private func addPoint(
        to ramp: EditorSpeedRamp,
        clipID: UUID,
        preferredPosition: Double?
    ) {
        let pairs = zip(ramp.points, ramp.points.dropFirst())
        let largestGap = pairs.max { lhs, rhs in
            (lhs.1.position - lhs.0.position) < (rhs.1.position - rhs.0.position)
        }
        guard let gap = largestGap else { return }
        let requested = preferredPosition ?? (gap.0.position + gap.1.position) / 2
        let position = ramp.points.contains(where: { abs($0.position - requested) < 0.025 })
            ? (gap.0.position + gap.1.position) / 2
            : requested
        vm.addSpeedRampPoint(clipID: clipID, position: position)
        if let updated = vm.selectedClip?.speedRamp,
           let index = updated.points.firstIndex(where: { abs($0.position - position) < 0.001 }) {
            selectedPointIndex = index
        }
    }

    private func speedChip(_ preset: (label: String, value: Float)) -> some View {
        let isActive = abs((activeSpeed ?? 1) - preset.value) < 0.02
        return Button {
            setSpeed(preset.value, commit: true)
        } label: {
            Text(preset.label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(isActive ? .black : .white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule().fill(isActive ? Color.appColors.primaryColor : Color.white.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
        .disabled(!hasSelection)
    }

    private func setSpeed(_ speed: Float, commit: Bool) {
        if let id = vm.selectedOverlayClipID {
            if commit {
                vm.commitOverlaySpeed(clipID: id, speed: speed)
            } else {
                vm.setOverlaySpeed(clipID: id, speed: speed)
            }
        } else if let id = vm.selectedClipID {
            if commit {
                vm.commitSpeed(clipID: id, speed: speed)
            } else {
                vm.setSpeed(clipID: id, speed: speed)
            }
        }
    }
}

private struct SpeedRampCurveEditor: View {
    let ramp: EditorSpeedRamp
    let playheadProgress: Double?
    @Binding var selectedPointIndex: Int
    let onChange: (_ index: Int, _ position: Double, _ speed: Float) -> Void
    let onCommit: () -> Void

    private let inset: CGFloat = 16

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.black.opacity(0.28))
                grid(in: size)
                if let playheadProgress {
                    Rectangle()
                        .fill(Color.white.opacity(0.6))
                        .frame(width: 1, height: max(1, size.height - inset * 2))
                        .position(
                            x: inset + CGFloat(playheadProgress) * max(1, size.width - inset * 2),
                            y: size.height / 2
                        )
                        .allowsHitTesting(false)
                }
                curve(in: size)
                    .stroke(
                        Color.appColors.primaryColor,
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                    )

                ForEach(Array(ramp.points.enumerated()), id: \.offset) { index, point in
                    Circle()
                        .fill(index == selectedPointIndex ? Color.appColors.primaryColor : .white)
                        .frame(width: index == selectedPointIndex ? 15 : 12,
                               height: index == selectedPointIndex ? 15 : 12)
                        .overlay(Circle().stroke(Color.black.opacity(0.65), lineWidth: 2))
                        .position(location(for: point, in: size))
                        .contentShape(Rectangle().inset(by: -12))
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    selectedPointIndex = index
                                    onChange(
                                        index,
                                        position(forX: value.location.x, in: size),
                                        speed(forY: value.location.y, in: size)
                                    )
                                }
                                .onEnded { _ in onCommit() }
                        )
                        .accessibilityLabel("Speed point \(index + 1)")
                        .accessibilityValue(String(format: "%.2f times", point.speed))
                }
            }
        }
    }

    private func grid(in size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach([0.1, 1.0, 8.0], id: \.self) { speed in
                let y = yPosition(for: Float(speed), in: size)
                Path { path in
                    path.move(to: CGPoint(x: inset, y: y))
                    path.addLine(to: CGPoint(x: size.width - inset, y: y))
                }
                .stroke(Color.white.opacity(speed == 1 ? 0.18 : 0.08), lineWidth: 1)

                Text(String(format: speed < 1 ? "%.1f×" : "%.0f×", speed))
                    .font(.system(size: 8, weight: .medium).monospacedDigit())
                    .foregroundColor(.white.opacity(0.35))
                    .position(x: 13, y: max(8, y - 7))
            }
        }
    }

    private func curve(in size: CGSize) -> Path {
        Path { path in
            for sample in 0...100 {
                let progress = Double(sample) / 100
                let point = CGPoint(
                    x: inset + CGFloat(progress) * max(1, size.width - inset * 2),
                    y: yPosition(for: ramp.speed(atSourceProgress: progress), in: size)
                )
                if sample == 0 {
                    path.move(to: point)
                } else {
                    path.addLine(to: point)
                }
            }
        }
    }

    private func location(for point: EditorSpeedRampPoint, in size: CGSize) -> CGPoint {
        CGPoint(
            x: inset + CGFloat(point.position) * max(1, size.width - inset * 2),
            y: yPosition(for: point.speed, in: size)
        )
    }

    private func position(forX x: CGFloat, in size: CGSize) -> Double {
        Double(min(max((x - inset) / max(1, size.width - inset * 2), 0), 1))
    }

    private func yPosition(for speed: Float, in size: CGSize) -> CGFloat {
        let minimum = log(Double(EditorSpeedRamp.minimumSpeed))
        let maximum = log(Double(EditorSpeedRamp.maximumSpeed))
        let value = log(Double(EditorSpeedRamp.clampedSpeed(speed)))
        let normalized = (value - minimum) / (maximum - minimum)
        return inset + CGFloat(1 - normalized) * max(1, size.height - inset * 2)
    }

    private func speed(forY y: CGFloat, in size: CGSize) -> Float {
        let normalized = Double(
            1 - min(max((y - inset) / max(1, size.height - inset * 2), 0), 1)
        )
        let minimum = log(Double(EditorSpeedRamp.minimumSpeed))
        let maximum = log(Double(EditorSpeedRamp.maximumSpeed))
        return Float(exp(minimum + normalized * (maximum - minimum)))
    }
}

struct PhotoDurationToolPanel: View {
    let vm: EditorViewModel

    private let presets: [TimeInterval] = [1, 3, 5, 10]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Photo duration")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                if let clip = vm.selectedDurationClip, clip.isPhoto {
                    Text(formatted(clip.duration))
                        .font(.system(size: 13, weight: .bold).monospacedDigit())
                        .foregroundColor(Color.appColors.primaryColor)
                }
            }

            if vm.selectedDurationClip?.isPhoto == true {
                HStack(spacing: 8) {
                    ForEach(presets, id: \.self) { preset in
                        durationChip(preset)
                    }
                }

                durationSlider
            } else {
                Text("Select a photo clip to change its duration.")
                    .font(.system(size: 12))
                    .foregroundColor(Color.white.opacity(0.55))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
        .padding(.horizontal, 12)
    }

    private func durationChip(_ duration: TimeInterval) -> some View {
        let isActive = abs((vm.selectedDurationClip?.duration ?? 0) - duration) < 0.05
        return Button {
            guard let id = vm.selectedOverlayClipID ?? vm.selectedClipID else { return }
            vm.commitPhotoDuration(clipID: id, duration: duration)
        } label: {
            Text(formatted(duration))
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(isActive ? .black : .white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule().fill(isActive ? Color.appColors.primaryColor : Color.white.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Set photo duration to \(formatted(duration))")
    }

    private var durationSlider: some View {
        Slider(
            value: durationBinding,
            in: EditorClip.photoMinimumDuration...EditorClip.photoMaximumDuration,
            step: 0.5,
            label: { Text("Photo duration") },
            minimumValueLabel: {
                Text("0.5 s").font(.system(size: 10)).foregroundColor(.white.opacity(0.5))
            },
            maximumValueLabel: {
                Text("30 s").font(.system(size: 10)).foregroundColor(.white.opacity(0.5))
            },
            onEditingChanged: finishSliderEdit
        )
        .tint(Color.appColors.primaryColor)
    }

    private var durationBinding: Binding<Double> {
        Binding(
            get: { vm.selectedDurationClip?.duration ?? EditorClip.photoDefaultDuration },
            set: { duration in
                guard let id = vm.selectedOverlayClipID ?? vm.selectedClipID else { return }
                vm.setPhotoDuration(clipID: id, duration: duration)
            }
        )
    }

    private func finishSliderEdit(_ isEditing: Bool) {
        guard !isEditing,
              let id = vm.selectedOverlayClipID ?? vm.selectedClipID,
              let duration = vm.selectedDurationClip?.duration else { return }
        vm.commitPhotoDuration(clipID: id, duration: duration)
    }

    private func formatted(_ duration: TimeInterval) -> String {
        duration.rounded() == duration
            ? String(format: "%.0f s", duration)
            : String(format: "%.1f s", duration)
    }
}

struct CropReframeToolPanel: View {
    let vm: EditorViewModel

    private var clip: EditorClip? { vm.selectedReframeClip }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("Crop & Reframe")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                    Button("Reset") {
                        vm.resetSelectedClipReframe()
                        vm.commitSelectedClipReframe()
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color.appColors.primaryColor)
                }

                if let clip {
                    modePicker(clip)
                    aspectPicker(clip)
                    transformButtons(clip)
                    valueSlider(
                        title: "Straighten",
                        valueText: String(format: "%.1f°", clip.straightenDegrees),
                        value: Binding(
                            get: { clip.straightenDegrees },
                            set: { vm.setSelectedClipStraighten($0) }
                        ),
                        range: -45...45,
                        step: 0.5
                    )
                    valueSlider(
                        title: "Scale",
                        valueText: String(format: "%.0f%%", clip.reframeScale * 100),
                        value: Binding(
                            get: { Double(clip.reframeScale) },
                            set: { vm.setSelectedClipReframeScale(CGFloat($0)) }
                        ),
                        range: 0.5...4,
                        step: 0.01
                    )

                    Toggle("Safe-area and rule-of-thirds guides", isOn: Binding(
                        get: { vm.showsReframeSafeAreaGuides },
                        set: { vm.showsReframeSafeAreaGuides = $0 }
                    ))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .tint(Color.appColors.primaryColor)

                    Text("Drag the preview to reposition. Pinch the preview to zoom.")
                        .font(.system(size: 11))
                        .foregroundColor(Color.white.opacity(0.55))
                } else {
                    Text("Select a clip to crop or reframe it.")
                        .foregroundColor(Color.white.opacity(0.6))
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 20)
        }
    }

    private func modePicker(_ clip: EditorClip) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Background framing")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color.white.opacity(0.7))
            Picker("Background framing", selection: Binding(
                get: { clip.reframeMode },
                set: { mode in
                    vm.setSelectedClipReframeMode(mode)
                    vm.commitSelectedClipReframe()
                }
            )) {
                ForEach(EditorReframeMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private func aspectPicker(_ clip: EditorClip) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Crop aspect")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color.white.opacity(0.7))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(EditorCropAspect.allCases) { aspect in
                        Button {
                            vm.setSelectedClipCropAspect(aspect)
                            vm.commitSelectedClipReframe()
                        } label: {
                            Text(aspect.title)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(clip.cropAspect == aspect ? .black : .white)
                                .padding(.horizontal, 13)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule().fill(
                                        clip.cropAspect == aspect
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
    }

    private func transformButtons(_ clip: EditorClip) -> some View {
        HStack(spacing: 10) {
            transformButton(title: "Rotate", image: "rotate.right") {
                vm.rotateSelectedClipClockwise()
                vm.commitSelectedClipReframe()
            }
            transformButton(
                title: "Flip H",
                image: "arrow.left.and.right.righttriangle.left.righttriangle.right",
                selected: clip.isFlippedHorizontally
            ) {
                vm.toggleSelectedClipHorizontalFlip()
                vm.commitSelectedClipReframe()
            }
            transformButton(
                title: "Flip V",
                image: "arrow.up.and.down.righttriangle.up.righttriangle.down",
                selected: clip.isFlippedVertically
            ) {
                vm.toggleSelectedClipVerticalFlip()
                vm.commitSelectedClipReframe()
            }
            transformButton(title: "Center", image: "scope") {
                vm.centerSelectedClipReframe()
                vm.commitSelectedClipReframe()
            }
        }
    }

    private func transformButton(
        title: String,
        image: String,
        selected: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: image).font(.system(size: 16, weight: .semibold))
                Text(title).font(.system(size: 10, weight: .semibold))
            }
            .foregroundColor(selected ? Color.appColors.primaryColor : .white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.07)))
        }
        .buttonStyle(.plain)
    }

    private func valueSlider(
        title: String,
        valueText: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double
    ) -> some View {
        VStack(spacing: 6) {
            HStack {
                Text(title).font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(valueText).font(.system(size: 12, weight: .bold).monospacedDigit())
                    .foregroundColor(Color.appColors.primaryColor)
            }
            .foregroundColor(.white)
            Slider(value: value, in: range, step: step) { Text(title) } onEditingChanged: { editing in
                if !editing { vm.commitSelectedClipReframe() }
            }
            .tint(Color.appColors.primaryColor)
        }
    }
}
