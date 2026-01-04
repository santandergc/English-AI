# EnglishAI - Product Registry

## Product Overview

**EnglishAI** is a macOS native application that monitors, records, and analyzes English text input to help users improve their language skills. The application operates as a background service, capturing keyboard input and voice transcriptions across all applications, then providing AI-powered analysis and progress tracking.

**Product Type**: macOS Desktop Application  
**Platform**: macOS 13.0+  
**Architecture**: Native Swift/SwiftUI  
**Current Version**: 1.0  
**Bundle Identifiers**: 
- Production: `com.englishai.app`
- Development: `com.englishai.app.dev`

## Core Functionality

### What the Product Does

EnglishAI performs three primary functions:

1. **Text Capture**: Monitors keyboard input system-wide using macOS Accessibility APIs and detects voice transcriptions via clipboard monitoring
2. **Data Storage**: Persists captured text and metadata in a local SQLite database
3. **AI Analysis**: Provides on-demand analysis of recorded text using external AI APIs (Claude/GPT)

### Technical Implementation

**Text Capture Mechanism**:
- Uses `CGEventTap` API with `.cgSessionEventTap` type
- Event tap placed at `.headInsertEventTap` position
- Operates in `.listenOnly` mode (observation only, no event modification)
- Monitors `keyDown` and `leftMouseDown` events
- Requires Accessibility permissions for keyboard monitoring

**Recording Services**:
- `KeyboardMonitorService`: Captures keyboard events via CGEventTap
- `ClipboardMonitorService`: Detects Wispr Flow transcriptions via clipboard pattern matching
- `AppFocusMonitorService`: Tracks active application using NSWorkspace notifications
- `RecordManager`: Orchestrates all services and applies filtering pipeline

**Data Storage**:
- SQLite 3 database with WAL (Write-Ahead Logging) mode
- Location: `~/Library/Application Support/EnglishAI/records.sqlite`
- Tables: `records`, `insights`, `analysis_sessions`
- Indexed queries for timestamp, source, and date-based retrieval
- IMMEDIATE transaction mode for inserts to prevent race conditions

## Features

### ✅ Implemented Features

#### 1. Keyboard Input Monitoring
- **Status**: ✅ Implemented
- **Technology**: CGEventTap API
- **Capabilities**:
  - Captures all keyboard input system-wide
  - Tracks cursor position for mid-text edits
  - Handles backspace, delete, word deletion, line deletion
  - Supports arrow key navigation tracking
  - Detects mouse clicks (resets cursor position)
  - Handles select-all operations (Cmd+A)
- **Buffer Management**:
  - 10-second idle timer triggers automatic flush
  - Flushes on application switch
  - Maintains cursor position across edits
- **Permissions Required**: Accessibility

#### 2. Voice Transcription Detection (Wispr Flow)
- **Status**: ✅ Implemented
- **Technology**: Clipboard monitoring with pattern detection
- **Detection Pattern**:
  1. Clipboard contains text A
  2. Wispr copies transcription (text B)
  3. Clipboard restored to A within 2.5 seconds
  4. Pattern detected → text B is transcription
- **Polling Interval**: 100ms
- **Deduplication**: 5-second cooldown for identical content
- **Permissions Required**: None (uses clipboard API)

#### 3. Intelligent Text Filtering
- **Status**: ✅ Implemented
- **Filter Pipeline**: 8-stage filtering system
  1. Single character filter (skip count <= 1)
  2. Numbers-only filter (skip all digits)
  3. Minimum length filter (skip < 5 non-space chars)
  4. Natural language detection (vowel ratio + special char ratio)
  5. Terminal command pattern detection
  6. Terminal app + non-natural language filter
  7. Special character ratio filter (> 25% code-like chars)
  8. Vowel ratio filter (< 20% vowels)
- **Terminal Detection**: Warp, Terminal, iTerm, iTerm2, Alacritty, Hyper, Kitty, WezTerm, Terminator
- **Natural Language Criteria**:
  - Vowel ratio: `vowels / letters >= 0.20`
  - Special chars: `codeChars / letters <= 0.25` (excludes `?!.,`)

#### 4. Database Storage
- **Status**: ✅ Implemented
- **Database Engine**: SQLite 3
- **Mode**: WAL (Write-Ahead Logging)
- **Tables**:
  - `records`: Text entries with timestamp, source, content, active_app
  - `insights`: AI analysis results with date ranges and JSON content
  - `analysis_sessions`: Analysis metadata and statistics
- **Indexes**:
  - `idx_records_timestamp` (DESC)
  - `idx_records_source`
  - `idx_insights_date` (DESC)
  - `idx_insights_type`
  - `idx_analysis_sessions_date` (DESC)
