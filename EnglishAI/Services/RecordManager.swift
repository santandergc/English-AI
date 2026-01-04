import Foundation

final class RecordManager {
    static let shared = RecordManager()

    private let keyboardMonitor = KeyboardMonitorService()
    private let clipboardMonitor = ClipboardMonitorService()
    private let appFocusMonitor = AppFocusMonitorService()
    private let database = DatabaseService.shared

    private var keyboardBuffer: String = ""
    private var bufferAppContext: String = ""
    private var recentWisprContent: Set<String> = []
    private let wisprDeduplicationQueue = DispatchQueue(label: "com.englishai.wispr.dedup")
    
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

        bufferAppContext = appFocusMonitor.activeAppName

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
        bufferAppContext = appFocusMonitor.activeAppName
    }

    private func flushKeyboardBuffer() {
        guard !keyboardBuffer.isEmpty else { return }

        let content = keyboardBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else {
            keyboardBuffer = ""
            return
        }
        
        // FILTER 1: Skip single characters (likely shortcuts or accidental presses)
        if content.count <= 1 {
            print("[RecordManager] ⏭️ Skipping single character: '\(content)'")
            keyboardBuffer = ""
            return
        }
        
        // FILTER 2: Skip numbers-only entries (likely passwords, codes, or numeric input)
        let nonNumericCharacters = content.rangeOfCharacter(from: CharacterSet.decimalDigits.inverted)
        if nonNumericCharacters == nil {
            print("[RecordManager] ⏭️ Skipping numbers-only entry: '\(content)'")
            keyboardBuffer = ""
            return
        }
        
        // FILTER 3: Skip entries with less than 5 non-space characters
        // Count only actual letters/characters, ignoring spaces
        let nonSpaceCharacters = content.replacingOccurrences(of: " ", with: "")
        if nonSpaceCharacters.count < 5 {
            print("[RecordManager] ⏭️ Skipping entry with less than 5 non-space characters: '\(content)' (non-space count: \(nonSpaceCharacters.count))")
            keyboardBuffer = ""
            return
        }
        
        // FILTER 4: Check if content looks like natural language first
        let isNaturalLanguage = hasEnoughVowels(content) && !hasTooManySpecialCharacters(content)
        
        // FILTER 5: Skip if looks like terminal commands
        // But allow natural language conversations even in terminals (e.g., Claude Code)
        if looksLikeTerminalCommand(content) {
            print("[RecordManager] ⏭️ Skipping terminal command pattern: '\(content)'")
            keyboardBuffer = ""
            return
        }
        
        // FILTER 6: For terminal apps, only block if it's NOT natural language
        // This allows conversations with LLMs in terminals while blocking actual commands
        if isTerminalApp(bufferAppContext) && !isNaturalLanguage {
            print("[RecordManager] ⏭️ Skipping non-natural language entry from terminal app '\(bufferAppContext)': '\(content)'")
            keyboardBuffer = ""
            return
        }
        
        // FILTER 7: Skip if too many special characters (likely code/commands)
        // But only if it's not from a terminal (where we already checked)
        if !isTerminalApp(bufferAppContext) && hasTooManySpecialCharacters(content) {
            print("[RecordManager] ⏭️ Skipping entry with too many special characters: '\(content)'")
            keyboardBuffer = ""
            return
        }
        
        // FILTER 8: Skip if doesn't contain enough vowels (likely not natural language)
        // But only if it's not from a terminal (where we already checked)
        if !isTerminalApp(bufferAppContext) && !hasEnoughVowels(content) {
            print("[RecordManager] ⏭️ Skipping entry with insufficient vowels (likely not words): '\(content)'")
            keyboardBuffer = ""
            return
        }

        print("[RecordManager] ✅ Saving keyboard record: \(content.prefix(50))...")
        
        let record = Record(
            source: .keyboard,
            content: content,
            activeApp: bufferAppContext.isEmpty ? "Unknown" : bufferAppContext
        )

        database.insertRecord(record)
        keyboardBuffer = ""
    }
}

// MARK: - KeyboardMonitorDelegate
extension RecordManager: KeyboardMonitorDelegate {
    func keyboardMonitor(_ monitor: KeyboardMonitorService, didReceiveCharacter char: String) {
        guard !isPaused else { return }

        // If select all was active and user types, it replaces selected text
        if selectAllActive {
            keyboardBuffer = ""
            cursorPosition = nil
            selectAllActive = false
        }
        
        if keyboardBuffer.isEmpty {
            bufferAppContext = appFocusMonitor.activeAppName
            cursorPosition = nil
        }

        // Insert character at cursor position
        let insertPos = safeCursorPosition
        keyboardBuffer.insert(contentsOf: char, at: insertPos)
        
        // Move cursor forward after insertion
        safeCursorPosition = keyboardBuffer.index(insertPos, offsetBy: char.count)
    }

