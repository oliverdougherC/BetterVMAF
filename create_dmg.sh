#!/bin/bash

# Exit on error
set -e

# Configuration
APP_NAME="Better VMAF"
DMG_NAME="${APP_NAME}.dmg"
VOLUME_NAME="${APP_NAME}"
TEMP_DIR="temp_dmg"
BUILD_DIR="build/Release"

# Clean up any previous build artifacts
rm -rf "${BUILD_DIR}"
rm -rf "${TEMP_DIR}"
rm -f "${DMG_NAME}"

# Build the app in Release configuration
echo "Building ${APP_NAME}..."
xcodebuild -project "VMAF.xcodeproj" -scheme "VMAF" -configuration Release clean build CONFIGURATION_BUILD_DIR="$(pwd)/${BUILD_DIR}"

# Verify the app was built
if [ ! -d "${BUILD_DIR}/${APP_NAME}.app" ]; then
    echo "Error: App was not built successfully"
    exit 1
fi

# Create temporary directory for DMG
echo "Creating temporary directory for DMG..."
mkdir -p "${TEMP_DIR}"

# Copy the app to the temporary directory
echo "Copying app to temporary directory..."
cp -R "${BUILD_DIR}/${APP_NAME}.app" "${TEMP_DIR}/"

# Create a symbolic link to Applications folder
echo "Creating Applications folder link..."
ln -s /Applications "${TEMP_DIR}/Applications"

# Create the DMG
echo "Creating DMG..."
hdiutil create -volname "${VOLUME_NAME}" -srcfolder "${TEMP_DIR}" -ov -format UDZO "${DMG_NAME}"

# Clean up
echo "Cleaning up..."
rm -rf "${TEMP_DIR}"

echo "DMG creation complete! Output: ${DMG_NAME}" 