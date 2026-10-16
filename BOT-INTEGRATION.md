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
Secret-chat records have no supported backend mapping in the current contract;
retain local behavior and do not silently export them through a cloud-only route.
Any future secret-chat upload capability needs an explicit product flow and a
distinct identity/schema that preserves isolation and deduplication.

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