    func keyboardMonitorDidReceiveBackspace(_ monitor: KeyboardMonitorService) {
        guard !isPaused else { return }

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
        guard !isPaused else { return }
        
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
        guard !isPaused else { return }
        
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
        
        print("[RecordManager] 🗑️ Deleted word, buffer now: '\(keyboardBuffer)'")
    }
    
    func keyboardMonitorDidReceiveDeleteLine(_ monitor: KeyboardMonitorService, forward: Bool) {
        guard !isPaused else { return }
        
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
        
        print("[RecordManager] 🗑️ Deleted line, buffer now: '\(keyboardBuffer)'")
    }
    
    func keyboardMonitorDidReceiveSelectAll(_ monitor: KeyboardMonitorService) {
        guard !isPaused else { return }
        
        // Mark that select all is active - next delete or character input will handle it
        selectAllActive = true
        print("[RecordManager] 📋 Select all detected, marking for potential deletion")
    }
    
    func keyboardMonitor(_ monitor: KeyboardMonitorService, didNavigate direction: CursorNavigation) {
        guard !isPaused else { return }
        
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
        guard !isPaused else { return }
        
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
        guard !isPaused else { return }
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
        
        // FILTER 1: Skip single characters (likely accidental or incomplete)
        if content.count <= 1 {
            print("[RecordManager] ⏭️ Skipping Wispr single character: '\(content)'")
            return
        }
        
        // FILTER 2: Skip numbers-only entries (likely passwords, codes, or numeric input)
        let nonNumericCharacters = content.rangeOfCharacter(from: CharacterSet.decimalDigits.inverted)
        if nonNumericCharacters == nil {
            print("[RecordManager] ⏭️ Skipping Wispr numbers-only entry: '\(content)'")
            return
        }
        
        // FILTER 3: Skip entries with less than 5 non-space characters
        // Count only actual letters/characters, ignoring spaces
        let nonSpaceCharacters = content.replacingOccurrences(of: " ", with: "")
        if nonSpaceCharacters.count < 5 {
            print("[RecordManager] ⏭️ Skipping Wispr entry with less than 5 non-space characters: '\(content)' (non-space count: \(nonSpaceCharacters.count))")
            return
        }
        
        // FILTER 4: Check if content looks like natural language first
        let isNaturalLanguage = hasEnoughVowels(content) && !hasTooManySpecialCharacters(content)
        
        // FILTER 5: Skip if looks like terminal commands
        // But allow natural language conversations even in terminals (e.g., Claude Code)
        if looksLikeTerminalCommand(content) {
            print("[RecordManager] ⏭️ Skipping Wispr terminal command pattern: '\(content)'")
            return
        }
        
        // FILTER 6: For terminal apps, only block if it's NOT natural language
        // This allows conversations with LLMs in terminals while blocking actual commands
        if isTerminalApp(appFocusMonitor.activeAppName) && !isNaturalLanguage {
            print("[RecordManager] ⏭️ Skipping Wispr non-natural language entry from terminal app '\(appFocusMonitor.activeAppName)': '\(content)'")
            return
        }
        
        // FILTER 7: Skip if too many special characters (likely code/commands)
        // But only if it's not from a terminal (where we already checked)
        if !isTerminalApp(appFocusMonitor.activeAppName) && hasTooManySpecialCharacters(content) {
            print("[RecordManager] ⏭️ Skipping Wispr entry with too many special characters: '\(content)'")
            return
        }
        
        // FILTER 8: Skip if doesn't contain enough vowels (likely not natural language)
        // But only if it's not from a terminal (where we already checked)
        if !isTerminalApp(appFocusMonitor.activeAppName) && !hasEnoughVowels(content) {
            print("[RecordManager] ⏭️ Skipping Wispr entry with insufficient vowels: '\(content)'")
            return
        }
        
        // Check in-memory set to prevent duplicates
        var shouldProcess = false
        wisprDeduplicationQueue.sync {
            if !recentWisprContent.contains(content) {
                recentWisprContent.insert(content)
                shouldProcess = true
                
                // FIXED: Reduced from 60 seconds to 5 seconds
                // This allows same text to be saved again after a short period
                DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
                    self?.wisprDeduplicationQueue.async {
                        self?.recentWisprContent.remove(content)
                    }
                }
            } else {
                print("[RecordManager] ⏭️ Duplicate Wispr content skipped: \(content.prefix(50))...")
            }
        }
        
