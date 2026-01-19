# PRD: Voice Recording & Transcription Feature

## Introduction

Add voice recording capability to EnglishAI that allows users to record their own voice during meetings (Zoom, Google Meet, or general conversations) and automatically transcribe the audio using OpenAI's Whisper API. This feature captures only the user's microphone input (not system audio or other participants), providing accurate transcriptions of what the user said. Transcriptions are saved by day and integrated into the existing AI analysis workflow to provide comprehensive English language feedback.

## Goals

- Enable users to record their voice during meetings with a single button press
- Capture only microphone input (user's voice), excluding system audio and other participants
- Automatically transcribe recordings using OpenAI Whisper API when recording stops
- Save transcriptions organized by day for easy review
- Integrate transcriptions into daily/weekly AI analysis for comprehensive English feedback
- Provide manual retry capability for failed transcriptions
- Delete audio files after successful transcription to save storage

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Audio storage | Delete after successful transcription | Save disk space |
| UI location | New dedicated "Recordings" tab | Clear separation of features |
| Transcription language | Always English | Matches app purpose (English learning) |
| Recording indicator | Both app UI + menu bar | Visible even when app is in background |
| Max recording duration | 1 hour | Balance between meeting length and API limits |
| Min recording duration | 10 seconds | Prevent accidental short recordings |
| Stop confirmation | Show dialog | Prevent accidental recording loss |
| App termination during recording | Save audio, transcribe on next launch | Don't lose user's recording |

## User Stories

### US-001: Add Recordings Tab to Main UI
**Description:** As a user, I want a dedicated "Recordings" tab so that I can access all voice recording features in one place.

**Acceptance Criteria:**
- [ ] New "Recordings" tab added to main navigation (alongside existing tabs)
- [ ] Tab shows list of recordings for selected day
- [ ] Empty state message when no recordings exist for the day
- [ ] Consistent styling with existing app UI
- [ ] Typecheck/build passes

### US-002: Create Recording Data Model and Database Schema
**Description:** As a developer, I need to store recording metadata and transcriptions so they persist across sessions.

**Acceptance Criteria:**
- [ ] New `recordings` table in SQLite database with fields:
  - `id` (primary key)
  - `date` (date of recording)
  - `startTime` (timestamp when recording started)
  - `endTime` (timestamp when recording stopped)
  - `duration` (recording length in seconds)
  - `audioFilePath` (temporary path, nullable after transcription)
  - `transcription` (text, nullable until transcribed)
  - `transcriptionStatus` (enum: pending, processing, completed, failed)
  - `errorMessage` (nullable, stores failure reason)
  - `createdAt` (timestamp)
- [ ] DatabaseService methods for CRUD operations on recordings
- [ ] Migration runs successfully without data loss
- [ ] Typecheck/build passes

### US-003: Implement Microphone Recording Service
**Description:** As a user, I want to record my voice using my Mac's microphone so that I can capture what I say during meetings.

**Acceptance Criteria:**
- [ ] New `VoiceRecordingService` singleton that handles audio capture
- [ ] Uses AVFoundation to capture microphone input only (no system audio)
- [ ] Saves audio in M4A format (AAC codec) for Whisper API compatibility
- [ ] Audio files saved to `~/Library/Application Support/EnglishAI/recordings/`
- [ ] Handles microphone permission request gracefully
- [ ] Minimum recording duration enforced at 10 seconds
- [ ] Maximum recording duration enforced at 1 hour
- [ ] Auto-stops recording at 1 hour limit with user notification
- [ ] Typecheck/build passes

### US-004: Add Recording Controls to Recordings Tab
**Description:** As a user, I want start/stop buttons so that I can control when recording happens.

**Acceptance Criteria:**
- [ ] Large, prominent "Start Recording" button when not recording
- [ ] Button changes to "Stop Recording" (red) when recording is active
- [ ] Recording timer displays elapsed time (MM:SS format)
- [ ] Visual waveform or pulsing indicator shows audio is being captured
- [ ] Remaining time indicator shows time until 1-hour limit
- [ ] Stop button disabled until minimum 10 seconds have been recorded
- [ ] Visual indication showing time remaining until stop is available (first 10 seconds)
- [ ] Typecheck/build passes

### US-004b: Stop Recording Confirmation Dialog
**Description:** As a user, I want a confirmation dialog before stopping a recording so that I don't accidentally lose my recording.

**Acceptance Criteria:**
- [ ] Confirmation dialog appears when user presses "Stop Recording"
- [ ] Dialog shows recording duration and asks "Stop recording and transcribe?"
- [ ] Two options: "Cancel" (continue recording) and "Stop & Transcribe"
- [ ] Dialog does not appear if recording is auto-stopped at 1-hour limit
- [ ] Typecheck/build passes

### US-005: Add Menu Bar Recording Indicator
**Description:** As a user, I want to see a recording indicator in the menu bar so that I know recording is active even when the app is in the background.

**Acceptance Criteria:**
- [ ] Menu bar icon changes when recording is active (red dot overlay or color change)
- [ ] Clicking menu bar icon while recording shows quick stop option
- [ ] Indicator visible system-wide regardless of focused app
- [ ] Reverts to normal icon when recording stops
- [ ] Typecheck/build passes

### US-006: Implement Whisper API Integration
**Description:** As a user, I want my recordings automatically transcribed so that I can review what I said in text form.

**Acceptance Criteria:**
- [ ] New `WhisperTranscriptionService` that handles API calls
- [ ] Uses OpenAI Whisper API endpoint (`/v1/audio/transcriptions`)
- [ ] Sends audio file with language parameter set to "en" (English)
- [ ] Handles files up to 25MB (Whisper API limit)
- [ ] For longer recordings, splits audio into chunks and combines transcriptions
- [ ] Updates recording status to "processing" when API call starts
- [ ] Saves transcription text to database on success
- [ ] Stores error message on failure
- [ ] Uses existing OpenAI API key from app settings
- [ ] Typecheck/build passes

### US-007: Auto-Transcribe on Recording Stop
**Description:** As a user, I want transcription to start automatically when I stop recording so that I don't have to manually trigger it.

**Acceptance Criteria:**
- [ ] Transcription begins immediately when user presses "Stop Recording"
- [ ] UI shows "Transcribing..." status with spinner
- [ ] Progress indicator if transcription takes more than a few seconds
- [ ] Success notification when transcription completes
- [ ] Error notification with retry option if transcription fails
- [ ] Typecheck/build passes

### US-008: Display Transcription Results
**Description:** As a user, I want to see the transcription text so that I can review what I said.

**Acceptance Criteria:**
- [ ] Each recording in the list shows:
  - Date and time of recording
  - Duration
  - Status indicator (pending/processing/completed/failed)
  - Transcription preview (first 100 characters)
- [ ] Clicking a recording expands to show full transcription
- [ ] Copy button to copy transcription to clipboard
- [ ] Scroll support for long transcriptions
- [ ] Typecheck/build passes

### US-009: Manual Retry for Failed Transcriptions
**Description:** As a user, I want to retry failed transcriptions manually so that I can recover from temporary API errors.

**Acceptance Criteria:**
- [ ] "Retry" button visible on recordings with failed status
- [ ] Retry button only available if audio file still exists
- [ ] Clear error message explaining why transcription failed
- [ ] Retry follows same flow as auto-transcription
- [ ] Typecheck/build passes

### US-010: Delete Audio After Successful Transcription
**Description:** As a user, I want audio files deleted after successful transcription so that my disk space is preserved.

**Acceptance Criteria:**
- [ ] Audio file automatically deleted after transcription succeeds
- [ ] `audioFilePath` set to null in database after deletion
- [ ] Failed transcriptions retain audio file for retry
- [ ] Pending transcriptions retain audio file
- [ ] Typecheck/build passes

### US-011: Include Transcriptions in AI Analysis
**Description:** As a user, I want my meeting transcriptions included in AI analysis so that I get feedback on my spoken English too.

**Acceptance Criteria:**
- [ ] Modify `AIAnalysisService` to fetch recordings for the analysis period
- [ ] Include transcriptions in the analysis prompt with clear labeling ("Voice Recording Transcriptions:")
- [ ] Transcriptions combined with keyboard/Wispr records for comprehensive analysis
- [ ] AI prompt updated to analyze spoken English patterns
- [ ] Only include completed transcriptions (not failed/pending)
- [ ] Typecheck/build passes

### US-012: Day-Based Recording Organization
**Description:** As a user, I want recordings organized by day so that I can review what I said on specific dates.

**Acceptance Criteria:**
- [ ] Recordings tab shows date picker (consistent with existing date navigation)
- [ ] List shows only recordings from selected day
- [ ] Recording count badge shows number of recordings per day
- [ ] Navigation between days matches existing app patterns
- [ ] Typecheck/build passes

### US-013: Microphone Permission Handling
**Description:** As a user, I want clear guidance when microphone permission is needed so that I can grant access and start recording.

**Acceptance Criteria:**
- [ ] Check microphone permission status on app launch
- [ ] Show permission request dialog when user first tries to record
- [ ] Display helpful message if permission is denied
- [ ] Provide button to open System Preferences > Privacy > Microphone
- [ ] Gracefully handle permission changes during runtime
- [ ] Typecheck/build passes

### US-014: Handle App Termination During Recording
**Description:** As a user, I want my recording saved if the app closes unexpectedly so that I don't lose my audio and can transcribe it later.

**Acceptance Criteria:**
- [ ] Detect app termination (quit, crash, force quit) while recording is active
- [ ] Automatically save current audio file before app terminates
- [ ] Create database entry with status "pending" for interrupted recordings
- [ ] On next app launch, detect any pending recordings with audio files
- [ ] Show notification/prompt to user about recovered recordings
- [ ] Allow user to manually trigger transcription for recovered recordings
- [ ] "Transcribe" button visible on recordings with pending status and existing audio file
- [ ] Typecheck/build passes

## Functional Requirements

- **FR-1:** The system must capture audio only from the user's microphone input, not system audio or other meeting participants
- **FR-2:** The system must save audio files in M4A format (AAC codec) compatible with OpenAI Whisper API
- **FR-3:** The system must enforce a minimum recording duration of 10 seconds
- **FR-4:** The system must limit individual recordings to a maximum of 1 hour duration
- **FR-5:** The system must automatically stop recording and notify the user when the 1-hour limit is reached
- **FR-6:** The system must display a visual recording indicator in both the app UI and menu bar
- **FR-7:** The system must show a confirmation dialog before stopping a recording (except for auto-stop at limit)
- **FR-8:** The system must automatically initiate transcription when the user confirms stop
- **FR-9:** The system must use the OpenAI Whisper API with language set to English ("en")
- **FR-10:** The system must handle audio files larger than 25MB by splitting into chunks
- **FR-11:** The system must delete audio files immediately after successful transcription
- **FR-12:** The system must retain audio files for recordings with failed transcriptions to enable retry
- **FR-13:** The system must store all recording metadata and transcriptions in the SQLite database
- **FR-14:** The system must include completed transcriptions in daily/weekly AI analysis
- **FR-15:** The system must request microphone permission before first recording attempt
- **FR-16:** The system must allow manual retry of failed transcriptions while audio file exists
- **FR-17:** The system must save audio and create a pending record if the app terminates during recording
- **FR-18:** The system must detect and notify users of recovered recordings on app launch
- **FR-19:** The system must allow manual transcription trigger for pending/recovered recordings

## Non-Goals (Out of Scope)

- Recording system audio or other meeting participants (explicitly excluded per requirements)
- Speaker diarization (identifying different speakers)
- Real-time transcription during recording
- Audio playback functionality
- Audio editing or trimming
- Transcription in languages other than English
- Automatic meeting detection (user must manually start recording)
- Integration with specific meeting apps (Zoom, Meet APIs)
- Cloud storage of recordings or transcriptions
- Sharing or exporting transcriptions to other formats
- Configurable audio quality settings
- Keyboard shortcuts for recording control

## Technical Considerations

### Audio Capture
- Use `AVFoundation` framework for microphone access
- Configure `AVAudioSession` for recording category
- Use `AVAudioRecorder` with M4A/AAC format settings:
  - Format: `.m4a` (AAC)
  - Sample rate: 44100 Hz
  - Channels: 1 (mono)
  - Quality: High

### File Management
- Audio files stored in: `~/Library/Application Support/EnglishAI/recordings/`
- Filename format: `recording_[timestamp].m4a`
- Implement cleanup routine for orphaned audio files on app launch

### Whisper API Integration
- Endpoint: `https://api.openai.com/v1/audio/transcriptions`
- Model: `whisper-1`
- File size limit: 25MB per request
- For files > 25MB: Split audio using AVAssetExportSession, transcribe chunks, concatenate results
- Reuse existing OpenAI API key from `SettingsService`

### Database
- Add new `recordings` table to existing SQLite database
- Follow existing patterns in `DatabaseService` for thread safety
- Use serial queue for database operations

### Threading
- Audio recording on dedicated background thread
- API calls on background thread
- UI updates via `DispatchQueue.main.async`
- New serial queue: `com.englishai.voicerecording`

### Menu Bar Integration
- Extend existing menu bar functionality (if present) or create new `NSStatusItem`
- Use SF Symbols for recording indicator

### App Termination Handling
- Register for `NSApplication.willTerminateNotification` to detect app quit
- Implement `applicationWillTerminate(_:)` in AppDelegate
- Finalize and save audio file before termination completes
- Mark recording as "pending" in database with audio file path
- On launch, query for recordings with status "pending" and valid audio file

## Success Metrics

- Users can start and stop recording within 1 tap/click
- Transcription completes successfully for 95%+ of recordings under normal network conditions
- Audio files are deleted within 5 seconds of successful transcription
- Recording indicator is visible within 500ms of starting recording
- Transcriptions appear in AI analysis results when analyzing days with recordings
- Failed transcriptions can be retried successfully after transient errors

## Open Questions

1. Should we add a "recording scheduled" feature for future meetings?
2. Should transcription errors trigger a system notification if the app is in the background?
