# TraceFox iOS: integration build and verification

Current state is recorded in `D:/TraceFoxBuild/ios-ci-status.json`.
Own-login, local archive and native privacy builds have passed compilation.
UI integration run 38844096749 also succeeded; its independent IPA verification
is tracked in the status file. Later cloud identity/queue/sender/adapter changes
passed host tests and await full native compilation. Device behavior, signing
and installation remain unverified. The sections below retain milestone history.
See [DEVICE-VALIDATION.md](DEVICE-VALIDATION.md) for remaining device checks.

## TraceFox login build (2026-10-16)

Run the same workflow with `enable_login=true` for validated own Telegram app
credentials from `TRACEFOX_API_ID` and `TRACEFOX_API_HASH` Actions secrets.
`TRACEFOX_SERVER` and `TRACEFOX_BOT` repository variables configure the HTTPS
origin and bot links. Missing/invalid values fail the build; placeholders are
never substituted for a requested login build. Diagnostic logs are scrubbed
before upload. The default remains the original baseline compile test.

The login build uses bundle `one.tracefox.telegram`, URL scheme `tracefox`,
and adds TraceFox bot and cloud-archive links to the native settings screen.
That verified login artifact is an initial integration, without automatic account
pairing or the later local archive/privacy patches. Native archive compilation
and staged privacy integration remain under verification. An unsigned IPA requires signing before device installation;
credentials being configured does not verify successful login on an iPhone.
The report records these capabilities and limits separately.

This repository tests whether the public DarkGram source compiles on a GitHub-hosted Mac.
The default baseline workflow uses placeholder API credentials and cannot log in.
The explicitly enabled own-login build uses encrypted Actions secrets. Actual
login, archive/privacy behavior and signing remain separate verification stages.

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

## Local archive storage work in progress

Foundation-only `ci/TraceFoxArchiveStore.swift` and a standalone macOS workflow now
cover persistent text records, negative message IDs, account-specific roots and
retention of completed media before native cache unlink. The storage layer uses
hard links with a copy fallback and limits media to 64 MiB/file and 1 GiB/root.
It is not yet wired into Telegram deletion/edit hooks or a native browser.
No secret-media decryption, automatic downloads or cloud synchronization is
provided by this storage layer. Standalone macOS tests are run independently of
the ongoing iPhone app build; see ios-ci-status.json for current results.

## Native local archive integration pending compilation

Login builds now overlay the Foundation store into TelegramCore, retain completed
local media and text immediately before `_internal_deleteMessages` removes native
records or secret cache files, and add a native settings archive browser with a
user-invoked share sheet. Duplicate deletion events reuse existing records.
Capture is limited to callers of that deletion helper: bulk history removal,
cloud TTL descriptor expiry, edits and message arrival are not covered yet.
The browser shows up to 100 records with at most 3,000 visible text characters
per row; sharing uses the full saved text and available retained files.
Private archive roots are excluded from system backup and use iOS file protection.
This code still needs full iPhone build and device verification.

## Staged temporary-media follow-up (not in queued native build yet)

Local source patches capture available media before interactive read, timer expiry
and remote descriptor invalidation, passing the account MediaBox to all three
remote-consumption callers. Native reads, timer values and media expiry still run.
An already retained read-stage file is reused when marking its record deleted;
metadata-only records can retry capture when the complete local resource appears.
Optional ttlSeconds metadata distinguishes one-view and timers while decoding
older JSON without this field. Fourteen local source/configuration tests pass.
Standalone macOS tests cover the optional-field migration separately; full Swift
integration and actual phone playback remain unverified. These changes are staged
for the next native build, avoiding repeated cancellation of queued full builds.

## Capture bridge regression checks

The separate archive workflow now compiles the actual TraceFoxLocalArchive Swift
file against small host-only Postbox/media API fixtures. It exercises metadata-only
retry after download, largest completed photo selection, one-view precedence,
retained-file disappearance and recovery, read-to-delete transition, duplicate
events, cache unlink survival and per-account isolation. Fixtures do not emulate
Telegram transport, native type compatibility, secret decryption or device UI;
those still require the full integration build and an iPhone. The native build
queue is not restarted by these standalone tests.

## Staged plain-text edit history

