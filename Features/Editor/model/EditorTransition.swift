//
//  EditorTransition.swift
//  Mixtape
//
//  Transition catalog metadata shared by the picker, timeline, persistence,
//  standard AVFoundation renderer, and custom GPU compositor.
//

import Foundation

enum EditorTransitionKind: String, Codable, CaseIterable, Identifiable {
    // Basic
    case none, fade, mix, dipToBlack, dipToWhite, blink, fadeLift, fadeDrop

    // Camera
    case zoomIn, zoomOut, shrink, expand, snapBack, clapAndPull
    case diveAndBounce, dofWiggle, tiltLeft, tiltRight, cameraShake
    case swingLeft, swingRight, orbitLeft, orbitRight
    case flipZoomIn, flipZoomOut, bounceIn, bounceOut

    // Motion
    case slideLeft, slideRight, slideUp, slideDown
    case pushLeft, pushRight, pushUp, pushDown
    case driftLeft, driftRight
    case diagonalUpLeft, diagonalUpRight, diagonalDownLeft, diagonalDownRight
    case whipLeft, whipRight, elasticLeft, elasticRight
    case compressLeft, compressRight, stretchUp, stretchDown
    case panLeftZoom, panRightZoom, skewLeft, skewRight

    // Distortion
    case spinLeft, spinRight, spinZoom, rollLeft, rollRight
    case flipHorizontal, flipVertical, squeezeHorizontal, squeezeVertical
    case stretchLeft, stretchRight, dragSwitch

    // Light
    case flash, flashZoom, glare, strobe, lightSweep

    // GPU blur
    case motionBlurLeft, motionBlurRight, motionBlurUp, motionBlurDown
    case zoomBlur, gaussianBlur, radialBlur

    // GPU glitch
    case pixelDissolve, crystallize, rgbSplit, glitch

    // GPU distortion
    case ripple, fisheye, kaleidoscope
    case bumpPulse, pinchPulse, vortexLeft, vortexRight
    case glassWarp, triangleMirror, torusLens

    // GPU artistic/color
    case comicFlash, bloom, vignettePulse
    case hueSpin, colorInvert, posterize, noirFlash, sepiaFlash
    case chromeFlash, processFlash, falseColor, edgeGlow

    // GPU masks
    case circleReveal, radialWipe

    var id: String { rawValue }

    var title: String { metadata.title }
    var systemImage: String { metadata.systemImage }
    var category: EditorTransitionCategory { metadata.category }
    var usesGPUCompositor: Bool { metadata.renderer == .gpu }
    var usesShaderMask: Bool { metadata.renderer == .gpuMask }

    private var metadata: EditorTransitionMetadata {
        guard let metadata = Self.catalog[self] else {
            assertionFailure("Missing transition metadata for \(rawValue)")
            return .init(title: rawValue, systemImage: "sparkles", category: .basic)
        }
        return metadata
    }

