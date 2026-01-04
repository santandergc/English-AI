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

        if keyboardBuffer.isEmpty {
            bufferAppContext = appFocusMonitor.activeAppName
        }

        keyboardBuffer.append(char)
    }

    func keyboardMonitorDidReceiveBackspace(_ monitor: KeyboardMonitorService) {
        guard !isPaused else { return }

        if !keyboardBuffer.isEmpty {
            keyboardBuffer.removeLast()
        }
    }

    func keyboardMonitorDidDetectIdle(_ monitor: KeyboardMonitorService) {
        guard !isPaused else { return }
        flushKeyboardBuffer()
    }
}

// MARK: - ClipboardMonitorDelegate
extension RecordManager: ClipboardMonitorDelegate {
    func clipboardMonitor(_ monitor: ClipboardMonitorService, didDetectWisprText text: String) {
        guard !isPaused else { return }

        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        
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