        guard shouldProcess else { return }
        
        print("[RecordManager] ✅ Saving Wispr record: \(content.prefix(50))...")

        let record = Record(
            source: .wispr,
            content: content,
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
    }
}

// MARK: - Intelligent Filter Helpers
private extension RecordManager {
    /// Check if the app is a terminal application
    func isTerminalApp(_ appName: String) -> Bool {
        let terminalApps = [
            "Warp", "Terminal", "iTerm", "iTerm2", "Alacritty", 
            "Hyper", "Kitty", "WezTerm", "Terminator"
        ]
        return terminalApps.contains { appName.localizedCaseInsensitiveContains($0) }
    }
    
    /// Detect if content looks like terminal commands
    func looksLikeTerminalCommand(_ content: String) -> Bool {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Common shell commands at the start
        let shellCommands = [
            "cd ", "ls ", "git ", "npm ", "yarn ", "python ", "node ", 
            "sudo ", "brew ", "docker ", "kubectl ", "ssh ", "scp ",
            "mv ", "cp ", "rm ", "mkdir ", "touch ", "cat ", "grep ",
            "find ", "ps ", "kill ", "chmod ", "chown ", "tar ", "zip ",
            "unzip ", "curl ", "wget ", "ping ", "ifconfig ", "netstat "
        ]
        
        for command in shellCommands {
            if trimmed.lowercased().hasPrefix(command.lowercased()) {
                return true
            }
        }
        
        // Check for command patterns: multiple short words separated by spaces
        // (e.g., "cd .. ls cd" = 3 words, all 2 chars or less)
        // BUT: Skip this check if content looks like natural language (has vowels)
        let hasNaturalLanguageIndicators = hasEnoughVowels(trimmed)
        
        if !hasNaturalLanguageIndicators {
            let words = trimmed.components(separatedBy: .whitespaces)
            if words.count >= 2 {
                let shortWords = words.filter { $0.count <= 2 && !$0.isEmpty }
                // If more than 50% are very short words, likely commands
                if shortWords.count >= words.count / 2 && words.count >= 3 {
                    return true
                }
            }
        }
        
        // Check for path-like patterns
        // Only flag "/" at the start (absolute paths like /usr/bin)
        // Allow "/" in the middle (natural language like "day/week", URLs, etc.)
        if trimmed.hasPrefix("/") {
            // Absolute path detected (e.g., /usr/bin, /path/to/file)
            return true
        }
        
        // Check for relative paths (./file, ../file)
        if trimmed.hasPrefix("./") || trimmed.hasPrefix("../") {
            return true
        }
        
        // Check for command chaining patterns (|, &&, ||, ;)
        if trimmed.contains("|") || trimmed.contains("&&") || 
           trimmed.contains("||") || trimmed.contains(";") {
            return true
        }
        
        return false
    }
    
    /// Check if content has too many special characters (likely code/commands)
    /// Excludes common punctuation used in natural language (?, !, ., ,)
    func hasTooManySpecialCharacters(_ content: String) -> Bool {
        // Exclude common punctuation that's normal in conversation
        let commonPunctuation = CharacterSet(charactersIn: "?!.,")
        // Focus on code-like special characters
        let codeSpecialChars = CharacterSet(charactersIn: "@#$%^&*()_+-=[]{}|;':\"/<>`~")
        
        let codeCharCount = content.unicodeScalars.filter { codeSpecialChars.contains($0) }.count
        let letterCount = content.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
        
        // If there are letters, check ratio of code chars to letters
        // If more than 25% are code-like special characters, likely not natural text
        if letterCount > 0 {
            let codeCharRatio = Double(codeCharCount) / Double(letterCount)
            return codeCharRatio > 0.25
        }
        
        // If no letters, check against total length
        let totalCharCount = content.count
        if totalCharCount > 0 {
            let codeCharRatio = Double(codeCharCount) / Double(totalCharCount)
            return codeCharRatio > 0.20
        }
        
        return false
    }
    
    /// Check if content has enough vowels to be natural language
    func hasEnoughVowels(_ content: String) -> Bool {
        let vowels = CharacterSet(charactersIn: "aeiouAEIOU")
        let vowelCount = content.unicodeScalars.filter { vowels.contains($0) }.count
        let letterCount = content.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
        
        // Need at least 20% vowels if there are letters
        if letterCount > 0 {
            let vowelRatio = Double(vowelCount) / Double(letterCount)
            return vowelRatio >= 0.20
        }
        
        // If no letters at all, probably not words
        return false
    }
}