The native replay patch snapshots the previous plain text before `.EditMessage`
updates the Postbox row. The independent record keeps the newest text and up to
100 previous versions / 512 KiB of history, suppresses repeated adjacent versions,
and carries history through deletion and optional-schema migration. The browser
previews three prior versions and its share action includes all retained versions.
This initial edit hook excludes both captioned messages and attachment changes.
Native source integration is staged for the next full build; standalone storage
and actual bridge code are tested on macOS with explicit host API fixtures.

## Privacy preparation and latest native candidate

Pure privacy decisions and account-scoped persistent preferences now pass macOS
Swift tests. The policy covers presence rewriting, read/typing suppression and
explicitly identified secret read-service actions, while forwarding normal
messages, calls, downloads and authentication. It is not wired into transport
and no ghost toggle is exposed yet. Do not claim working ghost mode.
The tests caught an incorrect Foundation setAttributes argument label; both
preferences and the iOS archive-protection branch now use ofItemAtPath.
The queued older native candidate was superseded before execution for this
confirmed compile defect. The replacement includes accumulated timer/read hooks
and plain-text revision integration; its current run is in ios-ci-status.json.

## Staged presence and typing integration

Presence and typing call-site patches now use a runtime facade rooted in native
Network.basePath (the account root, distinct from Postbox/media). Native online
updates become offline while enabled; both ordinary and encrypted typing are
suppressed before constructing the request. The native presence refresh timer
and disabled-mode behavior are retained. Corrupt persisted settings fail closed
for privacy-sensitive decisions; missing settings default off. Sixteen local
checks pass. Full native compilation, send-time races, read receipts, secret read
services and immediate toggle-to-offline behavior remain to implement/verify.
No user-facing ghost toggle is exposed and complete ghost mode is not claimed.

## Verified own-login IPA milestone

Run 38812374391 succeeded. Its full artifact was downloaded and independently
checked for ZIP integrity, arm64 iPhone Mach-O, bundle one.tracefox.telegram,
unsigned status and the workflow SHA-256. The report confirms own-login
configuration. This artifact has bot/archive links only, not local archive or
ghost functionality. It remains unsigned and no actual iPhone login was tested.
Local artifact and checksum are recorded in ios-ci-status.json.

## Staged read-receipt privacy hooks

Read-state pushes return the local read state while ghost mode is active, leaving
server read state untouched and allowing native pending-state cleanup. Content,
mention and reaction workers complete locally so native then(transaction) cleanup
still runs without an RPC-error retry loop or a fabricated server response.
Interactive content reads retain an available temporary file before suppression;
the original read/timer mutations are skipped in that mode. Remote events from
other clients are processed normally and already-running timers are not rewound.
An already-queued secret read-service operation uses the existing encrypted noop
action with the same native queue/delivery path; no sequence slots are removed.
This can still produce encrypted network activity and is not absolute invisibility.
Direct discussion/saved-history reads, stories and send-time races remain to cover.
No complete ghost mode is exposed. Twenty-one local checks pass; actual native
compilation and physical-device behavior remain unverified.

## Additional staged story and thread receipt coverage

Prepared guards for all six direct discussion/saved-history requests in
ApplyMaxReadIndexInteractively and both paths in ReplyThreadHistory. Local
transaction updates and unread-count changes remain before suppression. The
story read worker completes locally with native operation-log cleanup intact;
pinned story view increments are suppressed separately. These updates supersede
the remaining-path list above. Twenty-four local checks pass. The patches remain
local, outside currently running archive build 38820852381; no duplicate build
was started. Native compilation, setting changes during request execution,
immediate offline transition, UI and physical-device verification remain open.

## Staged lazy network request gate

Both Network.request and requestWithAdditionalInfo recheck the account setting
inside the Signal subscription closure before constructing MTRequest. Calls in
the silent-method policy complete without a value or synthetic RPC response;
account.updateStatus keeps its native response parser and uses an offline payload.
This closes the construction-to-subscription gap, not the interval after enqueue,
transport retries or already in-flight traffic. Secret encrypted read-service
classification still depends on the dedicated service-action hook. Twenty-five
local source/behavior checks pass. Native generic/type compilation and actual
transport behavior are unverified. No privacy toggle is exposed yet; staged
changes are outside the currently running archive build.

## Staged explicit privacy control

TraceFoxPrivacyControl.setEnabled persists the per-account preference before
subscribing to an immediate account.updateStatus(offline:true) request. It returns
a lazy Signal whose disposable must be retained by the eventual settings UI.
Persistence failure prevents a network request; network failure reports a distinct
error and leaves privacy enabled. Disabling completes after persistence and lets
the normal presence manager restore status on its next update. This control is
included in the next native overlay recipe, but no UI calls it yet. Its native
compilation/network behavior is unverified; the unchanged 25 local checks pass.
Publishing utilities now accept an optional UTF-8 BOM in the status JSON, avoiding
a parser failure after Windows PowerShell writes. Current archive build remains
in progress; staged privacy changes were not dispatched as a duplicate build.

