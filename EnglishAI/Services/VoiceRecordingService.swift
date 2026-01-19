import Foundation
import AVFoundation
import Combine

/// Notification posted when recording is auto-stopped at the maximum duration limit
extension Notification.Name {
    static let recordingAutoStopped = Notification.Name("VoiceRecordingService.recordingAutoStopped")
}

/// Singleton service for recording voice using AVFoundation
final class VoiceRecordingService: NSObject, ObservableObject {
    static let shared = VoiceRecordingService()

    // MARK: - Duration Constants

    /// Minimum recording duration in seconds (recording cannot be stopped before this)
    static let minimumDuration: TimeInterval = 10

    /// Maximum recording duration in seconds (1 hour)
    static let maximumDuration: TimeInterval = 3600

    // MARK: - Published Properties

    /// Published property indicating if recording is in progress
    @Published private(set) var isRecording: Bool = false

    /// Published property showing current recording duration in seconds (updates every second)
    @Published private(set) var currentDuration: TimeInterval = 0

    /// Published property indicating if recording can be stopped (duration >= minimum)
    @Published private(set) var canStop: Bool = false

    /// Published property showing seconds remaining until maximum duration limit
    @Published private(set) var timeRemaining: TimeInterval = VoiceRecordingService.maximumDuration

    // MARK: - Private Properties

    private var audioRecorder: AVAudioRecorder?
    private var recordingStartTime: Date?
    private var durationTimer: Timer?
    private var currentRecordingURL: URL?

    /// Directory where recordings are saved
    private var recordingsDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("EnglishAI/recordings", isDirectory: true)
    }

    private override init() {
        super.init()
    }

    /// Start recording audio from the microphone
    /// - Returns: The URL where the recording will be saved, or nil if recording failed to start
    @discardableResult
    func startRecording() -> URL? {
        guard !isRecording else {
            print("[VoiceRecordingService] Already recording")
            return currentRecordingURL
        }

        // Create recordings directory if needed
        do {
            try FileManager.default.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true, attributes: nil)
        } catch {
            print("[VoiceRecordingService] Failed to create recordings directory: \(error)")
            return nil
        }

        // Generate filename with timestamp
        let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let filename = "recording_\(timestamp).m4a"
        let fileURL = recordingsDirectory.appendingPathComponent(filename)

        // Audio settings: M4A format, AAC codec, 44100Hz, mono
        // Note: macOS does not require AVAudioSession configuration like iOS
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            audioRecorder = try AVAudioRecorder(url: fileURL, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.record()

            currentRecordingURL = fileURL
            recordingStartTime = Date()
            isRecording = true
            currentDuration = 0

            // Start timer to update duration every second
            startDurationTimer()

            print("[VoiceRecordingService] Started recording to: \(fileURL.path)")
            return fileURL
        } catch {
            print("[VoiceRecordingService] Failed to start recording: \(error)")
            return nil
        }
    }

    /// Stop recording and finalize the audio file
    /// - Parameter force: If true, stops recording regardless of duration (used for auto-stop at limit and app termination)
    /// - Returns: The URL of the saved recording, or nil if no recording was in progress or duration is below minimum
    @discardableResult
    func stopRecording(force: Bool = false) -> URL? {
        guard isRecording, let recorder = audioRecorder else {
            print("[VoiceRecordingService] No recording in progress")
            return nil
        }

        // Check minimum duration unless force is true
        if !force && currentDuration < VoiceRecordingService.minimumDuration {
            print("[VoiceRecordingService] Cannot stop recording - duration \(currentDuration)s is below minimum \(VoiceRecordingService.minimumDuration)s")
            return nil
        }

        recorder.stop()
        stopDurationTimer()

        let savedURL = currentRecordingURL

        // Reset state
        audioRecorder = nil
        recordingStartTime = nil
        currentRecordingURL = nil
        isRecording = false
        canStop = false
        timeRemaining = VoiceRecordingService.maximumDuration

        if let url = savedURL {
            print("[VoiceRecordingService] Stopped recording. File saved to: \(url.path)")
        }

        return savedURL
    }

    // MARK: - Private Methods

    private func startDurationTimer() {
        durationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, let startTime = self.recordingStartTime else { return }
            DispatchQueue.main.async {
                let duration = Date().timeIntervalSince(startTime)
                self.currentDuration = duration
                self.canStop = duration >= VoiceRecordingService.minimumDuration
                self.timeRemaining = max(0, VoiceRecordingService.maximumDuration - duration)

                // Auto-stop when maximum duration is reached
                if duration >= VoiceRecordingService.maximumDuration {
                    self.autoStopRecording()
                }
            }
        }
    }

    /// Auto-stop recording when maximum duration is reached
    private func autoStopRecording() {
        print("[VoiceRecordingService] Maximum recording duration reached, auto-stopping")
        let savedURL = stopRecording(force: true)

        // Post notification that recording was auto-stopped
        NotificationCenter.default.post(
            name: .recordingAutoStopped,
            object: self,
            userInfo: savedURL != nil ? ["audioFileURL": savedURL!] : nil
        )
    }

    private func stopDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
    }
}

// MARK: - AVAudioRecorderDelegate

extension VoiceRecordingService: AVAudioRecorderDelegate {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            print("[VoiceRecordingService] Recording finished unsuccessfully")
        }
    }

    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        if let error = error {
            print("[VoiceRecordingService] Recording encode error: \(error)")
        }
    }
}
