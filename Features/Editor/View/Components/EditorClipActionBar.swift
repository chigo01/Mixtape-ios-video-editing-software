//
//  EditorClipActionBar.swift
//  Mixtape
//
//  CapCut-style contextual toolbar shown when a timeline clip is selected.
//

import SwiftUI

enum EditorClipAction: String, CaseIterable, Identifiable {
    case split
    case precision
    case reverse
    case freeze
    case speed
    case duration
    case crop
    case volume
    case filter
    case compositing
    case text
    case keyframe
    case stabilize
    case track
    case duplicate
    case replace
    case delete

    var id: String { rawValue }

    var title: String {
        switch self {
        case .split: return "SPLIT"
        case .precision: return "PRECISION"
        case .reverse: return "REVERSE"
        case .freeze: return "FREEZE"
        case .speed: return "SPEED"
        case .duration: return "DURATION"
        case .crop: return "CROP"
        case .volume: return "VOLUME"
        case .filter: return "ADJUST"
        case .compositing: return "COMPOSITE"
        case .text: return "TEXT"
        case .keyframe: return "KEYFRAME"
        case .stabilize: return "STABILIZE"
        case .track: return "TRACK"
        case .duplicate: return "DUPLICATE"
        case .replace: return "REPLACE"
        case .delete: return "DELETE"
        }
    }

    var systemImage: String {
        switch self {
        case .split: return "scissors"
        case .precision: return "arrow.left.and.right"
        case .reverse: return "backward.end.alt.fill"
        case .freeze: return "snowflake"
        case .speed: return "speedometer"
        case .duration: return "timer"
        case .crop: return "crop.rotate"
        case .volume: return "speaker.wave.2.fill"
        case .filter: return "slider.horizontal.3"
        case .compositing: return "square.3.layers.3d"
        case .text: return "textformat"
        case .keyframe: return "diamond.fill"
        case .stabilize: return "gyroscope"
        case .track: return "viewfinder"
        case .duplicate: return "plus.square.on.square"
        case .replace: return "arrow.triangle.2.circlepath"
        case .delete: return "trash"
        }
    }

    var isDestructive: Bool { self == .delete }
}

struct EditorClipActionBar: View {
    let vm: EditorViewModel
    var onReplace: () -> Void = {}

    private var availableActions: [EditorClipAction] {
        EditorClipAction.allCases.filter { action in
            if action == .duration { return vm.selectedClip?.isPhoto == true }
            if action == .reverse || action == .freeze { return vm.selectedClip?.isVideo == true }
            return true
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    vm.deselectClip()
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to main tools")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(availableActions) { action in
                        ClipActionButton(
                            action: action,
                            isSelected: action == .reverse
                                ? (vm.selectedClip?.playback.isReverse == true || vm.selectedTool == .reverse)
                                : (action.tool.map { vm.selectedTool == $0 } ?? false),
                            isDisabled: isDisabled(action)
                        ) {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                if action == .replace { onReplace() } else { vm.performClipAction(action) }
                            }
                        }
                    }
                }
                .padding(.trailing, 8)
            }
        }
        .padding(.leading, 4)
        .padding(.top, 12)
        .padding(.bottom, 18)
        .background(
            Rectangle()
                .fill(Color.white.opacity(0.02))
                .overlay(
                    Rectangle()
                        .frame(height: 0.5)
                        .foregroundColor(Color.white.opacity(0.06)),
                    alignment: .top
                )
        )
    }

    private func isDisabled(_ action: EditorClipAction) -> Bool {
        switch action {
        case .delete: return !vm.canDeleteSelectedClip
        case .stabilize: return !vm.canStabilizeSelectedClip
        case .reverse: return !vm.canReverseSelectedClip
        case .freeze: return !vm.canFreezeSelectedClipAtPlayhead
        default: return false
        }
    }
}