    private static let catalog: [EditorTransitionKind: EditorTransitionMetadata] = [
        .none: m("None", "nosign", .basic),
        .fade: m("Fade", "circle.dotted", .basic),
        .mix: m("Mix", "circle.grid.cross.fill", .basic),
        .dipToBlack: m("Dip to Black", "circle.lefthalf.filled", .basic),
        .dipToWhite: m("Dip to White", "circle.righthalf.filled", .basic),
        .blink: m("Blink", "eye.slash.fill", .basic),
        .fadeLift: m("Fade Lift", "arrow.up.circle", .basic),
        .fadeDrop: m("Fade Drop", "arrow.down.circle", .basic),

        .zoomIn: m("Zoom In", "plus.magnifyingglass", .camera),
        .zoomOut: m("Zoom Out", "minus.magnifyingglass", .camera),
        .shrink: m("Shrink", "arrow.down.right.and.arrow.up.left", .camera),
        .expand: m("Expand", "arrow.up.left.and.arrow.down.right", .camera),
        .snapBack: m("Snap Back", "arrow.uturn.backward.circle.fill", .camera),
        .clapAndPull: m("Clap & Pull", "arrow.left.and.right.circle.fill", .camera),
        .diveAndBounce: m("Dive & Bounce", "arrow.up.and.down", .camera),
        .dofWiggle: m("DOF Wiggle", "camera.aperture", .camera),
        .tiltLeft: m("Tilt Left", "rotate.left", .camera),
        .tiltRight: m("Tilt Right", "rotate.right", .camera),
        .cameraShake: m("Camera Shake", "camera.fill", .camera),
        .swingLeft: m("Swing Left", "arrow.turn.up.left", .camera),
        .swingRight: m("Swing Right", "arrow.turn.up.right", .camera),
        .orbitLeft: m("Orbit Left", "arrow.counterclockwise", .camera),
        .orbitRight: m("Orbit Right", "arrow.clockwise", .camera),
        .flipZoomIn: m("Flip Zoom In", "viewfinder.circle", .camera),
        .flipZoomOut: m("Flip Zoom Out", "viewfinder", .camera),
        .bounceIn: m("Bounce In", "arrow.down.to.line.compact", .camera),
        .bounceOut: m("Bounce Out", "arrow.up.to.line.compact", .camera),

        .slideLeft: m("Slide Left", "arrow.left.to.line", .motion),
        .slideRight: m("Slide Right", "arrow.right.to.line", .motion),
        .slideUp: m("Slide Up", "arrow.up.to.line", .motion),
        .slideDown: m("Slide Down", "arrow.down.to.line", .motion),
        .pushLeft: m("Push Left", "arrowshape.left.fill", .motion),
        .pushRight: m("Push Right", "arrowshape.right.fill", .motion),
        .pushUp: m("Push Up", "arrowshape.up.fill", .motion),
        .pushDown: m("Push Down", "arrowshape.down.fill", .motion),
        .driftLeft: m("Drift Left", "chevron.left.2", .motion),
        .driftRight: m("Drift Right", "chevron.right.2", .motion),
        .diagonalUpLeft: m("Diagonal Up", "arrow.up.left", .motion),
        .diagonalUpRight: m("Diagonal Rise", "arrow.up.right", .motion),
        .diagonalDownLeft: m("Diagonal Fall", "arrow.down.left", .motion),
        .diagonalDownRight: m("Diagonal Down", "arrow.down.right", .motion),
        .whipLeft: m("Whip Left", "wind", .motion),
        .whipRight: m("Whip Right", "wind", .motion),
        .elasticLeft: m("Elastic Left", "arrow.left.and.right", .motion),
        .elasticRight: m("Elastic Right", "arrow.left.and.right", .motion),
        .compressLeft: m("Compress Left", "arrow.left.to.line.compact", .motion),
        .compressRight: m("Compress Right", "arrow.right.to.line.compact", .motion),
        .stretchUp: m("Stretch Up", "arrow.up.and.line.horizontal.and.arrow.down", .motion),
        .stretchDown: m("Stretch Down", "arrow.down.and.line.horizontal.and.arrow.up", .motion),
        .panLeftZoom: m("Pan Zoom Left", "camera.viewfinder", .motion),
        .panRightZoom: m("Pan Zoom Right", "camera.viewfinder", .motion),
        .skewLeft: m("Skew Left", "line.diagonal.arrow", .motion),
        .skewRight: m("Skew Right", "line.diagonal.arrow", .motion),

        .spinLeft: m("Spin Left", "rotate.left", .distortion),
        .spinRight: m("Spin Right", "rotate.right", .distortion),
        .spinZoom: m("Spin Zoom", "tornado", .distortion),
        .rollLeft: m("Roll Left", "arrow.counterclockwise.circle.fill", .distortion),
        .rollRight: m("Roll Right", "arrow.clockwise.circle.fill", .distortion),
        .flipHorizontal: m("Flip Horizontal", "arrow.left.and.right", .distortion),
        .flipVertical: m("Flip Vertical", "arrow.up.and.down", .distortion),
        .squeezeHorizontal: m("Squeeze Side", "arrow.left.and.right", .distortion),
        .squeezeVertical: m("Squeeze Down", "arrow.up.and.down", .distortion),
        .stretchLeft: m("Stretch Left", "arrow.left.and.right", .distortion),
        .stretchRight: m("Stretch Right", "arrow.left.and.right", .distortion),
        .dragSwitch: m("Drag Switch", "hand.draw.fill", .distortion),

        .flash: m("Flash", "bolt.fill", .light),
        .flashZoom: m("Flash Zoom", "bolt.badge.plus.fill", .light),
        .glare: m("Glare", "sun.max.fill", .light),
        .strobe: m("Strobe", "bolt.horizontal.fill", .light),
        .lightSweep: m("Light Sweep", "wand.and.rays", .light),

        .motionBlurLeft: g("Blur Left", "wind", .blur),
        .motionBlurRight: g("Blur Right", "wind", .blur),
        .motionBlurUp: g("Blur Up", "arrow.up", .blur),
        .motionBlurDown: g("Blur Down", "arrow.down", .blur),
        .zoomBlur: g("Zoom Blur", "scope", .blur),
        .gaussianBlur: g("Soft Blur", "drop.degreesign", .blur),
        .radialBlur: g("Radial Blur", "dot.radiowaves.left.and.right", .blur),

        .pixelDissolve: g("Pixel Dissolve", "square.grid.3x3.fill", .glitch),
        .crystallize: g("Crystallize", "snowflake", .glitch),
        .rgbSplit: g("RGB Split", "circle.hexagongrid.fill", .glitch),
        .glitch: g("Signal Glitch", "waveform.path.ecg", .glitch),

        .ripple: g("Liquid Ripple", "water.waves", .distortion),
        .fisheye: g("Fisheye", "camera.macro", .distortion),
        .kaleidoscope: g("Kaleidoscope", "hexagon.fill", .distortion),
        .bumpPulse: g("Bump Pulse", "circle.grid.2x2.fill", .distortion),
        .pinchPulse: g("Pinch Pulse", "smallcircle.filled.circle", .distortion),
        .vortexLeft: g("Vortex Left", "hurricane", .distortion),
        .vortexRight: g("Vortex Right", "hurricane", .distortion),
        .glassWarp: g("Glass Warp", "square.3.layers.3d", .distortion),
        .triangleMirror: g("Triangle Mirror", "triangle.fill", .distortion),
        .torusLens: g("Torus Lens", "circle.circle", .distortion),

        .comicFlash: g("Comic Flash", "bubble.left.fill", .artistic),
        .bloom: g("Dream Bloom", "sparkles", .artistic),
        .vignettePulse: g("Vignette Pulse", "circle.inset.filled", .artistic),
        .hueSpin: g("Hue Spin", "paintpalette.fill", .artistic),
        .colorInvert: g("Color Invert", "circle.lefthalf.striped.horizontal", .artistic),
        .posterize: g("Posterize", "square.stack.3d.up.fill", .artistic),
        .noirFlash: g("Noir Flash", "circle.fill", .artistic),
        .sepiaFlash: g("Sepia Flash", "camera.filters", .artistic),
        .chromeFlash: g("Chrome Flash", "diamond.fill", .artistic),
        .processFlash: g("Process Flash", "camera.filters", .artistic),
        .falseColor: g("Heat Shift", "thermometer.high", .artistic),
        .edgeGlow: g("Edge Glow", "scribble.variable", .artistic),

        .circleReveal: gm("Circle Reveal", "circle.dashed", .mask),
        .radialWipe: gm("Radial Wipe", "circle.circle.fill", .mask)
    ]

