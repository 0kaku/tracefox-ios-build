import plistlib
from pathlib import Path
import struct
import sys
import tempfile
import unittest
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "ci"))
from verify_ipa import verify_ipa

BUNDLE = "one.tracefox.ios.buildtest"


class VerifyIpaTest(unittest.TestCase):
    def make_ipa(self, folder, *, platform=2, signature=False, profile=False, unsafe=False, truncated=False):
        commands = struct.pack("<6I", 0x32, 24, platform, 0, 0, 0)
        if signature:
            commands += struct.pack("<4I", 0x1D, 16, 0, 0)
        binary = struct.pack("<8I", 0xFEEDFACF, 0x0100000C, 0, 2, 1 + signature, len(commands), 0, 0) + commands
        if truncated:
            binary = binary[:-1]
        path = Path(folder) / "sample.ipa"
        with zipfile.ZipFile(path, "w") as archive:
            archive.writestr("Payload/Test.app/Info.plist", plistlib.dumps({"CFBundleIdentifier": BUNDLE,
                "CFBundlePackageType": "APPL", "CFBundleExecutable": "Test", "CFBundleSupportedPlatforms": ["iPhoneOS"]}))
            archive.writestr("Payload/Test.app/Test", binary)
            if profile:
                archive.writestr("Payload/Test.app/embedded.mobileprovision", b"profile")
            if unsafe:
                archive.writestr("../escape", b"bad")
        return path

    def test_unsigned_device_accepted(self):
        with tempfile.TemporaryDirectory() as folder:
            self.assertFalse(verify_ipa(self.make_ipa(folder), BUNDLE)["signed"])

    def test_invalid_results_rejected(self):
        for options in [{"platform": 7}, {"signature": True}, {"profile": True}, {"unsafe": True}, {"truncated": True}]:
            with self.subTest(options=options), tempfile.TemporaryDirectory() as folder:
                with self.assertRaises(ValueError):
                    verify_ipa(self.make_ipa(folder, **options), BUNDLE)

    def test_wrong_bundle_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            with self.assertRaises(ValueError):
                verify_ipa(self.make_ipa(folder), "another.app")


if __name__ == "__main__":
    unittest.main()
