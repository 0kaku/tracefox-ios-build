# Native bot/archive integration audit

The current verified IPA opens bot/cloud-archive links only. Local iOS archive
records are not uploaded automatically. This audit reads the existing backend
contract in D:/TheMurconBot/app/android_bridge.py without modifying Android or
pairing/revoking any device.

## Existing backend contract

POST /api/android/link accepts a 64-character lowercase hex nonce. The bot must
first approve that nonce for its authenticated owner; polling returns ready:false
until approval. A ready response contains owner_id, a device bearer token and
archive_available. GET /api/android/status validates that token and reports owner,
expiry and archive access. Store any future native token in account-scoped Keychain
storage, never UserDefaults, logs or the local message archive. Verify owner_id
matches the logged-in Telegram account before accepting it.

POST /api/android/device is a different web-authenticated path that revokes the
owner's existing devices before issuing one token. It is unsuitable for silent
iPhone pairing while preserving Android. Do not call that path for native pairing.

## ID mapping requirement

AndroidMessage requires a positive message_id and a chat_id within its declared
range; its chat types do not include secret chats. Native iOS MessageId includes
peer namespace, message namespace and signed message ID. The local archive stores
these fields separately. Passing its packed peer Int64 or negative local message
ID directly to the backend is not a valid mapping and risks collisions/rejection.

Implement and test a mapping for supported cloud peer/message namespaces before
upload integration. Local/outgoing placeholders must wait for a stable cloud ID.
Android already maps secret records through a reserved synthetic chat-ID range
and positive message IDs before using the ordinary backend route. This was found
in TraceFoxArchiveIdentity.java after the initial backend-only audit. iOS has not
implemented or verified that mapping. Retain local behavior until cross-client
identity compatibility and the explicit secret-media upload flow are validated.

## Remaining implementation

Native user-initiated pairing, nonce lifecycle, owner verification, Keychain
storage, authenticated status/archive reads, expiration/revocation handling and
upload mapping are unimplemented. Validate these with API fixtures and test
accounts before claiming cloud integration. Bot links alone establish none of
these properties. No live pairing or messages were sent during this audit.

Pure native protocol preparation: TraceFoxBotLinkProtocol constructs the claim
endpoint/body and validates pending/ready responses, response size, exact token
shape and owner equality. It performs no network requests or token persistence.
Host run 38828251919 tests the initial validator; exact UTF-8 length checks were
added locally afterward and remain pending host verification. Real nonce generation,
Keychain, HTTP lifecycle and user-facing bot pairing remain unimplemented.

Keychain storage preparation: TraceFoxBotCredentialStore uses app-scoped generic
password items keyed by Telegram owner ID, synchronizable=false and
AfterFirstUnlockThisDeviceOnly accessibility. It validates ownership/token shape
on both save and read, distinguishes missing items from Keychain errors and can
remove only the specified account item. No live pairing is connected. Standalone
macOS run 38829694018 creates/updates/reads/removes synthetic credentials under a
unique CI service, leaving other Keychain items untouched. iPhone accessibility,
logout cleanup and actual app signing entitlements remain to verify. This source
postdates native candidate 38829268739 and is staged for a later build.
Run 38829694018 passed, including real macOS Keychain operations with the stated synthetic scope. This does not verify iOS signed-app access or live pairing.

Pairing-attempt preparation: TraceFoxBotPairingAttempt creates 32 random bytes via
SecRandomCopyBytes, binds approval/claim validation to one Telegram owner and
rejects use at/after its ten-minute local expiry. The existing backend approval
command is constructed only; no send operation is implemented or invoked. Tests
check nonce shape/distinct attempts, owner mismatch, pending state and expiry in
standalone run 38830159330. App lifecycle, user-facing approval, HTTP and iPhone
execution remain unimplemented/unverified. This source is staged after the active
native candidate and does not trigger a duplicate full build.

Coordinator preparation: explicit begin/cancel controls one account-bound attempt;
only one poll can run at a time. A generation check under a lock rejects callbacks
from cancelled/superseded attempts before Keychain writes. Valid credentials are
saved under the attempt owner; save failures propagate to the caller. Caller UI
must cancel on logout/account switch and own its polling/cancel presentation.
Run 38831144885 tests cancel-before-poll and synthetic URLProtocol claim through
real macOS Keychain persistence. Delayed callback races and iPhone UI lifecycle
still require additional tests. Sources postdate the running native candidate.

