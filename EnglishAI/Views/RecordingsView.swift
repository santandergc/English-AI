import SwiftUI

struct RecordingsView: View {
    @State private var selectedDate: Date = Date()
    @State private var recordings: [VoiceRecording] = []
    @ObservedObject private var recordingService = VoiceRecordingService.shared
    @State private var permissionStatus: MicrophonePermissionStatus = .notDetermined
    @State private var pulseAnimation: Bool = false
    @State private var showStopConfirmation: Bool = false
    @State private var durationAtStopRequest: TimeInterval = 0

    private let database = DatabaseService.shared
    private let permissionService = MicrophonePermissionService.shared

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

                // Recordings count for selected date
                if !recordings.isEmpty && !recordingService.isRecording {
                    Text("\(recordings.count) recording\(recordings.count == 1 ? "" : "s") for this day")
                        .font(.caption)
                        .foregroundColor(.blue)
                        .padding(.top, 16)
                }

                Spacer()
            }
        }
        .onAppear {
            loadRecordings()
            checkMicrophonePermission()
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
        // User confirmed stop - stop recording
        _ = recordingService.stopRecording()
        // Reload recordings to show the new one
        loadRecordings()
    }

    private func handleAutoStoppedRecording(notification: Notification) {
        // Recording was auto-stopped at 1-hour limit - no confirmation dialog needed
        // Just reload recordings to show the new one
        loadRecordings()
    }

    // MARK: - Permission

    private func checkMicrophonePermission() {
        permissionStatus = permissionService.checkPermissionStatus()
    }
}

#Preview {
    RecordingsView()
}
