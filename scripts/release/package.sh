#!/bin/bash
set -euo pipefail
# Remove credentials from child environments before invoking any tools.
source "$(dirname -- "${BASH_SOURCE[0]}")/check-signing-inputs.sh"
mode="${1:?Specify dry-run, staging, or production}"
destination="${2:?Specify a new output directory}"
if [[ "$destination" != /* ]]; then destination="$PWD/$destination"; fi
if [[ -e "$destination" ]]; then
    echo "Output directory already exists: $destination" >&2
    exit 1
fi
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.."
release=(python3 scripts/release/release.py)
version=$("${release[@]}" version)
bundle_id=neurophasia.BetterVMAF
build_settings=()
case "$mode" in
    dry-run)
        export SPARKLE_FEED_URL="" SPARKLE_PUBLIC_KEY=""
        ;;
    staging)
        version="${3:?Specify an isolated staging version}"
        bundle_id+=.Staging
        archive_url=$("${release[@]}" staging-archive "${SPARKLE_FEED_URL:?Missing staging feed}" "$version")
        build_settings+=("MARKETING_VERSION=$version" "CURRENT_PROJECT_VERSION=$("${release[@]}" build-number "$version")")
        ;;
    production)
        version=$("${release[@]}" version "${3:?Specify the validated release tag}")
        export SPARKLE_FEED_URL
        SPARKLE_FEED_URL=$("${release[@]}" stable-feed)
        archive_url=stable
        check_signing_inputs
        ;;
    *) echo "Invalid package mode: $mode" >&2; exit 2 ;;
esac
if [[ "$mode" != dry-run ]]; then
    : "${SPARKLE_PUBLIC_KEY:?Missing Sparkle public key}"
    : "${SPARKLE_PRIVATE_KEY:?Missing Sparkle private key}"
    export -n SPARKLE_PRIVATE_KEY
fi

umask 077
work=$(mktemp -d)
keychain="$work/signing.keychain-db"
original_keychains=()
while IFS= read -r line; do
    original_keychains+=("$(printf '%s' "$line" | sed 's/^ *"//; s/"$//')")
done < <(security list-keychains -d user)
cleanup() {
    if [[ -e "$keychain" ]]; then security list-keychains -d user -s "${original_keychains[@]}" || true; fi
    if [[ -e "$keychain" ]]; then security delete-keychain "$keychain" || true; fi
    rm -rf -- "$work"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

output="$work/output"
staging="$work/staging"
mkdir "$output" "$staging"
dmg="$output/$("${release[@]}" asset-name "$version")"

if [[ "$mode" != dry-run ]]; then
    if [[ "$mode" == staging && -n "${SPARKLE_TOOLS_DIR:-}" ]]; then
        tools="$SPARKLE_TOOLS_DIR"
    else
        scripts/release/sparkle-tools.sh "$work/sparkle"
        tools="$work/sparkle/bin"
    fi
    # A mismatched identity must fail before any signing or notarization.
    printf 'BetterVMAF signing identity check\n' > "$work/challenge"
    signature=$(printf '%s\n' "$SPARKLE_PRIVATE_KEY" | "$tools/sign_update" --ed-key-file - -p "$work/challenge")
    "${release[@]}" verify-signature "$work/challenge" "$signature"
fi


xcodebuild -project VMAF.xcodeproj -scheme VMAF -configuration Release \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "${RELEASE_DERIVED_DATA:-$work/DerivedData}" \
    -onlyUsePackageVersionsFromResolvedFile \
    'ARCHS=arm64 x86_64' ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO \
    "CONFIGURATION_BUILD_DIR=$work/build" "PRODUCT_BUNDLE_IDENTIFIER=$bundle_id" \
    "SPARKLE_FEED_URL=$SPARKLE_FEED_URL" "SPARKLE_PUBLIC_KEY=$SPARKLE_PUBLIC_KEY" \
    ${build_settings[@]+"${build_settings[@]}"} build

app="$staging/Better VMAF.app"
ditto "$work/build/Better VMAF.app" "$app"
ln -s /Applications "$staging/Applications"
minimum_os=$("${release[@]}" check-bundle "$app" "$version" "$mode")


if [[ "$mode" == production ]]; then
    printf '%s' "$APPLE_CERTIFICATE_P12" | base64 -D > "$work/certificate.p12"
    printf '%s' "$APPLE_NOTARY_KEY" | base64 -D > "$work/AuthKey.p8"
    password=$(openssl rand -hex 32)
    security create-keychain -p "$password" "$keychain"
    security unlock-keychain -p "$password" "$keychain"
    security list-keychains -d user -s "$keychain" "${original_keychains[@]}"
    security set-keychain-settings -lut 7200 "$keychain"
    security import "$work/certificate.p12" -k "$keychain" -P "$APPLE_CERTIFICATE_PASSWORD" -T /usr/bin/codesign
    rm -- "$work/certificate.p12"
    security set-key-partition-list -S apple-tool:,apple: -s -k "$password" "$keychain" >/dev/null
    identity=$(security find-identity -v -p codesigning "$keychain" |
        awk -v team="($APPLE_TEAM_ID)" '/Developer ID Application:/{if (index($0, team)) print $2}')
    [[ "$identity" =~ ^[[:xdigit:]]{40}$ ]] ||
        { echo "Expected one Developer ID Application identity for $APPLE_TEAM_ID" >&2; exit 1; }
    signing=(--sign "$identity" --keychain "$keychain" --options runtime --timestamp)
elif [[ "$mode" == staging ]]; then
    signing=(--sign - --timestamp=none)
    # An ATS exception scoped to local networking, only in the staging bundle.
    /usr/libexec/PlistBuddy -c 'Add :NSAppTransportSecurity:NSAllowsLocalNetworking bool true' "$app/Contents/Info.plist"
fi

notarize() {
    local artifact="$1" result="$work/notary.json"
    local credentials=(--key "$work/AuthKey.p8" --key-id "$APPLE_NOTARY_KEY_ID" --issuer "$APPLE_NOTARY_ISSUER_ID")
    if ! xcrun notarytool submit "$artifact" "${credentials[@]}" --wait --timeout 30m --output-format json > "$result" ||
        [[ "$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["status"])' "$result")" != Accepted ]]; then
        cat "$result" >&2
        local submission
        submission=$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1])).get("id", ""))' "$result") || submission=""
        if [[ -n "$submission" ]]; then xcrun notarytool log "$submission" "${credentials[@]}" >&2 || true; fi
        return 1
    fi
    cat "$result"
}

if [[ "$mode" != dry-run ]]; then
    # Sign inside out. Keep both FFmpeg signatures and pinned binary hashes intact.
    framework="$app/Contents/Frameworks/Sparkle.framework"
    sparkle="$framework/Versions/Current"
    for component in "$sparkle/Autoupdate" "$sparkle/Updater.app" \
        "$sparkle/XPCServices/Installer.xpc" "$sparkle/XPCServices/Downloader.xpc"; do
        codesign --force "${signing[@]}" --preserve-metadata=identifier,entitlements "$component"
    done
    codesign --force "${signing[@]}" "$framework"
    "${release[@]}" write-entitlements "$work/app.entitlements" "$mode"
    codesign --force "${signing[@]}" --entitlements "$work/app.entitlements" "$app"
    codesign --verify --strict --deep "$app"
    if [[ "$mode" == production ]]; then
        # Give the installed app an offline ticket in addition to the DMG ticket.
        ditto -c -k --keepParent "$app" "$work/app.zip"
        notarize "$work/app.zip"
        xcrun stapler staple "$app"
        rm -- "$work/app.zip"
    fi
fi

hdiutil create -volname "Better VMAF" -srcfolder "$staging" -format UDZO "$dmg"
if [[ "$mode" == production ]]; then
    codesign --force --sign "$identity" --keychain "$keychain" --timestamp "$dmg"
    notarize "$dmg"
    xcrun stapler staple "$dmg"
fi
if [[ "$mode" != dry-run ]]; then
    signature=$(printf '%s\n' "$SPARKLE_PRIVATE_KEY" | "$tools/sign_update" --ed-key-file - -p "$dmg")
    "${release[@]}" render-feed "$output/appcast.xml" "$dmg" "$version" "$archive_url" "$minimum_os" "$signature"
    printf '%s\n' "$SPARKLE_PRIVATE_KEY" |
        "$tools/sign_update" --ed-key-file - --disable-signing-warning "$output/appcast.xml"
fi
"${release[@]}" checksum "$dmg" > "$dmg.sha256"
scripts/release/verify-dmg.sh "$dmg" "$version" "$mode"

mkdir -p -- "$(dirname -- "$destination")"
mv -- "$output" "$destination"
echo "Verified $mode artifacts: $destination"
