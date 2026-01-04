# EnglishAI Installer Guide

This guide explains how to create installers for the EnglishAI macOS application.

## Prerequisites

- Xcode installed and configured
- macOS development tools
- Code signing certificate (optional, but recommended for distribution)

## Installer Options

### Option 1: DMG Installer (Simple Drag-and-Drop)

The DMG installer is the simplest option for users. They just drag the app to Applications.

**To create:**
```bash
./create_installer.sh
```

**Output:** `build/EnglishAI-Installer.dmg`

**User experience:**
1. User downloads and opens the DMG
2. Drags EnglishAI.app to Applications folder
3. Opens the app from Applications
4. Grants Accessibility permissions when prompted

### Option 2: PKG Installer (Professional Installer)

The PKG installer provides a more professional installation experience with a guided installer.

**To create:**
```bash
./create_pkg_installer.sh
```

**Output:** `build/EnglishAI-Installer.pkg`

**User experience:**
1. User downloads and double-clicks the PKG
2. Follows the installer wizard
3. App is installed to Applications
4. Post-install script opens System Settings for permissions
5. User grants Accessibility permissions

## App Icon

The app icon has been set up using your logo file (`logo.webp`). The icon will appear:
- In the Applications folder
- In Launchpad
- In the Dock when running
- In System Settings

All required icon sizes have been generated automatically.

## Accessibility Permissions

**Important:** macOS does not allow automatic granting of Accessibility permissions. Users must manually enable them.

The app will:
1. Automatically prompt for permissions on first launch
2. Open System Settings to the Accessibility section
3. Guide users to enable EnglishAI in the list

## Code Signing (Recommended for Distribution)

For distribution outside the Mac App Store, you should code sign your app:

1. Get a Developer ID certificate from Apple Developer
2. Update the Xcode project with your Team ID
3. The installer scripts will automatically use your certificate

## Distribution

### For Testing:
- Share the DMG or PKG file directly
- Users can install without code signing (may see security warnings)

### For Production:
- Code sign the app and installer
- Notarize with Apple (required for macOS 10.15+)
- Distribute via your website or app distribution platform

## Troubleshooting

### Build Errors
- Ensure Xcode command line tools are installed: `xcode-select --install`
- Check that the project builds in Xcode first

### Icon Not Showing
- Clean build folder: `rm -rf build`
- Rebuild the app
- Check that Assets.xcassets is included in the project

### Permissions Not Working
- Users must manually grant permissions in System Settings
- The app cannot grant permissions automatically (macOS security)

## Next Steps

1. Test both installer types
2. Choose the one that fits your distribution needs
3. Code sign and notarize for production use
4. Distribute to your users
