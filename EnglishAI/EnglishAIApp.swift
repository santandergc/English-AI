import SwiftUI
import AppKit

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
    private let permissionsCheckedKey = "hasCheckedAccessibilityPermissions"

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        setupRecordManager()
        // Delay permission check slightly to allow system to recognize permissions
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.checkAccessibilityPermissions()
        }
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

        let permissionsItem = NSMenuItem(title: "Check Permissions...", action: #selector(openPermissions), keyEquivalent: "")
        permissionsItem.target = self
        menu.addItem(permissionsItem)

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

    private func checkAccessibilityPermissions() {
        // Check WITHOUT prompting (to avoid showing dialog if already granted)
        let checkOptions = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: false] as CFDictionary
        let accessEnabled = AXIsProcessTrustedWithOptions(checkOptions)

        if accessEnabled {
            print("Accessibility permissions are granted")
            hasShownPermissionAlert = false
            // Remember that permissions are granted
            UserDefaults.standard.set(true, forKey: permissionsCheckedKey)
            return
        }

        // Permissions not granted
        // Check if permissions were previously granted (might have been revoked)
        let werePreviouslyGranted = UserDefaults.standard.bool(forKey: permissionsCheckedKey)
        
        // Only show alert once per app session if permissions are missing
        if !hasShownPermissionAlert {
            hasShownPermissionAlert = true
            if werePreviouslyGranted {
                print("Accessibility permissions appear to have been revoked")
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.showPermissionAlert()
            }
        } else {
            // Already shown in this session
            print("Accessibility permissions not granted (alert already shown)")
        }
        
        // Remember that we checked (even if not granted)
        UserDefaults.standard.set(false, forKey: permissionsCheckedKey)
    }

    private func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = "EnglishAI needs Accessibility access to monitor keyboard input.\n\nPlease grant permission in System Settings > Privacy & Security > Accessibility."
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
        recordManager?.stopMonitoring()
    }
}
