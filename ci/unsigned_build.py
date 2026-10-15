"""Compile the pinned upstream client without Apple credentials or a provisioning profile."""
import argparse
import hashlib
import importlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
from types import SimpleNamespace

from verify_ipa import verify_ipa

COMMIT = "e45952ec5f30338dc83989e5798c9c683298794c"
BUNDLE_ID = "one.tracefox.ios.buildtest"
XCODE = Path("/Applications/Xcode_26.2.app/Contents/Developer")


def check_source(source):
    head = subprocess.check_output(["git", "-C", str(source), "rev-parse", "HEAD"], text=True).strip()
    if head != COMMIT:
        raise RuntimeError("Source commit differs from the reviewed build recipe")
    versions = json.loads((source / "versions.json").read_text())
    if versions["xcode"] != "26.2" or not versions["bazel"].startswith("8.4.2:"):
        raise RuntimeError("Upstream toolchain changed; review the recipe")
    for path in ["build-system/Make/Make.py", "submodules/TelegramCore/BUILD", "Swiftgram/SGSettingsUI/BUILD"]:
        if not (source / path).is_file():
            raise RuntimeError("Missing source dependency: " + path)
    signing = source / "build-system/bazel-rules/rules_apple/apple/internal/codesigning_support.bzl"
    if 'if "disable_legacy_signing" in features:' not in signing.read_text():
        raise RuntimeError("Upstream no-signing support changed")
    return versions


def preflight(source, output):
    versions = check_source(source)
    environment = {"commit": COMMIT, "versions": versions, "system": platform.system(),
                   "architecture": platform.machine(), "disk_free_gib": round(shutil.disk_usage(source).free / 2**30, 1)}
    output.mkdir(parents=True, exist_ok=True)
    (output / "environment.json").write_text(json.dumps(environment, indent=2))
    if platform.system() != "Darwin":
        raise RuntimeError("Compilation requires macOS; source validation can run on Windows")
    if not XCODE.is_dir():
        raise RuntimeError("Xcode 26.2 is not installed on this runner")
    os.environ["DEVELOPER_DIR"] = str(XCODE)
    actual = subprocess.check_output(["/usr/bin/xcodebuild", "-version"], text=True)
    if not actual.startswith("Xcode 26.2\n"):
        raise RuntimeError("Unexpected selected Xcode: " + actual)
    subprocess.run(["/usr/bin/xcrun", "--sdk", "iphoneos", "--show-sdk-path"], check=True)
    if environment["disk_free_gib"] < 12:
        raise RuntimeError("Less than 12 GiB free: choose a runner with more space")
    print(json.dumps(environment, indent=2), flush=True)


def configuration():
    # Deliberate compile-only placeholders. This artifact cannot log into Telegram.
    # No backend secrets, Telegram session keys or Apple credentials are read.
    return {"bundle_id": BUNDLE_ID, "api_id": "1", "api_hash": "0" * 32,
            "team_id": "0000000000", "app_center_id": "0", "is_internal_build": "true",
            "is_appstore_build": "false", "appstore_id": "0", "app_specific_url_scheme": "tracefoxbuildtest",
            "premium_iap_product_id": "", "enable_siri": False, "enable_icloud": False,
            "sg_config": json.dumps({"api_url": "https://example.invalid", "webapp_url": "https://example.invalid",
                                     "bot_username": "tracefox_build_test", "iaps": []})}


def compile_app(source, output, build_number):
    os.chdir(source)
    build_file = source / "Telegram/BUILD"
    original = build_file.read_text()
    watch = '    watch_application = ":TelegramWatchApp", # MARK: Swiftgram'
    if original.count(watch) != 1:
        raise RuntimeError("Watch target changed; review the unsigned build patch")
    # Only the disposable runner checkout is changed. Avoid a second watchOS build.
    build_file.write_text(original.replace(watch, '    watch_application = None, # build-test only'))
    try:
        config_path = source / "build-input/tracefox-build-test.json"
        config_path.parent.mkdir(exist_ok=True)
        config_path.write_text(json.dumps(configuration()))
        sys.path.insert(0, str(source / "build-system/Make"))
        make = importlib.import_module("Make")
        bazel = make.locate_bazel(base_path=str(source), cache_host_or_path=None, cache_dir=None)
        command = make.BazelCommandLine(bazel=bazel, override_bazel_version=False,
                                       override_xcode_version=False, bazel_user_root=None)
        args = SimpleNamespace(configurationPath=str(config_path), gitCodesigningRepository=None,
                               codesigningInformationPath=None, xcodeManagedCodesigning=True)
        make.resolve_configuration(base_path=str(source), bazel_command_line=command, arguments=args,
                                   additional_codesigning_output_path=None)
        command.set_configuration("release_arm64")
        command.set_build_number(build_number)
        command.set_disable_provisioning_profiles()
        command.common_args += ["--features=disable_legacy_signing", "--//Telegram:disableExtensions=true"]
        command.common_build_args = [arg for arg in command.common_build_args if not arg.startswith("--jobs=")]
        command.common_build_args += ["--jobs=2", "--local_ram_resources=4096"]
        command.invoke_build()
        ipa = source / "bazel-bin/Telegram/Swiftgram.ipa"
        report = verify_ipa(ipa, BUNDLE_ID)
        target = output / "TraceFox-iOS-build-test-unsigned.ipa"
        shutil.copyfile(ipa, target)
        report.update(source_commit=COMMIT, build_number=build_number, login_enabled=False,
                      tracefox_bot_integrated=False, size=target.stat().st_size)
        digest = hashlib.sha256()
        with target.open("rb") as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(chunk)
        report["sha256"] = digest.hexdigest()
        (output / "ipa-verification.json").write_text(json.dumps(report, indent=2))
        print("Unsigned device build verified; this is not a signed or functional TraceFox release.", flush=True)
    finally:
        build_file.write_text(original)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--preflight-only", action="store_true")
    parser.add_argument("--check-source-only", action="store_true")
    args = parser.parse_args()
    source, output = args.source.resolve(), args.output.resolve()
    if args.check_source_only:
        print(json.dumps(check_source(source), indent=2))
        return
    preflight(source, output)
    if not args.preflight_only:
        number = int(os.environ.get("BUILD_NUMBER", "1"))
        if number < 1:
            raise ValueError("Build number must be positive")
        compile_app(source, output, number)


if __name__ == "__main__":
    main()