extension EditorClipAction {
    var tool: EditorTool? {
        switch self {
        case .split: return .split
        case .precision: return .precision
        case .reverse: return .reverse
        case .freeze: return .freeze
        case .speed: return .speed
        case .duration: return .duration
        case .crop: return .crop
        case .volume: return .volume
        case .filter: return .filter
        case .compositing: return .compositing
        case .text: return .text
        case .keyframe: return .keyframe
        case .stabilize: return .stabilize
        case .track: return .track
        case .duplicate, .replace: return nil
        case .delete: return nil
        }
    }
}

struct ClipActionButton: View {
    let action: EditorClipAction
    let isSelected: Bool
    let isDisabled: Bool
    let onTap: () -> Void

    private var accentColor: Color {
        if action.isDestructive { return Color.red.opacity(0.9) }
        return isSelected ? Color.appColors.primaryColor : .white
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                Image(systemName: action.systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(isDisabled ? Color.white.opacity(0.25) : accentColor)
                Text(action.title)
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.5)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .foregroundColor(
                        isDisabled
                            ? Color.white.opacity(0.25)
                            : (isSelected ? Color.appColors.primaryColor : Color.white.opacity(0.75))
                    )
            }
            .padding(.vertical, 6)
            .frame(width: 78)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityLabel(action.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct ReverseClipToolPanel: View {
    let vm: EditorViewModel
    var onStart: () -> Void

    @State private var audioPolicy: EditorReverseAudioPolicy = .reverse

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("REVERSE CLIP")
                    .font(.caption.bold())
                    .tracking(1)
                Text("A reusable render is generated from the selected visible range. Your original stays untouched.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Picker("Embedded audio", selection: $audioPolicy) {
                ForEach(EditorReverseAudioPolicy.allCases) { policy in
                    Text(policy.title).tag(policy)
                }
            }
            .pickerStyle(.segmented)

            Text(audioPolicy == .reverse
                ? "Picture and embedded clip audio play backward together."
                : "Only picture is reversed; music, voiceover, and other lanes are unaffected.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                vm.toggleReverseSelectedClip(audioPolicy: audioPolicy)
                onStart()
            } label: {
                Label("Generate Reverse", systemImage: "backward.end.alt.fill")
                    .font(.body.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.appColors.primaryColor, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.black)
            }
            .buttonStyle(.plain)
            .disabled(!vm.canReverseSelectedClip)
        }
        .padding(20)
    }
}

struct FreezeFrameToolPanel: View {
    let vm: EditorViewModel
    var onDone: () -> Void

    @State private var duration: Double = 2
    @State private var audioPolicy: EditorFreezeAudioPolicy = .mute

    private var requiresMutedClipAudio: Bool {
        vm.selectedOverlayClip != nil || vm.selectedVideoPlayback?.isReverse == true
    }

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("FREEZE FRAME")
                        .font(.caption.bold())
                        .tracking(1)
                    Text("Hold the frame under the playhead")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(String(format: "%.1fs", duration))
                    .font(.body.bold().monospacedDigit())
                    .foregroundStyle(Color.appColors.primaryColor)
            }

            Slider(value: $duration, in: 0.1...10, step: 0.1)
                .tint(Color.appColors.primaryColor)
                .accessibilityLabel("Freeze duration")

            HStack(spacing: 8) {
                ForEach([0.5, 1, 2, 3, 5], id: \.self) { preset in
                    Button {
                        duration = preset
                    } label: {
                        Text(String(format: preset < 1 ? "%.1fs" : "%.0fs", preset))
                            .font(.caption.bold().monospacedDigit())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(abs(duration - preset) < 0.01
                                        ? Color.appColors.primaryColor.opacity(0.22)
                                        : Color.white.opacity(0.06))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            Picker("Audio", selection: $audioPolicy) {
                ForEach(EditorFreezeAudioPolicy.allCases) { policy in
                    Text(policy.title).tag(policy)
                }
            }
            .pickerStyle(.segmented)
            .disabled(requiresMutedClipAudio)

            Text(vm.selectedOverlayClip != nil
                ? "Overlay freezes mute their embedded audio so the resumed overlay stays source-synchronous; music, voiceover, and other lanes continue."
                : vm.selectedVideoPlayback?.isReverse == true
                ? "Reverse audio cannot continue forward through a hold; the freeze uses Mute Clip Audio."
                : audioPolicy == .mute
                ? "The selected clip is silent during the hold; music, voiceover, and other lanes continue."
                : "Source audio continues forward under the still image, creating an intentional J-cut.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                vm.insertFreezeFrame(duration: duration, audioPolicy: audioPolicy)
                onDone()
            } label: {
                Label("Insert Freeze Frame", systemImage: "snowflake")
                    .font(.body.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.appColors.primaryColor, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.black)
            }
            .buttonStyle(.plain)
            .disabled(!vm.canFreezeSelectedClipAtPlayhead)
        }
        .padding(20)
    }
}

