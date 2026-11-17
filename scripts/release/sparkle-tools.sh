#!/bin/bash
set -euo pipefail
destination="${1:?Specify a new directory for the Sparkle tools}"
version=2.10.1
sha256=1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27
archive=$(mktemp)
trap 'rm -f -- "$archive"' EXIT

curl --fail --silent --show-error --location --retry 3 \
    "https://github.com/sparkle-project/Sparkle/releases/download/$version/Sparkle-$version.tar.xz" \
    -o "$archive"
printf '%s  %s\n' "$sha256" "$archive" | shasum -a 256 -c -
mkdir -- "$destination"
tar -xJf "$archive" -C "$destination" bin/sign_update bin/generate_keys
