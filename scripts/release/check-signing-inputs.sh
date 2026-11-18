#!/bin/bash
# Source this file: keep secrets as shell variables, outside subprocess environments.
set -euo pipefail
for name in SPARKLE_PRIVATE_KEY APPLE_CERTIFICATE_P12 APPLE_CERTIFICATE_PASSWORD \
    APPLE_NOTARY_KEY APPLE_NOTARY_KEY_ID APPLE_NOTARY_ISSUER_ID; do
    export -n "$name"
done
check_signing_inputs() {
    local missing=0 name
    for name in SPARKLE_PUBLIC_KEY SPARKLE_PRIVATE_KEY APPLE_TEAM_ID APPLE_CERTIFICATE_P12 \
        APPLE_CERTIFICATE_PASSWORD APPLE_NOTARY_KEY APPLE_NOTARY_KEY_ID APPLE_NOTARY_ISSUER_ID; do
        if [[ -z "${!name:-}" ]]; then
            echo "Missing production signing setting: $name" >&2
            missing=1
        fi
    done
    [[ "$missing" == 0 ]] || return 1
    [[ "$APPLE_TEAM_ID" =~ ^[A-Z0-9]{10}$ ]] || { echo 'Invalid Apple Team ID' >&2; return 1; }
    export APPLE_TEAM_ID
}
