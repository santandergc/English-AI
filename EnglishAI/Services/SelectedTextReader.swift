import Foundation
import AppKit
import ApplicationServices
import CoreGraphics

enum SelectedTextReaderError: LocalizedError {
    case noSelection
    case blockedApp(String)
    case replacementUnavailable

    var errorDescription: String? {
        switch self {
        case .noSelection:
            return "Select text in any app, then press Option+E twice."
        case .blockedApp(let appName):
            return "\(appName) is blocked in Trust Center."
        case .replacementUnavailable:
            return "The selected app could not be reactivated for replacement."
        }
    }
}

final class SelectedTextReader {
    static let shared = SelectedTextReader()

    private init() {}

    func captureSelectedText() async throws -> SelectedTextCapture {
        let app = NSWorkspace.shared.frontmostApplication
        let appName = app?.localizedName ?? "Unknown"
        let mouseFrame = mouseAnchorFrame()

        guard TrustCenter.shared.canAnalyzeSelectedText(from: appName) else {
            throw SelectedTextReaderError.blockedApp(appName)
        }

        if let selection = readSelectionViaAccessibility(),
           !selection.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return SelectedTextCapture(
                text: selection.text,
                appName: appName,
                bundleIdentifier: app?.bundleIdentifier,
                processIdentifier: app?.processIdentifier,
                method: .accessibility,
                selectionFrame: selection.frame ?? mouseFrame
            )
        }

        if let text = await readSelectionViaClipboardFallback(), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return SelectedTextCapture(
                text: text,
                appName: appName,
                bundleIdentifier: app?.bundleIdentifier,
                processIdentifier: app?.processIdentifier,
                method: .clipboardFallback,
                selectionFrame: mouseFrame
            )
        }

        throw SelectedTextReaderError.noSelection
    }

    func replaceSelection(with text: String, target: SelectedTextCapture) async throws {
        let targetApp = runningApplication(for: target)
        guard let targetApp else {
            throw SelectedTextReaderError.replacementUnavailable
        }

        let pasteboard = NSPasteboard.general
        let savedItems = savedPasteboardItems(from: pasteboard)

        RecordManager.shared.setClipboardCaptureSuppressed(true)
        defer { RecordManager.shared.setClipboardCaptureSuppressed(false) }

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        targetApp.activate(options: [.activateIgnoringOtherApps])
        try? await Task.sleep(nanoseconds: 180_000_000)
        postKeyboardShortcut(keyCode: 9, flags: .maskCommand) // V
        try? await Task.sleep(nanoseconds: 250_000_000)

        restorePasteboardItems(savedItems, to: pasteboard)
    }

    private struct AccessibilitySelection {
        let text: String
        let frame: CGRect?
    }

    private func readSelectionViaAccessibility() -> AccessibilitySelection? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedValue: CFTypeRef?
        let focusResult = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedValue)

        guard focusResult == .success, let focusedValue else { return nil }
        let focusedElement = focusedValue as! AXUIElement

        var selectedTextValue: CFTypeRef?
        let selectedTextResult = AXUIElementCopyAttributeValue(focusedElement, kAXSelectedTextAttribute as CFString, &selectedTextValue)

        guard selectedTextResult == .success else { return nil }
        guard let selectedText = selectedTextValue as? String else { return nil }
        return AccessibilitySelection(text: selectedText, frame: selectedTextFrame(from: focusedElement))
    }

    private func readSelectionViaClipboardFallback() async -> String? {
        let pasteboard = NSPasteboard.general
        let savedItems = savedPasteboardItems(from: pasteboard)
        let startingChangeCount = pasteboard.changeCount

        RecordManager.shared.setClipboardCaptureSuppressed(true)
        defer { RecordManager.shared.setClipboardCaptureSuppressed(false) }

        pasteboard.clearContents()
        postKeyboardShortcut(keyCode: 8, flags: .maskCommand) // C

        var selectedText: String?
        for _ in 0..<8 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            if pasteboard.changeCount != startingChangeCount,
               let value = pasteboard.string(forType: .string),
               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                selectedText = value
                break
            }
        }

        restorePasteboardItems(savedItems, to: pasteboard)
        return selectedText
    }

    private func savedPasteboardItems(from pasteboard: NSPasteboard) -> [NSPasteboardItem] {
        pasteboard.pasteboardItems?.map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                } else if let string = item.string(forType: type) {
                    copy.setString(string, forType: type)
                }
            }
            return copy
        } ?? []
    }

    private func restorePasteboardItems(_ items: [NSPasteboardItem], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        pasteboard.writeObjects(items)
    }

    private func postKeyboardShortcut(keyCode: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        keyDown?.flags = flags
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        keyUp?.flags = flags

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    private func runningApplication(for capture: SelectedTextCapture) -> NSRunningApplication? {
        if let processIdentifier = capture.processIdentifier,
           let app = NSRunningApplication(processIdentifier: processIdentifier),
           !app.isTerminated {
            return app
        }

        if let bundleIdentifier = capture.bundleIdentifier {
            return NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first
        }

        return nil
    }

    private func selectedTextFrame(from element: AXUIElement) -> CGRect? {
        var rangeReference: CFTypeRef?
        let rangeResult = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeReference)
        guard rangeResult == .success, let rangeReference else { return nil }
        let rangeValue = rangeReference as! AXValue

        var range = CFRange()
        guard AXValueGetValue(rangeValue, .cfRange, &range), range.length > 0 else { return nil }
        guard let rangeParameter = AXValueCreate(.cfRange, &range) else { return nil }

        var boundsReference: CFTypeRef?
        let boundsResult = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeParameter,
            &boundsReference
        )

        guard boundsResult == .success, let boundsReference else { return nil }
        let boundsValue = boundsReference as! AXValue

        var rect = CGRect.zero
        guard AXValueGetValue(boundsValue, .cgRect, &rect), !rect.isNull, !rect.isEmpty else { return nil }
        return normalizedAccessibilityRect(rect)
    }

    private func normalizedAccessibilityRect(_ rect: CGRect) -> CGRect {
        guard let screen = screen(forX: rect.midX) else { return rect }

        return CGRect(
            x: rect.minX,
            y: screen.frame.maxY - rect.maxY + screen.frame.minY,
            width: rect.width,
            height: rect.height
        )
    }

    private func screen(forX x: CGFloat) -> NSScreen? {
        NSScreen.screens.first { screen in
            x >= screen.frame.minX && x <= screen.frame.maxX
        } ?? NSScreen.main
    }

    private func mouseAnchorFrame() -> CGRect {
        let mouse = NSEvent.mouseLocation
        return CGRect(x: mouse.x - 4, y: mouse.y - 4, width: 8, height: 8)
    }
}

private extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}
