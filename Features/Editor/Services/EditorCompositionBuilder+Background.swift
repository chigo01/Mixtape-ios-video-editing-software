//
//  EditorCompositionBuilder+Background.swift
//  Mixtape
//

import AVFoundation
import Photos
import UIKit

extension EditorCompositionBuilder {
    static func makeBackgroundVideoTracks(
        in composition: AVMutableComposition,
        duration: CMTime,
        renderSize: CGSize,
        canvasSettings: EditorCanvasSettings,
        needsWhite: Bool
    ) async -> BackgroundVideoTracks {
        guard duration.seconds > 0 else {
            return BackgroundVideoTracks(black: nil, white: nil)
        }

        let primaryColor = UIColor(
            red: CGFloat((canvasSettings.backgroundColorRGB >> 16) & 0xff) / 255,
            green: CGFloat((canvasSettings.backgroundColorRGB >> 8) & 0xff) / 255,
            blue: CGFloat(canvasSettings.backgroundColorRGB & 0xff) / 255,
            alpha: 1
        )
        let primary: AVMutableCompositionTrack?
        if canvasSettings.backgroundKind == .image,
           let path = canvasSettings.backgroundImagePath {
            primary = await insertCanvasImageTrack(
                path: path, in: composition, duration: duration, renderSize: renderSize
            )
        } else {
            primary = await insertSolidVideoTrack(
                color: primaryColor,
                colorKey: String(format: "canvas-%06x", canvasSettings.backgroundColorRGB),
                in: composition,
                duration: duration,
                renderSize: renderSize
            )
        }
        let white: AVMutableCompositionTrack?
        if needsWhite {
            white = await insertSolidVideoTrack(
                color: .white,
                colorKey: "white",
                in: composition,
                duration: duration,
                renderSize: renderSize
            )
        } else {
            white = nil
        }
        return BackgroundVideoTracks(black: primary, white: white)
    }

    private static func insertSolidVideoTrack(
        color: UIColor,
        colorKey: String,
        in composition: AVMutableComposition,
        duration: CMTime,
        renderSize: CGSize
    ) async -> AVMutableCompositionTrack? {
        guard
            let url = await solidVideoURL(color: color, colorKey: colorKey, renderSize: renderSize),
            let track = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
        else { return nil }

        let asset = AVURLAsset(url: url)
        guard
            let sourceTrack = try? await asset.loadTracks(withMediaType: .video).first,
            let sourceDuration = try? await asset.load(.duration),
            sourceDuration.seconds > 0
        else { return nil }

        let sourceRange = CMTimeRange(start: .zero, duration: sourceDuration)
        do {
            try track.insertTimeRange(sourceRange, of: sourceTrack, at: .zero)
            track.scaleTimeRange(sourceRange, toDuration: duration)
            return track
        } catch {
            composition.removeTrack(track)
            return nil
        }
    }

    private static func insertCanvasImageTrack(
        path: String,
        in composition: AVMutableComposition,
        duration: CMTime,
        renderSize: CGSize
    ) async -> AVMutableCompositionTrack? {
        guard let image = UIImage(contentsOfFile: path),
              let url = await canvasImageVideoURL(image: image, path: path, renderSize: renderSize),
              let track = composition.addMutableTrack(
                withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid
              ) else { return nil }
        let asset = AVURLAsset(url: url)
        guard let source = try? await asset.loadTracks(withMediaType: .video).first,
              let sourceDuration = try? await asset.load(.duration) else { return nil }
        let range = CMTimeRange(start: .zero, duration: sourceDuration)
        do {
            try track.insertTimeRange(range, of: source, at: .zero)
            track.scaleTimeRange(range, toDuration: duration)
            return track
        } catch {
            composition.removeTrack(track)
            return nil
        }
    }
}
