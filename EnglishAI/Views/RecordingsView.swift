import SwiftUI
import UserNotifications

struct RecordingsView: View {
    @State private var selectedDate: Date = Date()
    @State private var recordings: [VoiceRecording] = []
    @ObservedObject private var recordingService = VoiceRecordingService.shared
    @State private var permissionStatus: MicrophonePermissionStatus = .notDetermined
    @State private var pulseAnimation: Bool = false
    @State private var showStopConfirmation: Bool = false
    @State private var durationAtStopRequest: TimeInterval = 0
    @State private var isTranscribing: Bool = false
    @State private var transcribingRecordingId: Int64? = nil

    private let database = DatabaseService.shared
    private let permissionService = MicrophonePermissionService.shared
    private let transcriptionService = WhisperTranscriptionService.shared

    var body: some View {
        VStack(spacing: 0) {
            // Header with date navigation
            HStack {
                // Previous day button
                Button(action: { navigateDay(by: -1) }) {
                    Image(systemName: "chevron.left")
                        .font(.title3)
                }
                .buttonStyle(.borderless)
                .help("Previous day")

                Spacer()

                // Date display with picker
                VStack(spacing: 2) {
                    Text(formatDateHeader(selectedDate))
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text(formatDateSubtitle(selectedDate))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Next day button
                Button(action: { navigateDay(by: 1) }) {
                    Image(systemName: "chevron.right")
                        .font(.title3)
                }
                .buttonStyle(.borderless)
                .disabled(Calendar.current.isDateInToday(selectedDate))
                .help("Next day")

                // Date picker
                DatePicker("", selection: $selectedDate, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .frame(width: 30)
                    .onChange(of: selectedDate) { _ in
                        loadRecordings()
                    }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Recording controls
            VStack(spacing: 16) {
                Spacer()

                // Recording indicator and timer
                if recordingService.isRecording {
                    recordingIndicatorView
                } else {
                    // Idle state icon
                    Image(systemName: "mic.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Voice Recordings")
                        .font(.title3)
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                    Text("Record your voice and get transcriptions")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Start/Stop button
                recordingButton

                // Permission status warning
                if permissionStatus == .denied {
                    permissionDeniedView
                }

                // Transcribing indicator
                if isTranscribing {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Transcribing...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 16)
                }

                Spacer()
            }
            .frame(maxHeight: recordingService.isRecording ? .infinity : 280)

            Divider()

            // Recordings list section
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Recordings")
                        .font(.headline)
                    Spacer()
                    if !recordings.isEmpty {
                        Text("\(recordings.count) recording\(recordings.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 12)

                if recordings.isEmpty {
                    // Empty state
                    VStack {
                        Spacer()
                        Image(systemName: "waveform")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        Text("No recordings for this day")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.top, 8)
                        Text("Use the Start Recording button above to record your voice")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, minHeight: 150)
                } else {
                    // Recordings list
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(recordings) { recording in
                                RecordingRowView(
                                    recording: recording,
                                    isCurrentlyTranscribing: transcribingRecordingId == recording.id,
                                    onCopy: { copyToClipboard(recording.transcription ?? "") },
                                    onRetry: { retryTranscription(for: recording) }
                                )
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom)
                    }
                }
            }
        }
        .onAppear {
            loadRecordings()
            checkMicrophonePermission()
            recoverInterruptedRecordings()
        }
        .onReceive(NotificationCenter.default.publisher(for: .recordingAutoStopped)) { notification in
            // Handle auto-stop at 1-hour limit - no confirmation dialog needed
            handleAutoStoppedRecording(notification: notification)
        }
        .alert("Stop Recording?", isPresented: $showStopConfirmation) {
            Button("Cancel", role: .cancel) {
                // Continue recording - no action needed
            }
            Button("Stop & Transcribe", role: .destructive) {
                confirmStopRecording()
            }
        } message: {
            Text("You have recorded \(formatDuration(durationAtStopRequest)). Stop and transcribe this recording?")
        }
    }

    // MARK: - Recording Indicator View

    private var recordingIndicatorView: some View {
        VStack(spacing: 12) {
            // Pulsing red dot with elapsed time
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 12, height: 12)
                    .scaleEffect(pulseAnimation ? 1.2 : 1.0)
                    .opacity(pulseAnimation ? 0.7 : 1.0)
                    .animation(
                        Animation.easeInOut(duration: 0.8)
                            .repeatForever(autoreverses: true),
                        value: pulseAnimation
                    )

                Text("Recording")
                    .font(.headline)
                    .foregroundColor(.red)
            }
            .onAppear {
                pulseAnimation = true
            }
            .onDisappear {
                pulseAnimation = false
            }

            // Elapsed time in MM:SS format
            Text(formatDuration(recordingService.currentDuration))
                .font(.system(size: 48, weight: .medium, design: .monospaced))
                .foregroundColor(.primary)

            // Time remaining until 1-hour limit
            Text("Time remaining: \(formatDuration(recordingService.timeRemaining))")
                .font(.caption)
                .foregroundColor(.secondary)

            // Minimum duration countdown if still in first 10 seconds
            if !recordingService.canStop {
                let secondsUntilCanStop = Int(ceil(VoiceRecordingService.minimumDuration - recordingService.currentDuration))
                Text("Can stop in \(secondsUntilCanStop) seconds")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
    }

    // MARK: - Recording Button

    private var recordingButton: some View {
        Group {
            if recordingService.isRecording {
                // Stop Recording button
                Button(action: handleStopRecording) {
                    HStack {
                        Image(systemName: "stop.fill")
                        Text("Stop Recording")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(recordingService.canStop ? Color.red : Color.red.opacity(0.5))
                    .cornerRadius(25)
                }
                .buttonStyle(.plain)
                .disabled(!recordingService.canStop)
                .help(recordingService.canStop ? "Stop recording" : "Minimum recording time not reached")
            } else {
                // Start Recording button
                Button(action: handleStartRecording) {
                    HStack {
                        Image(systemName: "mic.fill")
                        Text("Start Recording")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(permissionStatus == .denied ? Color.green.opacity(0.5) : Color.green)
                    .cornerRadius(25)
                }
                .buttonStyle(.plain)
                .disabled(permissionStatus == .denied)
                .help(permissionStatus == .denied ? "Microphone permission required" : "Start recording")
            }
        }
        .padding(.top, 16)
    }

    // MARK: - Permission Denied View

    private var permissionDeniedView: some View {
        VStack(spacing: 8) {
            Text("Microphone access is required")
                .font(.caption)
                .foregroundColor(.orange)

            Button("Open System Preferences") {
                permissionService.openSystemPreferences()
            }
            .font(.caption)
        }
        .padding(.top, 8)
    }

    // MARK: - Date Navigation

    private func navigateDay(by offset: Int) {
        if let newDate = Calendar.current.date(byAdding: .day, value: offset, to: selectedDate) {
            selectedDate = newDate
            loadRecordings()
        }
    }

    private func loadRecordings() {
        let dayStart = Calendar.current.startOfDay(for: selectedDate)
        DispatchQueue.global(qos: .userInitiated).async {
            let fetchedRecordings = database.getRecordingsForDate(dayStart)
            DispatchQueue.main.async {
                self.recordings = fetchedRecordings
            }
        }
    }

    // MARK: - Date Formatting

    private func formatDateHeader(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE"
            return formatter.string(from: date)
        }
    }

    private func formatDateSubtitle(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }

    // MARK: - Duration Formatting

    private func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(duration)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    // MARK: - Recording Actions

    private func handleStartRecording() {
        // Check permission first
        if permissionStatus == .notDetermined {
            Task {
                let granted = await permissionService.requestPermission()
                await MainActor.run {
                    permissionStatus = granted ? .authorized : .denied
                    if granted {
                        startRecording()
                    }
                }
            }
        } else if permissionStatus == .authorized {
            startRecording()
        }
    }

    private func startRecording() {
        _ = recordingService.startRecording()
    }

    private func handleStopRecording() {
        // Capture current duration for the confirmation dialog
        durationAtStopRequest = recordingService.currentDuration
        // Show confirmation dialog
        showStopConfirmation = true
    }

    private func confirmStopRecording() {
        // User confirmed stop - stop recording and get audio file URL
        guard let audioFileURL = recordingService.stopRecording() else {
            print("[RecordingsView] Failed to stop recording or get audio file URL")
            loadRecordings()
            return
        }

        // Start transcription flow
        startTranscription(audioFileURL: audioFileURL, duration: durationAtStopRequest)
    }

    private func handleAutoStoppedRecording(notification: Notification) {
        // Recording was auto-stopped at 1-hour limit - no confirmation dialog needed
        // Get audio file URL from notification userInfo
        guard let userInfo = notification.userInfo,
              let audioFileURL = userInfo["audioFileURL"] as? URL else {
            print("[RecordingsView] Auto-stopped recording but no audio file URL in notification")
            loadRecordings()
            return
        }

        // Start transcription flow with max duration
        startTranscription(audioFileURL: audioFileURL, duration: VoiceRecordingService.maximumDuration)
    }

    private func startTranscription(audioFileURL: URL, duration: TimeInterval) {
        let now = Date()
        let startTime = now.addingTimeInterval(-duration)

        // Create recording with 'processing' status
        let recording = VoiceRecording(
            date: Calendar.current.startOfDay(for: now),
            startTime: startTime,
            endTime: now,
            duration: duration,
            audioFilePath: audioFileURL.path,
            transcription: nil,
            transcriptionStatus: .processing,
            errorMessage: nil,
            createdAt: now
        )

        // Insert into database
        guard let recordingId = database.createRecording(recording) else {
            print("[RecordingsView] Failed to create recording in database")
            loadRecordings()
            return
        }

        // Update UI state
        DispatchQueue.main.async {
            self.isTranscribing = true
            self.transcribingRecordingId = recordingId
            self.loadRecordings()
        }

        // Start async transcription
        Task {
            await performTranscription(recordingId: recordingId, audioFilePath: audioFileURL.path)
        }
    }

    private func performTranscription(recordingId: Int64, audioFilePath: String) async {
        do {
            // Call Whisper API
            let transcriptionText = try await transcriptionService.transcribe(audioFilePath: audioFilePath)

            // Update recording with success
            if var recording = database.getRecordingById(recordingId) {
                recording.transcription = transcriptionText
                recording.transcriptionStatus = .completed
                recording.errorMessage = nil

                // Delete audio file after successful transcription to save disk space
                deleteAudioFile(at: audioFilePath)
                recording.audioFilePath = nil

                database.updateRecording(recording)
            }

            // Update UI and show success notification
            await MainActor.run {
                isTranscribing = false
                transcribingRecordingId = nil
                loadRecordings()
                showTranscriptionNotification(success: true, message: "Transcription completed successfully")
            }

        } catch {
            // Update recording with failure
            // Note: Do NOT delete audio file on failure - user may want to retry
            let errorMessage = (error as? WhisperTranscriptionError)?.errorDescription ?? error.localizedDescription

            if var recording = database.getRecordingById(recordingId) {
                recording.transcriptionStatus = .failed
                recording.errorMessage = errorMessage
                database.updateRecording(recording)
            }

            // Update UI and show failure notification
            await MainActor.run {
                isTranscribing = false
                transcribingRecordingId = nil
                loadRecordings()
                showTranscriptionNotification(success: false, message: errorMessage)
            }
        }
    }

    /// Delete audio file after successful transcription to save disk space.
    /// Logs if deletion fails but does not block the flow.
    private func deleteAudioFile(at path: String) {
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: path) else {
            print("[RecordingsView] Audio file already deleted or not found: \(path)")
            return
        }

        do {
            try fileManager.removeItem(atPath: path)
            print("[RecordingsView] Successfully deleted audio file: \(path)")
        } catch {
            // Log but don't block the flow - transcription was successful
            print("[RecordingsView] Failed to delete audio file: \(error.localizedDescription)")
        }
    }

    private func showTranscriptionNotification(success: Bool, message: String) {
        let content = UNMutableNotificationContent()
        content.title = success ? "Transcription Complete" : "Transcription Failed"
        content.body = message
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("[RecordingsView] Failed to show notification: \(error)")
            }
        }
    }

