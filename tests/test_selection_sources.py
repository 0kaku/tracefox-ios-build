import ast
import fnmatch
from pathlib import Path
import shutil
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "ci"))
from unsigned_build import ORPHAN_SOURCES, orphan_source_changes

SOURCE = Path(r"D:\TraceFoxBuild\tracefox-darkgram-ios")


@unittest.skipUnless(SOURCE.is_dir(), "Pinned checkout is required for source-list regression checks")
class SelectionSourcesTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.source = Path(self.temp.name)
        for package in ORPHAN_SOURCES:
            dst = self.source / package / "BUILD"
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(SOURCE / package / "BUILD", dst)

    def source_list(self, package, text):
        calls = [node for node in ast.walk(ast.parse(text)) if isinstance(node, ast.Call)
                 and isinstance(node.func, ast.Name) and node.func.id == "glob"]
        call = next(call for call in calls if ast.literal_eval(call.args[0]) == ["Sources/**/*.swift"])
        excluded = next((ast.literal_eval(k.value) for k in call.keywords if k.arg == "exclude"), [])
        paths = {p.relative_to(SOURCE / package).as_posix()
                 for p in (SOURCE / package).glob("Sources/**/*.swift")}
        return {p for p in paths if not any(fnmatch.fnmatch(p, rule) for rule in excluded)}

    def test_only_reviewed_orphans_are_excluded(self):
        changes = orphan_source_changes(self.source)
        count = 0
        for package, excluded in ORPHAN_SOURCES.items():
            original, patched = changes[self.source / package / "BUILD"]
            before, after = self.source_list(package, original), self.source_list(package, patched)
            self.assertEqual(before - after, set(excluded), package)
            self.assertFalse(after - before)
            self.assertTrue(after, package)
            self.assertEqual((self.source / package / "BUILD").read_text(encoding="utf-8"), original)
            count += len(excluded)
        self.assertEqual(count, 7)

    def test_normal_selection_panel_is_retained(self):
        package = next(iter(ORPHAN_SOURCES))
        _, patched = orphan_source_changes(self.source)[self.source / package / "BUILD"]
        paths = self.source_list(package, patched)
        self.assertIn("Sources/ChatMessageSelectionInputPanelNode.swift", paths)
        for path in paths:
            self.assertNotIn("darkgramAIPresentSelectionActions", (SOURCE / package / path).read_text(encoding="utf-8"))

    def test_changed_upstream_rule_fails_closed(self):
        path = self.source / next(iter(ORPHAN_SOURCES)) / "BUILD"
        path.write_text(path.read_text(encoding="utf-8").replace("Sources/**/*.swift", "Different/**/*.swift"), encoding="utf-8")
        with self.assertRaisesRegex(RuntimeError, "Orphan-source rule changed"):
            orphan_source_changes(self.source)


if __name__ == "__main__":
    unittest.main()
