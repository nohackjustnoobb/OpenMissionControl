#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

# Check if npm is installed
if ! command -v npm &> /dev/null
then
    echo "Error: npm is not installed. Please install Node.js/npm to automatically install dependencies."
    exit 1
fi

echo "Building OpenMissionControl..."
rm -rf build
xcodebuild -project OpenMissionControl.xcodeproj -scheme OpenMissionControl -configuration Release -derivedDataPath ./build build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""

echo "Renaming app..."
mv "build/Build/Products/Release/OpenMissionControl.app" "build/Build/Products/Release/Open Mission Control.app"

echo "Creating DMG..."
npx create-dmg "build/Build/Products/Release/Open Mission Control.app" --no-version-in-filename --overwrite --no-code-sign

echo "Renaming DMG..."
if [ -f "Open Mission Control.dmg" ]; then
    mv "Open Mission Control.dmg" "OpenMissionControl.dmg"
fi

echo "Build and DMG creation completed successfully!"