    // MARK: - Permission

    private func checkMicrophonePermission() {
        permissionStatus = permissionService.checkPermissionStatus()
    }

    // MARK: - Clipboard

    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    // MARK: - Recover Interrupted Recordings

    /// On app launch, check for pending recordings and verify audio files exist
    /// If audio file exists, recording can be transcribed via 'Transcribe' button
    /// If audio file is missing, update status to 'failed' with error message
    private func recoverInterruptedRecordings() {
        DispatchQueue.global(qos: .userInitiated).async {
            let pendingRecordings = database.getPendingRecordingsWithAudioFile()

            for recording in pendingRecordings {
                guard let recordingId = recording.id,
                      let audioFilePath = recording.audioFilePath else {
                    continue
                }

                // Check if audio file actually exists on disk
                if !FileManager.default.fileExists(atPath: audioFilePath) {
                    // Audio file not found - update status to failed
                    if var updatedRecording = database.getRecordingById(recordingId) {
                        updatedRecording.transcriptionStatus = .failed
                        updatedRecording.errorMessage = "Audio file not found"
                        updatedRecording.audioFilePath = nil
                        database.updateRecording(updatedRecording)
                        print("[RecordingsView] Recovered recording \(recordingId): audio file not found, marked as failed")
                    }
                } else {
                    // Audio file exists - recording is ready for transcription
                    print("[RecordingsView] Recovered recording \(recordingId): audio file exists, ready for transcription")
                }
            }

            // Reload recordings to show updated statuses
            DispatchQueue.main.async {
                self.loadRecordings()
            }
        }
    }

