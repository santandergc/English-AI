import Foundation
import CoreGraphics
import Carbon

/// Navigation direction for cursor movement
enum CursorNavigation {
    case left
    case right
    case wordLeft
    case wordRight
    case lineStart
    case lineEnd
    case up
    case down
}

protocol KeyboardMonitorDelegate: AnyObject {
    func keyboardMonitor(_ monitor: KeyboardMonitorService, didReceiveCharacter char: String)
    func keyboardMonitorDidReceiveBackspace(_ monitor: KeyboardMonitorService)
    func keyboardMonitorDidReceiveForwardDelete(_ monitor: KeyboardMonitorService)
    func keyboardMonitorDidReceiveDeleteWord(_ monitor: KeyboardMonitorService, forward: Bool)
    func keyboardMonitorDidReceiveDeleteLine(_ monitor: KeyboardMonitorService, forward: Bool)
    func keyboardMonitorDidReceiveSelectAll(_ monitor: KeyboardMonitorService)
    func keyboardMonitor(_ monitor: KeyboardMonitorService, didNavigate direction: CursorNavigation)
    func keyboardMonitorDidDetectMouseClick(_ monitor: KeyboardMonitorService)
    func keyboardMonitorDidDetectIdle(_ monitor: KeyboardMonitorService)
}

final class KeyboardMonitorService {
    weak var delegate: KeyboardMonitorDelegate?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var idleTimer: Timer?
    private let idleThreshold: TimeInterval = 10.0  // Longer idle = more complete text before saving

    private var isMonitoring = false

    func startMonitoring() {
        guard !isMonitoring else { return }

        // Check Accessibility permissions first
        // Note: Use takeUnretainedValue() for constants, not takeRetainedValue()
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        let accessEnabled = AXIsProcessTrustedWithOptions(options)
        
        if !accessEnabled {
            return
        }

        // Create event tap for key down and mouse click events
        // Mouse clicks indicate cursor repositioning which we can't track precisely
        let eventMask = (1 << CGEventType.keyDown.rawValue) | 
                        (1 << CGEventType.leftMouseDown.rawValue)

        // Use a callback that bridges to our instance method
        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let refcon = refcon else { return Unmanaged.passRetained(event) }
            let monitor = Unmanaged<KeyboardMonitorService>.fromOpaque(refcon).takeUnretainedValue()
            return monitor.handleEvent(proxy: proxy, type: type, event: event)
        }

        let refcon = Unmanaged.passUnretained(self).toOpaque()

        // Try creating event tap - use listenOnly since we only want to observe, not modify events
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,  // We only observe, don't modify events
            eventsOfInterest: CGEventMask(eventMask),
            callback: callback,
            userInfo: refcon
        )

        guard let eventTap = eventTap else {
            return
        }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)

        guard let runLoopSource = runLoopSource else {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            self.eventTap = nil
            return
        }

        // Ensure we add to the main run loop (required for event taps)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        
        isMonitoring = true
    }

    func stopMonitoring() {
        guard isMonitoring else { return }

        idleTimer?.invalidate()
        idleTimer = nil

        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }

        if let runLoopSource = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }

        eventTap = nil
        runLoopSource = nil
        isMonitoring = false
    }

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Handle tap disabled events (system may disable the tap)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap = eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passRetained(event)
        }
        
        // Handle mouse clicks - indicates potential cursor repositioning
        if type == .leftMouseDown {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.keyboardMonitorDidDetectMouseClick(self)
            }
            return Unmanaged.passRetained(event)
        }

        guard type == .keyDown else {
            return Unmanaged.passRetained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        let hasCommand = flags.contains(.maskCommand)
        let hasOption = flags.contains(.maskAlternate)
        let hasControl = flags.contains(.maskControl)
        
        // Reset idle timer on any keypress
        resetIdleTimer()
        
        // Handle Cmd+A (Select All) - keycode 0 is 'A'
        if hasCommand && keyCode == 0 {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.keyboardMonitorDidReceiveSelectAll(self)
            }
            return Unmanaged.passRetained(event)
        }
        
        // Handle arrow keys for cursor navigation
        // Left: 123, Right: 124, Down: 125, Up: 126
        let isLeftArrow = keyCode == 123
        let isRightArrow = keyCode == 124
        let isUpArrow = keyCode == 126
        let isDownArrow = keyCode == 125
        
        if isLeftArrow || isRightArrow || isUpArrow || isDownArrow {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                
                let direction: CursorNavigation
                if isLeftArrow {
                    if hasCommand {
                        direction = .lineStart
                    } else if hasOption {
                        direction = .wordLeft
                    } else {
                        direction = .left
                    }
                } else if isRightArrow {
                    if hasCommand {
                        direction = .lineEnd
                    } else if hasOption {
                        direction = .wordRight
                    } else {
                        direction = .right
                    }
                } else if isUpArrow {
                    direction = .up
                } else {
                    direction = .down
                }
                
                self.delegate?.keyboardMonitor(self, didNavigate: direction)
            }
            return Unmanaged.passRetained(event)
        }
        
        // Handle backspace (keycode 51) and delete (keycode 117)
        let isBackspace = keyCode == 51
        let isForwardDelete = keyCode == 117
        
        if isBackspace || isForwardDelete {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                
                if hasCommand {
                    // Cmd+Backspace = delete to beginning of line
                    // Cmd+Delete = delete to end of line
                    self.delegate?.keyboardMonitorDidReceiveDeleteLine(self, forward: isForwardDelete)
                } else if hasOption {
                    // Option+Backspace = delete word backward
                    // Option+Delete = delete word forward
                    self.delegate?.keyboardMonitorDidReceiveDeleteWord(self, forward: isForwardDelete)
                } else if isForwardDelete {
                    // Forward delete (fn+backspace or delete key)
                    self.delegate?.keyboardMonitorDidReceiveForwardDelete(self)
                } else {
                    // Regular backspace = single character backward
                    self.delegate?.keyboardMonitorDidReceiveBackspace(self)
                }
            }
            return Unmanaged.passRetained(event)
        }
        
        // FILTER: Ignore other keystrokes with modifier keys (Cmd, Ctrl, Alt/Option)
        // This prevents shortcuts like Cmd+C, Cmd+V, Cmd+B from being recorded
        if hasCommand || hasControl || hasOption {
            // Modifier key pressed - ignore this keystroke (it's a shortcut)
            return Unmanaged.passRetained(event)
        }

        // Get the character from the event
        if let characters = getCharactersFromEvent(event) {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.keyboardMonitor(self, didReceiveCharacter: characters)
            }
        }

        return Unmanaged.passRetained(event)
    }

    private func getCharactersFromEvent(_ event: CGEvent) -> String? {
        var length = 0
        event.keyboardGetUnicodeString(maxStringLength: 0, actualStringLength: &length, unicodeString: nil)

        guard length > 0 else { return nil }

        var chars = [UniChar](repeating: 0, count: length)
        event.keyboardGetUnicodeString(maxStringLength: length, actualStringLength: &length, unicodeString: &chars)

        let string = String(utf16CodeUnits: chars, count: length)

        // Filter out control characters except common ones like newline, tab
        let filtered = string.filter { char in
            let scalar = char.unicodeScalars.first!
            return scalar.value >= 32 || scalar.value == 9 || scalar.value == 10 || scalar.value == 13
        }

        return filtered.isEmpty ? nil : filtered
    }

    private func resetIdleTimer() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            self.idleTimer?.invalidate()
            self.idleTimer = Timer.scheduledTimer(withTimeInterval: self.idleThreshold, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                self.delegate?.keyboardMonitorDidDetectIdle(self)
            }
        }
    }
}
