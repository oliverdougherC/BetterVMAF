#!/bin/bash
set -euo pipefail

# Create an unsigned local build. Public distribution still requires a separate
# signing and notarization workflow.
REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="Better VMAF"
DMG_NAME="Better-VMAF.dmg"

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "Error: DMG creation requires macOS and Xcode." >&2
    exit 1
fi

for tool in xcodebuild hdiutil ditto; do
    if ! command -v "${tool}" >/dev/null 2>&1; then
        echo "Error: Required tool '${tool}' is unavailable." >&2
        exit 1
    fi
done

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/better-vmaf-dmg.XXXXXX")"
trap 'rm -rf -- "${WORK_DIR}"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

BUILD_DIR="${WORK_DIR}/build/Release"
STAGING_DIR="${WORK_DIR}/staging"

echo "Building ${APP_NAME}..."
xcodebuild \
    -project "${REPO_ROOT}/VMAF.xcodeproj" \
    -scheme VMAF \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "${WORK_DIR}/DerivedData" \
    "CONFIGURATION_BUILD_DIR=${BUILD_DIR}" \
    CODE_SIGNING_ALLOWED=NO \
    build

if [[ ! -d "${BUILD_DIR}/${APP_NAME}.app" ]]; then
    echo "Error: App was not built successfully." >&2
    exit 1
fi

mkdir -p "${STAGING_DIR}"
ditto "${BUILD_DIR}/${APP_NAME}.app" "${STAGING_DIR}/${APP_NAME}.app"
ln -s /Applications "${STAGING_DIR}/Applications"

echo "Creating DMG..."
hdiutil create \
    -volname "${APP_NAME}" \
    -srcfolder "${STAGING_DIR}" \
    -format UDZO \
    "${WORK_DIR}/${DMG_NAME}"

# Replace the previous output only after both the build and packaging succeed.
mv -f "${WORK_DIR}/${DMG_NAME}" "${REPO_ROOT}/${DMG_NAME}"
echo "DMG creation complete: ${REPO_ROOT}/${DMG_NAME}"
