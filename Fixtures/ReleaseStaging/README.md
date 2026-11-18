# Signed staging feed fixture

Generated on 2026-11-17 by the pinned Sparkle 2.10.1 sign_update tool from a real
`staging-smoke.sh` 1.4.1 DMG, using a disposable identity. Only the public key and
signed appcast are retained here. The private key and Keychain entry were removed.

This fixture tests feed-signature verification and Pages byte transport. Its archive
URL is loopback-only; it cannot install an update from the public Pages site. The
large DMG is deliberately excluded. Full archive, mounted-bundle and engine validation
belong to staging-smoke.sh and the independent Actions artifact-consumer job.
