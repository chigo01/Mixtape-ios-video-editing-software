//
//  PrecisionEditToolPanel.swift
//  Mixtape
//

import SwiftUI
import PhotosUI

enum EditorPrecisionMode: String, CaseIterable, Identifiable {
    case ripple = "Ripple"
    case roll = "Roll"
    case slip = "Slip"
    case slide = "Slide"
    case audio = "J/L Cuts"
    var id: String { rawValue }
}

struct PrecisionEditToolPanel: View {
    let vm: EditorViewModel
    @State private var mode: EditorPrecisionMode = .ripple
    @State private var step: TimeInterval = 0.10

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Picker("Edit type", selection: $mode) {
                        ForEach(EditorPrecisionMode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    if let message = vm.precisionEditMessage {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .font(.footnote).foregroundStyle(.orange)
                    }

                    if mode == .audio {
                        audioControls
                    } else {
                        editControls
                    }
                }
                .padding(18)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
        }
        .background(Color.appColors.backgroundColor)
    }

    private var header: some View {
        ZStack {
            Text("Timeline Precision").font(.headline)
            HStack {
                Spacer()
                Button("Done") { vm.selectedTool = nil }
                    .font(.subheadline.bold()).foregroundStyle(Color.appColors.primaryColor)
            }
        }
        .padding(.horizontal, 18).frame(height: 48)
    }

    private var editControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(explanation).font(.footnote).foregroundStyle(.secondary)

            Picker("Adjustment", selection: $step) {
                Text("1 frame").tag(TimeInterval(1.0 / 30.0))
                Text("0.10s").tag(TimeInterval(0.10))
                Text("0.50s").tag(TimeInterval(0.50))
            }
            .pickerStyle(.segmented)

            HStack(spacing: 12) {
                adjustmentButton(title: "Earlier", image: "minus", delta: -step)
                adjustmentButton(title: "Later", image: "plus", delta: step)
            }

            if mode == .ripple {
                Button(role: .destructive) { vm.deleteSelectedClip() } label: {
                    Label("Ripple delete selected clip", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!vm.canDeleteSelectedClip)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.055)))
    }

    private var audioControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let clip = vm.selectedClip, clip.isVideo {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(clip.isAudioLinked ? "Linked A/V" : "Independent audio handles")
                            .font(.subheadline.bold())
                        Text("J starts audio before picture; L keeps audio after picture.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(clip.isAudioLinked ? "Unlink" : "Relink") {
                        vm.toggleSelectedClipAudioLink()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.appColors.primaryColor)
                    .foregroundStyle(.black)
                }

                precisionBoundaryRow(
                    title: "J cut · audio start",
                    value: clip.effectiveAudioTrimStart,
                    earlier: { vm.adjustSelectedClipAudioStart(by: -step) },
                    later: { vm.adjustSelectedClipAudioStart(by: step) }
                )
                precisionBoundaryRow(
                    title: "L cut · audio end",
                    value: clip.effectiveAudioTrimEnd,
                    earlier: { vm.adjustSelectedClipAudioEnd(by: -step) },
                    later: { vm.adjustSelectedClipAudioEnd(by: step) }
                )
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.055)))
    }

    private func adjustmentButton(title: String, image: String, delta: TimeInterval) -> some View {
        Button {
            switch mode {
            case .ripple: vm.rippleTrimSelectedClipOut(by: delta)
            case .roll: vm.rollSelectedCut(by: delta)
            case .slip: vm.slipSelectedClip(by: delta)
            case .slide: vm.slideSelectedClip(by: delta)
            case .audio: break
            }
        } label: {
            Label("\(title) \(formatted(step))", systemImage: image)
                .frame(maxWidth: .infinity).padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .tint(Color.appColors.primaryColor)
        .foregroundStyle(.black)
        .disabled(
            vm.precisionEditMessage != nil
                || (mode == .roll && !vm.canRollSelectedCut)
                || (mode == .slide && !vm.canSlideSelectedClip)
        )
    }

    private func precisionBoundaryRow(
        title: String,
        value: TimeInterval,
        earlier: @escaping () -> Void,
        later: @escaping () -> Void
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline)
                Text(String(format: "Source %.2fs", value))
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: earlier) { Image(systemName: "minus") }.buttonStyle(.bordered)
            Button(action: later) { Image(systemName: "plus") }.buttonStyle(.bordered)
        }
    }

    private var explanation: String {
        switch mode {
        case .ripple: return "Trim the selected out-point and move every downstream timed item by the exact duration change."
        case .roll: return "Move the cut between the selected clip and the next clip without changing total duration."
        case .slip: return "Change source content while preserving the selected clip's timeline position and duration."
        case .slide: return "Move the selected middle clip while compensating the neighboring edit points."
        case .audio: return "Adjust linked picture and embedded-audio boundaries independently."
        }
    }

    private func formatted(_ value: TimeInterval) -> String {
        value < 0.05 ? "1f" : String(format: "%.2fs", value)
    }
}


