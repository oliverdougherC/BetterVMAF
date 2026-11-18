#!/bin/bash
# Run interactively on the trusted maintainer Mac. Never run prepare in Actions.
set -euo pipefail
set +x
umask 077
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.."
mode="${1:?Use prepare <account> <encrypted-backup> or recover-test <backup> <public-key-file>}"
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
if [[ -n "${SPARKLE_TOOLS_DIR:-}" ]]; then
    tools="$SPARKLE_TOOLS_DIR"
else
    scripts/release/sparkle-tools.sh "$work/tools"
    tools="$work/tools/bin"
fi
verify_recovered() {
    printf 'BetterVMAF offline key recovery test\n' > "$work/challenge"
    signature=$("$tools/sign_update" --ed-key-file "$work/recovered.key" -p "$work/challenge")
    SPARKLE_PUBLIC_KEY="$public" python3 scripts/release/release.py verify-signature "$work/challenge" "$signature"
    printf 'modified\n' >> "$work/challenge"
    if SPARKLE_PUBLIC_KEY="$public" python3 scripts/release/release.py verify-signature "$work/challenge" "$signature" 2>/dev/null; then
        echo 'Corruption rejection failed' >&2; exit 1
    fi
}
case "$mode" in
    prepare)
        [[ -z "${CI:-}" && -t 0 ]] || { echo 'Prepare requires an interactive trusted Mac, outside CI' >&2; exit 1; }
        account="${2:?Specify a dedicated keychain account}"
        backup="${3:?Specify a new encrypted backup on offline media}"
        # Prevent accidental backup commits, including through symlinked directories.
        python3 - "$backup" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]).resolve()
if p.is_relative_to(Path.cwd()) or p.exists() or Path(str(p)+'.public').exists():
    raise SystemExit('Choose a new backup path outside the repository')
if not p.parent.is_dir():
    raise SystemExit('Backup parent directory must already exist')
PY
        "$tools/generate_keys" --account "$account"
        public=$("$tools/generate_keys" --account "$account" -p)
        "$tools/generate_keys" --account "$account" -x "$work/private.key"
        echo 'Enter a strong backup passphrase; store it separately in your password manager.'
        openssl enc -aes-256-cbc -salt -pbkdf2 -iter 600000 -in "$work/private.key" -out "$backup"
        echo 'Enter the passphrase again to prove the encrypted backup can be recovered.'
        openssl enc -d -aes-256-cbc -pbkdf2 -iter 600000 -in "$backup" -out "$work/recovered.key"
        cmp "$work/private.key" "$work/recovered.key"
        verify_recovered
        printf '%s\n' "$public" > "$backup.public"
        echo "Verified encrypted backup and public key: $backup"
        echo "Key remains in your login Keychain under account: $account"
        ;;
    recover-test)
        backup="${2:?Specify encrypted backup}"
        public=$(cat "${3:?Specify the saved public-key file}")
        openssl enc -d -aes-256-cbc -pbkdf2 -iter 600000 -in "$backup" -out "$work/recovered.key"
        verify_recovered
        echo 'Encrypted backup passed recovery and signature/corruption checks.'
        ;;
    provision)
        [[ -z "${CI:-}" && -t 0 ]] || { echo 'Provision requires the trusted maintainer Mac' >&2; exit 1; }
        backup="${2:?Specify verified encrypted stable backup}"
        public=$(cat "$backup.public")
        openssl enc -d -aes-256-cbc -pbkdf2 -iter 600000 -in "$backup" -out "$work/recovered.key"
        verify_recovered
        expected=$("$tools/generate_keys" --account bettervmaf-stable -p)
        [[ "$public" == "$expected" ]] || { echo 'Backup does not match stable Keychain identity' >&2; exit 1; }
        gh secret set SPARKLE_PRIVATE_KEY --repo oliverdougherC/BetterVMAF --env release-signing < "$work/recovered.key"
        printf '%s' "$public" | gh variable set SPARKLE_PUBLIC_KEY --repo oliverdougherC/BetterVMAF
        echo 'Configured stable Sparkle secret and repository public variable.'
        ;;
    *) echo 'Unknown identity command' >&2; exit 2 ;;
esac
