#!/bin/bash
# Disposable identity only. This never reads release-signing secrets or deploys Pages.
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.."
destination="${1:?Specify a new staging output directory}"
[[ "$destination" == /* ]] || destination="$PWD/$destination"
[[ ! -e "$destination" ]] || { echo 'Output already exists' >&2; exit 1; }
umask 077
work=$(mktemp -d)
account="bettervmaf-staging-smoke-$(uuidgen)"
cleanup() {
    security delete-generic-password -s https://sparkle-project.org -a "$account" >/dev/null 2>&1 || true
    rm -rf -- "$work"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
scripts/release/sparkle-tools.sh "$work/tools"
export SPARKLE_TOOLS_DIR="$work/tools/bin"
"$SPARKLE_TOOLS_DIR/generate_keys" --account "$account"
"$SPARKLE_TOOLS_DIR/generate_keys" --account "$account" -x "$work/private.key"
export SPARKLE_PRIVATE_KEY
SPARKLE_PRIVATE_KEY=$(cat "$work/private.key")
# Mask before any child workflow could log the disposable key.
if [[ "${GITHUB_ACTIONS:-}" == true ]]; then printf '::add-mask::%s\n' "$SPARKLE_PRIVATE_KEY"; fi
export SPARKLE_PUBLIC_KEY
SPARKLE_PUBLIC_KEY=$("$SPARKLE_TOOLS_DIR/generate_keys" --account "$account" -p)
export SPARKLE_FEED_URL=http://localhost:18742/appcast.xml
mkdir -p "$destination"
printf '%s\n' "$SPARKLE_PUBLIC_KEY" > "$destination/staging-public-key.txt"
export RELEASE_DERIVED_DATA="${RELEASE_DERIVED_DATA:-$work/DerivedData}"
scripts/release/package.sh staging "$destination/old" 1.4.0
scripts/release/package.sh staging "$destination/new" 1.4.1
unset SPARKLE_PRIVATE_KEY
"$SPARKLE_TOOLS_DIR/sign_update" --ed-key-file "$work/private.key" --verify "$destination/new/appcast.xml"
python3 scripts/release/staging-negative-tests.py "$destination/new"
echo "Staging pair and real signature rejection tests passed: $destination"
