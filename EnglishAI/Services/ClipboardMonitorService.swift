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
    
    // Debounce: Track pending detection
    private var pendingDetection: (text: String, timestamp: Date)?
    private var debounceTimer: Timer?
    private let debounceDelay: TimeInterval = 0.3

    private let restorationThreshold: TimeInterval = 2.5
    private let detectionCooldown: TimeInterval = 5.0

    private var isMonitoring = false
    
    private let enableDebugLogs = false

    func startMonitoring() {
        guard !isMonitoring else { return }

        lastChangeCount = NSPasteboard.general.changeCount
        previousContent = getClipboardString()
        
        debugLog("ClipboardMonitor started")

        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.checkClipboard()
        }

        isMonitoring = true
    }

    func stopMonitoring() {
        guard isMonitoring else { return }

        pollTimer?.invalidate()
        pollTimer = nil
        debounceTimer?.invalidate()
        debounceTimer = nil
        isMonitoring = false
        debugLog("🛑 ClipboardMonitor stopped")
    }

    private func checkClipboard() {
        let currentChangeCount = NSPasteboard.general.changeCount
        guard currentChangeCount != lastChangeCount else { return }

        lastChangeCount = currentChangeCount
        let currentContent = getClipboardString()
        
        debugLog("Clipboard change detected (\(currentContent?.count ?? 0) chars)")

        // Check if this is a restoration to the previous content (Wispr pattern)
        if let pending = pendingContent,
           let pendingTime = pendingTimestamp,
           let current = currentContent,
           let previous = previousContent {

            let elapsed = Date().timeIntervalSince(pendingTime)
            
            debugLog("   Checking pattern: current==previous? \(current == previous), pending!=previous? \(pending != previous), elapsed: \(String(format: "%.2f", elapsed))s")

            // Pattern detected: clipboard changed to something new, then restored to previous within threshold
            if elapsed <= restorationThreshold && current == previous && pending != previous {
                debugLog("Wispr pattern matched (\(pending.count) chars)")
                
                let now = Date()
                let trimmedPending = pending.trimmingCharacters(in: .whitespacesAndNewlines)
                
                // Check cooldown - skip if EXACT same text was just detected
                if let lastText = lastDetectedWisprText,
                   let lastTime = lastDetectionTime {
                    let trimmedLast = lastText.trimmingCharacters(in: .whitespacesAndNewlines)
                    let timeSinceLast = now.timeIntervalSince(lastTime)
                    if trimmedPending == trimmedLast && timeSinceLast < detectionCooldown {
                        debugLog("⏭️ Skipping duplicate (same text \(String(format: "%.1f", timeSinceLast))s ago)")
                        // FIXED: Reset state properly - keep previousContent as the restored content
                        pendingContent = nil
                        pendingTimestamp = nil
                        // previousContent stays as 'current' (the restored content)
                        return
                    }
                }
                
                // If there's already a pending detection with different text, process it first
                if let existingPending = pendingDetection {
                    let existingTrimmed = existingPending.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmedPending == existingTrimmed {
                        debugLog("⏭️ Duplicate during debounce, keeping original")
                        pendingContent = nil
                        pendingTimestamp = nil
                        return
                    } else {
                        debugLog("📝 New text during debounce, processing previous immediately")
                        debounceTimer?.invalidate()
                        processDetection(existingPending.text)
                    }
                }
                
                // Store for debouncing
                pendingDetection = (text: pending, timestamp: now)
                
                // FIXED: Reset clipboard tracking state properly
                // The clipboard has been restored to 'current', so that becomes our new baseline
                pendingContent = nil
                pendingTimestamp = nil
                previousContent = current  // FIXED: Set to the RESTORED content, not the detected text
                
                // Wait for debounce period before processing
                debounceTimer?.invalidate()
                debounceTimer = Timer.scheduledTimer(withTimeInterval: debounceDelay, repeats: false) { [weak self] _ in
                    guard let self = self,
                          let pending = self.pendingDetection else { return }
                    self.processDetection(pending.text)
                }
                
                return
            }
        }

        // Check if pending content timed out (not a Wispr pattern)
        if let pendingTime = pendingTimestamp {
            let elapsed = Date().timeIntervalSince(pendingTime)
            if elapsed > restorationThreshold {
                debugLog("⏰ Pending content timed out after \(String(format: "%.1f", elapsed))s (not Wispr pattern)")
                // The pending content wasn't restored, so it becomes the new previous
                previousContent = pendingContent
                pendingContent = nil
                pendingTimestamp = nil
            }
        }

        // New clipboard content detected - track it as potential Wispr text
        if let current = currentContent {
            let trimmedCurrent = current.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Skip if this exact text was just detected as Wispr
            if let lastText = lastDetectedWisprText,
               let lastTime = lastDetectionTime {
                let trimmedLast = lastText.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmedCurrent == trimmedLast && Date().timeIntervalSince(lastTime) < detectionCooldown {
                    debugLog("   Skipping - recently detected as Wispr")
                    return
                }
            }
            
            // Don't update if current equals previous (no real change for tracking purposes)
            if current == previousContent {
                debugLog("   Current equals previous, no state change needed")
                return
            }
            
            if pendingContent == nil {
                pendingContent = current
                pendingTimestamp = Date()
                debugLog("   Set as pending content")
            } else if pendingContent != current {
                // New content while we had pending - shift the state
                debugLog("   Shifting: previous=pending, pending=current")
                previousContent = pendingContent
                pendingContent = current
                pendingTimestamp = Date()
            }
        }
    }
    
    private func processDetection(_ text: String) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let now = Date()
        
        // Final cooldown check
        if let lastText = lastDetectedWisprText,
           let lastTime = lastDetectionTime {
            let trimmedLast = lastText.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedText == trimmedLast && now.timeIntervalSince(lastTime) < detectionCooldown {
                debugLog("⏭️ Final check: duplicate, skipping")
                pendingDetection = nil
                return
            }
        }
        
        lastDetectedWisprText = trimmedText
        lastDetectionTime = now
        pendingDetection = nil
        
        debugLog("Processing Wispr text (\(text.count) chars)")
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.clipboardMonitor(self, didDetectWisprText: text)
        }
    }

    private func getClipboardString() -> String? {
        return NSPasteboard.general.string(forType: .string)
    }
    
    private func debugLog(_ message: String) {
        if enableDebugLogs {
            print("[ClipboardMonitor] \(message)")
        }
    }
}
