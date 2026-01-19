# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

EnglishAI is a native macOS app (Swift/SwiftUI) that monitors keyboard input and Wispr Flow voice transcriptions system-wide to help users improve their English language skills through AI-powered analysis.

**Platform**: macOS 13.0+ (Ventura)
**Framework**: SwiftUI
**Bundle IDs**: `com.englishai.app` (Release), `com.englishai.app.dev` (Debug)

## Build Commands

```bash
# Quick development build + DMG
./quick_update.sh

# Release DMG installer
./create_installer.sh

# PKG installer
./create_pkg_installer.sh

# Xcode command line build
xcodebuild -project EnglishAI.xcodeproj -scheme EnglishAI -configuration Debug build
xcodebuild -project EnglishAI.xcodeproj -scheme EnglishAI -configuration Release build
```

## Architecture

### Core Flow
```
Keyboard/Wispr Input → Monitor Services → RecordManager (orchestrator)
    → 8-stage Filter Pipeline → DatabaseService (SQLite) → UI / AIAnalysisService
```

### Key Singletons
- **RecordManager** (`Services/RecordManager.swift`): Central orchestrator managing keyboard buffer, cursor tracking, filtering, and service coordination
- **DatabaseService** (`Services/DatabaseService.swift`): Thread-safe SQLite operations via serial queue
- **AIAnalysisService** (`Services/AIAnalysisService.swift`): Claude/OpenAI API integration

### Monitor Services
- **KeyboardMonitorService**: CGEventTap for system-wide keystroke capture (requires Accessibility permission)
- **ClipboardMonitorService**: Detects Wispr Flow transcriptions via clipboard restore pattern (100ms polling)
- **AppFocusMonitorService**: NSWorkspace notifications for active app tracking

### Data Storage
- **Location**: `~/Library/Application Support/EnglishAI/records.sqlite`
- **Tables**: `records`, `insights`, `analysis_sessions`
- **Mode**: WAL (Write-Ahead Logging) with IMMEDIATE transactions

## Important Patterns

### Filtering Pipeline (8 stages in RecordManager)
1. Single character check
2. Numbers-only filter
3. Minimum length (5 chars)
4. Natural language detection (vowel ratio ≥20%, special chars ≤25%)
5. Terminal command patterns
6. Terminal app context check
7. Special character ratio (non-terminal)
8. Vowel ratio (non-terminal)

### Terminal Detection
Recognized apps: Warp, Terminal, iTerm, iTerm2, Alacritty, Hyper, Kitty, WezTerm, Terminator

### Threading
- **Database**: Serial queue `com.englishai.database`
- **Wispr dedup**: Serial queue `com.englishai.wispr.dedup`
- **UI**: Always update via `DispatchQueue.main.async`

### Key Constants
| Parameter | Value |
|-----------|-------|
| Keyboard idle threshold | 10s |
| Clipboard poll interval | 100ms |
| Wispr restoration window | 2.5s |
| Minimum text for AI analysis | 300 chars |

## Debugging

Log prefixes to filter:
- `[RecordManager]`: Buffer operations, filtering
- `[ClipboardMonitor]`: Wispr detection
- `[KeyboardMonitor]`: Event tap events

## Permissions

Accessibility permission is required for keyboard monitoring. Dev and Release builds require separate permission grants due to different bundle IDs. Both share the same database.