- **Features**:
  - Duplicate detection (60-second window)
  - Thread-safe operations via serial dispatch queue
  - Data persistence across app updates

#### 5. AI-Powered Text Analysis
- **Status**: ✅ Implemented
- **Providers**: Anthropic Claude (primary), OpenAI GPT (fallback)
- **Analysis Types**:
  - Grammar corrections with specific suggestions
  - Phrasing improvements
  - Vocabulary insights
  - Positive feedback recognition
  - Overall score (1-10 scale)
- **Minimum Threshold**: 300 characters
- **Storage**: Results saved as JSON in `insights` table
- **Configuration**: API keys stored in UserDefaults, configurable via Settings UI

#### 6. User Interface
- **Status**: ✅ Implemented
- **Framework**: SwiftUI
- **Layout**: NavigationSplitView (sidebar + detail)
- **Sections**:
  - History: Date-based record browsing with counts
  - AI Insights: Weekly Progress, All Analyses
  - Profile: Settings access
- **Views**:
  - Day Detail View: Records list with filters and analysis
  - Weekly Progress View: Progress visualization
  - All Analyses View: Historical insights
  - Insights View: Detailed analysis display
- **Menu Bar Integration**:
  - Open EnglishAI (Cmd+O)
  - Pause/Resume Recording (Cmd+P)
  - Check Permissions
  - Reset Permission State
  - Quit (Cmd+Q)

#### 7. Progress Tracking
- **Status**: ✅ Implemented
- **Features**:
  - Date-based record browsing
  - Record count per day
  - Source filtering (keyboard vs. wispr)
  - Application context tracking
  - Weekly progress visualization
  - Analysis history review

#### 8. Permission Management
- **Status**: ✅ Implemented
- **Permissions Required**: Accessibility (for keyboard monitoring)
- **Grant Process**:
  1. App prompts on first launch
  2. Opens System Settings > Privacy & Security > Accessibility
  3. User enables EnglishAI
  4. App retries check (3 attempts with delays)
- **Verification**: `AXIsProcessTrustedWithOptions`
- **State Tracking**: UserDefaults (`accessibilityPermissionsGranted`)

### ❌ Known Limitations

1. **Mouse Selection**: Cannot track selected text range
2. **Multi-line Navigation**: Up/Down arrow position uncertain
3. **Paste Operations**: Not tracked (only clipboard changes detected)
4. **Drag & Drop**: Not detected
5. **Terminal Mouse Edits**: Buffer order may be imperfect after mouse clicks
6. **Password Fields**: Filtered out (numbers-only detection)

## Technical Requirements

### System Requirements
- **macOS**: 13.0 (Ventura) or later
- **Architecture**: Apple Silicon (arm64) or Intel (x86_64)
- **Memory**: Minimal (background service)
- **Storage**: ~10MB app size + database growth over time

### Required Permissions
- **Accessibility**: Required for keyboard monitoring via CGEventTap
  - Requested automatically on first launch
  - Can be revoked via System Settings
  - Separate permissions for dev and production builds

### Optional Dependencies
- **API Keys**: Anthropic Claude or OpenAI GPT (for AI analysis features)
- **Wispr Flow**: Third-party app for voice transcription support

### Development Requirements
- **Xcode**: Latest version with command line tools
- **macOS SDK**: Included with Xcode
- **Code Signing**: Optional (Apple Developer account recommended)

## Data Architecture

### Database Schema

**records Table**:
```sql
CREATE TABLE records (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp REAL NOT NULL,
    source TEXT NOT NULL CHECK(source IN ('keyboard', 'wispr')),
    content TEXT NOT NULL,
    active_app TEXT NOT NULL
);
```

**insights Table**:
```sql
CREATE TABLE insights (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    date_range_start REAL NOT NULL,
    date_range_end REAL NOT NULL,
    insight_type TEXT NOT NULL,
    content TEXT NOT NULL,
    record_count INTEGER NOT NULL,
    character_count INTEGER NOT NULL,
    created_at REAL NOT NULL
);
```

**analysis_sessions Table**:
```sql
CREATE TABLE analysis_sessions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    analyzed_at REAL NOT NULL,
    date_range_start REAL NOT NULL,
    date_range_end REAL NOT NULL,
    records_analyzed INTEGER NOT NULL,
    characters_analyzed INTEGER NOT NULL
);
```

### Data Storage Location
- **Database**: `~/Library/Application Support/EnglishAI/records.sqlite`
- **UserDefaults**: Standard macOS UserDefaults for settings and API keys
- **Data Persistence**: All data stored outside app bundle, persists across updates

