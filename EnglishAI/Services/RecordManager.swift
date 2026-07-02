import Foundation
import AppKit

final class RecordManager {
    static let shared = RecordManager()

    private let keyboardMonitor = KeyboardMonitorService()
    private let clipboardMonitor = ClipboardMonitorService()
    private let appFocusMonitor = AppFocusMonitorService()
    private let database = DatabaseService.shared
    private let privacyFilter = CapturePrivacyFilter.shared

    private var keyboardBuffer: String = ""
    private var bufferAppContext: String = ""
    private var bufferAppBundleIdentifier: String?
    private var bufferAppProcessIdentifier: pid_t?
    private var recentWisprContent: Set<String> = []
    private let wisprDeduplicationQueue = DispatchQueue(label: "com.englishai.wispr.dedup")
    private var isKeyboardPrivacySuppressed = false
    
    /// Tracks if user pressed Cmd+A (select all) - next delete should clear buffer
    private var selectAllActive: Bool = false
    
    /// Cursor position within the buffer (index where next character will be inserted)
    /// This allows us to track edits in the middle of text
    private var cursorPosition: String.Index?
    
    /// Helper to get safe cursor position
    private var safeCursorPosition: String.Index {
        get {
            if let pos = cursorPosition, pos <= keyboardBuffer.endIndex && pos >= keyboardBuffer.startIndex {
                return pos
            }
            return keyboardBuffer.endIndex
        }
        set {
            cursorPosition = newValue
        }
    }

    private(set) var isPaused: Bool = false

    private init() {
        setupDelegates()
    }

    private func setupDelegates() {
        keyboardMonitor.delegate = self
        clipboardMonitor.delegate = self
        appFocusMonitor.delegate = self
    }

    func startMonitoring() {
        appFocusMonitor.startMonitoring()
        keyboardMonitor.startMonitoring()
        clipboardMonitor.startMonitoring()

        updateBufferAppContextFromActiveApp()

        // Clean up duplicates after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.database.removeDuplicateRecords()
        }
    }

    func stopMonitoring() {
        flushKeyboardBuffer()
        keyboardMonitor.stopMonitoring()
        clipboardMonitor.stopMonitoring()
        appFocusMonitor.stopMonitoring()
    }

    func pause() {
        isPaused = true
        flushKeyboardBuffer()
    }

    func resume() {
        isPaused = false
        updateBufferAppContextFromActiveApp()
    }

    private func flushKeyboardBuffer() {
        guard !keyboardBuffer.isEmpty else { return }

        let content = keyboardBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else {
            keyboardBuffer = ""
            return
        }

        let context = currentCaptureContext(source: .keyboard, useBufferContext: true)
        let decision = privacyFilter.evaluate(content, context: context)

        guard case .save(let filteredContent) = decision else {
            if case .skip(let reason) = decision {
                print("[RecordManager] Skipping keyboard record (\(reason.rawValue), \(content.count) chars)")
            }
            keyboardBuffer = ""
            return
        }

        print("[RecordManager] Saving keyboard record (\(filteredContent.count) chars)")
        
        let record = Record(
            source: .keyboard,
            content: filteredContent,
            activeApp: bufferAppContext.isEmpty ? "Unknown" : bufferAppContext
        )

        database.insertRecord(record)
        keyboardBuffer = ""
    }

    private func updateBufferAppContextFromActiveApp() {
        bufferAppContext = appFocusMonitor.activeAppName
        bufferAppBundleIdentifier = appFocusMonitor.activeBundleIdentifier
        bufferAppProcessIdentifier = appFocusMonitor.activeProcessIdentifier
    }

    private func currentCaptureContext(source: RecordSource, useBufferContext: Bool = false) -> CapturePrivacyContext {
        if useBufferContext {
            return CapturePrivacyContext(
                source: source,
                appName: bufferAppContext.isEmpty ? "Unknown" : bufferAppContext,
                bundleIdentifier: bufferAppBundleIdentifier,
                processIdentifier: bufferAppProcessIdentifier
            )
        }

        if isEnglishAIFrontmost() {
            return CapturePrivacyContext(
                source: source,
                appName: Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "EnglishAI",
                bundleIdentifier: Bundle.main.bundleIdentifier,
                processIdentifier: pid_t(ProcessInfo.processInfo.processIdentifier)
            )
        }

        return CapturePrivacyContext(
            source: source,
            appName: appFocusMonitor.activeAppName,
            bundleIdentifier: appFocusMonitor.activeBundleIdentifier,
            processIdentifier: appFocusMonitor.activeProcessIdentifier
        )
    }

    private func isEnglishAIFrontmost() -> Bool {
        if NSApp.isActive {
            return true
        }

        return NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Bundle.main.bundleIdentifier
    }

    private func shouldIgnoreKeyboardEventForPrivacy() -> Bool {
        guard !isPaused else {
            return true
        }

        let context = currentCaptureContext(source: .keyboard)
        guard privacyFilter.shouldSuppressInput(context: context) else {
            isKeyboardPrivacySuppressed = false
            return false
        }

        if !isKeyboardPrivacySuppressed {
            print("[RecordManager] Pausing keyboard capture for private input in \(context.appName)")
        }

        isKeyboardPrivacySuppressed = true
        keyboardBuffer = ""
        cursorPosition = nil
        selectAllActive = false
        return true
    }
}

