import Foundation

// Run with:
// swiftc Core/SavedAudioFileResolver.swift Tests/Persistence/SavedAudioFileResolverTests.swift -o /tmp/audio-path-tests && /tmp/audio-path-tests
@main
struct SavedAudioFileResolverTests {
    static func main() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let home = root.appendingPathComponent("new-container")
        let bundle = root.appendingPathComponent("new-install/Mixtape.app")
        defer { try? fm.removeItem(at: root) }
        func write(_ url: URL) throws {
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("audio".utf8).write(to: url)
        }
        for relative in [
            "Library/Application Support/MixtapeAudio/id-Type%20Shit (Raag.Fm).mp3",
            "Library/Application Support/MixtapeAudio/voiceover.m4a",
            "Library/Application Support/MixtapeCanvas/background.jpg",
            "Library/Application Support/MixtapeTemplateAppliedAssets/project/template/audio.wav",
            "Library/Application Support/MixtapeAudioLibraryCache/sound.mp3",
            "Documents/music.m4a",
            "Library/Caches/audio.mp3"
        ] {
            let expected = home.appendingPathComponent(relative)
            try write(expected)
            let saved = "/var/mobile/Containers/Data/Application/OLD-UUID/" + relative
            // Exercise serialized saved paths, including literal percent escapes.
            let decoded = try JSONDecoder().decode(String.self, from: JSONEncoder().encode(saved))
            precondition(SavedAudioFileResolver.resolve(decoded, home: home, bundle: bundle) == expected)
        }
        print("PASS: imported project assets survive container relocation")
        let bundled = bundle.appendingPathComponent("Audio/beat.wav")
        try write(bundled)
        precondition(SavedAudioFileResolver.resolve("/old/install/Mixtape.app/Audio/beat.wav", home: home, bundle: bundle) == bundled)
        print("PASS: bundled audio survives app replacement")
        let external = root.appendingPathComponent("external.wav")
        try write(external)
        precondition(SavedAudioFileResolver.resolve(external.path, home: home, bundle: bundle) == external)
        precondition(SavedAudioFileResolver.resolve("/old/Library/Application Support/MixtapeAudio/missing.mp3", home: home, bundle: bundle) == nil)
        precondition(SavedAudioFileResolver.resolve("/unrelated/beat.wav", home: home, bundle: bundle) == nil)
        print("PASS: existing files preserved; missing files do not resolve to unrelated audio")
    }
}
