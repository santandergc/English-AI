import Foundation
import CoreGraphics
import ApplicationServices

final class SelectionShortcutMonitorService {
    static let shared = SelectionShortcutMonitorService()

    var onShortcut: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isMonitoring = false
    private var lastOptionEPress: Date?
    private let doublePressWindow: TimeInterval = 1.0

    private init() {}

    func startMonitoring() {
        guard !isMonitoring else { return }
        guard TrustCenter.shared.selectedTextShortcutEnabled else { return }

        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else { return }

        let eventMask = 1 << CGEventType.keyDown.rawValue
        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let refcon else { return Unmanaged.passRetained(event) }
            let monitor = Unmanaged<SelectionShortcutMonitorService>.fromOpaque(refcon).takeUnretainedValue()
            return monitor.handleEvent(proxy: proxy, type: type, event: event)
        }

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let eventTap else { return }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        guard let runLoopSource else {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            self.eventTap = nil
            return
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        isMonitoring = true
    }

    func stopMonitoring() {
        guard isMonitoring else { return }

        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }

        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }

        eventTap = nil
        runLoopSource = nil
        lastOptionEPress = nil
        isMonitoring = false
    }

    func refreshMonitoringState() {
        if TrustCenter.shared.selectedTextShortcutEnabled {
            startMonitoring()
        } else {
            stopMonitoring()
        }
    }

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passRetained(event)
        }

        guard type == .keyDown else {
            return Unmanaged.passRetained(event)
        }

        guard TrustCenter.shared.selectedTextShortcutEnabled else {
            return Unmanaged.passRetained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        let flags = event.flags
        let isPlainOptionE = keyCode == 14 &&
            flags.contains(.maskAlternate) &&
            !flags.contains(.maskCommand) &&
            !flags.contains(.maskControl) &&
            !flags.contains(.maskShift)

        guard isPlainOptionE else {
            return Unmanaged.passRetained(event)
        }

        guard !isRepeat else {
            return nil
        }

        let now = Date()
        if let lastPress = lastOptionEPress, now.timeIntervalSince(lastPress) <= doublePressWindow {
            lastOptionEPress = nil
            DispatchQueue.main.async { [weak self] in
                self?.onShortcut?()
            }
        } else {
            lastOptionEPress = now
        }

        return nil
    }
}
