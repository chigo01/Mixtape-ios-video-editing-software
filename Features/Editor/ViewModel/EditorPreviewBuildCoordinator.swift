//
//  EditorPreviewBuildCoordinator.swift
//  Mixtape
//

import Foundation

// MARK: Preview build coordination

/// Shares an in-flight build and lets only the newest request consume its result.
/// A different edit waits for that build to drain before starting another one.
@MainActor
final class EditorPreviewBuildCoordinator<Value> {
    private var latestRequest = UUID()
    private var pending: (id: UUID, key: String, task: Task<Value?, Never>)?

    func value(for key: String, build: @escaping @MainActor () async -> Value?) async -> Value? {
        guard !Task.isCancelled else { return nil }
        let request = UUID()
        latestRequest = request
        while !Task.isCancelled, latestRequest == request {
            if pending == nil {
                pending = (UUID(), key, Task { await build() })
            }
            guard let current = pending else { return nil }
            let result = await current.task.value
            if pending?.id == current.id { pending = nil }
            guard latestRequest == request, !Task.isCancelled else { return nil }
            if current.key == key, !current.task.isCancelled { return result }
        }
        return nil
    }

    func cancel() {
        latestRequest = UUID()
        pending?.task.cancel()
        // Keep the task until it drains so a new session cannot overlap its work.
    }
}

