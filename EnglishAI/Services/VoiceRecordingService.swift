import Foundation
import AVFoundation
import Combine

/// Singleton service for recording voice using AVFoundation
final class VoiceRecordingService: NSObject, ObservableObject {
    static let shared = VoiceRecordingService()

    /// Published property indicating if recording is in progress
    @Published private(set) var isRecording: Bool = false

    /// Published property showing current recording duration in seconds (updates every second)
    @Published private(set) var currentDuration: TimeInterval = 0

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
    /// - Returns: The URL of the saved recording, or nil if no recording was in progress
    @discardableResult
    func stopRecording() -> URL? {
        guard isRecording, let recorder = audioRecorder else {
            print("[VoiceRecordingService] No recording in progress")
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
                self.currentDuration = Date().timeIntervalSince(startTime)
            }
        }
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
