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
    let highlightedCaptionWordID: UUID?
    let blurRadius: CGFloat

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
                        .blur(radius: blurRadius)
                        .offset(x: overlay.xOffset, y: overlay.yOffset)

                    if overlay.horizontalAlignment != .trailing { Spacer(minLength: 0) }
                }

                if overlay.verticalAlignment != .bottom { Spacer(minLength: 0) }
            }
            .padding(EditorTextOverlayLayout.previewPadding)
        }
        .frame(width: screenWidth, height: screenWidth * (renderSize.height / renderSize.width))
        .scaleEffect(scale)
        .frame(width: renderSize.width, height: renderSize.height)
    }

    @ViewBuilder
    private func styledTextView(_ overlay: EditorTextOverlay) -> some View {
        let baseText: Text = overlay.isCaption
            ? captionText(overlay)
            : Text(overlay.text)

        let styledBase = baseText
            .font(overlay.resolvedFont())
            .multilineTextAlignment(overlay.horizontalAlignment.alignment)

        switch overlay.fontStyle {
        case .plain, .bold, .italic:
            styledBase
                .foregroundColor(overlay.isCaption ? nil : overlay.textColor.color)

        case .outlined:
            styledBase
                .foregroundColor(overlay.isCaption ? nil : overlay.textColor.color)
                .shadow(color: .black, radius: 0, x: 1, y: 1)
                .shadow(color: .black, radius: 0, x: -1, y: -1)
                .shadow(color: .black, radius: 0, x: 1, y: -1)
                .shadow(color: .black, radius: 0, x: -1, y: 1)

        case .shadow:
            styledBase
                .foregroundColor(overlay.isCaption ? nil : overlay.textColor.color)
                .shadow(color: .black.opacity(0.7), radius: 4, x: 2, y: 2)

        case .background:
            styledBase
                .foregroundColor(overlay.isCaption ? nil : overlay.textColor.color)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.black.opacity(0.6))
                )
        }
    }

    private func captionText(_ overlay: EditorTextOverlay) -> Text {
        overlay.captionWords.enumerated().reduce(Text("")) { result, pair in
            let (index, word) = pair
            let color = word.id == highlightedCaptionWordID
                ? overlay.captionHighlightColor.color
                : overlay.textColor.color
            return result + Text((index == 0 ? "" : " ") + word.text).foregroundColor(color)
        }
    }
}

struct EditorGraphicOverlayExportView: View {
    let graphic: EditorGraphicOverlay
    let renderSize: CGSize

    private var screenWidth: CGFloat { EditorTextOverlayLayout.referenceWidth }
    private var screenHeight: CGFloat { screenWidth * renderSize.height / renderSize.width }
    private var renderScale: CGFloat { renderSize.width / screenWidth }

    var body: some View {
        ZStack {
            Color.clear
            content
                .frame(width: graphic.size, height: graphic.size)
                .scaleEffect(
                    x: graphic.scale * (graphic.isFlippedHorizontally ? -1 : 1),
                    y: graphic.scale * (graphic.isFlippedVertically ? -1 : 1)
                )
                .rotationEffect(.degrees(graphic.rotationDegrees))
                .opacity(graphic.opacity)
                .blendMode(graphic.blendMode.swiftUIValue)
                .offset(x: graphic.xOffset, y: graphic.yOffset)
        }
        .frame(width: screenWidth, height: screenHeight)
        .scaleEffect(renderScale)
        .frame(width: renderSize.width, height: renderSize.height)
    }

    @ViewBuilder private var content: some View {
        switch graphic.source {
        case let .emoji(value):
            Text(value).font(.system(size: graphic.size * 0.72)).minimumScaleFactor(0.1)
        case let .symbol(name):
            Image(systemName: name).resizable().scaledToFit().padding(10)
                .foregroundStyle(graphic.tintRGB.map { rgb in
                    Color(red: Double((rgb >> 16) & 0xff) / 255,
                          green: Double((rgb >> 8) & 0xff) / 255,
                          blue: Double(rgb & 0xff) / 255)
                } ?? .white)
        case let .image(path):
            if let image = UIImage(contentsOfFile: path) {
                Image(uiImage: image).resizable().scaledToFit()
            }
        }
    }
}

@MainActor
enum EditorGraphicOverlayRenderer {
    static func render(graphic: EditorGraphicOverlay, renderSize: CGSize) -> UIImage? {
        let view = EditorGraphicOverlayExportView(graphic: graphic, renderSize: renderSize)
            .frame(width: renderSize.width, height: renderSize.height)
        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = ProposedViewSize(renderSize)
        renderer.isOpaque = false
        renderer.scale = 1
        return renderer.uiImage
    }
}

@MainActor
enum EditorTextOverlayRenderer {
    static func render(
        overlay: EditorTextOverlay,
        renderSize: CGSize,
        highlightedCaptionWordID: UUID? = nil,
        blurRadius: CGFloat = 0
    ) -> UIImage? {
        let screenWidth = EditorTextOverlayLayout.referenceWidth
        let view = EditorTextOverlayExportView(
            overlay: overlay,
            renderSize: renderSize,
            screenWidth: screenWidth,
            highlightedCaptionWordID: highlightedCaptionWordID,
            blurRadius: blurRadius
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
