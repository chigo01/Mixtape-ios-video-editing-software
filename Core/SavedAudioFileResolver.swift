import Foundation

/// iOS may relocate both containers when installing a new build. Preserve the
/// path within the container instead of treating its old UUID as file identity.
/// This applies to every app-owned project asset, including audio, graphics,
/// and canvas background images.
enum SavedProjectFileResolver {
    static func resolve(
        _ path: String,
        home: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true),
        bundle: URL = Bundle.main.bundleURL
    ) -> URL? {
        let original = URL(fileURLWithPath: path)
        if FileManager.default.fileExists(atPath: original.path) { return original }

        var candidate: URL?
        for marker in ["/Library/Application Support/", "/Documents/", "/Library/Caches/"] {
            if let range = path.range(of: marker) {
                candidate = home.appendingPathComponent(String(path[range.lowerBound...].dropFirst()))
                break
            }
        }
        if candidate == nil, let range = path.range(of: ".app/") {
            candidate = bundle.appendingPathComponent(String(path[range.upperBound...]))
        }
        guard let candidate,
              FileManager.default.fileExists(atPath: candidate.path) else { return nil }
        return candidate
    }
}

/// Kept as a source-compatible name for the existing saved-audio call sites.
typealias SavedAudioFileResolver = SavedProjectFileResolver