### Threading Model
- **Database Queue**: Serial queue (`com.englishai.database`)
- **Wispr Deduplication**: Serial queue (`com.englishai.wispr.dedup`)
- **UI Updates**: Main thread via `DispatchQueue.main.async`

## Configuration

### Build Configurations
- **Debug**: Bundle ID `com.englishai.app.dev`
- **Release**: Bundle ID `com.englishai.app`
- **Data Sharing**: Both configurations share the same database location

### User Configuration
- **API Keys**: Stored in UserDefaults
  - `anthropic_api_key`: Claude API key
  - `openai_api_key`: OpenAI API key
- **Settings**: Accessible via Profile section in UI

### Key Constants
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

## Current State

### ✅ Completed Features
- [x] Keyboard input monitoring
- [x] Voice transcription detection (Wispr Flow)
- [x] 8-stage intelligent filtering pipeline
- [x] SQLite database with WAL mode
- [x] AI analysis integration (Claude/GPT)
- [x] SwiftUI user interface
- [x] Menu bar integration
- [x] Progress tracking and visualization
- [x] Permission management
- [x] Data persistence across updates
- [x] Duplicate detection
- [x] Cursor position tracking
- [x] App context awareness

### 🔄 In Progress
- None currently

### ❌ Not Implemented
- Paste operation tracking
- Drag & drop detection
- Multi-line navigation accuracy improvements
- Mouse selection range tracking

## Roadmap / What's Next (EXAMPLES)

### Short-term (Next Release)
- [ ] Export functionality (CSV, JSON, PDF)
- [ ] Data backup/restore feature
- [ ] Enhanced filtering options in UI
- [ ] Search functionality across records
- [ ] Statistics dashboard improvements
- [ ] Dark mode optimization

### Medium-term
- [ ] Multiple language support (beyond English)
- [ ] Custom filter rules configuration
- [ ] Advanced analytics and insights
- [ ] Integration with more voice transcription services
- [ ] Cloud sync option (optional)
- [ ] Keyboard shortcuts customization
- [ ] Batch analysis operations

### Long-term
- [ ] Machine learning model for local analysis (privacy-focused)
- [ ] Collaborative features (shared progress, challenges)
- [ ] Mobile companion app (iOS)
- [ ] Browser extension for web-based writing
- [ ] Integration with writing tools (Grammarly, etc.)
- [ ] Custom AI model fine-tuning
- [ ] Advanced progress visualization (charts, trends)

### Technical Improvements
- [ ] Performance optimization for large datasets
- [ ] Database migration system for schema updates
- [ ] Enhanced error handling and recovery
- [ ] Unit and integration test coverage
- [ ] Accessibility improvements (VoiceOver support)
- [ ] Internationalization (i18n) support

## Build & Distribution

### Build Scripts
- **create_installer.sh**: Builds Release configuration and creates DMG installer
- **create_pkg_installer.sh**: Creates PKG installer with post-install script
- **quick_update.sh**: Quick build + open DMG for development testing

### Installation Methods
- **DMG**: Drag-and-drop installation
- **PKG**: Professional installer wizard with post-install permissions guidance

### Code Signing
- Supports Apple Developer code signing
- Development builds use development certificate
- Release builds use distribution certificate (when configured)

## Privacy & Security

### Data Handling
- **Local Storage**: All data stored locally on user's Mac
- **No Telemetry**: No usage data sent to external servers
- **AI Analysis**: Text sent to AI providers only when user explicitly requests analysis
- **API Keys**: Stored securely in macOS UserDefaults

### Permissions
- **Accessibility**: Required for keyboard monitoring, can be revoked anytime
- **No Network Access**: App does not require network permissions (except for AI API calls)
- **No File System Access**: Only accesses its own Application Support directory

## Development Notes

### Key Files
- **Entry Point**: `EnglishAIApp.swift`
- **Main Coordinator**: `RecordManager.swift`
- **UI Root**: `ContentView.swift`
- **Services**: `KeyboardMonitorService.swift`, `ClipboardMonitorService.swift`, `AppFocusMonitorService.swift`, `DatabaseService.swift`, `AIAnalysisService.swift`

### Debugging
- **Log Prefixes**:
  - `[RecordManager]`: Buffer operations, filters
  - `[ClipboardMonitor]`: Wispr detection
  - `[KeyboardMonitor]`: Event tap events

### Common Issues
- Permissions not recognized → Check bundle path
- Buffer not saving → Check idle timer
- Wispr not detected → Check clipboard pattern

---

**Last Updated**: 2024-01-04  
**Document Version**: 1.0  
**Maintainer**: Product Registry