    // MARK: - Retry Transcription (and Transcribe Pending)

    /// Transcribe a pending recording or retry a failed transcription
    private func retryTranscription(for recording: VoiceRecording) {
        guard let recordingId = recording.id,
              let audioFilePath = recording.audioFilePath else {
            print("[RecordingsView] Cannot retry: recording has no ID or audio file path")
            return
        }

        // Verify audio file still exists
        guard FileManager.default.fileExists(atPath: audioFilePath) else {
            print("[RecordingsView] Cannot retry: audio file not found at \(audioFilePath)")
            // Update recording to show file not found error
            if var updatedRecording = database.getRecordingById(recordingId) {
                updatedRecording.transcriptionStatus = .failed
                updatedRecording.errorMessage = "Audio file not found"
                database.updateRecording(updatedRecording)
                loadRecordings()
            }
            return
        }

        // Update status to processing
        if var updatedRecording = database.getRecordingById(recordingId) {
            updatedRecording.transcriptionStatus = .processing
            updatedRecording.errorMessage = nil
            database.updateRecording(updatedRecording)
        }

        // Update UI state
        DispatchQueue.main.async {
            self.isTranscribing = true
            self.transcribingRecordingId = recordingId
            self.loadRecordings()
        }

        // Start async transcription
        Task {
            await performTranscription(recordingId: recordingId, audioFilePath: audioFilePath)
        }
    }
}

