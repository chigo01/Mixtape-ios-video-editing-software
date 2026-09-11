"""Exercise the production AVFoundation insertion helper without the iOS UI target."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
source = (root / "Features/Editor/Services/EditorCompositionBuilder.swift").read_text()
start = source.index("    private static func applySpeed(")
end = source.index("    /// Extends the last video segment", start)
# Compile the actual production methods, including the uniform-rate fallback.
helper = source[start:end].replace("private static func", "static func")
with tempfile.TemporaryDirectory(prefix="mixtape-speed-tests-") as directory:
    directory = Path(directory)
    renderer = directory / "Renderer.swift"
    renderer.write_text(
        "import AVFoundation\nstruct SpeedRampRenderer {\n"
        "static let timescale: CMTimeScale = 600\n" + helper + "\n}"
    )
    binary = directory / "media-tests"
    subprocess.run([
        "swiftc", "-module-cache-path", str(directory / "module-cache"),
        str(root / "Features/Editor/Model/EditorSpeedRamp.swift"),
        str(renderer), str(root / "Tests/Editor/SpeedRampMediaTests.swift"),
        "-o", str(binary),
    ], check=True)
    subprocess.run([str(binary)], check=True)
