import SwiftUI
import AppKit
import CoreGraphics
import Combine

@main
struct EnglishAIApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var recordManager: RecordManager?
    private var hasShownPermissionAlert = false
    private var isCheckingPermissions = false  // Prevent parallel permission checks
    private var hasCompletedInitialCheck = false
    private let permissionsCheckedKey = "hasCheckedAccessibilityPermissions"
    private let permissionsGrantedKey = "accessibilityPermissionsGranted"

    // Voice recording status bar support
    private var voiceRecordingCancellables = Set<AnyCancellable>()
    private var menuUpdateTimer: Timer?
    private var showStopConfirmationAlert: Bool = false
    private var durationAtStopRequest: TimeInterval = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        setupRecordManager()
        setupVoiceRecordingObservers()
        setupSelectedTextReview()

        // Listen for app becoming active (user might have granted permissions)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(trustCenterSettingsDidChange),
            name: .trustCenterSettingsChanged,
            object: nil
        )

        // Daily-preparation triggers. An always-running menu bar app may not
        // "activate" for days, so the Morning Brief rides several redundant
        // signals: launch, activation, popover open, machine wake, day change.
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(machineDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(calendarDayDidChange),
            name: .NSCalendarDayChanged,
            object: nil
        )
        FocusQueueService.shared.ensureTodayPrepared()

        // Delay permission check to allow system to recognize permissions
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.checkAccessibilityPermissionsWithRetry()
        }
    }

    @objc private func machineDidWake(_ notification: Notification) {
        FocusQueueService.shared.ensureTodayPrepared()
    }

    @objc private func calendarDayDidChange(_ notification: Notification) {
        DispatchQueue.main.async {
            FocusQueueService.shared.ensureTodayPrepared()
        }
    }

    @objc func applicationDidBecomeActive(_ notification: Notification) {
        FocusQueueService.shared.ensureTodayPrepared()

        // Check permissions when app becomes active (user might have just granted them)
        // Only check if initial check is complete and we don't have permissions yet
        guard hasCompletedInitialCheck,
              !isCheckingPermissions,
              !UserDefaults.standard.bool(forKey: permissionsGrantedKey) else {
            return
        }
        checkAccessibilityPermissionsWithRetry()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            for window in sender.windows {
                window.makeKeyAndOrderFront(self)
            }
        }
        return true
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "EnglishAI")
        }

        setupMenu()
    }

    private func setupMenu() {
        let menu = NSMenu()
        menu.delegate = self  // menuWillOpen doubles as a daily-preparation trigger

        let statusMenuItem = NSMenuItem(title: "EnglishAI", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        menu.addItem(NSMenuItem.separator())

        let fixSelectedTextItem = NSMenuItem(
            title: "Fix Selected Text",
            action: #selector(reviewSelectedTextFromMenu),
            keyEquivalent: ""
        )
        fixSelectedTextItem.target = self
        menu.addItem(fixSelectedTextItem)

        let shortcutItem = NSMenuItem(
            title: "Option+E Twice Shortcut",
            action: #selector(toggleSelectedTextShortcut),
            keyEquivalent: ""
        )
        shortcutItem.target = self
        shortcutItem.state = TrustCenter.shared.selectedTextShortcutEnabled ? .on : .off
        menu.addItem(shortcutItem)

        menu.addItem(NSMenuItem.separator())

        let trustCenterItem = NSMenuItem(title: "Trust Center...", action: #selector(openTrustCenter), keyEquivalent: "")
        trustCenterItem.target = self
        menu.addItem(trustCenterItem)

        let captureItem = NSMenuItem(
            title: TrustCenter.shared.captureEnabled ? "Pause Capture" : "Resume Capture",
            action: #selector(toggleTrustCenterCapture),
            keyEquivalent: ""
        )
        captureItem.target = self
        menu.addItem(captureItem)

        let blockCurrentAppItem = NSMenuItem(
            title: "Block Current App...",
            action: #selector(blockCurrentAppFromMenu),
            keyEquivalent: ""
        )
        blockCurrentAppItem.target = self
        menu.addItem(blockCurrentAppItem)

        menu.addItem(NSMenuItem.separator())

        // Voice Recording section - show when recording is active
        let isVoiceRecording = VoiceRecordingService.shared.isRecording
        if isVoiceRecording {
            let recordingStatusItem = NSMenuItem(
                title: "Recording... \(formatDuration(VoiceRecordingService.shared.currentDuration))",
                action: nil,
                keyEquivalent: ""
            )
            recordingStatusItem.isEnabled = false
            recordingStatusItem.tag = 100  // Tag for dynamic updates
            menu.addItem(recordingStatusItem)

            let stopRecordingItem = NSMenuItem(
                title: "Stop Recording",
                action: #selector(stopVoiceRecordingWithConfirmation),
                keyEquivalent: ""
            )
            stopRecordingItem.target = self
            menu.addItem(stopRecordingItem)

            menu.addItem(NSMenuItem.separator())
        }

        let openItem = NSMenuItem(title: "Open EnglishAI", action: #selector(openMainWindow), keyEquivalent: "o")
        openItem.target = self
        menu.addItem(openItem)

        let focusItem = NSMenuItem(title: "Focus Queue & Morning Brief", action: #selector(openMainWindow), keyEquivalent: "f")
        focusItem.target = self
        menu.addItem(focusItem)

        menu.addItem(NSMenuItem.separator())

        let pauseItem = NSMenuItem(title: "Pause Recording", action: #selector(toggleRecording), keyEquivalent: "p")
        pauseItem.target = self
        menu.addItem(pauseItem)

        menu.addItem(NSMenuItem.separator())

        let permissionsItem = NSMenuItem(title: "Check Permissions...", action: #selector(checkAndShowPermissions), keyEquivalent: "")
        permissionsItem.target = self
        menu.addItem(permissionsItem)

        let resetPermissionsItem = NSMenuItem(title: "Reset Permission State", action: #selector(resetPermissionState), keyEquivalent: "")
        resetPermissionsItem.target = self
        menu.addItem(resetPermissionsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit EnglishAI", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    private func setupRecordManager() {
        recordManager = RecordManager.shared
        recordManager?.startMonitoring()
    }

    private func setupSelectedTextReview() {
        SelectionShortcutMonitorService.shared.onShortcut = { [weak self] in
            self?.reviewSelectedTextFromMenu()
        }
        SelectionShortcutMonitorService.shared.startMonitoring()
    }

    @objc private func reviewSelectedTextFromMenu() {
        Task { @MainActor in
            SelectedTextReviewWindowController.shared.reviewCurrentSelection()
        }
    }

    @objc private func openTrustCenter() {
        let appName = TrustCenter.shared.frontmostAppName
        Task { @MainActor in
            TrustCenterWindowController.shared.show(initialAppName: appName)
        }
    }

    @objc private func toggleTrustCenterCapture() {
        TrustCenter.shared.captureEnabled.toggle()
        setupMenu()
        restoreNormalMenuBarIcon()
    }

    @objc private func toggleSelectedTextShortcut() {
        TrustCenter.shared.selectedTextShortcutEnabled.toggle()
        SelectionShortcutMonitorService.shared.refreshMonitoringState()
        setupMenu()
    }

    @objc private func blockCurrentAppFromMenu() {
        let appName = TrustCenter.shared.frontmostAppName
        let alert = NSAlert()
        alert.messageText = "Block \(appName)?"
        alert.informativeText = "EnglishAI will stop saving typing and Wispr text from this app. Selected-text AI review is also blocked for this app."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Block App")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            TrustCenter.shared.addBlockedApp(appName)
            setupMenu()
        }
    }

    @objc private func trustCenterSettingsDidChange() {
        SelectionShortcutMonitorService.shared.refreshMonitoringState()
        setupMenu()
        if !VoiceRecordingService.shared.isRecording {
            restoreNormalMenuBarIcon()
        }
    }

    private func checkAccessibilityPermissionsWithRetry(retryCount: Int = 0, maxRetries: Int = 3) {
        // Prevent multiple parallel checks
        guard !isCheckingPermissions || retryCount > 0 else {
            print("⚠️ Permission check already in progress, skipping")
            return
        }
        
        if retryCount == 0 {
            isCheckingPermissions = true
        }
        
        // Check using AXIsProcessTrustedWithOptions (without prompting)
        let checkOptions = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        let axTrusted = AXIsProcessTrustedWithOptions(checkOptions)
        
        if axTrusted {
            print("✅ Accessibility permissions are granted (AXIsProcessTrusted = true)")
            hasShownPermissionAlert = false
            isCheckingPermissions = false
            hasCompletedInitialCheck = true
            UserDefaults.standard.set(true, forKey: permissionsGrantedKey)
            UserDefaults.standard.set(true, forKey: permissionsCheckedKey)
            return
        }
        
        // AX check says not trusted - retry a few times (macOS can be slow)
        if retryCount < maxRetries {
            let delay = 1.0 // 1 second between retries
            print("⏳ Permissions check returned false, retrying in \(delay)s... (attempt \(retryCount + 1)/\(maxRetries))")
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                self.checkAccessibilityPermissionsWithRetry(retryCount: retryCount + 1, maxRetries: maxRetries)
            }
            return
        }
        
        // After all retries, permissions are truly not granted for THIS app instance
        // This can happen when running from Xcode (different path than installed app)
        print("❌ Accessibility permissions not granted after \(maxRetries) attempts")
        print("ℹ️ Note: If you see EnglishAI enabled in System Settings, it may be a different build.")
        print("ℹ️ This app is running from: \(Bundle.main.bundlePath)")
        
        isCheckingPermissions = false
        hasCompletedInitialCheck = true
        UserDefaults.standard.set(false, forKey: permissionsGrantedKey)
        UserDefaults.standard.set(false, forKey: permissionsCheckedKey)
        
        // Only show alert once per session
        if !hasShownPermissionAlert {
            hasShownPermissionAlert = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.showPermissionAlert()
            }
        }
    }
    
    private func verifyAccessibilityPermissionsWork() -> Bool {
        // Use AXIsProcessTrustedWithOptions - this is the authoritative check
        // Note: Use takeUnretainedValue() for constants, not takeRetainedValue()
        let checkOptions = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        return AXIsProcessTrustedWithOptions(checkOptions)
    }
    
    private func checkAccessibilityPermissions() -> Bool {
        // Use the same verification method as the retry check
        let permissionsWork = verifyAccessibilityPermissionsWork()
        
        if permissionsWork {
            UserDefaults.standard.set(true, forKey: permissionsGrantedKey)
        } else {
            UserDefaults.standard.set(false, forKey: permissionsGrantedKey)
        }
        
        return permissionsWork
    }

    private func showPermissionAlert() {
        // First, trigger the system prompt to add this app to Accessibility
        // This will show macOS's native permission dialog if the app isn't already in the list
        let promptOptions = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let _ = AXIsProcessTrustedWithOptions(promptOptions)
        
        // Then show our custom alert with more context
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = """
            EnglishAI needs Accessibility access to monitor keyboard input.
            
            If you already enabled EnglishAI in System Settings but still see this message, you may need to:
            1. Remove the old EnglishAI entry from Accessibility
            2. Add this version of the app
            
            Current app location:
            \(Bundle.main.bundlePath)
            """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")

        if alert.runModal() == .alertFirstButtonReturn {
            openPermissions()
        }
    }

    @objc private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows {
            if window.canBecomeMain {
                window.makeKeyAndOrderFront(nil)
            }
        }
    }

    @objc private func toggleRecording() {
        if let item = statusItem?.menu?.item(withTitle: "Pause Recording") {
            recordManager?.pause()
            item.title = "Resume Recording"
            statusItem?.button?.image = NSImage(systemSymbolName: "keyboard.badge.ellipsis", accessibilityDescription: "EnglishAI (Paused)")
        } else if let item = statusItem?.menu?.item(withTitle: "Resume Recording") {
            recordManager?.resume()
            item.title = "Pause Recording"
            statusItem?.button?.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "EnglishAI")
        }
    }

    @objc private func checkAndShowPermissions() {
        let accessEnabled = checkAccessibilityPermissions()
        
        let alert = NSAlert()
        if accessEnabled {
            alert.messageText = "Permissions Granted ✅"
            alert.informativeText = "EnglishAI has Accessibility permissions enabled.\n\nThe app should be working correctly."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
        } else {
            alert.messageText = "Permissions Required"
            alert.informativeText = "EnglishAI needs Accessibility permissions to monitor keyboard input.\n\nPlease enable it in System Settings > Privacy & Security > Accessibility."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Cancel")
        }
        
        if alert.runModal() == .alertFirstButtonReturn && !accessEnabled {
            openPermissions()
        }
    }
    
    @objc private func resetPermissionState() {
        // Clear permission state - useful if UserDefaults got into a bad state
        UserDefaults.standard.removeObject(forKey: permissionsGrantedKey)
        UserDefaults.standard.removeObject(forKey: permissionsCheckedKey)
        hasShownPermissionAlert = false
        
        let alert = NSAlert()
        alert.messageText = "Permission State Reset"
        alert.informativeText = "Permission state has been reset. The app will check permissions again on next launch."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
        
        // Recheck permissions now
        checkAccessibilityPermissionsWithRetry()
    }
    
    @objc private func openPermissions() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quitApp() {
        recordManager?.stopMonitoring()
        NSApplication.shared.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        recordManager?.stopMonitoring()
        SelectionShortcutMonitorService.shared.stopMonitoring()
        menuUpdateTimer?.invalidate()
        voiceRecordingCancellables.removeAll()
    }

    // MARK: - Voice Recording Menu Bar Support

    private func setupVoiceRecordingObservers() {
        // Observe isRecording changes to update menu bar icon
        VoiceRecordingService.shared.$isRecording
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isRecording in
                self?.updateMenuBarForRecordingState(isRecording: isRecording)
            }
            .store(in: &voiceRecordingCancellables)
    }

    private func updateMenuBarForRecordingState(isRecording: Bool) {
        if isRecording {
            // Show recording indicator in menu bar
            updateMenuBarIconWithRecordingDot()
            startMenuUpdateTimer()
        } else {
            // Restore normal menu bar icon
            restoreNormalMenuBarIcon()
            stopMenuUpdateTimer()
        }
        // Rebuild menu to show/hide recording items
        setupMenu()
    }

    private func startMenuUpdateTimer() {
        // Update menu every second to show elapsed recording time
        menuUpdateTimer?.invalidate()
        menuUpdateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateRecordingMenuItem()
            }
        }
    }

    private func stopMenuUpdateTimer() {
        menuUpdateTimer?.invalidate()
        menuUpdateTimer = nil
    }

    private func updateRecordingMenuItem() {
        guard let menu = statusItem?.menu,
              let recordingItem = menu.item(withTag: 100) else { return }

        let duration = VoiceRecordingService.shared.currentDuration
        recordingItem.title = "Recording... \(formatDuration(duration))"
    }

    private func updateMenuBarIconWithRecordingDot() {
        guard let button = statusItem?.button else { return }

        // Create a composite image with the keyboard icon and a red recording dot
        let baseImage = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "EnglishAI (Recording)")
        let dotSize: CGFloat = 6
        let imageSize = NSSize(width: 18, height: 18)

        let compositeImage = NSImage(size: imageSize)
        compositeImage.lockFocus()

        // Draw the base keyboard icon
        if let base = baseImage {
            let baseRect = NSRect(origin: .zero, size: imageSize)
            base.draw(in: baseRect, from: .zero, operation: .sourceOver, fraction: 1.0)
        }

        // Draw a red dot in the top-right corner
        let dotRect = NSRect(
            x: imageSize.width - dotSize - 1,
            y: imageSize.height - dotSize - 1,
            width: dotSize,
            height: dotSize
        )
        NSColor.red.setFill()
        let dotPath = NSBezierPath(ovalIn: dotRect)
        dotPath.fill()

        compositeImage.unlockFocus()
        compositeImage.isTemplate = false  // Required to show red color

        button.image = compositeImage
    }

    private func restoreNormalMenuBarIcon() {
        guard let button = statusItem?.button else { return }
        let isPaused = recordManager?.isPaused ?? false
        if isPaused || !TrustCenter.shared.captureEnabled {
            button.image = NSImage(systemSymbolName: "keyboard.badge.ellipsis", accessibilityDescription: "EnglishAI (Paused)")
        } else {
            button.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "EnglishAI")
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(duration)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    @objc private func stopVoiceRecordingWithConfirmation() {
        let recordingService = VoiceRecordingService.shared

        // Check if we can stop (minimum duration)
        guard recordingService.canStop else {
            let secondsRemaining = Int(ceil(VoiceRecordingService.minimumDuration - recordingService.currentDuration))
            let alert = NSAlert()
            alert.messageText = "Cannot Stop Yet"
            alert.informativeText = "Minimum recording time not reached. Please wait \(secondsRemaining) more seconds."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }

        // Capture current duration for the confirmation dialog
        durationAtStopRequest = recordingService.currentDuration

        let alert = NSAlert()
        alert.messageText = "Stop Recording?"
        alert.informativeText = "You have recorded \(formatDuration(durationAtStopRequest)). Stop and transcribe this recording?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Stop & Transcribe")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            // User confirmed - stop the recording
            _ = recordingService.stopRecording()
        }
    }
}

// MARK: - NSMenuDelegate

extension AppDelegate: NSMenuDelegate {
    /// Opening the status menu doubles as a daily-preparation trigger
    /// (invisible; keeps the Morning Brief alive for an always-running app)
    func menuWillOpen(_ menu: NSMenu) {
        FocusQueueService.shared.ensureTodayPrepared()
    }
}
