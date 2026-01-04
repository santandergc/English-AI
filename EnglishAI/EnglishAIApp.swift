import SwiftUI
import AppKit
import CoreGraphics

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

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        setupRecordManager()
        
        // Listen for app becoming active (user might have granted permissions)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        
        // Delay permission check to allow system to recognize permissions
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.checkAccessibilityPermissionsWithRetry()
        }
    }
    
    @objc func applicationDidBecomeActive(_ notification: Notification) {
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

        let statusMenuItem = NSMenuItem(title: "EnglishAI", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        menu.addItem(NSMenuItem.separator())

        let openItem = NSMenuItem(title: "Open EnglishAI", action: #selector(openMainWindow), keyEquivalent: "o")
        openItem.target = self
        menu.addItem(openItem)

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
        recordManager?.stopMonitoring()
    }
}
