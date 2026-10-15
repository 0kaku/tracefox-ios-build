# TraceFox iOS: unsigned upstream build test

This repository tests whether the public DarkGram source compiles on a GitHub-hosted Mac.
It does **not** contain a working TraceFox iOS integration. No Telegram account can log into
the test artifact: API credentials are deliberate placeholders. Bot integration, branding,
archive behavior and signing remain separate work after a successful upstream build.

Upstream: https://github.com/nepcukk/Darkgram
Pinned commit: `e45952ec5f30338dc83989e5798c9c683298794c`.
Its versions.json requires Xcode 26.2 and Bazel 8.4.2; the reviewed upstream
rules_apple supports `disable_legacy_signing`. Upstream source is downloaded by the job,
not copied into this recipe repository. Retain all upstream licences when distributing a fork.

## Start from Windows or a phone

1. Sign into your GitHub account and create a **public** empty repository, for example
   `tracefox-ios-build`. Standard macOS Actions runners are free for public repositories;
   do not enable a paid larger runner for this test. Private repositories have different billing.
2. Upload the contents of this directory, including `.github/workflows/ios-unsigned.yml`,
   `ci/unsigned_build.py`, `ci/verify_ipa.py` and the tests. No secrets are required.
   In the GitHub web uploader you can upload the workflow file under the path
   `.github/workflows/ios-unsigned.yml` using **Add file → Create new file**.
3. Open **Actions → iOS unsigned build test → Run workflow**. If GitHub asks to enable
   Actions for the repository, enable it. The recipe runs only when manually started.
4. Inspect the run log. A failed run uploads diagnostics. Only a successful build with
   IPA verification uploads `TraceFox-iOS-build-test-unsigned-<run number>`.

The job uses macos-26, selects installed Xcode 26.2 exactly, checks disk capacity, and
limits Bazel to two jobs. A 12 GiB minimum free-space check is only an early failure check,
not a guarantee that this large application fits a standard runner. If the build runs out
of disk or memory, retain its log to choose the next environment. Nothing is purchased
automatically. The run times out after 180 minutes; artifacts expire after seven days.

Apple Watch and app extensions are omitted from this compile test. Provisioning and
code signing are disabled using the upstream build flags. No Apple ID, certificates,
Telegram session or bot/backend secret is read. The build recipe has only read access
to repository contents and never creates a GitHub Release or sends an IPA to users.

The pinned upstream packaging rule additionally requires a profile even when signing
is disabled. The recipe patches only its main application packaging branch in the
disposable source checkout, skipping profile embedding when `disable_legacy_signing`
is enabled. Normal signed-build behavior stays intact; all patches are restored afterward.

The vendored Metal compiler rule is also patched to declare sibling shader sources as
inputs to each Metal compile action. DustEffect shaders include `loki_header.metal`;
without that dependency declaration the header is absent inside Bazel's compile sandbox.
Sandboxing stays enabled, shader code and application behavior stay unchanged.

The public DarkGram source includes incomplete, unwired additions. The baseline
compilation test excludes 17 exact files from five reachable build targets:
selection/composition AI helpers, unfinished settings controllers, AI runtime,
deleted-history/reply helpers, and sync. Their top-level entry declarations have
no references outside the DarkGram addition group in the reviewed Swiftgram,
TelegramUI and TelegramCore source. Independent optional libraries remain in the
checkout but are not added to the application dependency graph.

No placeholder sync settings are injected in this baseline. The older compatibility
Swift file is retained in recipe history but is not copied into the build.
All other members of the five source globs remain unchanged; regression tests check
this. Changes are restored after compilation. This tests the underlying client,
not a complete or working implementation of DarkGram/TraceFox features.

## What success proves

A success proves that the pinned source builds an unsigned arm64 iPhone application,
not a simulator application. Verification checks bundle identity, ZIP integrity,
Mach-O platform and absence of main executable signing/provisioning. The IPA still
needs a valid signing and installation method. It is **not ready for normal use**.
No device/UI test is performed by this pipeline.

## Local checks without a Mac

```powershell
python -m unittest discover -s tests -v
python ci/unsigned_build.py --source D:/TraceFoxBuild/tracefox-darkgram-ios --output artifacts --check-source-only
```

The second command validates the upstream commit, toolchain versions and required files.
It does not compile Swift. Building requires the macOS runner.


The pinned-source audit checked 40 top-level entry symbols from the 17 excluded
files against 3,851 retained Swift files across Swiftgram and submodules, with no
outside references. The IPA verification report labels any result baseline_only
and lists all excluded paths; it must not be presented as working DarkGram.

## WebRTC private compilation inputs

The Objective-C WebRTC target includes C++ headers such as rtc_base/checks.h, but
its original source list does not declare the existing webrtc_headers list.
The build-test patch adds those 1,367 headers as private source inputs of
webrtc_objc. It does not change compiler flags, public module headers, source
implementations, libraries, or sandboxing. The SDK include graph was inspected
across 673 files; remaining undeclared headers belong to inactive Windows/Abseil
branches for this iPhone build. The upstream BUILD file is restored afterward.
