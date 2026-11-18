#!/bin/bash
# Pinned actionlint; lint workflow structure and expressions before expensive builds.
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.."
case "$(uname -m)" in
    arm64) architecture=arm64; sha256=aba9ced2dee8d27fecca3dc7feb1a7f9a52caefa1eb46f3271ea66b6e0e6953f ;;
    x86_64) architecture=amd64; sha256=5b44c3bc2255115c9b69e30efc0fecdf498fdb63c5d58e17084fd5f16324c644 ;;
    *) echo 'Unsupported actionlint host architecture' >&2; exit 1 ;;
esac
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
curl --fail --silent --show-error --location --retry 3 \
    "https://github.com/rhysd/actionlint/releases/download/v1.7.12/actionlint_1.7.12_darwin_$architecture.tar.gz" -o "$work/actionlint.tar.gz"
printf '%s  %s\n' "$sha256" "$work/actionlint.tar.gz" | shasum -a 256 -c -
tar -xzf "$work/actionlint.tar.gz" -C "$work" actionlint
# Shell syntax is checked separately; do not depend on a runner's shellcheck install.
"$work/actionlint" -shellcheck=