// MARK: - KeyboardMonitorDelegate
extension RecordManager: KeyboardMonitorDelegate {
    func keyboardMonitor(_ monitor: KeyboardMonitorService, didReceiveCharacter char: String) {
        guard !shouldIgnoreKeyboardEventForPrivacy() else { return }

        // If select all was active and user types, it replaces selected text
        if selectAllActive {
            keyboardBuffer = ""
            cursorPosition = nil
            selectAllActive = false
        }
        
        if keyboardBuffer.isEmpty {
            updateBufferAppContextFromActiveApp()
            cursorPosition = nil
        }

        // Insert character at cursor position
        let insertPos = safeCursorPosition
        keyboardBuffer.insert(contentsOf: char, at: insertPos)
        
        // Move cursor forward after insertion
        safeCursorPosition = keyboardBuffer.index(insertPos, offsetBy: char.count)
    }

    func keyboardMonitorDidReceiveBackspace(_ monitor: KeyboardMonitorService) {
        guard !shouldIgnoreKeyboardEventForPrivacy() else { return }

        // If select all was active, delete clears everything
        if selectAllActive {
            print("[RecordManager] 🗑️ Clearing buffer after select all + backspace")
            keyboardBuffer = ""
            cursorPosition = nil
            selectAllActive = false
            return
        }
        
        guard !keyboardBuffer.isEmpty else { return }
        
        let pos = safeCursorPosition
        // Can only delete backward if cursor is not at start
        if pos > keyboardBuffer.startIndex {
            let deletePos = keyboardBuffer.index(before: pos)
            keyboardBuffer.remove(at: deletePos)
            safeCursorPosition = deletePos
        }
    }
    
    func keyboardMonitorDidReceiveForwardDelete(_ monitor: KeyboardMonitorService) {
        guard !shouldIgnoreKeyboardEventForPrivacy() else { return }
        
        // If select all was active, delete clears everything
        if selectAllActive {
            print("[RecordManager] 🗑️ Clearing buffer after select all + forward delete")
            keyboardBuffer = ""
            cursorPosition = nil
            selectAllActive = false
            return
        }
        
        guard !keyboardBuffer.isEmpty else { return }
        
        let pos = safeCursorPosition
        // Can only delete forward if cursor is not at end
        if pos < keyboardBuffer.endIndex {
            keyboardBuffer.remove(at: pos)
            // Cursor stays at same position (now pointing to next char)
        }
    }
    
