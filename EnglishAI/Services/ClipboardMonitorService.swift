import Foundation
import AppKit

protocol ClipboardMonitorDelegate: AnyObject {
    func clipboardMonitor(_ monitor: ClipboardMonitorService, didDetectWisprText text: String)
}

final class ClipboardMonitorService {
    weak var delegate: ClipboardMonitorDelegate?

    private var pollTimer: Timer?
    private let pollInterval: TimeInterval = 0.1

    private var lastChangeCount: Int = 0
    private var previousContent: String?
    private var pendingContent: String?
    private var pendingTimestamp: Date?
    
    private var lastDetectedWisprText: String?
    private var lastDetectionTime: Date?
    private var isProcessingDetection = false
    
    // Debounce: Track pending detections to catch duplicates
    private var pendingDetection: (text: String, timestamp: Date)?
    private var debounceTimer: Timer?
    private let debounceDelay: TimeInterval = 0.5

    private let restorationThreshold: TimeInterval = 1.5
    private let detectionCooldown: TimeInterval = 60.0

    private var isMonitoring = false

    func startMonitoring() {
        guard !isMonitoring else { return }

        lastChangeCount = NSPasteboard.general.changeCount
        previousContent = getClipboardString()

        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.checkClipboard()
        }

        isMonitoring = true
    }

    func stopMonitoring() {
        guard !isMonitoring else { return }

        pollTimer?.invalidate()
        pollTimer = nil
        debounceTimer?.invalidate()
        debounceTimer = nil
        isMonitoring = false
    }

    private func checkClipboard() {
        let currentChangeCount = NSPasteboard.general.changeCount
        guard currentChangeCount != lastChangeCount else { return }

        lastChangeCount = currentChangeCount
        let currentContent = getClipboardString()

        // Check if this is a restoration to the previous content (Wispr pattern)
        if let pending = pendingContent,
           let pendingTime = pendingTimestamp,
           let current = currentContent,
           let previous = previousContent {

            let elapsed = Date().timeIntervalSince(pendingTime)

            // Pattern detected: clipboard changed to something new, then restored to previous within threshold
            if elapsed <= restorationThreshold && current == previous && pending != previous {
                guard !isProcessingDetection else { return }
                
                let now = Date()
                let trimmedPending = pending.trimmingCharacters(in: .whitespacesAndNewlines)
                
                // Check cooldown
                if let lastText = lastDetectedWisprText,
                   let lastTime = lastDetectionTime {
                    let trimmedLast = lastText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmedPending == trimmedLast && now.timeIntervalSince(lastTime) < detectionCooldown {
                        pendingContent = nil
                        pendingTimestamp = nil
                        return
                    }
                }
                
                // Debounce: Check if same text is already pending
                if let existingPending = pendingDetection {
                    let existingTrimmed = existingPending.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmedPending == existingTrimmed {
                        // Duplicate detected - cancel both
                        debounceTimer?.invalidate()
                        debounceTimer = nil
                        pendingDetection = nil
                        pendingContent = nil
                        pendingTimestamp = nil
                        previousContent = pending
                        return
                    }
                }
                
                // Cancel any existing debounce timer
                debounceTimer?.invalidate()
                
                // Store for debouncing
                pendingDetection = (text: pending, timestamp: now)
                pendingContent = nil
                pendingTimestamp = nil
                previousContent = pending
                
                // Wait for debounce period before processing
                debounceTimer = Timer.scheduledTimer(withTimeInterval: debounceDelay, repeats: false) { [weak self] _ in
                    guard let self = self,
                          let pending = self.pendingDetection else { return }
                    
                    let detectedText = pending.text
                    let trimmedDetected = detectedText.trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    // Final cooldown check
                    let now = Date()
                    if let lastText = self.lastDetectedWisprText,
                       let lastTime = self.lastDetectionTime {
                        let trimmedLast = lastText.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmedDetected == trimmedLast && now.timeIntervalSince(lastTime) < self.detectionCooldown {
                            self.pendingDetection = nil
                            self.debounceTimer = nil
                            return
                        }
                    }
                    
                    self.isProcessingDetection = true
                    self.lastDetectedWisprText = trimmedDetected
                    self.lastDetectionTime = now
                    self.pendingDetection = nil
                    self.debounceTimer = nil
                    
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        self.delegate?.clipboardMonitor(self, didDetectWisprText: detectedText)
                        self.isProcessingDetection = false
                    }
                }
                
                return
            }
        }

        // Check if pending content timed out
        if let pendingTime = pendingTimestamp {
            let elapsed = Date().timeIntervalSince(pendingTime)
            if elapsed > restorationThreshold {
                previousContent = pendingContent
                pendingContent = nil
                pendingTimestamp = nil
            }
        }

        // New clipboard content detected
        if let current = currentContent {
            guard !isProcessingDetection else { return }
            
            // Skip if recently detected
            let trimmedCurrent = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if let lastText = lastDetectedWisprText,
               let lastTime = lastDetectionTime {
                let trimmedLast = lastText.trimmingCharacters(in: .whitespacesAndNewlines)
                if (current == lastText || trimmedCurrent == trimmedLast) && Date().timeIntervalSince(lastTime) < detectionCooldown {
                    return
                }
            }
            
            if pendingContent == nil {
                // Double-check before setting as pending
                let trimmedCurrent = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if let lastText = lastDetectedWisprText,
                   let lastTime = lastDetectionTime {
                    let trimmedLast = lastText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmedCurrent == trimmedLast && Date().timeIntervalSince(lastTime) < detectionCooldown {
                        return
                    }
                }
                
                pendingContent = current
                pendingTimestamp = Date()
            } else {
                // Double-check before updating pending
                let trimmedCurrent = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if let lastText = lastDetectedWisprText,
                   let lastTime = lastDetectionTime {
                    let trimmedLast = lastText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmedCurrent == trimmedLast && Date().timeIntervalSince(lastTime) < detectionCooldown {
                        return
                    }
                }
                
                previousContent = pendingContent
                pendingContent = current
                pendingTimestamp = Date()
            }
        }
    }

    private func getClipboardString() -> String? {
        return NSPasteboard.general.string(forType: .string)
    }
}
