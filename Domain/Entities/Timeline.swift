//  Timeline.swift
//  Mixtape  —  Domain/Entities

import Foundation

struct Timeline: Equatable {
    var id: UUID
    var videoTracks: [VideoTrack]
    var audioTracks: [AudioTrack]
    var duration: TimeInterval

    init() {
        self.id = UUID()
        self.videoTracks = [VideoTrack()]
        self.audioTracks = []
        self.duration = 0
    }

    mutating func addClip(_ clip: VideoClip, to trackIndex: Int = 0) {
        guard trackIndex < videoTracks.count else { return }
        videoTracks[trackIndex].clips.append(clip)
        recalculateDuration()
    }

    mutating func removeClip(id: UUID) {
        for index in videoTracks.indices {
            videoTracks[index].clips.removeAll { $0.id == id }
        }
        recalculateDuration()
    }

    mutating func recalculateDuration() {
        duration = videoTracks.flatMap(\.clips)
            .map { $0.startTime + $0.duration }
            .max() ?? 0
    }
}