    private static func m(
        _ title: String,
        _ systemImage: String,
        _ category: EditorTransitionCategory
    ) -> EditorTransitionMetadata {
        .init(title: title, systemImage: systemImage, category: category)
    }

    private static func g(
        _ title: String,
        _ systemImage: String,
        _ category: EditorTransitionCategory
    ) -> EditorTransitionMetadata {
        .init(title: title, systemImage: systemImage, category: category, renderer: .gpu)
    }

    private static func gm(
        _ title: String,
        _ systemImage: String,
        _ category: EditorTransitionCategory
    ) -> EditorTransitionMetadata {
        .init(title: title, systemImage: systemImage, category: category, renderer: .gpuMask)
    }
}

enum EditorTransitionCategory: String, CaseIterable, Identifiable {
    case all = "All"
    case basic = "Basic"
    case camera = "Camera"
    case motion = "Motion"
    case light = "Light"
    case blur = "Blur"
    case glitch = "Glitch"
    case mask = "Mask"
    case artistic = "Artistic"
    case distortion = "Distortion"

    var id: String { rawValue }
}

private struct EditorTransitionMetadata {
    enum Renderer {
        case standard
        case gpu
        case gpuMask
    }

    let title: String
    let systemImage: String
    let category: EditorTransitionCategory
    var renderer: Renderer = .standard
}

enum EditorTransitionTarget: Hashable, Identifiable {
    case opening
    case closing
    case cut(afterClipAt: Int)

    var id: String {
        switch self {
        case .opening: return "opening"
        case .closing: return "closing"
        case .cut(let index): return "cut-\(index)"
        }
    }

    var isEndpoint: Bool {
        switch self {
        case .opening, .closing: return true
        case .cut: return false
        }
    }

    var navigationTitle: String {
        switch self {
        case .opening: return "Opening Transition"
        case .closing: return "Closing Transition"
        case .cut: return "Transition"
        }
    }
}
