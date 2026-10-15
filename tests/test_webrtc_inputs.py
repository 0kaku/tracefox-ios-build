from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "ci"))
from unsigned_build import webrtc_source_changes

SOURCE = Path(r"D:\TraceFoxBuild\tracefox-darkgram-ios")


def targets(text):
    result = {}
    def select(values):
        return values.get("//conditions:default", next(iter(values.values())))
    def objc_library(**kwargs):
        result[kwargs["name"]] = kwargs
    exec(text, {"config_setting": lambda **kw: None,
        "genrule": lambda **kw: None, "cc_library": lambda **kw: None,
        "objc_library": objc_library, "select": select})
    return result


@unittest.skipUnless(SOURCE.is_dir(), "Pinned source checkout is required")
class WebRtcInputsTest(unittest.TestCase):
    def test_private_headers_are_exposed_to_objc_compile(self):
        path = SOURCE / "third-party/webrtc/BUILD"
        original, patched = webrtc_source_changes(SOURCE)[path]
        before, after = targets(original), targets(patched)
        old_sources = set(before["webrtc_objc"]["srcs"])
        new_sources = set(after["webrtc_objc"]["srcs"])
        self.assertNotIn("webrtc/rtc_base/checks.h", old_sources)
        self.assertIn("webrtc/rtc_base/checks.h", new_sources)
        self.assertIn("webrtc/rtc_base/logging.h", new_sources)
        self.assertTrue(old_sources <= new_sources)
        self.assertTrue(all(name.endswith(".h") for name in new_sources - old_sources))
        self.assertTrue(all((SOURCE / "third-party/webrtc" / name).is_file() for name in new_sources - old_sources))
        before["webrtc_objc"]["srcs"] = after["webrtc_objc"]["srcs"]
        self.assertEqual(before, after, "Changed compiler flags, libraries or other rule attributes")
        self.assertEqual(path.read_text(encoding="utf-8"), original)


if __name__ == "__main__":
    unittest.main()
