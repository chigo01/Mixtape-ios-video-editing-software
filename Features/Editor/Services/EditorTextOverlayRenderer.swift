//
//  EditorTextOverlayRenderer.swift
//  Mixtape
//

import SwiftUI
import UIKit

struct EditorTextOverlayExportView: View {
    let overlay: EditorTextOverlay
    let renderSize: CGSize
    let screenWidth: CGFloat

    private var scale: CGFloat {
        max(1.0, renderSize.width / screenWidth)
    }

    var body: some View {
        ZStack {
            Color.clear // Transparent background
            
            VStack {
                if overlay.verticalAlignment != .top { Spacer(minLength: 0) }

                HStack {
                    if overlay.horizontalAlignment != .leading { Spacer(minLength: 0) }

                    styledTextView(overlay)
                        .offset(x: overlay.xOffset, y: overlay.yOffset)

                    if overlay.horizontalAlignment != .trailing { Spacer(minLength: 0) }
                }

                if overlay.verticalAlignment != .bottom { Spacer(minLength: 0) }
            }
            .padding(12)
        }
        .frame(width: screenWidth, height: screenWidth * (renderSize.height / renderSize.width))
        .scaleEffect(scale)
        .frame(width: renderSize.width, height: renderSize.height)
    }

    @ViewBuilder
    private func styledTextView(_ overlay: EditorTextOverlay) -> some View {
        let baseText = Text(overlay.text)
            .font(overlay.resolvedFont())
            .multilineTextAlignment(overlay.horizontalAlignment.alignment)
            .opacity(overlay.opacity)

        switch overlay.fontStyle {
        case .plain, .bold, .italic:
            baseText
                .foregroundColor(overlay.textColor.color)

        case .outlined:
            baseText
                .foregroundColor(overlay.textColor.color)
                .shadow(color: .black, radius: 0, x: 1, y: 1)
                .shadow(color: .black, radius: 0, x: -1, y: -1)
                .shadow(color: .black, radius: 0, x: 1, y: -1)
                .shadow(color: .black, radius: 0, x: -1, y: 1)

        case .shadow:
            baseText
                .foregroundColor(overlay.textColor.color)
                .shadow(color: .black.opacity(0.7), radius: 4, x: 2, y: 2)

        case .background:
            baseText
                .foregroundColor(overlay.textColor.color)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.black.opacity(0.6))
                )
        }
    }
}

@MainActor
enum EditorTextOverlayRenderer {
    static func render(overlay: EditorTextOverlay, renderSize: CGSize) -> UIImage? {
        let screenWidth = UIScreen.main.bounds.width
        let view = EditorTextOverlayExportView(
            overlay: overlay,
            renderSize: renderSize,
            screenWidth: screenWidth
        )
        .frame(width: renderSize.width, height: renderSize.height)

        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = ProposedViewSize(renderSize)
        renderer.isOpaque = false
        renderer.scale = 1

        if let image = renderer.uiImage {
            return image
        }

        // Fallback: off-screen hosting controller (alpha must stay 1 for layer capture).
        return renderOffScreen(view: view, size: renderSize)
    }

    private static func renderOffScreen<V: View>(view: V, size: CGSize) -> UIImage? {
        let controller = UIHostingController(rootView: view)
        controller.view.bounds = CGRect(origin: .zero, size: size)
        controller.view.backgroundColor = .clear

        let window = UIWindow(frame: CGRect(x: -size.width * 2, y: -size.height * 2, width: size.width, height: size.height))
        window.windowLevel = .normal
        window.isHidden = false
        window.rootViewController = controller

        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()

        let image = UIGraphicsImageRenderer(size: size).image { context in
            controller.view.layer.render(in: context.cgContext)
        }

        window.isHidden = true
        window.rootViewController = nil
        return image
    }
}
