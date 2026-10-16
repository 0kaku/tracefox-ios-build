"""Compile the pinned upstream client without Apple credentials or a provisioning profile."""
import argparse
import hashlib
import importlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys
from types import SimpleNamespace

from verify_ipa import verify_ipa
from tracefox_configuration import login_configuration, login_enabled, integration_changes

COMMIT = "e45952ec5f30338dc83989e5798c9c683298794c"
BUNDLE_ID = "one.tracefox.ios.buildtest"
XCODE = Path("/Applications/Xcode_26.2.app/Contents/Developer")


def check_source(source):
    head = subprocess.check_output(["git", "-C", str(source), "rev-parse", "HEAD"], text=True).strip()
    if head != COMMIT:
        raise RuntimeError("Source commit differs from the reviewed build recipe")
    versions = json.loads((source / "versions.json").read_text(encoding="utf-8"))
    if versions["xcode"] != "26.2" or not versions["bazel"].startswith("8.4.2:"):
        raise RuntimeError("Upstream toolchain changed; review the recipe")
    for path in ["build-system/Make/Make.py", "submodules/TelegramCore/BUILD", "Swiftgram/SGSettingsUI/BUILD"]:
        if not (source / path).is_file():
            raise RuntimeError("Missing source dependency: " + path)
    signing = source / "build-system/bazel-rules/rules_apple/apple/internal/codesigning_support.bzl"
    if 'if "disable_legacy_signing" in features:' not in signing.read_text(encoding="utf-8"):
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
    return login_configuration({"bundle_id": BUNDLE_ID, "api_id": "1", "api_hash": "0" * 32,
            "team_id": "0000000000", "app_center_id": "0", "is_internal_build": "true",
            "is_appstore_build": "false", "appstore_id": "0", "app_specific_url_scheme": "tracefoxbuildtest",
            "premium_iap_product_id": "", "enable_siri": False, "enable_icloud": False,
            "sg_config": json.dumps({"api_url": "https://example.invalid", "webapp_url": "https://example.invalid",
                                     "bot_username": "tracefox_build_test", "iaps": []}, separators=(",", ":"))})


ORPHAN_SOURCES = {
    "submodules/TelegramUI/Components/Chat/ChatMessageSelectionInputPanelNode": [
        "Sources/DarkgramAISelectionActions.swift"],
    "submodules/TelegramUI/Components/Chat/ChatTextInputPanelNode": [
        "Sources/DarkgramAIComposeRuntime.swift"],
    "Swiftgram/SGSettingsUI": [
        "Sources/DarkgramAISettingsController.swift", "Sources/DarkgramAIAPIKeysController.swift",
        "Sources/DarkgramVoiceLabSettingsController.swift",
        "Sources/DarkgramAboutController.swift", "Sources/DarkgramArchiveMobileDataExceptionsController.swift",
        "Sources/DarkgramDeletedMessagesBrowser.swift", "Sources/DarkgramDesign.swift",
        "Sources/DarkgramEncryptionSettingsController.swift", "Sources/DarkgramGhostReadExceptionsController.swift"],
    "submodules/TelegramUI": [
        "Sources/Chat/DarkgramAIRuntime.swift", "Sources/Chat/DarkgramAIMessageActions.swift",
        "Sources/DarkgramDialogDeletedHistoryScreen.swift", "Sources/Chat/DarkgramReplySubject.swift"],
    "submodules/TelegramCore": [
        "Sources/Swiftgram/DarkgramSync.swift", "Sources/Swiftgram/DarkgramReplyQuote.swift"],
}


def orphan_source_changes(source):
    changes = {}
    pattern = re.compile(r'(glob\(\[\s*"Sources/\*\*/\*\.swift",\s*\])(\))')
    for package, excluded in ORPHAN_SOURCES.items():
        path = source / package / "BUILD"
        original = path.read_text(encoding="utf-8")
        if len(pattern.findall(original)) != 1:
            raise RuntimeError("Orphan-source rule changed: " + package)
        replacement = pattern.sub(lambda match: match[1] + ", exclude = " + json.dumps(excluded) + match[2], original)
        changes[path] = (original, replacement)
    return changes


def webrtc_source_changes(source):
    path = source / "third-party/webrtc/BUILD"
    original = path.read_text(encoding="utf-8")
    anchor = '        "webrtc/rtc_base/system/gcd_helpers.m",\n    ],\n    copts = ['
    if original.count(anchor) != 1:
        raise RuntimeError("WebRTC Objective-C source rule changed; review private header inputs")
    replacement = '        "webrtc/rtc_base/system/gcd_helpers.m",\n    ] + ["webrtc/" + path for path in webrtc_headers],\n    copts = ['
    return {path: (original, original.replace(anchor, replacement))}


