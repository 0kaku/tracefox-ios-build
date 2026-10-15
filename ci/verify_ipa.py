"""Reject simulator, signed, provisioned or malformed results before uploading an IPA."""
import plistlib
from pathlib import PurePosixPath
import struct
import zipfile


def verify_ipa(path, expected_bundle):
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        bad = archive.testzip()
        if bad:
            raise ValueError("Corrupt ZIP entry: " + bad)
        for name in names:
            part = PurePosixPath(name)
            if part.is_absolute() or ".." in part.parts or "\\" in name:
                raise ValueError("Unsafe archive path")
            if name.endswith("embedded.mobileprovision") or "_CodeSignature" in part.parts:
                raise ValueError("Build unexpectedly contains a provisioning profile or bundle signature")
        plists = [name for name in names if name.startswith("Payload/") and name.endswith(".app/Info.plist") and name.count("/") == 2]
        if len(plists) != 1:
            raise ValueError("Expected exactly one main iPhone application")
        info = plistlib.loads(archive.read(plists[0]))
        if info.get("CFBundleIdentifier") != expected_bundle or info.get("CFBundlePackageType") != "APPL":
            raise ValueError("Unexpected app identity")
        if "iPhoneOS" not in info.get("CFBundleSupportedPlatforms", []):
            raise ValueError("Not an iPhone device application")
        executable = info.get("CFBundleExecutable", "")
        if not executable or "/" in executable or executable in (".", ".."):
            raise ValueError("Invalid executable name")
        binary = archive.read(plists[0].rsplit("/", 1)[0] + "/" + executable)
        if len(binary) < 32:
            raise ValueError("Missing Mach-O header")
        magic, cpu, subtype, filetype, commands, size, flags, reserved = struct.unpack_from("<8I", binary)
        if magic != 0xFEEDFACF or cpu != 0x0100000C or filetype != 2:
            raise ValueError("Main executable is not an arm64 Mach-O application")
        offset, end, device = 32, 32 + size, False
        if end > len(binary):
            raise ValueError("Truncated Mach-O command list")
        for _ in range(commands):
            if offset + 8 > end:
                raise ValueError("Truncated Mach-O command")
            command, length = struct.unpack_from("<II", binary, offset)
            if length < 8 or offset + length > end:
                raise ValueError("Invalid Mach-O command length")
            if command == 0x1D:
                raise ValueError("Executable unexpectedly contains a code signature")
            if command == 0x32 and length >= 24:
                device = struct.unpack_from("<I", binary, offset + 8)[0] == 2
            offset += length
        if offset != end or not device:
            raise ValueError("Missing iOS device build platform")
        return {"bundle_id": expected_bundle, "architecture": "arm64", "platform": "iphoneos", "signed": False}
