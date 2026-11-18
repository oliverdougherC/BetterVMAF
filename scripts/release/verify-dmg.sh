#!/bin/bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.."
source scripts/release/verify-developer-id.sh
dmg="${1:?Specify an absolute DMG path}"
version="${2:?Specify the expected version}"
mode="${3:?Specify production, staging, or dry-run}"
case "$mode" in
    production|staging|dry-run) ;;
    *) echo "Invalid package mode: $mode" >&2; exit 2 ;;
esac

work=$(mktemp -d)
mount="$work/mount"
mkdir "$mount"
mounted=false
cleanup() {
    if [[ "$mounted" == true ]]; then
        hdiutil detach "$mount" >/dev/null 2>&1 || hdiutil detach "$mount" -force >&2 || true
    fi
    rmdir "$mount" "$work" 2>/dev/null || true
}
trap cleanup EXIT

python3 scripts/release/release.py verify-checksum "$dmg"
if [[ "$mode" == production ]]; then
    export SPARKLE_FEED_URL
    SPARKLE_FEED_URL=$(python3 scripts/release/release.py stable-feed)
fi
if [[ "$mode" == production || "$mode" == staging ]]; then
    # Reject untrusted update bytes before mounting. Read the OS value from the
    # verified feed, then compare it against the mounted app below.
    archive_url=stable
    if [[ "$mode" == staging ]]; then
        archive_url=$(python3 scripts/release/release.py staging-archive "$SPARKLE_FEED_URL" "$version")
    fi
    minimum_os=$(python3 scripts/release/release.py verify-feed "$(dirname "$dmg")/appcast.xml" "$dmg" "$version" "$archive_url")
fi
if [[ "$mode" == production ]]; then
    team="${APPLE_TEAM_ID:?Missing expected Developer ID team}"
    verify_developer_id "$team" "$dmg"
    xcrun stapler validate "$dmg"
    spctl --assess --type open --context context:primary-signature --verbose "$dmg"
fi

hdiutil verify "$dmg" >&2
hdiutil attach -readonly -nobrowse -noautoopen -mountpoint "$mount" "$dmg" >&2
mounted=true
app="$mount/Better VMAF.app"

test "$(readlink "$mount/Applications")" = /Applications
bundle_minimum=$(python3 scripts/release/release.py check-bundle "$app" "$version" "$mode")
if [[ "$mode" != dry-run ]]; then
    test "$bundle_minimum" = "$minimum_os"
    codesign --verify --strict --deep "$app"
    python3 scripts/release/release.py check-entitlements "$app" "$mode"
fi
if [[ "$mode" == production ]]; then
    # Deep verification checks integrity, but not each component's team/runtime.
    sparkle="$app/Contents/Frameworks/Sparkle.framework/Versions/Current"
    for component in "$app" "$app/Contents/Frameworks/Sparkle.framework" \
        "$sparkle/Autoupdate" "$sparkle/Updater.app" \
        "$sparkle/XPCServices/Installer.xpc" "$sparkle/XPCServices/Downloader.xpc"; do
        verify_developer_id "$team" "$component"
        info=$(codesign -dvv "$component" 2>&1)
        [[ "$info" == *'runtime)'* && "$info" == *'Timestamp='* ]] ||
            { echo "Missing hardened runtime or secure timestamp: $component" >&2; exit 1; }
        python3 scripts/release/release.py check-component-entitlements "$component"
    done
    xcrun stapler validate "$app"
    spctl --assess --type execute --verbose "$app"
fi
scripts/release/verify-app.sh "$app"