## Staged privacy screen

TraceFoxPrivacyController displays the current account preference, an apply/busy
state, distinct persistence/network errors, and an explicit retry-offline action
that does not toggle protection off. The model retains its operation disposable
and disposes it on teardown; completion/error callbacks hold the model weakly.
The screen describes limits for already sent requests and normal outgoing activity.
Its overlay is included for the next native compile but no settings navigation
opens it yet. Existing 25 local checks pass; UIKit/type compilation and UI behavior
are not covered by those checks. Running archive build remains in progress.

## Privacy syntax check passed

Standalone macOS run 38824250797 at a6e02ebd9e39b621da545d644f32e9b22e3eeaac
passed Swift frontend parsing of TraceFoxPrivacyControl and PrivacyController,
plus existing real Foundation archive/policy/runtime and adapter-fixture tests.
Parsing does not resolve Telegram/UIKit types or execute the new control/screen.
Main native build 38820852381 remains in progress; it predates these privacy files.

## Privacy control failure verification

The privacy screen now rereads persisted state on settings-write failure because
an atomic JSON replacement may succeed before permission/backup updates fail.
It no longer falsely promises that the state was unchanged.
Run 38824791820 adds executable tests of the actual TraceFoxPrivacyControl Swift
file using synchronous Signal and Telegram API fixtures. Tests cover lazy start,
persistence-before-offline ordering, retaining enabled protection after network
failure, disabling without a request and preventing requests on persistence failure.
These fixtures do not validate native scheduling, MTProto or UIKit types. The main
archive build is not restarted. Local Python checks remain 25 passing.
Run 38824791820 completed successfully, including the actual control source compiled and executed against the stated host fixtures. Native transport and device validation remain open.

## Staged text archive quota fix

The total archive quota previously gated media retention only; text-only JSON
writes could grow past it. save now checks projected size excluding the existing
record being atomically replaced. The default remains 1 GiB. A configurable small
quota permits an executable test that same-record replacement succeeds, a second
oversized aggregate write fails, and the previous record remains readable.
Standalone run 38825246926 verifies this Foundation change. The current native
archive build predates the fix; no duplicate full build was dispatched.

## Failed capture rollback

Quota regression run 38825246926 succeeded. A capture could still retain a file
and fail its JSON commit, leaving quota-consuming unreachable media. The adapter
now rolls back only the newly created filenames for that failed capture. Internal
cleanup validates paths/media names and does not receive previously committed
files. Tests confirm removal of the new hardlink while preserving the source,
existing record and rejection of traversal/non-media names. Standalone regression
run 38825746008 is dispatched; native build 38820852381 remains in progress and
predates these changes.

## Next native candidate publication guard

The publisher checks the native workflow for incomplete runs before repository or
secret mutations and refuses duplicate dispatch while a run is active. Its tests
cover completed failures and queued/running/waiting/unknown states; 27 local checks
pass. The next candidate includes accumulated privacy hooks/control/screen and
archive quota/rollback fixes. Its report distinguishes compiled privacy sources
from disabled navigation and unverified transport/device behavior. Main native
run 38820852381 is still compiling and was not restarted.

## Staged resilient archive reading

Folder-load failure is now a visible archive-browser error rather than a false
empty state. Listing skips individual malformed, oversized, unreadable or escaping
entries while retaining valid records. Both listing and direct lookup check size
before loading JSON into memory. Host regressions add malformed/oversized files
and a symlink escape alongside a valid record. Standalone run 38827233109 also
parses the changed archive controller; parsing does not resolve UIKit types.

## Artifact state accuracy and strict pairing inputs

The artifact downloader now uses an unconditional checksum/login validation
exception rather than Python assert, accepts status JSON with an optional BOM,
and updates current-run compile flags only from the downloaded verification report.
Device and signing flags remain false. Bot-link tests add trailing-newline nonce
and token rejection with exact UTF-8 length guards; standalone run 38828722166.
Local 27 checks pass. Main native build 38820852381 remains in progress.

## Archive native compilation milestone and privacy candidate