    func keyboardMonitorDidReceiveDeleteWord(_ monitor: KeyboardMonitorService, forward: Bool) {
        guard !shouldIgnoreKeyboardEventForPrivacy() else { return }
        
        // If select all was active, delete clears everything
        if selectAllActive {
            print("[RecordManager] 🗑️ Clearing buffer after select all + delete word")
            keyboardBuffer = ""
            cursorPosition = nil
            selectAllActive = false
            return
        }
        
        guard !keyboardBuffer.isEmpty else { return }
        
        let pos = safeCursorPosition
        
        if forward {
            // Delete word forward: remove from cursor to end of word
            var endPos = pos
            // First, skip any spaces
            while endPos < keyboardBuffer.endIndex && keyboardBuffer[endPos] == " " {
                endPos = keyboardBuffer.index(after: endPos)
            }
            // Then skip word characters
            while endPos < keyboardBuffer.endIndex && keyboardBuffer[endPos] != " " {
                endPos = keyboardBuffer.index(after: endPos)
            }
            keyboardBuffer.removeSubrange(pos..<endPos)
        } else {
            // Delete word backward: remove from start of word to cursor
            var startPos = pos
            // First, skip any spaces going backward
            while startPos > keyboardBuffer.startIndex {
                let prevIndex = keyboardBuffer.index(before: startPos)
                if keyboardBuffer[prevIndex] != " " { break }
                startPos = prevIndex
            }
            // Then skip word characters going backward
            while startPos > keyboardBuffer.startIndex {
                let prevIndex = keyboardBuffer.index(before: startPos)
                if keyboardBuffer[prevIndex] == " " { break }
                startPos = prevIndex
            }
            keyboardBuffer.removeSubrange(startPos..<pos)
            safeCursorPosition = startPos
        }
        
        print("[RecordManager] Deleted word from keyboard buffer (\(keyboardBuffer.count) chars remaining)")
    }
    
    func keyboardMonitorDidReceiveDeleteLine(_ monitor: KeyboardMonitorService, forward: Bool) {
        guard !shouldIgnoreKeyboardEventForPrivacy() else { return }
        
        // If select all was active, delete clears everything
        if selectAllActive {
            print("[RecordManager] 🗑️ Clearing buffer after select all + delete line")
            keyboardBuffer = ""
            cursorPosition = nil
            selectAllActive = false
            return
        }
        
        guard !keyboardBuffer.isEmpty else { return }
        
        let pos = safeCursorPosition
        
        if forward {
            // Delete to end of line: remove from cursor to newline or end
            var endPos = pos
            while endPos < keyboardBuffer.endIndex && keyboardBuffer[endPos] != "\n" {
                endPos = keyboardBuffer.index(after: endPos)
            }
            keyboardBuffer.removeSubrange(pos..<endPos)
        } else {
            // Delete to beginning of line: remove from newline or start to cursor
            var startPos = pos
            while startPos > keyboardBuffer.startIndex {
                let prevIndex = keyboardBuffer.index(before: startPos)
                if keyboardBuffer[prevIndex] == "\n" { break }
                startPos = prevIndex
            }
            keyboardBuffer.removeSubrange(startPos..<pos)
            safeCursorPosition = startPos
        }
        
        print("[RecordManager] Deleted line from keyboard buffer (\(keyboardBuffer.count) chars remaining)")
    }
    
    func keyboardMonitorDidReceiveSelectAll(_ monitor: KeyboardMonitorService) {
        guard !shouldIgnoreKeyboardEventForPrivacy() else { return }
        
        // Mark that select all is active - next delete or character input will handle it
        selectAllActive = true
        print("[RecordManager] 📋 Select all detected, marking for potential deletion")
    }
    
    func keyboardMonitor(_ monitor: KeyboardMonitorService, didNavigate direction: CursorNavigation) {
        guard !shouldIgnoreKeyboardEventForPrivacy() else { return }
        
        // Navigation cancels select all
        selectAllActive = false
        
        guard !keyboardBuffer.isEmpty else { return }
        
        let pos = safeCursorPosition
        
        switch direction {
        case .left:
            if pos > keyboardBuffer.startIndex {
                safeCursorPosition = keyboardBuffer.index(before: pos)
            }
            
        case .right:
            if pos < keyboardBuffer.endIndex {
                safeCursorPosition = keyboardBuffer.index(after: pos)
            }
            
        case .wordLeft:
            var newPos = pos
            // Skip spaces going backward
            while newPos > keyboardBuffer.startIndex {
                let prevIndex = keyboardBuffer.index(before: newPos)
                if keyboardBuffer[prevIndex] != " " { break }
                newPos = prevIndex
            }
            // Skip word characters going backward
            while newPos > keyboardBuffer.startIndex {
                let prevIndex = keyboardBuffer.index(before: newPos)
                if keyboardBuffer[prevIndex] == " " { break }
                newPos = prevIndex
            }
            safeCursorPosition = newPos
            
        case .wordRight:
            var newPos = pos
            // Skip word characters going forward
            while newPos < keyboardBuffer.endIndex && keyboardBuffer[newPos] != " " {
                newPos = keyboardBuffer.index(after: newPos)
            }
            // Skip spaces going forward
            while newPos < keyboardBuffer.endIndex && keyboardBuffer[newPos] == " " {
                newPos = keyboardBuffer.index(after: newPos)
            }
            safeCursorPosition = newPos
            
        case .lineStart:
            // Move to start of line (after previous newline)
            var newPos = pos
            while newPos > keyboardBuffer.startIndex {
                let prevIndex = keyboardBuffer.index(before: newPos)
                if keyboardBuffer[prevIndex] == "\n" { break }
                newPos = prevIndex
            }
            safeCursorPosition = newPos
            
        case .lineEnd:
            // Move to end of line (before next newline)
            var newPos = pos
            while newPos < keyboardBuffer.endIndex && keyboardBuffer[newPos] != "\n" {
                newPos = keyboardBuffer.index(after: newPos)
            }
            safeCursorPosition = newPos
            
        case .up, .down:
            // For up/down, we can't really track line position accurately
            // Just leave cursor where it is - this is a limitation
            break
        }
        
        print("[RecordManager] ➡️ Cursor moved \(direction), position now at offset \(keyboardBuffer.distance(from: keyboardBuffer.startIndex, to: safeCursorPosition))")
    }
    
