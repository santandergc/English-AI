# EnglishAI

macOS application that records and analyzes English text input to help improve language skills.

## Overview

EnglishAI monitors keyboard input and voice transcriptions (via Wispr Flow) to:
- Record all English text you type or speak
- Analyze grammar, phrasing, and vocabulary
- Track progress over time
- Provide AI-powered feedback

## Architecture

### Core Components

```
┌─────────────────────────────────────────────────────────┐
│                    EnglishAIApp                         │
│  - App lifecycle & menu bar                            │
│  - Permission management                                │
│  - Window management                                    │
└──────────────┬──────────────────────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────────────────────┐
│                   RecordManager                         │
│  - Orchestrates all monitoring services                 │
│  - Applies intelligent filters                         │
│  - Manages keyboard buffer & cursor tracking            │
└──────┬──────────────┬──────────────┬────────────────────┘
       │              │              │
       ▼              ▼              ▼
┌─────────────┐ ┌──────────────┐ ┌──────────────────┐
│  Keyboard   │ │  Clipboard   │ │  App Focus       │
│  Monitor    │ │  Monitor     │ │  Monitor         │
└──────┬──────┘ └──────┬───────┘ └────────┬─────────┘
       │               │                   │
       └───────────────┴───────────────────┘
                       │
                       ▼
              ┌─────────────────┐
              │  DatabaseService │
              │  - SQLite storage│
              │  - Records       │
              │  - Insights      │
              └────────┬─────────┘
                       │
                       ▼
              ┌─────────────────┐
              │ AIAnalysisService│
              │  - Claude/GPT API│
              │  - Text analysis │
              └──────────────────┘
```

## Project Structure

```
EnglishAI/
├── EnglishAIApp.swift          # App entry point, menu bar, permissions
├── Models/
│   ├── Record.swift            # Text record model
│   └── Insight.swift           # AI analysis result model
├── Services/
│   ├── RecordManager.swift     # Main orchestrator
│   ├── KeyboardMonitorService.swift    # Keyboard event capture
│   ├── ClipboardMonitorService.swift   # Wispr transcription detection
│   ├── AppFocusMonitorService.swift    # Active app tracking
│   ├── DatabaseService.swift           # SQLite operations
│   └── AIAnalysisService.swift         # AI API integration
└── Views/
    ├── ContentView.swift        # Main UI (sidebar + detail)
    ├── InsightsView.swift       # AI analysis display
    └── RecordsWindowController.swift   # Records window
```

## Services

### RecordManager

**Purpose**: Central coordinator for all recording services

**Responsibilities**:
- Manages keyboard buffer with cursor position tracking
- Applies 8-stage filtering pipeline
- Handles deletion (backspace, delete, word, line)
- Tracks cursor navigation (arrows, mouse clicks)
- Flushes buffer on app switch or idle (10s)