Native run 38820852381 succeeded. Downloaded IPA independently passed structure,
arm64/iPhone identity, unsigned-status and SHA-256 checks:
cbca1e93981378859c3b16bacb43b1b6abad72077db99f97f6442b228ee0640c.
It includes local archive browser, deletion/read/timer hooks and plain-text edit
history. Device behavior is unverified; it predates quota/rollback/read resilience
fixes and privacy integration. The verified artifact is recorded separately in
status so a later in-progress candidate does not erase that milestone.
Next native run 38829268739, recipe 64fbe8ff16eca998694c96c966149c6e4fb8096c,
contains accumulated privacy sources and archive fixes. Privacy navigation remains
disabled pending native validation. Standalone strict bot-link tests 38828722166
also succeeded. Signing and physical-device acceptance remain required.

## Native privacy compile failure fixed

Run 38829268739 failed in ManagedSecretChatOutgoingOperations: noop requires
SecretChatSequenceBasedLayer, while queued reads supply SecretChatLayer. The
patch now converts compatible rawValue cases explicitly; legacy layer8 uses a
native read-service payload with an empty ID vector, preserving queue processing
without disclosing actual read message IDs. Protocol behavior still needs device
verification. Sanitized diagnostics are saved in ios-ci-runs/38829268739.
The corrected candidate was dispatched at ed6d6f205e6fe05a3e38f72121a0e58237757c50.
Host run 38830649430 passed, including URLSession claim-client tests through local
URLProtocol fixtures. HTTP redirects are rejected; cookies/cache are disabled.
This performs no live pairing. Native HTTP/Keychain integration and UI remain open.

## Privacy native compilation passed; UI integration candidate

Run 38830755770 succeeded. Its IPA was independently verified with SHA-256
53c6808d4c211e7670cde88f15bf5733332292d34de0a22f342b9eb6a43aea11.
This confirms compilation of native privacy hooks/control and the original hidden
privacy screen, not real-account privacy behavior. It predates later bot pairing
and account lifecycle UI updates. Signing/device verification remains absent.
Run 38844096749 at e598e8dde970e141d7d19e310c77efaf68f8ab04 now compiles
settings navigation for privacy and manual bot pairing, plus Keychain, status,
logout and current-account guards. This is a changed candidate, not a duplicate.
Standalone run 38834408132 passed syntax/host checks for the prior account-aware
privacy screen. Final navigation and reset changes await full native validation.

## Native settings integration milestone

Run 38844096749 succeeded and its unsigned IPA independently verified with SHA-256
6bb62e8e629a5c4c2b5d86e2caf2119e5891ea4a429a7fff4918aafce4c59301.
It includes settings navigation for privacy and manual bot pairing, record-scoped
Keychain and account lifecycle integration. Device behavior remains unverified.
The milestone is preserved separately in status while the next candidate runs.
Recipe 5fd41fab25bf5f62f1618271ff6defa0ec4c6248 compiles accumulated cloud
identity/payload/queue/sender/adapter components and validation fixes; automatic
cloud sync is still not wired/enabled. Host adapter run 38849172907 succeeded.

## Staged archive pagination

Archive records now accept a before cursor using timestamp plus stable record key,
so identical timestamps cannot cause skipped/duplicate page boundaries. The UI
appends pages of 100 off the main queue, preserves existing records on load error,
and guards repeated load-more requests. Host run 38850909511 checks 205 equal-time
records across three pages with no duplicate IDs and parses the changed UI.
This still scans JSON metadata rather than using a database index; large-archive
performance and UIKit/native integration remain unverified. It is staged after
the active native build and is not part of the previously verified IPA.

2026-10-16: Standalone Swift checks passed in run 38852169320 (recipe 4fa960a). Explicit cloud export now reports the remaining durable queue count on its worker queue. Native run 38849586897 is still active and predates this UI refinement; physical-device behavior remains unverified.

2026-10-16: Archive UI now labels deleted/edited records and distinguishes a next-page load failure from an initial archive failure. Local regression suite: 28 passed. Swift checks dispatched at recipe 05995f9; native compilation and device verification pending.

2026-10-16: Swift run 38852968713 passed for archive state labels and pagination failure text. Added backlog-count regressions for adjacent duplicate coalescing, cross-instance acknowledgement visibility and corrupt-queue errors; verification dispatched separately without restarting active native compilation.

2026-10-16: Queue backlog regressions passed in macOS Swift run 38853381950: adjacent duplicate count, persisted acknowledgement visibility across instances and corrupt queue count failure. Native build 38849586897 remains in its compile step; no duplicate native build dispatched.

