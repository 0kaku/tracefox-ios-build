Automatic-parity candidate: confirm bot linkage after first login without opening settings or sending a command manually, restore token after relaunch, verify cloud metadata/file upload without a switch, expire a token and verify automatic re-pair, and switch/logout during pending work. Compare the three local category tabs to deleted media, view-once media and secret chat fixtures. Earlier manual pairing/export checklist entries are historical and superseded for this candidate.

# TraceFox iPhone acceptance record

No physical-device checks below have passed yet. An unsigned IPA and host-fixture
tests do not establish device readiness. Do not put Apple/Telegram credentials,
session exports, private message contents or signing keys in this document.

## Verified artifact facts

Login-only run: 38812374391. Bundle: `one.tracefox.telegram`. Its actual Info.plist
declares minimum iOS 13.0, arm64, device families iPhone/iPad, version 12.4 (9).
These declarations do not prove compatibility on any particular OS/device.
Its independent SHA-256 is recorded in ios-ci-status.json. It contains own API
configuration and bot links, without the later archive and privacy changes.

## Installation prerequisite

Windows installation research (official sources checked 2026-10-16):
[AltStore Classic Windows instructions](https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows)
provide an AltServer path requiring a connected/unlocked trusted iPhone and user
Apple ID interaction. They specify Apple iTunes/iCloud prerequisites and include
an alternate path for Windows Store iCloud. No installers have been run here.
[Apple developer account overview](https://developer.apple.com/help/account/basics/about-your-developer-account)
documents that Personal Team device provisioning profiles expire after seven days.
This route has not been tested with TraceFox signing/entitlements and is not yet
a verified installation method. No iPhone/iPad/Apple Mobile device was detected by
the Windows present-device inventory during this check; that does not establish
whether the user owns a phone or has working drivers. The existing question about
their chosen installation method remains pending.

The user's available iPhone and signing/installation method are still unknown;
the question is already pending in the conversation. Do not request credentials
or attempt Apple/Telegram login without user participation. After a method is
chosen, record device OS, signing method, artifact run/hash, install result and
launch result. Never describe an unsigned download as an installable release.

## Account and integration checks

Use a user-controlled test account and a second test client. Verify login and
relaunch, account switching, opening the configured bot and opening its archive.
Bot links alone do not prove pairing or cloud synchronization. Verify account
isolation for settings and archives and behavior after logout.

## Archive checks

Verify ordinary text deletion, successive text edits and deletion after an edit.
For a timed plain-text message with no prior local archive entry, edit it before
reading or deleting it. Confirm the first saved edit already displays its timer,
then edit again, delete and restart: the latest text, prior versions and timer
must remain together. This specifically covers the host-verified first-edit TTL
fix, which is absent from native candidate 38857408262.

For media, first fully download a test image/video, trigger each applicable read,
expiry and remote-deletion path, then open the retained copy after restarting.
Repeat in cloud and secret test chats and with one-view/timed test media.
An unavailable or incomplete original must not be reported as successfully saved.
Check filename/playback, iPad share presentation, size-limit behavior and failure
without damaged existing records. Do not claim expired server media recovery.

## Explicit cloud export checks

After a candidate containing the manual export UI compiles, pair a user-controlled
account manually. Export a plain text record and confirm server acknowledgement,
queue count reduction and the matching row in that owner's archive. Repeat an
edited and deleted record and verify text, event and TTL metadata. This path sends
no media files and excludes secret/local records.

With two queued records, select the later record: the oldest event must be sent
first and the UI must say that the selected copy remains pending. Use the explicit
next-event action to drain it. Disconnect the network, retry, restart the app and
confirm unacknowledged entries persist. Switch accounts or close the screen during
a request; stale completion must not change the newly active account's UI or queue.
Server receipt before a lost acknowledgement can lead to an at-least-once retry.
Check expired/revoked credentials and denied access without losing queued events.

Create more than 100 local archive records, including equal timestamps. Load every
page and verify each record appears once, with earlier loaded rows retained after
a page-load failure. Large-archive scan performance still requires device testing.
## Privacy checks

After native compilation and navigation are enabled, verify default-off and
account-specific persistence. Observe online status, typing, normal/secret read
receipts, thread/saved-history receipts, mentions/reactions and story views from
the second client. Verify normal outgoing messages and secret-chat sequencing.
Test enable/disable, rapid taps, network loss, offline-update retry, relaunch and
account switching. Already transmitted activity cannot be recalled. Host fixtures
do not establish MTProto behavior, timing, cancellation or retry behavior.

## Release gate

Record pass/fail with artifact run/hash for each required behavior, distinguish
unsupported features and unresolved failures, and verify the selected signing and
installation path on a physical iPhone. Keep the automation active until the
agreed client functionality and device path are verified or need user action.
