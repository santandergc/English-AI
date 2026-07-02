# Recording Mechanisms

## Overview

EnglishAI records text from two sources:
1. **Wispr Flow** - Voice transcription via clipboard monitoring
2. **Keyboard Typing** - Direct keystroke capture

---

## Wispr Flow Transcription

### How It Works

Wispr Flow copies transcribed text to clipboard using a specific pattern:
1. Clipboard contains text A
2. Wispr copies transcription (text B) to clipboard
3. Clipboard is restored to text A within 2.5 seconds

### Detection Algorithm

**ClipboardMonitorService** polls clipboard every 100ms:

```
State Machine:
- previousContent: Last known clipboard state
- pendingContent: New clipboard content detected
- pendingTimestamp: When new content appeared

Pattern Detection:
IF (current == previous) AND (pending != previous) AND (elapsed < 2.5s)
THEN → Wispr transcription detected
```

### Processing Flow

1. **Debounce**: 300ms delay to avoid duplicates
2. **Cooldown**: Skip identical text detected within 5 seconds
3. **Filters Applied**: Same as keyboard (see below)
4. **Deduplication**: In-memory set prevents duplicates for 5 seconds

### Key Properties

- **Poll Interval**: 100ms
- **Restoration Threshold**: 2.5 seconds
- **Debounce Delay**: 300ms
- **Detection Cooldown**: 5 seconds

---

## Keyboard Typing

### Architecture

**KeyboardMonitorService** uses `CGEventTap` to intercept:
- Key down events
- Mouse clicks (left button)

**RecordManager** maintains:
- `keyboardBuffer`: Accumulated text
- `cursorPosition`: Current insertion point
- `bufferAppContext`: Active app name

### Cursor Tracking

**Arrow Keys**:
- Left/Right: Move cursor 1 character
- Option+Left/Right: Move by word
- Cmd+Left/Right: Move to line start/end
- Up/Down: Tracked but position uncertain

**Mouse Click**:
- Resets cursor to buffer end
- Does NOT flush buffer (preserves complete text)

### Deletion Handling

| Action | Behavior |
|--------|----------|
| Backspace | Delete char before cursor |
| Delete | Delete char after cursor |
| Option+Backspace | Delete word backward |
| Option+Delete | Delete word forward |
| Cmd+Backspace | Delete to line start |
| Cmd+Delete | Delete to line end |
| Cmd+A + Delete | Clear entire buffer |

### Save Triggers

Buffer is saved (flushed) when:
1. **App Switch**: User changes active application
2. **Idle**: 10 seconds of no keyboard activity
3. **Manual**: Pause/resume or stop monitoring

### Buffer Lifecycle

```
Type → Append to buffer at cursor position
Edit → Modify buffer at cursor position
Navigate → Update cursor position
Save Trigger → Apply filters → Save to DB → Clear buffer
```

---

## Filtering System

### Privacy Gate

All keyboard and Wispr text goes through `CapturePrivacyFilter` before it can be saved.

For keyboard events, sensitive input protection also runs **before** characters enter the in-memory buffer. If the focused field is private, the current buffer is discarded and the keystroke is ignored.

Sensitive input detection uses:
- macOS Accessibility focused element metadata
- `AXSecureTextField` subrole
- sensitive field labels/placeholders such as password, passcode, OTP, verification code, token, API key, private key, CVV, and Spanish equivalents like `contraseña`, `clave`, and `código de seguridad`
- built-in and user-configurable excluded apps such as password managers and Keychain Access
- an unconditional self-capture block so EnglishAI never records typing inside its own Settings/API-key fields

### Language Filtering

Spanish filtering is local-only through Apple's `NaturalLanguage` framework plus a small lexical fallback for short Spanish phrases. Text is split into sentence-like segments; Spanish-dominant segments are dropped and English/unknown segments continue through the normal quality filters. If nothing remains, the record is skipped.

No network API is called to decide whether text is safe to store.

### Quality Filter Order (Applied Sequentially)

**FILTER 1**: Single character
- Skip if `count <= 1`

**FILTER 2**: Numbers only
- Skip if all characters are digits

**FILTER 3**: Minimum length
- Skip if `< 5` non-space characters

**FILTER 4**: Natural language check
- Calculate: `hasEnoughVowels` AND `!hasTooManySpecialCharacters`

**FILTER 5**: Terminal commands
- Skip if matches shell command patterns

**FILTER 6**: Terminal app + non-natural language
- Skip if from terminal app AND not natural language

**FILTER 7**: Special characters (non-terminal)
- Skip if `> 25%` code-like special chars (excludes `?!.,`)

**FILTER 8**: Vowel ratio (non-terminal)
- Skip if `< 20%` vowels in letters

### Terminal Detection

**Terminal Apps**: Warp, Terminal, iTerm, iTerm2, Alacritty, Hyper, Kitty, WezTerm, Terminator

**Command Patterns**:
- Starts with shell command (`cd`, `ls`, `git`, etc.)
- Multiple short words (`cd .. ls`)
- Path patterns (`/path`, `.file`)
- Command chaining (`|`, `&&`, `||`, `;`)

**Special Handling**:
- Terminal apps allow natural language (e.g., LLM conversations)
- Non-terminal apps apply stricter filters

### Natural Language Detection

**Vowel Ratio**: `vowelCount / letterCount >= 0.20`

**Special Character Ratio**: 
- With letters: `codeChars / letters <= 0.25`
- No letters: `codeChars / total <= 0.20`
- Excludes: `?!.,` (normal punctuation)

---

## Data Flow

```
┌─────────────────┐
│ Keyboard Events │
└────────┬────────┘
         │
         ▼
┌─────────────────┐     ┌──────────────┐
│ KeyboardMonitor │────▶│ RecordManager│
└─────────────────┘     └──────┬───────┘
                                │
┌─────────────────┐             │
│ ClipboardMonitor│─────────────┘
└────────┬────────┘
         │
         ▼
┌─────────────────┐     ┌──────────────┐
│ Clipboard Poll  │────▶│ Pattern Match│
└─────────────────┘     └──────┬───────┘
                                │
                                ▼
                         ┌──────────────┐
                         │ Apply Filters│
                         └──────┬───────┘
                                │
                                ▼
                         ┌──────────────┐
                         │ Database Save │
                         └───────────────┘
```

---

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
| Sensitive input cache | 150ms positive-only | Avoid repeated AX checks while never caching a safe result |

---

## Limitations

1. **Mouse Selection**: Cannot track selected text range
2. **Multi-line Navigation**: Up/Down arrow position uncertain
3. **Paste Operations**: Not tracked (only clipboard changes)
4. **Drag & Drop**: Not detected
5. **Terminal Mouse Edits**: Buffer order may be imperfect after mouse clicks

---

## Privacy & Permissions

- **Accessibility**: Required for keyboard monitoring
- **Event Tap**: System-level keyboard event interception
- **Clipboard Access**: Required for Wispr detection
- **App Focus**: Tracks active application context
