import Foundation

@MainActor
final class BuildGate {
    var started = 0
    var waiting: [CheckedContinuation<Int?, Never>] = []
    func build() async -> Int? {
        started += 1
        return await withCheckedContinuation { waiting.append($0) }
    }
    func finish(_ value: Int?) { waiting.removeFirst().resume(returning: value) }
}

struct SlowDocument: Encodable {
    let value: Int
    let started: DispatchSemaphore
    let release: DispatchSemaphore
    func encode(to encoder: Encoder) throws {
        precondition(!Thread.isMainThread, "Autosave encoding blocked the UI thread")
        started.signal()
        release.wait()
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

@main
struct ResponsivenessTests {
    @MainActor
    static func settle() async { for _ in 0..<30 { await Task.yield() } }

    @MainActor
    static func main() async throws {
        let coordinator = EditorPreviewBuildCoordinator<Int>()
        let gate = BuildGate()
        let first = Task { await coordinator.value(for: "A") { await gate.build() } }
        await settle()
        precondition(gate.started == 1)
        let same = Task { await coordinator.value(for: "A") { await gate.build() } }
        await settle()
        precondition(gate.started == 1, "Same edit started a duplicate build")
        gate.finish(1)
        let firstValue = await first.value
        let sameValue = await same.value
        precondition(firstValue == nil && sameValue == 1)
        print("PASS: identical edits share one build; only newest request receives it")

        let old = Task { await coordinator.value(for: "old") { await gate.build() } }
        await settle()
        let skipped = Task { await coordinator.value(for: "skipped") { await gate.build() } }
        await settle()
        let latest = Task { await coordinator.value(for: "latest") { await gate.build() } }
        await settle()
        precondition(gate.started == 2, "Different edits overlapped builds")
        gate.finish(2)
        await settle()
        precondition(gate.started == 3, "Intermediate edit was not coalesced")
        gate.finish(3)
        let oldValue = await old.value
        let skippedValue = await skipped.value
        let latestValue = await latest.value
        precondition(oldValue == nil && skippedValue == nil && latestValue == 3)
        print("PASS: rapid edits drain old work and build only the latest waiting edit")

        let abandoned = Task { await coordinator.value(for: "closed") { await gate.build() } }
        await settle()
        coordinator.cancel()
        let reopened = Task { await coordinator.value(for: "closed") { await gate.build() } }
        await settle()
        precondition(gate.started == 4)
        gate.finish(4)
        await settle()
        precondition(gate.started == 5)
        gate.finish(5)
        let abandonedValue = await abandoned.value
        let reopenedValue = await reopened.value
        precondition(abandonedValue == nil && reopenedValue == 5)
        print("PASS: teardown rejects late results and reopening waits for old work")

        let failed = Task { await coordinator.value(for: "failure") { await gate.build() } }
        await settle()
        gate.finish(nil)
        let failedValue = await failed.value
        precondition(failedValue == nil)
        let recovered = await coordinator.value(for: "failure") { 7 }
        precondition(recovered == 7)
        print("PASS: failed builds can be retried")

        let cancelled = Task { await coordinator.value(for: "cancelled") { await gate.build() } }
        await settle()
        cancelled.cancel()
        gate.finish(8)
        let cancelledValue = await cancelled.value
        precondition(cancelledValue == nil)
        print("PASS: cancelled refresh callers cannot receive a result")

        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("project.json")
        let writer = ProjectFileWriter()
        let started = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let autosave = Task {
            try await writer.saveInBackground(SlowDocument(value: 1, started: started, release: release), to: url)
        }
        await Task.detached { started.wait() }.value
        // Reaching here while encoding is blocked proves the main actor is available.
        release.signal()
        try writer.save(2, to: url)
        try await autosave.value
        let savedValue = try JSONDecoder().decode(Int.self, from: writer.read(from: url))
        precondition(savedValue == 2)
        print("PASS: autosave encodes off the UI thread; final save cannot be overwritten")

        let deletionStarted = DispatchSemaphore(value: 0)
        let deletionRelease = DispatchSemaphore(value: 0)
        let pendingSave = Task {
            try await writer.saveInBackground(SlowDocument(value: 3, started: deletionStarted, release: deletionRelease), to: url)
        }
        await Task.detached { deletionStarted.wait() }.value
        deletionRelease.signal()
        try writer.delete(at: url)
        try await pendingSave.value
        precondition(!FileManager.default.fileExists(atPath: url.path))
        print("PASS: queued autosave cannot recreate a deleted project")

        struct Document: Codable, Equatable { let date: Date; let name: String }
        let document = Document(date: Date(timeIntervalSince1970: 0), name: "Mixtape")
        try await writer.saveInBackground(document, to: url)
        let data = try writer.read(from: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode(Document.self, from: data)
        precondition(restored == document)
        precondition(String(decoding: data, as: UTF8.self).contains("1970-01-01T00:00:00Z"))
        print("PASS: saved JSON preserves date format and round-trips")
    }
}