// MARK: - Recording Row View

struct RecordingRowView: View {
    let recording: VoiceRecording
    let isCurrentlyTranscribing: Bool
    let onCopy: () -> Void
    let onRetry: () -> Void

    @State private var isExpanded: Bool = false

    /// Check if audio file exists for retry functionality
    private var audioFileExists: Bool {
        guard let audioFilePath = recording.audioFilePath else { return false }
        return FileManager.default.fileExists(atPath: audioFilePath)
    }

    private var statusColor: Color {
        switch recording.transcriptionStatus {
        case .pending:
            return .gray
        case .processing:
            return .blue
        case .completed:
            return .green
        case .failed:
            return .red
        }
    }

    private var statusText: String {
        switch recording.transcriptionStatus {
        case .pending:
            return "Pending"
        case .processing:
            return "Processing"
        case .completed:
            return "Completed"
        case .failed:
            return "Failed"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header row with time, duration, and status
            HStack {
                // Time
                Text(formatTime(recording.startTime))
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text("•")
                    .foregroundColor(.secondary)

                // Duration
                Text(formatDuration(recording.duration))
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Spacer()

                // Status badge
                HStack(spacing: 4) {
                    if isCurrentlyTranscribing || recording.transcriptionStatus == .processing {
                        ProgressView()
                            .scaleEffect(0.6)
                    }
                    Text(statusText)
                        .font(.caption)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(statusColor)
                .cornerRadius(6)
            }

            // Transcription preview or status message
            if recording.transcriptionStatus == .completed, let transcription = recording.transcription {
                VStack(alignment: .leading, spacing: 8) {
                    // Preview or full transcription
                    if isExpanded {
                        Text(transcription)
                            .font(.body)
                            .textSelection(.enabled)
                    } else {
                        Text(transcription.prefix(100) + (transcription.count > 100 ? "..." : ""))
                            .font(.body)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }

                    // Action buttons
                    HStack {
                        Button(action: { isExpanded.toggle() }) {
                            HStack(spacing: 4) {
                                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                Text(isExpanded ? "Show less" : "Show more")
                            }
                            .font(.caption)
                        }
                        .buttonStyle(.borderless)

                        Spacer()

                        Button(action: onCopy) {
                            HStack(spacing: 4) {
                                Image(systemName: "doc.on.doc")
                                Text("Copy")
                            }
                            .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            } else if recording.transcriptionStatus == .failed {
                VStack(alignment: .leading, spacing: 8) {
                    // Error message
                    if let errorMessage = recording.errorMessage {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundColor(.orange)
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }

                    // Retry button - only shown if audio file exists
                    if audioFileExists {
                        Button(action: onRetry) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.clockwise")
                                Text("Retry Transcription")
                            }
                            .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    } else {
                        // Audio file not found message
                        HStack(spacing: 4) {
                            Image(systemName: "xmark.circle")
                                .foregroundColor(.secondary)
                            Text("Audio file not available for retry")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            } else if recording.transcriptionStatus == .pending {
                // Pending recordings - show Transcribe button if audio file exists
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recording recovered - ready for transcription")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if audioFileExists {
                        Button(action: onRetry) {
                            HStack(spacing: 4) {
                                Image(systemName: "waveform")
                                Text("Transcribe")
                            }
                            .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    } else {
                        // Audio file not found message
                        HStack(spacing: 4) {
                            Image(systemName: "xmark.circle")
                                .foregroundColor(.secondary)
                            Text("Audio file not available")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            } else if recording.transcriptionStatus == .processing || isCurrentlyTranscribing {
                Text("Transcription in progress...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func formatDuration(_ duration: Double) -> String {
        let totalSeconds = Int(duration)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

#Preview {
    RecordingsView()
}