enum EditorOverlayAction: String, CaseIterable, Identifiable {
    case addOverlay
    case split
    case reverse
    case freeze
    case speed
    case duration
    case crop
    case volume
    case filter
    case compositing
    case opacity
    case smaller
    case larger
    case sendBackward
    case bringForward
    case reset
    case text
    case keyframe
    case stabilize
    case track
    case duplicate
    case replace
    case delete

    var id: String { rawValue }
    var title: String {
        switch self {
        case .addOverlay: return "ADD OVERLAY"
        case .split: return "SPLIT"
        case .reverse: return "REVERSE"
        case .freeze: return "FREEZE"
        case .speed: return "SPEED"
        case .duration: return "DURATION"
        case .crop: return "CROP"
        case .volume: return "VOLUME"
        case .filter: return "ADJUST"
        case .compositing: return "COMPOSITE"
        case .opacity: return "OPACITY"
        case .smaller: return "SMALLER"
        case .larger: return "LARGER"
        case .sendBackward: return "SEND BACK"
        case .bringForward: return "BRING FRONT"
        case .reset: return "RESET"
        case .text: return "TEXT"
        case .keyframe: return "KEYFRAME"
        case .stabilize: return "STABILIZE"
        case .track: return "TRACK"
        case .duplicate: return "DUPLICATE"
        case .replace: return "REPLACE"
        case .delete: return "DELETE"
        }
    }
    var systemImage: String {
        switch self {
        case .addOverlay: return "plus.rectangle.on.rectangle"
        case .split: return "scissors"
        case .reverse: return "backward.end.alt.fill"
        case .freeze: return "snowflake"
        case .speed: return "speedometer"
        case .duration: return "timer"
        case .crop: return "crop.rotate"
        case .volume: return "speaker.wave.2.fill"
        case .filter: return "slider.horizontal.3"
        case .compositing: return "square.3.layers.3d"
        case .opacity: return "circle.lefthalf.filled"
        case .smaller: return "minus.magnifyingglass"
        case .larger: return "plus.magnifyingglass"
        case .sendBackward: return "arrow.down"
        case .bringForward: return "arrow.up"
        case .reset: return "arrow.counterclockwise"
        case .text: return "textformat"
        case .keyframe: return "diamond.fill"
        case .stabilize: return "gyroscope"
        case .track: return "viewfinder"
        case .duplicate: return "plus.square.on.square"
        case .replace: return "arrow.triangle.2.circlepath"
        case .delete: return "trash"
        }
    }

    var tool: EditorTool? {
        switch self {
        case .reverse: return .reverse
        case .freeze: return .freeze
        case .speed: return .speed
        case .duration: return .duration
        case .crop: return .crop
        case .volume: return .volume
        case .filter: return .filter
        case .compositing: return .compositing
        case .opacity: return .opacity
        case .text: return .text
        case .keyframe: return .keyframe
        case .stabilize: return .stabilize
        case .track: return .track
        default: return nil
        }
    }
}

struct EditorOverlayActionBar: View {
    let vm: EditorViewModel
    var onAddOverlay: () -> Void = {}
    var onReplace: () -> Void = {}
    var onBack: () -> Void = {}