def unsigned_source_changes(source):
    build_file = source / "Telegram/BUILD"
    rules_file = source / "build-system/bazel-rules/rules_apple/apple/internal/ios_rules.bzl"
    original = build_file.read_text(encoding="utf-8")
    rules = rules_file.read_text(encoding="utf-8")
    watch = '    watch_application = ":TelegramWatchApp", # MARK: Swiftgram'
    profile = "    if platform_prerequisites.platform.is_device:\n        processor_partials.append(\n            partials.provisioning_profile_partial("
    if original.count(watch) != 1 or profile not in rules:
        raise RuntimeError("Upstream device packaging changed; review the unsigned build patch")
    # Only the application packaging branch is changed, and only for the explicit
    # no-signing feature. A normal signed build still requires its original profile.
    patched_rules = rules.replace(profile,
        '    if platform_prerequisites.platform.is_device and "disable_legacy_signing" not in platform_prerequisites.features:\n'
        '        processor_partials.append(\n            partials.provisioning_profile_partial(', 1)
    metal_file = source / "build-system/bazel-rules/rules_apple/apple/internal/resource_actions/metals.bzl"
    metal = metal_file.read_text(encoding="utf-8")
    metal_input = "            inputs = [input_metal] + hdrs,"
    if metal.count(metal_input) != 1:
        raise RuntimeError("Metal input rule changed; review included shader dependencies")
    # Shader sources can include other .metal files (loki_header.metal). Bazel
    # must expose them inside the compile sandbox, not just the current source.
    patched_metal = metal.replace(metal_input, "            inputs = metal_files + hdrs,")
    changes = {build_file: (original, original.replace(watch, '    watch_application = None, # build-test only')),
               rules_file: (rules, patched_rules), metal_file: (metal, patched_metal)}
    changes.update(orphan_source_changes(source))
    changes.update(webrtc_source_changes(source))
    changes.update(integration_changes(source))
    if login_enabled():
        settings_build = source / 'Swiftgram/SGSettingsUI/BUILD'
        original, modified = changes[settings_build]
        dependency = '        "//Swiftgram/SGItemListUI:SGItemListUI",'
        if modified.count(dependency) != 1:
            raise RuntimeError('TraceFox settings dependency anchor changed')
        changes[settings_build] = (original, modified.replace(dependency, dependency + '\n        "//Swiftgram/SGConfig:SGConfig",'))
    return changes



def compile_app(source, output, build_number):
    os.chdir(source)
    changes = unsigned_source_changes(source)
    try:
        for file, (_, replacement) in changes.items():
            file.write_text(replacement)
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
        report = verify_ipa(ipa, configuration()['bundle_id'])
        target = output / "TraceFox-iOS-build-test-unsigned.ipa"
        shutil.copyfile(ipa, target)
        report.update(automatic_bot_connection=login_enabled(), automatic_backup=login_enabled(), automatic_backup_scope='Supported cloud records and first retained file; secret records local; foreground/resume worker', automatic_backup_device_verified=False, archive_categories=login_enabled(), source_commit=COMMIT, build_number=build_number, login_enabled=login_enabled(),
                      tracefox_bot_integrated=login_enabled(), baseline_only=not login_enabled(), darkgram_features_integrated=False,
                      excluded_source_files=sum(ORPHAN_SOURCES.values(), []), size=target.stat().st_size)
        report.update(tracefox_settings_integrated=login_enabled(), cloud_archive_bot_link=login_enabled(),
                      device_tested=False, signing_required=True, local_media_archive=login_enabled(), ghost_mode=False,
                      local_archive_scope='deletion, read and native timer expiry hooks; completed local media only',
                      edit_history=login_enabled(), edit_history_scope='plain text only; 100 prior versions / 512 KiB',
                      temporary_media_expiry_hooks=login_enabled(), local_archive_browser=login_enabled())
        report.update(privacy_native_hooks=login_enabled(), privacy_control=login_enabled(),
                      privacy_screen_compiled=login_enabled(), privacy_settings_navigation=login_enabled(),
                      bot_pairing_navigation=login_enabled(), bot_pairing_device_verified=False,
                      privacy_transport_device_verified=False,
                      archive_total_quota_bytes=1024 * 1024 * 1024)
        digest = hashlib.sha256()
        with target.open("rb") as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(chunk)
        report["sha256"] = digest.hexdigest()
        (output / "ipa-verification.json").write_text(json.dumps(report, indent=2))
        print("Unsigned device build verified; this is not a signed or functional TraceFox release.", flush=True)
    finally:
        for file, (original, _) in changes.items():
            if original is None:
                file.unlink(missing_ok=True)
            else:
                file.write_text(original)


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
