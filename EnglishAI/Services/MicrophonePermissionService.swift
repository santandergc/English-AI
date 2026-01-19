import Foundation
import AVFoundation
import AppKit

/// Enum representing microphone permission status
enum MicrophonePermissionStatus {
    case authorized
    case denied
    case notDetermined
}

/// Singleton service for handling microphone permission requests and status checks
final class MicrophonePermissionService {
    static let shared = MicrophonePermissionService()

    private init() {}

    /// Check the current microphone permission status
    /// - Returns: The current MicrophonePermissionStatus
    func checkPermissionStatus() -> MicrophonePermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return .authorized
        case .denied, .restricted:
            return .denied
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .notDetermined
        }
    }

    /// Request microphone permission from the user
    /// - Returns: True if permission was granted, false otherwise
    @MainActor
    func requestPermission() async -> Bool {
        let status = checkPermissionStatus()

        switch status {
        case .authorized:
            return true
        case .denied:
            return false
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    /// Open System Preferences to the Privacy > Microphone settings
    func openSystemPreferences() {
        // On macOS 13+, use the new Security & Privacy URL scheme
        // For microphone specifically, we need to open Privacy & Security > Microphone
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }
}
