#!/bin/bash

# EnglishAI PKG Installer Creation Script
# Creates a professional PKG installer with post-install script

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_NAME="EnglishAI"
APP_NAME="${PROJECT_NAME}.app"
BUILD_DIR="${SCRIPT_DIR}/build"
PKG_NAME="${PROJECT_NAME}-Installer"
VERSION="1.0"

echo "🚀 Starting PKG installer creation process..."

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

# Create package directory structure
PKG_ROOT="${BUILD_DIR}/pkg_root"
rm -rf "${PKG_ROOT}"
mkdir -p "${PKG_ROOT}/Applications"

# Copy app to package root
cp -R "${APP_PATH}" "${PKG_ROOT}/Applications/"

# Create post-install script
POSTINSTALL_SCRIPT="${BUILD_DIR}/postinstall"
cat > "${POSTINSTALL_SCRIPT}" << 'EOF'
#!/bin/bash

# Post-install script for EnglishAI
# This script runs after the app is installed

APP_NAME="EnglishAI.app"
APP_PATH="/Applications/${APP_NAME}"

echo "EnglishAI has been installed successfully!"

# Set proper permissions
chmod -R 755 "${APP_PATH}"

# Open System Settings to Accessibility (macOS will prompt user)
# Note: We cannot automatically grant permissions, but we can guide the user
if [ -d "${APP_PATH}" ]; then
    # Open the app once to trigger permission request
    open "${APP_PATH}" &
    
    # Wait a moment, then open System Settings
    sleep 2
    
    # Open System Settings to Accessibility section
    open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    
    echo ""
    echo "IMPORTANT: Please grant Accessibility permissions for EnglishAI"
    echo "1. Check the box next to 'EnglishAI' in the Accessibility list"
    echo "2. If EnglishAI is not listed, click the lock icon and unlock it first"
    echo ""
fi

exit 0
EOF

chmod +x "${POSTINSTALL_SCRIPT}"

# Create distribution file for pkgbuild
DISTRIBUTION_FILE="${BUILD_DIR}/Distribution.xml"
cat > "${DISTRIBUTION_FILE}" << EOF
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="1">
    <title>${PROJECT_NAME} ${VERSION}</title>
    <organization>com.englishai</organization>
    <domains enable_anywhere="false" enable_currentUserHome="false" enable_localSystem="true"/>
    <options customize="never" require-scripts="false" rootVolumeOnly="true"/>
    <welcome file="welcome.html" mime-type="text/html"/>
    <pkg-ref id="com.englishai.app"/>
    <choices-outline>
        <line choice="com.englishai.app"/>
    </choices-outline>
    <choice id="com.englishai.app" visible="false">
        <pkg-ref id="com.englishai.app"/>
    </choice>
    <pkg-ref id="com.englishai.app" version="${VERSION}" onConclusion="none">${PROJECT_NAME}.pkg</pkg-ref>
</installer-gui-script>
EOF

# Create welcome HTML
WELCOME_HTML="${BUILD_DIR}/welcome.html"
cat > "${WELCOME_HTML}" << EOF
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Welcome to ${PROJECT_NAME}</title>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; padding: 20px; }
        h1 { color: #333; }
        p { line-height: 1.6; }
    </style>
</head>
<body>
    <h1>Welcome to ${PROJECT_NAME}!</h1>
    <p>Thank you for installing ${PROJECT_NAME}.</p>
    <h2>What to expect:</h2>
    <ul>
        <li>The app will be installed in your Applications folder</li>
        <li>After installation, System Settings will open automatically</li>
        <li>You'll need to grant Accessibility permissions for the app to work</li>
    </ul>
    <h2>Important:</h2>
    <p><strong>${PROJECT_NAME} requires Accessibility permissions</strong> to monitor keyboard input for recording your typing practice.</p>
    <p>Please enable ${PROJECT_NAME} in System Settings > Privacy & Security > Accessibility.</p>
</body>
</html>
EOF

# Build the component package
echo "📦 Creating component package..."
pkgbuild \
    --root "${PKG_ROOT}" \
    --identifier "com.englishai.app" \
    --version "${VERSION}" \
    --install-location "/" \
    --scripts "${BUILD_DIR}" \
    "${BUILD_DIR}/${PROJECT_NAME}.pkg"

# Build the distribution package
echo "📦 Creating distribution package..."
PKG_PATH="${BUILD_DIR}/${PKG_NAME}.pkg"
productbuild \
    --distribution "${DISTRIBUTION_FILE}" \
    --package-path "${BUILD_DIR}" \
    --resources "${BUILD_DIR}" \
    "${PKG_PATH}"

echo "✅ PKG created successfully at: ${PKG_PATH}"

# Cleanup
rm -rf "${PKG_ROOT}" "${BUILD_DIR}/${PROJECT_NAME}.pkg"

echo ""
echo "🎉 PKG installer creation complete!"
echo "📦 PKG location: ${PKG_PATH}"
echo ""
echo "Next steps:"
echo "1. Test the PKG by double-clicking it"
echo "2. Distribute the PKG to users"
echo "3. Users can install by double-clicking the PKG file"
