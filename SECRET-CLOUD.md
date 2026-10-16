# Secret-chat cloud copies (2026-10-16)

The iOS automatic worker submits retained secret-chat text and the first retained completed file through authenticated `/api/client/secret/messages` and `/api/client/secret/media`.

This is a readable archive on the TraceFox server, not Telegram secret-chat synchronization or an end-to-end encrypted cloud backup. Session keys and secret-chat encryption keys are never serialized or uploaded. Only already captured local copies can be sent; unavailable media cannot be recovered. iOS foreground/resume scheduling applies.

Identity: native secret peer namespace 3, message namespace 1, positive Int32 secret-chat ID and nonzero signed Int64 globallyUniqueId. The random ID is encoded as a canonical decimal string to preserve every bit. Missing stable IDs remain local. Backend maps `(owner, secret_chat_id, random_id)` to a durable surrogate in the range above 2^52, separate from Android legacy Int32 IDs, and uses synthetic chat ID `-(2000000000000 + secret_chat_id)`. Legacy Android secret records are not merged by guessed local numbers.

Server routes enforce device credentials and Premium owner access, metadata before media, max 64 MiB/file, idempotent reupload, deletion and TTL preservation. New DB table `client_secret_message_identities` is created by normal startup schema initialization. Existing live server has NOT been restarted; earlier automatic approval rejected restarting it, so deployment remains pending.

Validation: backend ASGI tests cover owner isolation, duplicate metadata/media, invalid/extreme Int64 values, TTL and deletion. Swift workflow covers native bridge fixtures, exact Int64 JSON and fake-HTTP upload routing. Native compilation and physical iPhone login/upload remain separate checks. Do not call the feature deployed or device-tested on the basis of host tests.
