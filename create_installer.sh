#!/bin/bash

# EnglishAI Installer Creation Script
# This script builds the app and creates a DMG installer

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_NAME="EnglishAI"
APP_NAME="${PROJECT_NAME}.app"
BUILD_DIR="${SCRIPT_DIR}/build"
DMG_NAME="${PROJECT_NAME}-Installer"
VERSION="1.0"

echo "🚀 Starting installer creation process..."

# Clean previous builds
echo "🧹 Cleaning previous builds..."
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

# Build the app
echo "🔨 Building ${PROJECT_NAME}..."
xcodebuild \
    -project "${SCRIPT_DIR}/${PROJECT_NAME}.xcodeproj" \
    -scheme "${PROJECT_NAME}" \
    -configuration Release \
    -derivedDataPath "${BUILD_DIR}/DerivedData" \
    clean build

# Find the built app
APP_PATH=$(find "${BUILD_DIR}/DerivedData" -name "${APP_NAME}" -type d | head -1)

if [ -z "${APP_PATH}" ]; then
    echo "❌ Error: Could not find built app"
    exit 1
fi

echo "✅ App built successfully at: ${APP_PATH}"

# Create DMG directory structure
DMG_TEMP_DIR="${BUILD_DIR}/dmg_temp"
rm -rf "${DMG_TEMP_DIR}"
mkdir -p "${DMG_TEMP_DIR}"

# Copy app to DMG directory
cp -R "${APP_PATH}" "${DMG_TEMP_DIR}/"

# Create Applications symlink
ln -s /Applications "${DMG_TEMP_DIR}/Applications"

# Create README file
cat > "${DMG_TEMP_DIR}/README.txt" << EOF
Welcome to ${PROJECT_NAME}!

INSTALLATION INSTRUCTIONS:
1. Drag ${APP_NAME} to the Applications folder
2. Open ${APP_NAME} from Applications
3. When prompted, grant Accessibility permissions in System Settings

IMPORTANT:
- ${PROJECT_NAME} requires Accessibility permissions to monitor keyboard input
- After installation, go to System Settings > Privacy & Security > Accessibility
- Enable ${PROJECT_NAME} in the list

For support, visit: https://github.com/yourusername/EnglishAI
EOF

# Create DMG
DMG_PATH="${BUILD_DIR}/${DMG_NAME}.dmg"
echo "📦 Creating DMG installer..."

# Remove existing DMG if it exists
rm -f "${DMG_PATH}"

# Create DMG with proper formatting
hdiutil create -volname "${PROJECT_NAME}" \
    -srcfolder "${DMG_TEMP_DIR}" \
    -ov -format UDZO \
    "${DMG_PATH}"

# Set DMG icon (optional - requires icon file)
# hdiutil attach "${DMG_PATH}"
# # Set icon here if needed
# hdiutil detach /Volumes/"${PROJECT_NAME}"

echo "✅ DMG created successfully at: ${DMG_PATH}"

# Cleanup
rm -rf "${DMG_TEMP_DIR}"

echo ""
echo "🎉 Installer creation complete!"
echo "📦 DMG location: ${DMG_PATH}"
echo ""
echo "Next steps:"
echo "1. Test the DMG by double-clicking it"
echo "2. Distribute the DMG to users"
echo "3. Users can drag the app to Applications and install"
