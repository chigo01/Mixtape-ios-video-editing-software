import AVFoundation
import CoreVideo

@main struct MediaTest {
    static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("source.mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.jpeg, AVVideoWidthKey: 64, AVVideoHeightKey: 64])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB, kCVPixelBufferWidthKey as String: 64, kCVPixelBufferHeightKey as String: 64])
        writer.add(input)
        precondition(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<120 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 1_000_000) }
            var buffer: CVPixelBuffer?
            CVPixelBufferCreate(nil, 64, 64, kCVPixelFormatType_32ARGB, nil, &buffer)
            let pixel = buffer!
            CVPixelBufferLockBaseAddress(pixel, [])
            memset(CVPixelBufferGetBaseAddress(pixel), Int32(frame * 2), CVPixelBufferGetDataSize(pixel))
            CVPixelBufferUnlockBaseAddress(pixel, [])
            precondition(adaptor.append(pixel, withPresentationTime: CMTime(value: Int64(frame), timescale: 30)))
        }
        input.markAsFinished()
        await writer.finishWriting()
        precondition(writer.status == .completed, "\(String(describing: writer.error))")
        let asset = AVURLAsset(url: url)
        let source = try await asset.loadTracks(withMediaType: .video)[0]
        for preset in EditorSpeedRampPreset.allCases {
            let ramp = preset.ramp
            let composition = AVMutableComposition()
            let track = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
            let duration = ramp.timelineDuration(forSourceDuration: 3.733333333)
            SpeedRampRenderer.insertSpeedAdjusted(sourceTrack: source, into: track, sourceStart: CMTime(value: 4, timescale: 30), sourceDuration: CMTime(seconds: 3.733333333, preferredTimescale: 600), timelineDuration: CMTime(seconds: duration, preferredTimescale: 600), timelineStart: .zero, uniformSpeed: 1, ramp: ramp)
            let segments = track.segments ?? []
            precondition(!segments.isEmpty)
            precondition(!segments.contains { $0.isEmpty }, "Gap in \(preset)")
            precondition(abs(composition.duration.seconds - duration) < 1.0 / 30, "Wrong duration \(preset)")
            for pair in zip(segments, segments.dropFirst()) {
                precondition(pair.0.timeMapping.target.end == pair.1.timeMapping.target.start)
                precondition(pair.0.timeMapping.source.end == pair.1.timeMapping.source.start)
            }
            let exportURL = directory.appendingPathComponent("\(preset.rawValue).mov")
            let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality)!
            try await exporter.export(to: exportURL, as: .mov)
            let exported = AVURLAsset(url: exportURL)
            let exportedDuration = try await exported.load(.duration).seconds
            precondition(abs(exportedDuration - duration) < 1.0 / 30)
            print("PASS: \(preset.title), contiguous video composition and export, \(exportedDuration)s")
        }
    }
}