**Key Features**:
- Cursor position tracking for mid-text edits
- Mouse click detection (resets cursor, doesn't flush)
- Select-all detection (Cmd+A)
- Terminal app detection with natural language exception

### KeyboardMonitorService

**Purpose**: Captures keyboard events via CGEventTap

**Technology**: CoreGraphics Event Tap API

**Captures**:
- Key presses (characters)
- Backspace/Delete (single, word, line)
- Arrow keys (with modifiers)
- Mouse clicks (left button)

**Permissions**: Requires Accessibility access

**Idle Detection**: 10-second timer triggers buffer flush

### ClipboardMonitorService

**Purpose**: Detects Wispr Flow voice transcriptions

**Detection Pattern**:
1. Clipboard contains text A
2. Wispr copies transcription (text B)
3. Clipboard restored to A within 2.5 seconds
4. → Pattern detected, text B is transcription

**Polling**: 100ms intervals

**Deduplication**: 5-second cooldown for identical text

### AppFocusMonitorService

**Purpose**: Tracks active application

**Technology**: NSWorkspace notifications

**Events**:
- App activation
- App deactivation
- Triggers buffer flush on app switch

### DatabaseService

**Purpose**: SQLite database operations

**Tables**:
- `records`: Text entries (keyboard/wispr)
- `insights`: AI analysis results
- `analysis_sessions`: Analysis metadata

**Location**: `~/Library/Application Support/EnglishAI/records.sqlite`

**Features**:
- WAL mode for concurrent access
- Duplicate detection (60-second window)
- Indexed queries by timestamp, source, date

### AIAnalysisService

**Purpose**: AI-powered text analysis

**Providers**: Anthropic Claude, OpenAI GPT

**Analysis Types**:
- Grammar corrections
- Phrasing improvements
- Vocabulary suggestions
- Positive feedback
- Overall score (1-10)

**Minimum Threshold**: 300 characters

**Storage**: Results saved as JSON in `insights` table

## Filtering System

8-stage filter pipeline applied to all text:

1. **Single Character**: Skip `count <= 1`
2. **Numbers Only**: Skip if all digits
3. **Minimum Length**: Skip if `< 5` non-space chars
4. **Natural Language Check**: Vowel ratio + special char ratio
5. **Terminal Commands**: Shell command patterns
6. **Terminal App + Non-Natural**: Block terminal apps unless natural language
7. **Special Characters**: Skip if `> 25%` code-like chars (non-terminal)
8. **Vowel Ratio**: Skip if `< 20%` vowels (non-terminal)

**Terminal Detection**: Warp, Terminal, iTerm, iTerm2, Alacritty, Hyper, Kitty, WezTerm, Terminator

**Natural Language Detection**:
- Vowel ratio: `vowels / letters >= 0.20`
- Special chars: `codeChars / letters <= 0.25` (excludes `?!.,`)

## User Interface

### ContentView

**Layout**: NavigationSplitView (sidebar + detail)

**Sidebar Sections**:
- **History**: Dates with record counts
- **AI Insights**: Weekly Progress, All Analyses
- **Profile**: Settings access

**Detail Views**:
- **Day Detail**: Records list, filters, analysis
- **Weekly Progress**: Progress visualization
- **All Analyses**: Historical insights

### InsightsView

**Features**:
- Grammar issues with corrections
- Phrasing suggestions
- Vocabulary notes
- Positive feedback
- Overall score card

**Actions**:
- Analyze button (requires API key)
- Settings link
- Error banners

### Menu Bar

**Items**:
- Open EnglishAI (Cmd+O)
- Pause/Resume Recording (Cmd+P)
- Check Permissions
- Reset Permission State
- Quit (Cmd+Q)

## Data Models

### Record

```swift
struct Record {
    let id: Int64?
    let timestamp: Date
    let source: RecordSource  // .keyboard | .wispr
    let content: String
    let activeApp: String
}
```

### Insight

```swift
struct Insight {
    let id: Int64?
    let dateRangeStart: Date
    let dateRangeEnd: Date
    let insightType: InsightType
    let content: String  // JSON-encoded AnalysisResult
    let recordCount: Int
    let characterCount: Int
    let createdAt: Date
}
```

### AnalysisResult

```swift
struct AnalysisResult {
    let grammarIssues: [GrammarIssue]
    let phrasingIssues: [PhrasingIssue]
    let vocabularyInsights: [VocabularyInsight]
    let positives: [String]
    let overallScore: Int  // 1-10
    let summary: String
}
```

## Permissions

### Accessibility

**Required For**: Keyboard monitoring

**Grant Process**:
1. App prompts on first launch
2. Opens System Settings > Privacy & Security > Accessibility
3. User enables EnglishAI
4. App retries check (3 attempts with delays)

**Verification**: `AXIsProcessTrustedWithOptions`

**State Tracking**: UserDefaults (`accessibilityPermissionsGranted`)

**Development vs Production**: The app uses different bundle identifiers for development (`com.englishai.app.dev`) and release (`com.englishai.app`) configurations, which means each version requires its own separate Accessibility permission grant and they will not interfere with each other; additionally, all user data including records, insights, and analysis sessions are stored in `~/Library/Application Support/EnglishAI/records.sqlite` outside the app bundle, ensuring that data persists across app updates and replacements, and both development and production versions share the same database location so you'll see the same records regardless of which version you're running.

## Build & Distribution

### Build Scripts

**create_installer.sh**:
- Builds Release configuration
- Creates DMG installer
- Includes README.txt

**create_pkg_installer.sh**:
- Creates PKG installer
- Professional installer wizard
- Post-install script for permissions

**quick_update.sh**:
- Quick build + open DMG
- For development testing

### Build Requirements

- Xcode with command line tools
- macOS SDK
- Code signing certificate (optional)

### Installation

**DMG Method**:
1. Open DMG
2. Drag app to Applications
3. Grant Accessibility permissions

**PKG Method**:
1. Double-click PKG
2. Follow installer wizard
3. Grant Accessibility permissions

## Configuration

### API Keys

**Storage**: UserDefaults

**Keys**:
- `anthropic_api_key`: Claude API key
- `openai_api_key`: OpenAI API key

**Access**: Settings view in app

**Priority**: Anthropic first, then OpenAI

## Key Constants

| Parameter | Value | Purpose |
|-----------|-------|---------|
| Keyboard idle threshold | 10s | Auto-save delay |
| Clipboard poll interval | 100ms | Detection frequency |
| Wispr restoration window | 2.5s | Pattern matching |
| Debounce delay | 300ms | Duplicate prevention |
| Detection cooldown | 5s | Duplicate suppression |
| Minimum length | 5 chars | Basic filter |
| Vowel ratio threshold | 20% | Natural language |
| Special char threshold | 25% | Code detection |
| Minimum analysis chars | 300 | AI analysis threshold |

## Limitations

1. **Mouse Selection**: Cannot track selected text range
2. **Multi-line Navigation**: Up/Down arrow position uncertain
3. **Paste Operations**: Not tracked (only clipboard changes)
4. **Drag & Drop**: Not detected
5. **Terminal Mouse Edits**: Buffer order may be imperfect after mouse clicks
6. **Password Fields**: Filtered out (numbers-only detection)

## Technical Details

### Event Tap

**Type**: `.cgSessionEventTap`
**Place**: `.headInsertEventTap`
**Mode**: `.listenOnly` (observation only)

**Events Monitored**:
- `keyDown`
- `leftMouseDown`

### Database

**Engine**: SQLite 3
**Mode**: WAL (Write-Ahead Logging)
**Transactions**: IMMEDIATE for inserts

**Indexes**:
- `idx_records_timestamp` (DESC)
- `idx_records_source`
- `idx_insights_date` (DESC)
- `idx_insights_type`
- `idx_analysis_sessions_date` (DESC)

### Threading

**Database Queue**: Serial queue (`com.englishai.database`)
**Wispr Deduplication**: Serial queue (`com.englishai.wispr.dedup`)
**UI Updates**: Main thread via `DispatchQueue.main.async`

## Development

### Key Files

**Entry Point**: `EnglishAIApp.swift`
**Main Coordinator**: `RecordManager.swift`
**UI Root**: `ContentView.swift`

### Testing

1. Run in Xcode
2. Grant Accessibility permissions manually
3. Test keyboard monitoring
4. Test Wispr detection (requires Wispr Flow)
5. Test AI analysis (requires API key)

### Debugging

**Log Prefixes**:
- `[RecordManager]`: Buffer operations, filters
- `[ClipboardMonitor]`: Wispr detection
- `[KeyboardMonitor]`: Event tap events

**Common Issues**:
- Permissions not recognized → Check bundle path
- Buffer not saving → Check idle timer
- Wispr not detected → Check clipboard pattern

## See Also

- `RECORDING_MECHANISMS.md`: Detailed recording documentation
