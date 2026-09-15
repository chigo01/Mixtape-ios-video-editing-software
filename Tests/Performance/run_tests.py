"""Compile production coordination/I/O helpers without iOS UI dependencies."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
store = (root / 'Features/ProjectList/Services/ProjectStore.swift').read_text()
writer = store.split('// MARK: Ordered project file I/O\n', 1)[1].split('enum EditorTemplateStoreError', 1)[0]
with tempfile.TemporaryDirectory(prefix='mixtape-performance-') as directory:
    directory = Path(directory)
    helpers = directory / 'Helpers.swift'
    helpers.write_text('import Foundation\n' + writer)
    binary = directory / 'tests'
    subprocess.run(['swiftc', '-swift-version', '5', '-module-cache-path', '/tmp/mixtape-swift-cache', str(root / 'Features/Editor/ViewModel/EditorPreviewBuildCoordinator.swift'), str(helpers), str(root / 'Tests/Performance/ResponsivenessTests.swift'), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True, timeout=30)
