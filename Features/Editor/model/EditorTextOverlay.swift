//
//  EditorTextOverlay.swift
//  Mixtape
//
//  Created by Favour Baruch on 14/05/2026.
//

import Foundation

struct EditorTextOverlay: Identifiable, Hashable {
    let id: UUID
    var text: String
    var startTime: TimeInterval
    var endTime: TimeInterval

    init(text: String, startTime: TimeInterval, endTime: TimeInterval) {
        self.id = UUID()
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
    }

    var duration: TimeInterval { max(0, endTime - startTime) }
}