2026-10-16: The native publisher now records a per-file SHA-256 manifest for the exact uploaded candidate in ios-ci-status.json. This distinguishes later local edits from the source actually compiled by each run. Publisher regression suite: 28 passed; manifest becomes available on the next authorized dispatch after active compilation finishes.

2026-10-16 candidate boundary audit: exact Git blob hashes against active recipe 5fd41fa identify six changed/added build inputs: tracefox_configuration.py, TraceFoxArchiveCloudAction.swift, TraceFoxArchiveController.swift, TraceFoxArchiveStore.swift, TraceFoxCloudArchiveBridge.swift and TraceFoxCloudArchiveQueue.swift. These comprise manual text export UI, archive pagination, saved-record conversion and queue display refinements. A successful active run must not be reported as compiling these later local versions. The exact list is stored under pending_candidate_diff_from_run in ios-ci-status.json.

2026-10-16: Authorization-failure/re-pair sender regression passed in run 38855559700. Archive paging now retains at most the requested page (maximum 100 decoded records), instead of accumulating every decoded archive record before sorting. The scan still reads directory entries and each eligible JSON; device latency for large archives is unverified. Existing 205 equal-timestamp pagination regression is dispatched against this implementation.

2026-10-16: Bounded-memory archive page selection passed Swift run 38855996883, including 205 same-timestamp records paged 100/100/5 with no duplicates. This verifies host behavior, not iPhone memory profiling or native UI performance. Current native run 38849586897 predates the optimization.

2026-10-16: Prepared an explicit archive refresh action. Refresh loads the newest first page off the UI thread, shares a loading guard with pagination, and preserves already displayed rows on failure. Initial load failure can now be retried on the same screen. Swift syntax validation dispatched; native/UI device validation pending.

2026-10-16: Native run 38849586897 succeeded; downloaded unsigned IPA independently verified (bundle one.tracefox.telegram, 75564079 bytes, SHA-256 5e5c3c87ea93825727bae35d0160c0d926ec24c08b514fea13b865a403ac07a2). Cloud identity/payload/queue/sender/native Message adapter compile. Later manual export UI, archived-record adapter and pagination are excluded. Swift refresh syntax run 38856866514 also passed. Next candidate includes these accumulated changes; device/signing/live login remain unverified.

2026-10-16: Candidate 7ebb365 / native run 38857408262 exact-source audit passed: all 34 manifest files match both local SHA-256 and published Git blob hashes. Pending-source history was cleared after dispatch; current candidate scope is recorded separately from verified prior builds. Native compilation remains in progress.

2026-10-16: Fixed missing TTL metadata when the first archived event is a plain-text edit. The native bridge now shares lifetime extraction between capture and edit; saveTextEdit accepts optional TTL while preserving legacy callers and stored metadata. Added timed-edit host regression. Corrected the new fixture call to its unlabeled initializer before republishing tests. Active native run 38857408262 predates this change.

2026-10-16: Timed first-edit regression passed in macOS Swift run 38858248667. Native lifetime extraction preserves timer metadata before deletion, including existing archive callers; active candidate 38857408262 predates the fix. Current timer acceptance is a host-fixture result, not secret-chat transport or iPhone validation.

2026-10-16: saveTextEdit now preserves previously retained file references instead of replacing files with an empty list. This avoids orphaning original archive media when a later supported text edit is captured. Regression checks file bytes, deletion state and one-view TTL after text update; this does not add attachment/caption revision tracking. Active native run predates this change.

2026-10-16: User-requested in-app update screen prepared and wired in settings. Manual public GitHub latest-release check compares numeric ios-build-N with installed CFBundleVersion and opens the exact repository's release page only when a newer IPA release exists. UI syntax and release-validation tests passed in run 38860034998. No automatic installation; no release was published by this change. Native compilation and iPhone update installation pending; see UPDATES.md.


Android parity port: 29 local regressions passed; macOS Swift run 38900556630 passed category filters/pagination, acknowledgement ledger and media upload URLProtocol tests. Native automatic worker/API integration still requires the next native build. Earlier manual-export candidate 38857408262 unsigned IPA independently verified, SHA-256 f640b443a1ed7ca1645b9f13029225ca6605b5c2c1f18ea324469f8f55d9a67f; does not include these automatic/category changes. See ANDROID-PARITY.md for scope and remaining device/backend gates.
