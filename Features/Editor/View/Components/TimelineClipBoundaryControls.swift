//
//  TimelineClipBoundaryControls.swift
//  Mixtape
//

import SwiftUI
import UIKit
import Photos
import AVFoundation

// MARK: - Insert slot (dedicated gap between clips)

private struct ClipInsertSlot: View {
    let width: CGFloat
    let height: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Rectangle()
                    .fill(Color.white.opacity(0.04))
                Rectangle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 1)
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.appColors.primaryColor))
                    .overlay(Circle().stroke(Color.black.opacity(0.35), lineWidth: 1))
            }
            .frame(width: width, height: height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add media after this clip")
    }
}

struct ClipBoundarySlot: View {
    let width: CGFloat
    let height: CGFloat
    let transitionKind: EditorTransitionKind
    let onTransition: () -> Void
    let onInsert: () -> Void

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.white.opacity(0.04))
            Rectangle()
                .fill(Color.white.opacity(0.16))
                .frame(width: 1)

            Button(action: onTransition) {
                Image(systemName: transitionKind == .none
                      ? "rectangle.split.2x1"
                      : transitionKind.systemImage)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(transitionKind == .none ? .white : .black)
                    .frame(width: 26, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(
                                transitionKind == .none
                                    ? Color.white.opacity(0.16)
                                    : Color.appColors.primaryColor
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(Color.white.opacity(0.35), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .offset(y: -9)
            .accessibilityLabel("Edit transition at cut")

            Button(action: onInsert) {
                Image(systemName: "plus")
                    .font(.system(size: 8, weight: .black))
                    .foregroundColor(.black)
                    .frame(width: 17, height: 17)
                    .background(Circle().fill(Color.white))
            }
            .buttonStyle(.plain)
            .offset(y: 16)
            .accessibilityLabel("Add media at this cut")
        }
        .frame(width: width, height: height)
        .clipped()
    }
}

struct ClipEndingSlot: View {
    let width: CGFloat
    let height: CGFloat
    let transitionKind: EditorTransitionKind
    let onTransition: () -> Void
    let onInsert: () -> Void

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.white.opacity(0.04))
            Rectangle()
                .fill(Color.white.opacity(0.16))
                .frame(width: 1)

            Button(action: onTransition) {
                Image(
                    systemName: transitionKind == .none
                        ? "rectangle.portrait.and.arrow.forward"
                        : transitionKind.systemImage
                )
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(transitionKind == .none ? .white : .black)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(
                            transitionKind == .none
                                ? Color.white.opacity(0.16)
                                : Color.appColors.primaryColor
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(Color.white.opacity(0.35), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .offset(y: -9)
            .accessibilityLabel("Edit closing transition")
            .accessibilityHint("Applies an exit effect to the final clip")

            Button(action: onInsert) {
                Image(systemName: "plus")
                    .font(.system(size: 8, weight: .black))
                    .foregroundColor(.black)
                    .frame(width: 17, height: 17)
                    .background(Circle().fill(Color.white))
            }
            .buttonStyle(.plain)
            .offset(y: 16)
            .accessibilityLabel("Add media after this clip")
        }
        .frame(width: width, height: height)
        .clipped()
    }
}

struct OpeningTransitionControl: View {
    let transitionKind: EditorTransitionKind
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(
                systemName: transitionKind == .none
                    ? "rectangle.portrait.and.arrow.forward"
                    : transitionKind.systemImage
            )
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(transitionKind == .none ? .white : .black)
            .frame(width: 26, height: 30)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        transitionKind == .none
                            ? Color.white.opacity(0.18)
                            : Color.appColors.primaryColor
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(0.4), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Edit opening transition")
        .accessibilityHint("Applies an entrance effect to the first clip")
        .frame(maxWidth: .infinity)
        .clipped()
    }
}

