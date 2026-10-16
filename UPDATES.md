# TraceFox iOS update checks

The settings screen performs an explicit public GitHub latest-release check. No Telegram session, bot credential or account identifier is sent. No background polling or automatic installation is enabled.

A supported release in 0kaku/tracefox-ios-build must be published (not draft/prerelease), tagged ios-build-N where N is the positive decimal CFBundleVersion from the verified IPA, and contain an IPA asset. The release page must belong to this exact repository and tag. The client only offers its release page when N exceeds the installed CFBundleVersion. Release maintainers must use increasing build numbers; do not infer readiness from artifact existence or publish an unverified build as device-ready.

Before publishing: independently verify the artifact, document SHA-256, signing and installation requirements, supported iOS/device checks and material limitations in the release notes. An Actions artifact is not a release; 404 is displayed as no published version. The download button opens the GitHub release page so the user can read these details. Installation requires the signing method used for that iPhone; no silent replacement is implemented.

Tests use synthetic release JSON only. Native UI compilation, real release discovery and signed-device update installation remain separate acceptance gates. Test newer/equal/older builds, invalid links, missing IPA, draft/prerelease, network failure, GitHub rate limiting, cancellation and leaving/reopening the screen.