Delayed-response regression: the claim transport now has a cancellable interface
implemented by URLSessionDataTask. Tests can deliberately deliver a superseded
account's callback after beginning another owner attempt, verify no stale Keychain
write or UI completion, reject a duplicate in-flight poll and accept the new owner
response. Standalone run 38831585871 covers this deterministic ordering with
synthetic accounts/Keychain namespace. Native UI must still call cancel at its
actual account-switch/logout boundaries; that wiring remains pending.

Staged native screen: the current account can explicitly create a code, copy its
approval command to a local-only expiring pasteboard, open the bot, manually send
it, then manually check confirmation. No automatic bot message is sent. Success
comes from the owner-validated HTTP/Keychain coordinator; stored credentials are
not presented as server-verified or as archive synchronization. Local disconnect
removes only this owner's local item. Screen disappearance cancels the attempt.
Native type compilation and actual app-switch/account-switch/logout lifecycle
remain unverified. Settings navigation is still disabled. Run 38832117693 parses
the new UI source and reruns existing host behavior tests, without emulating UIKit.

Staged logout/account lifecycle: the authorized native cleanup path removes the
owner's local bot token before its Telegram logout RPC. Removal is best-effort and
does not block Telegram logout on a Keychain error. The pairing screen observes
activeAccountsWithInfo, cancels/suspends when its account is no longer primary,
and removes a local token if an account previously observed present is removed.
It does not delete a token merely because an initial account snapshot is absent.
The unauthorized cleanup path has no owner ID; remote logout while no pairing
screen exists remains a case to resolve/verify. Native type checking, observation
timing and actual logout behavior are still unverified; no device claim is made.

Record-scoped Keychain update supersedes the owner-only native UI layout above.
The native UI supplies AccountRecordId.int64; each record keeps a separate item
while read/write still validates the Telegram owner. Logout can now remove an
item by record ID inside its transaction even when already logged out remotely.
The account cleanup entry also removes the record item before authorization is
resolved. Both removals are best-effort and never block Telegram logout. Tests
store two records for the same synthetic owner and verify removing one preserves
the other. Host run 38833078610; native hook/type/device behavior remains pending.
No released iPhone pairing existed before this staged key layout change.

Authenticated status preparation: the HTTP client can GET /api/android/status
with the stored bearer token using the same redirect-rejecting, cookieless,
uncached session. A successful response must be bounded JSON, connected=true,
the exact expected owner and a future expires_at timestamp. Host run 38833521284
checks valid/foreign-owner/expired responses with URLProtocol fixtures; no real
server request is issued. The native status UI action remains to connect.
Record-isolation Keychain tests in prior run 38833078610 passed.

Status screen action prepared: explicit status check reads the record-scoped token,
shows verified server expiry/archive entitlement, clears a token on HTTP 401 and
preserves it on transient/other errors. Status tasks are cancelled on disappearance
and account changes. Both status and claim UI delivery check a local generation
before changing state. Host run 38833946187 parses the status UI addition and
reruns underlying HTTP/Keychain tests; the final claim UI generation guard was
added locally afterward and is pending syntax/native validation. UIKit behavior
and real server interaction remain unverified; navigation is still disabled.

Cloud identity preparation: TraceFoxCloudArchiveIdentity accepts unpacked peer
namespace/ID and a positive cloud message ID. User/group/channel mapping matches
Android archiveDialog, including the channel offset. Secret, local, scheduled and
out-of-range components are rejected. Host run 38844565949 validates these rules;
no upload queue or network submission is enabled. The earlier backend-only claim
that secret mapping did not exist is corrected: Android uses a reserved synthetic
mapping, which remains unimplemented/unverified for iOS.

Secret message identity audit: Android SecretChatHelper assigns native message IDs
with getNewMessageId(), while iOS secret replay uses its local tagLocalIndex in
MessageId and preserves decrypted randomId separately as globallyUniqueId. Thus
abs(nativeId) is not a cross-client identity even if secret chat IDs agree. The
local iOS record now retains optional globallyUniqueId through capture/deletion
and text history; older JSON decodes with nil. Host tests exercise a signed 64-bit
value through retained media and deletion. This is local metadata only; the
backend's positive/53-bit message_id field cannot blindly receive randomId.
Secret cloud sync requires a separate stable identity contract before enabling.

