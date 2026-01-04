#!/bin/bash
# run in terminal: ./quick_update.sh

# Quick Update Script
# Builds new installer and opens it for easy testing

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🔄 Quick Update Workflow"
echo "========================"
echo ""

# Build the installer
echo "1️⃣ Building new installer..."
"${SCRIPT_DIR}/create_installer.sh"

if [ $? -eq 0 ]; then
    echo ""
    echo "2️⃣ Opening DMG installer..."
    DMG_PATH="${SCRIPT_DIR}/build/EnglishAI-Installer.dmg"
    
    if [ -f "${DMG_PATH}" ]; then
        open "${DMG_PATH}"
        echo ""
        echo "✅ DMG opened!"
        echo ""
        echo "📋 Next steps:"
        echo "   - Drag EnglishAI.app to Applications folder"
        echo "   - Click 'Replace' when prompted"
        echo "   - Your data and settings will be preserved ✅"
    else
        echo "❌ DMG not found at ${DMG_PATH}"
        exit 1
    fi
else
    echo "❌ Build failed"
    exit 1
fi
