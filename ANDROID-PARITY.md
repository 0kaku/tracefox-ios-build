# Android behavior port to iPhone

This candidate supersedes the earlier manual pairing/manual text export UI.

| Requested behavior | iOS implementation | Validation still needed |
| --- | --- | --- |
| Deleted media / view-once / secret chat tabs | Native ItemList textWithTabs, category predicate before page selection; missing retained files excluded from media tabs | Native compile and iPhone layout |
| Automatic bot connection after login | Authorized main-app AccountContext owns worker; native bot resolve/enqueue of authentication nonce, validated claim to account-record Keychain | Real Telegram delivery and signed-device lifecycle |
| Backups without switch | Account-root archive is durable outbox; scan pages, authenticated metadata POST and first completed file PUT; acknowledgement ledger written only after both succeed | Native compile, network/offline/device behavior |
| Existing credentials/offline/logout | Status checks, 401 re-pair, transient backoff; logout stops worker before Keychain removal; weak registry prevents duplicate workers | Native scheduler and late-callback device checks |
| Lifetime TraceFox Premium | Shared server policy grants authenticated client link owners lifetime, upgrades existing linked clients on next valid request | Backend source tested (269 tests); live restart previously blocked by automatic approval |
| Updates | Manual latest-release check and verified repo release-page link, no silent iOS install | Native compile and signing-dependent device installation |

Secret chats remain local. Their iOS message identity is not yet mapped to the Android cloud archive contract. Captions/media revision tracking and initial cloud upload of every historical text version are not implemented. Media upload currently sends the first retained file for a cloud record; multi-attachment history is not claimed. The local archive retains all available captured files.

iOS can suspend app execution. Work resumes when the account context starts again; there is no claim of unrestricted background execution. The ledger persists per-account acknowledgements, including text, deletion and file-reference fingerprints, with atomic protected writes. Failure or cancellation does not delete local records. A lost server reply can cause at-least-once retry. Before initial credentials are saved, relaunch can create another authenticated nonce command; temporary network retries within one process reuse the attempt.

No new device login, Apple login, purchases or automation activation was performed by this port. Runtime tests use synthetic fixtures. Do not call the candidate ready until native compilation, signing and physical iPhone checks pass.
