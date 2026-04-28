//  VideoProjectDTO.swift
//  Mixtape  —  Data/DTOs

import Foundation

struct VideoProjectDTO: Codable {
    let id: String
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var duration: TimeInterval
    var aspectRatio: String
    var timeline: TimelineDTO
    var exportSettings: ExportSettingsDTO

    func toDomain() -> VideoProject {
        var project = VideoProject(
            id: UUID(uuidString: id) ?? UUID(),
            name: name,
            aspectRatio: AspectRatio(rawValue: aspectRatio) ?? .widescreen,
            timeline: timeline.toDomain()
        )
        project.createdAt = createdAt
        project.updatedAt = updatedAt
        project.duration = duration
        project.exportSettings = exportSettings.toDomain()
        return project
    }

    static func fromDomain(_ entity: VideoProject) -> VideoProjectDTO {
        VideoProjectDTO(
            id: entity.id.uuidString,
            name: entity.name,
            createdAt: entity.createdAt,
            updatedAt: entity.updatedAt,
            duration: entity.duration,
            aspectRatio: entity.aspectRatio.rawValue,
            timeline: TimelineDTO.fromDomain(entity.timeline),
            exportSettings: ExportSettingsDTO.fromDomain(entity.exportSettings)
        )
    }
}

struct TimelineDTO: Codable {
    var id: String
    var videoTracks: [VideoTrackDTO]
    var audioTracks: [AudioTrackDTO]
    var duration: TimeInterval

    func toDomain() -> Timeline {
        var timeline = Timeline()
        timeline.id = UUID(uuidString: id) ?? UUID()
        timeline.videoTracks = videoTracks.map { $0.toDomain() }
        timeline.audioTracks = audioTracks.map { $0.toDomain() }
        timeline.duration = duration
        return timeline
    }

    static func fromDomain(_ entity: Timeline) -> TimelineDTO {
        TimelineDTO(
            id: entity.id.uuidString,
            videoTracks: entity.videoTracks.map { VideoTrackDTO.fromDomain($0) },
            audioTracks: entity.audioTracks.map { AudioTrackDTO.fromDomain($0) },
            duration: entity.duration
        )
    }
}

struct VideoTrackDTO: Codable {
    let id: String
    var clips: [VideoClipDTO]
    var isMuted: Bool
    var volume: Float

    func toDomain() -> VideoTrack {
        var track = VideoTrack()
        track.clips = clips.map { $0.toDomain() }
        track.isMuted = isMuted
        track.volume = volume
        return track
    }

    static func fromDomain(_ entity: VideoTrack) -> VideoTrackDTO {
        VideoTrackDTO(
            id: entity.id.uuidString,
            clips: entity.clips.map { VideoClipDTO.fromDomain($0) },
            isMuted: entity.isMuted,
            volume: entity.volume
        )
    }
}

struct VideoClipDTO: Codable {
    let id: String
    var assetURL: String
    var startTime: TimeInterval
    var duration: TimeInterval
    var trimStart: TimeInterval
    var trimEnd: TimeInterval
    var speed: Float
    var volume: Float
    var isMuted: Bool
    var effects: [EffectDTO]
    var transform: ClipTransformDTO

    func toDomain() -> VideoClip {
        var clip = VideoClip(assetURL: URL(string: assetURL) ?? URL(fileURLWithPath: ""), duration: duration)
        clip.startTime = startTime
        clip.trimStart = trimStart
        clip.trimEnd = trimEnd
        clip.speed = speed
        clip.volume = volume
        clip.isMuted = isMuted
        clip.effects = effects.map { $0.toDomain() }
        clip.transform = transform.toDomain()
        return clip
    }

    static func fromDomain(_ entity: VideoClip) -> VideoClipDTO {
        VideoClipDTO(
            id: entity.id.uuidString,
            assetURL: entity.assetURL.absoluteString,
            startTime: entity.startTime,
            duration: entity.duration,
            trimStart: entity.trimStart,
            trimEnd: entity.trimEnd,
            speed: entity.speed,
            volume: entity.volume,
            isMuted: entity.isMuted,
            effects: entity.effects.map { EffectDTO.fromDomain($0) },
            transform: ClipTransformDTO.fromDomain(entity.transform)
        )
    }
}

struct AudioTrackDTO: Codable {
    let id: String
    var assetURL: String
    var startTime: TimeInterval
    var duration: TimeInterval
    var volume: Float
    var isMuted: Bool
    var fadeIn: TimeInterval
    var fadeOut: TimeInterval

    func toDomain() -> AudioTrack {
        var track = AudioTrack(assetURL: URL(string: assetURL) ?? URL(fileURLWithPath: ""), duration: duration)
        track.startTime = startTime
        track.volume = volume
        track.isMuted = isMuted
        track.fadeIn = fadeIn
        track.fadeOut = fadeOut
        return track
    }

    static func fromDomain(_ entity: AudioTrack) -> AudioTrackDTO {
        AudioTrackDTO(
            id: entity.id.uuidString,
            assetURL: entity.assetURL.absoluteString,
            startTime: entity.startTime,
            duration: entity.duration,
            volume: entity.volume,
            isMuted: entity.isMuted,
            fadeIn: entity.fadeIn,
            fadeOut: entity.fadeOut
        )
    }
}

struct EffectDTO: Codable {
    let id: String
    var type: String
    var intensity: Float
    var startTime: TimeInterval
    var duration: TimeInterval

    func toDomain() -> Effect {
        var effect = Effect(type: EffectType(rawValue: type) ?? .brightness, intensity: intensity)
        effect.startTime = startTime
        effect.duration = duration
        return effect
    }

    static func fromDomain(_ entity: Effect) -> EffectDTO {
        EffectDTO(
            id: entity.id.uuidString,
            type: entity.type.rawValue,
            intensity: entity.intensity,
            startTime: entity.startTime,
            duration: entity.duration
        )
    }
}

struct ClipTransformDTO: Codable {
    var scale: CGFloat
    var rotation: CGFloat
    var positionX: CGFloat
    var positionY: CGFloat
    var opacity: Float

    func toDomain() -> ClipTransform {
        ClipTransform(scale: scale, rotation: rotation, position: CGPoint(x: positionX, y: positionY), opacity: opacity)
    }

    static func fromDomain(_ entity: ClipTransform) -> ClipTransformDTO {
        ClipTransformDTO(scale: entity.scale, rotation: entity.rotation, positionX: entity.position.x, positionY: entity.position.y, opacity: entity.opacity)
    }
}

struct ExportSettingsDTO: Codable {
    var resolution: String
    var frameRate: Int
    var bitrate: Int
    var format: String

    func toDomain() -> ExportSettings {
        var settings = ExportSettings()
        settings.resolution = ExportResolution(rawValue: resolution) ?? .hd1080p
        settings.frameRate = frameRate
        settings.bitrate = bitrate
        settings.format = ExportFormat(rawValue: format) ?? .mp4
        return settings
    }

    static func fromDomain(_ entity: ExportSettings) -> ExportSettingsDTO {
        ExportSettingsDTO(
            resolution: entity.resolution.rawValue,
            frameRate: entity.frameRate,
            bitrate: entity.bitrate,
            format: entity.format.rawValue
        )
    }
}