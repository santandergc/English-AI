# Update Workflow Guide

## Quick Answer: Do I Need to Uninstall?

**No, you don't need to uninstall!** You can install the new version directly over the old one.

## How Updates Work

### Option 1: DMG Installer (Drag & Drop)

1. **Open the new DMG** you just created
2. **Drag the app to Applications folder**
3. macOS will ask: **"Replace 'EnglishAI'?"**
4. Click **"Replace"** ✅
5. Done! The new version is installed

**What happens:**
- Old app is replaced with new version
- Your app data/preferences are preserved (stored in `~/Library/Application Support/EnglishAI/` or similar)
- Database files persist
- User settings remain intact

### Option 2: PKG Installer

1. **Double-click the new PKG**
2. Follow the installer wizard
3. It will automatically detect the existing installation
4. Click **"Continue"** to update ✅
5. Done!

**What happens:**
- Old version is automatically replaced
- All user data is preserved
- No manual uninstall needed

## When You Might Want to Clean Install

You only need to uninstall if:

1. **Major version changes** - If you're testing something completely different
2. **Database schema changes** - If your database structure changed significantly
3. **Troubleshooting** - If the app is behaving strangely after update

### How to Clean Install (if needed):

```bash
# 1. Quit the app completely
# 2. Delete the app
rm -rf /Applications/EnglishAI.app

# 3. Delete app data (optional - only if you want to reset everything)
rm -rf ~/Library/Application\ Support/EnglishAI
rm -rf ~/Library/Preferences/com.englishai.app.plist
rm -rf ~/Library/Caches/com.englishai.app

# 4. Install fresh version
```

## Recommended Workflow

### For Development/Testing:
1. Make your fixes in Xcode
2. Run `./create_installer.sh` to create new DMG
3. Open DMG and replace the app (click "Replace")
4. Test the new version
5. Repeat as needed ✅

### For Distribution:
1. Make your fixes
2. **Update version number** in Xcode:
   - Go to project settings
   - Update "Marketing Version" (e.g., 1.0 → 1.1)
   - Update "Current Project Version" (e.g., 1 → 2)
3. Run `./create_installer.sh`
4. Distribute the new DMG/PKG
5. Users can install over their existing version ✅

## Version Numbering Best Practice

Update version numbers in Xcode when distributing updates:

**In Xcode:**
- **Marketing Version**: User-facing version (1.0, 1.1, 1.2, etc.)
- **Current Project Version**: Build number (1, 2, 3, etc.)

This helps users know they're getting an update.

## Quick Update Script

You can create a quick update script:

```bash
#!/bin/bash
# Quick update workflow
./create_installer.sh
open build/EnglishAI-Installer.dmg
```

This builds and opens the DMG so you can quickly replace the app.

## Summary

✅ **Normal updates**: Just install over the existing app  
✅ **Your data persists**: Settings, database, preferences all stay  
✅ **No uninstall needed**: macOS handles replacement automatically  
⚠️ **Clean install only if**: Major changes or troubleshooting needed