    func keyboardMonitorDidDetectMouseClick(_ monitor: KeyboardMonitorService) {
        guard !shouldIgnoreKeyboardEventForPrivacy() else { return }
        
        // Mouse click means cursor position may have changed unpredictably
        // DON'T flush - we want to capture complete text, not fragments
        // Just reset cursor to end (assume new typing will append)
        // The buffer might be slightly out of order, but captures all words
        
        if !keyboardBuffer.isEmpty {
            print("[RecordManager] 🖱️ Mouse click detected - cursor position now uncertain, resetting to end")
        }
        
        // Reset cursor to end of buffer (new text will append)
        selectAllActive = false
        cursorPosition = keyboardBuffer.endIndex
    }

    func keyboardMonitorDidDetectIdle(_ monitor: KeyboardMonitorService) {
        guard !shouldIgnoreKeyboardEventForPrivacy() else { return }
        selectAllActive = false
        cursorPosition = nil // Reset cursor on idle
        flushKeyboardBuffer()
    }
}

// MARK: - ClipboardMonitorDelegate
extension RecordManager: ClipboardMonitorDelegate {
    func clipboardMonitor(_ monitor: ClipboardMonitorService, didDetectWisprText text: String) {
        guard !isPaused else { return }

        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }

        let context = currentCaptureContext(source: .wispr)
        let decision = privacyFilter.evaluate(content, context: context)

        guard case .save(let filteredContent) = decision else {
            if case .skip(let reason) = decision {
                print("[RecordManager] Skipping Wispr record (\(reason.rawValue), \(content.count) chars)")
            }
            return
        }
        
        // Check in-memory set to prevent duplicates
        var shouldProcess = false
        wisprDeduplicationQueue.sync {
            if !recentWisprContent.contains(filteredContent) {
                recentWisprContent.insert(filteredContent)
                shouldProcess = true
                
                // FIXED: Reduced from 60 seconds to 5 seconds
                // This allows same text to be saved again after a short period
                DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
                    self?.wisprDeduplicationQueue.async {
                        self?.recentWisprContent.remove(filteredContent)
                    }
                }
            } else {
                print("[RecordManager] Duplicate Wispr record skipped (\(filteredContent.count) chars)")
            }
        }
        
        guard shouldProcess else { return }
        
        print("[RecordManager] Saving Wispr record (\(filteredContent.count) chars)")

        let record = Record(
            source: .wispr,
            content: filteredContent,
            activeApp: appFocusMonitor.activeAppName.isEmpty ? "Unknown" : appFocusMonitor.activeAppName
        )

        database.insertRecord(record)
    }
}

// MARK: - AppFocusMonitorDelegate
extension RecordManager: AppFocusMonitorDelegate {
    func appFocusMonitor(_ monitor: AppFocusMonitorService, didChangeFocusTo appName: String) {
        guard !isPaused else { return }
        flushKeyboardBuffer()
        bufferAppContext = appName
        bufferAppBundleIdentifier = appFocusMonitor.activeBundleIdentifier
        bufferAppProcessIdentifier = appFocusMonitor.activeProcessIdentifier
    }
}