Coordinator reentrancy fix: invoking claim while holding its lock could deadlock
with an inline-completing transport. It now reserves a unique poll ID, releases
the lock before invoking transport, and attaches/cancels the returned task only
if that poll is still current. Completion and synchronous throws clear only their
own reservation. Repeated callbacks cannot overwrite an already committed token.
Host run 38845337525 adds inline completion, throw recovery and duplicate callback
regressions. The actual URLSession transport is asynchronous, but the coordinator
interface now handles both completion timings. Native integration remains pending.

Cloud payload preparation: the explicit Encodable payload mirrors AndroidMessage
fields for message/edited/deleted events, chat type, title/text/date and optional
TTL. Unicode limits use scalar counts to match Python string lengths rather than
Swift grapheme counts; oversized content fails instead of silent truncation.
Host tests encode a channel deletion/one-view timer and reject oversized combining
Unicode text, invalid date and negative TTL. No queue or upload operation exists
yet. Backend behavior and native ID extraction still need integration validation.

Actual Swift-to-backend contract check: run 38846150467 exported three synthetic
JSON payloads from JSONEncoder. Downloaded fixtures were validated locally by the
real app.android_bridge.AndroidMessage Pydantic model, including one-view TTL,
deleted event and 16000 Unicode scalar values. All three passed without database
or server mutations. Fixture path: ios-ci-runs/38846150467/cloud-payload-fixtures.json.
This proves payload schema compatibility, not authenticated upload or sync.

Explicit event submit preparation: the HTTP client can POST one validated cloud
payload to /api/android/messages with the account bearer token. Only HTTP 200,
ok=true and a positive archive_id acknowledge success; denied/malformed responses
fail. Redirect rejection/cookie/cache policy is shared with pairing. URLProtocol
fixtures verify headers, valid/invalid acknowledgements and HTTP 403. No UI/action
or automatic queue calls this API yet; no live content was submitted.

Durable queue preparation: an explicitly account-specific root stores an atomic
bounded FIFO (1000 entries/32 MiB defaults), excluded from backup and protected
until first unlock on iOS. Only the head UUID can be acknowledged. Identical
adjacent pending events coalesce; a -> b -> a remains distinct. Corruption errors
propagate rather than resetting pending events. Host run 38847021506 checks
reopen, ordering, quota and account-root isolation. Capture/drainer wiring remains
absent; the queue currently requires a single coordinated instance per root.
No automatic synchronization or live data submission is enabled.

Queue concurrency update supersedes the single-instance requirement above:
read/modify/write transactions now share a process-wide lock across queue objects.
Run 38847387598 concurrently appends 30 distinct events through two instances
sharing one root, then acknowledges them through the other instance and checks
all payloads survived. This is in-process coordination, not cross-process locking;
no extension/background upload worker has been enabled.

Queue sender preparation: an owner-bound explicit one-event worker submits only
the current FIFO head and acknowledges it only after a positive server archive ID.
Network errors, invalid acknowledgements, cancellation and stale/duplicate
callbacks cannot drop pending events. Credentials for another owner are rejected.
Host run 38847892532 exercises these outcomes with a controlled fake submitter.
Retries are at-least-once, not exactly-once: a server commit with a lost response
can be resent. Cross-device edit conflicts still need a separate server policy.
No capture hooks, automatic scheduling or sync UI starts the sender yet.

Persisted payload validation: synthesized Codable decoding bypasses the validating
public initializer. The queue now revalidates entries on enqueue/read and HTTP
submit validates again, reconstructing a supported cloud identity and checking
text/title/date/TTL/temporary invariants. A test mutates a valid persisted event
to message_id=0 and confirms it is rejected without silently clearing the queue.
The format remains local staged code; native compilation and sync wiring pending.

Native message adapter preparation: TraceFoxCloudArchiveBridge reads Message.id
peer namespace and raw peer ID separately, filters unsupported secret/local IDs,
Telegram service peer 777000 and pairing commands, then builds a validated cloud
payload with one-view TTL priority. It does not enqueue or send anything. Host
run 38849172907 compiles the actual adapter with Postbox/media API fixtures whose
packed/unpacked IDs deliberately differ. Existing archive bridge regressions also
run after extending fixtures with message ID components. Native compatibility and
real capture/opt-in wiring remain pending. Prior persisted-validation tests passed.