    private var availableActions: [EditorOverlayAction] {
        EditorOverlayAction.allCases.filter { action in
            if action == .duration { return vm.selectedOverlayClip?.isPhoto == true }
            if action == .reverse || action == .freeze {
                return vm.selectedOverlayClip?.isVideo == true
            }
            return true
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    vm.deselectOverlayClip()
                    onBack()
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to main tools")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(availableActions) { action in
                        Button { perform(action) } label: {
                            VStack(spacing: 6) {
                                Image(systemName: action.systemImage)
                                    .font(.system(size: 18, weight: .semibold))
                                Text(action.title)
                                    .font(.system(size: 10, weight: .semibold))
                                    .tracking(0.5)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.72)
                            }
                            .foregroundColor(
                                isDisabled(action)
                                    ? Color.white.opacity(0.25)
                                    : action == .delete
                                    ? Color.red.opacity(0.9)
                                    : (isSelected(action)
                                        ? Color.appColors.primaryColor
                                        : Color.white.opacity(0.85))
                            )
                            .padding(.vertical, 6)
                            .frame(width: 78)
                            .frame(minHeight: 56)
                        }
                        .buttonStyle(.plain)
                        .disabled(isDisabled(action))
                        .accessibilityLabel(action.title)
                    }
                }
                .padding(.trailing, 8)
            }
        }
        .padding(.leading, 4)
        .padding(.top, 12)
        .padding(.bottom, 18)
        .background(Rectangle().fill(Color.white.opacity(0.02)))
    }

    private func isDisabled(_ action: EditorOverlayAction) -> Bool {
        switch action {
        case .split: return vm.selectedOverlayClip?.playback.isFreezeFrame == true
        case .sendBackward: return !vm.canSendSelectedOverlayBackward
        case .bringForward: return !vm.canBringSelectedOverlayForward
        case .stabilize: return !vm.canStabilizeSelectedClip
        case .reverse: return !vm.canReverseSelectedClip
        case .freeze: return !vm.canFreezeSelectedClipAtPlayhead
        default: return false
        }
    }

    private func isSelected(_ action: EditorOverlayAction) -> Bool {
        if action == .reverse {
            return vm.selectedOverlayClip?.playback.isReverse == true
                || vm.selectedTool == .reverse
        }
        return action.tool.map { vm.selectedTool == $0 } == true
    }

    private func perform(_ action: EditorOverlayAction) {
        switch action {
        case .addOverlay:
            onAddOverlay()
        case .split:
            vm.splitSelectedOverlayAtPlayhead()
        case .reverse:
            if vm.selectedOverlayClip?.playback.isReverse == true {
                vm.toggleReverseSelectedClip()
            } else {
                vm.selectTool(.reverse)
            }
        case .freeze:
            vm.selectTool(.freeze)
        case .speed:
            vm.selectTool(.speed)
        case .duration:
            vm.selectTool(.duration)
        case .crop:
            vm.selectTool(.crop)
        case .volume:
            vm.selectTool(.volume)
        case .filter:
            vm.selectTool(.filter)
        case .compositing:
            vm.selectTool(.compositing)
        case .opacity:
            vm.selectTool(.opacity)
        case .smaller:
            guard let clip = vm.selectedOverlayClip else { return }
            vm.setOverlayScale(id: clip.id, scale: clip.scale - 0.1)
            vm.commitOverlayTransform()
        case .larger:
            guard let clip = vm.selectedOverlayClip else { return }
            vm.setOverlayScale(id: clip.id, scale: clip.scale + 0.1)
            vm.commitOverlayTransform()
        case .sendBackward:
            vm.sendSelectedOverlayBackward()
        case .bringForward:
            vm.bringSelectedOverlayForward()
        case .reset:
            vm.resetSelectedOverlayTransform()
        case .text:
            vm.performToolAction(.text)
        case .keyframe:
            vm.selectTool(.keyframe)
        case .stabilize:
            vm.selectTool(.stabilize)
        case .track:
            vm.selectTool(.track)
        case .duplicate:
            vm.duplicateSelectedOverlayClip()
        case .replace:
            onReplace()
        case .delete:
            vm.deleteSelectedOverlayClip()
        }
    }
}
