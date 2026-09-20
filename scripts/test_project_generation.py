import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import generate_project
from check_source_membership import source_fingerprint, source_paths


class SourceMembershipTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="DailyRhythm-project-tests-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        for file in ("DailyRhythm/App/App.swift", "DailyRhythm/Shared/Shared.swift",
                     "DailyRhythmWidgets/Widget.swift", "DailyRhythmSchemaTests/Schema.swift"):
            self.add(file)

    def add(self, name):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("// fixture\n")
        return path

    def fingerprint(self, target):
        return source_fingerprint(self.root, source_paths(self.root, target))

    def check(self, target, expected):
        return subprocess.run([sys.executable, str(Path(__file__).with_name("check_source_membership.py")),
                               "--root", str(self.root), "--target", target, "--expected", expected],
                              capture_output=True, text=True)

    def test_old_loaded_graph_rejects_added_shared_source_in_both_targets(self):
        old = {target: self.fingerprint(target) for target in ("app", "widget", "schema-tests")}
        self.add("DailyRhythm/Shared/Notifications.swift")
        for target in ("app", "widget"):
            result = self.check(target, old[target])
            self.assertEqual(result.returncode, 1)
            self.assertIn("Close Project", result.stdout)
            self.assertEqual(self.check(target, self.fingerprint(target)).returncode, 0)
        self.assertEqual(self.check("schema-tests", old["schema-tests"]).returncode, 0)

    def test_rename_removal_and_target_specific_changes(self):
        app, widget = self.fingerprint("app"), self.fingerprint("widget")
        path = self.root / "DailyRhythm/App/App.swift"
        path.rename(path.with_name("Renamed.swift"))
        self.assertEqual(self.check("app", app).returncode, 1)
        self.assertEqual(self.check("widget", widget).returncode, 0)
        current = self.fingerprint("app")
        path.with_name("Renamed.swift").unlink()
        self.assertEqual(self.check("app", current).returncode, 1)

    def test_content_edits_and_non_swift_files_do_not_require_reload(self):
        current = self.fingerprint("app")
        (self.root / "DailyRhythm/Shared/Shared.swift").write_text("// ordinary code edit\n")
        self.add("DailyRhythm/App/Notes.md")
        self.assertEqual(self.check("app", current).returncode, 0)

    def test_atomic_generation_preserves_unchanged_file_and_original_on_failure(self):
        path = self.root / "generated.pbxproj"
        self.assertTrue(generate_project.write_if_changed(path, "old"))
        stat = path.stat()
        self.assertFalse(generate_project.write_if_changed(path, "old"))
        self.assertEqual(path.stat().st_mtime_ns, stat.st_mtime_ns)
        self.assertEqual(path.stat().st_ino, stat.st_ino)
        with patch("generate_project.os.replace", side_effect=OSError("fixture failure")):
            with self.assertRaises(OSError):
                generate_project.write_if_changed(path, "new")
        self.assertEqual(path.read_text(), "old")
        self.assertFalse(list(self.root.glob(".generated.pbxproj.*")))
        self.assertTrue(generate_project.write_if_changed(path, "new"))
        self.assertEqual(path.read_text(), "new")


if __name__ == "__main__":
    unittest.main()
