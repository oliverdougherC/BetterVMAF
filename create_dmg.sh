#!/bin/bash

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# Set Xcode path
echo "Setting Xcode path..."
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer

# Verify project file exists
if [ ! -d "VMAF.xcodeproj" ]; then
    echo "Error: VMAF.xcodeproj not found in current directory"
    echo "Current directory: $(pwd)"
    echo "Directory contents:"
    ls -la
    exit 1
fi

# Clean build directory
echo "Cleaning build directory..."
rm -rf build/

# Build the app
echo "Building app..."
xcodebuild -project VMAF.xcodeproj -scheme VMAF -configuration Release -verbose

# Check if build was successful
if [ $? -ne 0 ]; then
    echo "Build failed!"
    exit 1
fi

# Find the app in DerivedData
DERIVED_DATA_DIR="$HOME/Library/Developer/Xcode/DerivedData"
APP_PATH=$(find "$DERIVED_DATA_DIR" -name "Better VMAF.app" -type d | head -n 1)

if [ -z "$APP_PATH" ]; then
    echo "Error: Better VMAF.app not found in DerivedData"
    echo "Searching in: $DERIVED_DATA_DIR"
    exit 1
fi

echo "Found app at: $APP_PATH"

# Create a temporary directory for packaging
echo "Creating DMG..."
mkdir -p dmg_temp

# Copy the app to the temporary directory
echo "Copying app to temporary directory..."
cp -R "$APP_PATH" dmg_temp/

# Create a symbolic link to Applications folder
echo "Creating Applications folder shortcut..."
ln -s /Applications dmg_temp/Applications

# Create the DMG
echo "Creating DMG file..."
hdiutil create -volname "Better VMAF" -srcfolder dmg_temp -ov -format UDZO Better-VMAF.dmg

# Clean up
echo "Cleaning up..."
rm -rf dmg_temp

echo "DMG created successfully!" 