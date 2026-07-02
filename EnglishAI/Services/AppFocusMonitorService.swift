import Foundation
import AppKit

protocol AppFocusMonitorDelegate: AnyObject {
    func appFocusMonitor(_ monitor: AppFocusMonitorService, didChangeFocusTo appName: String)
}

final class AppFocusMonitorService {
    weak var delegate: AppFocusMonitorDelegate?

    private var currentApp: String = ""
    private var currentBundleIdentifier: String?
    private var currentProcessIdentifier: pid_t?
    private var observers: [NSObjectProtocol] = []

    private var isMonitoring = false

    var activeAppName: String {
        // If current app is empty, try to get it now
        if currentApp.isEmpty {
            if let frontApp = NSWorkspace.shared.frontmostApplication,
               frontApp.bundleIdentifier != Bundle.main.bundleIdentifier,
               let appName = frontApp.localizedName {
                return appName
            }
        }
        return currentApp.isEmpty ? "Unknown" : currentApp
    }

    var activeBundleIdentifier: String? {
        if currentBundleIdentifier == nil {
            updateCurrentApp()
        }
        return currentBundleIdentifier
    }

    var activeProcessIdentifier: pid_t? {
        if currentProcessIdentifier == nil {
            updateCurrentApp()
        }
        return currentProcessIdentifier
    }

    func startMonitoring() {
        guard !isMonitoring else { return }

        // Get initial focused app
        updateCurrentApp()

        // Observe app activation changes
        let activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleAppActivation(notification)
        }
        observers.append(activationObserver)

        // Also observe when our app loses focus
        let deactivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didDeactivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // After deactivation, update to the new frontmost app
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.updateCurrentApp()
            }
        }
        observers.append(deactivationObserver)

        isMonitoring = true
    }

    func stopMonitoring() {
        guard isMonitoring else { return }

        for observer in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observers.removeAll()

        isMonitoring = false
    }

    private func handleAppActivation(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return
        }
        
        // Skip if it's our own app
        if app.bundleIdentifier == Bundle.main.bundleIdentifier {
            return
        }
        
        guard let appName = app.localizedName else {
            return
        }

        if appName != currentApp || app.bundleIdentifier != currentBundleIdentifier || app.processIdentifier != currentProcessIdentifier {
            let oldApp = currentApp
            currentApp = appName
            currentBundleIdentifier = app.bundleIdentifier
            currentProcessIdentifier = app.processIdentifier

            if !oldApp.isEmpty {
                delegate?.appFocusMonitor(self, didChangeFocusTo: appName)
            }
        }
    }

    private func updateCurrentApp() {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            return
        }
        
        // Skip if it's our own app
        if frontApp.bundleIdentifier == Bundle.main.bundleIdentifier {
            return
        }
        
        guard let appName = frontApp.localizedName else {
            return
        }

        if appName != currentApp || frontApp.bundleIdentifier != currentBundleIdentifier || frontApp.processIdentifier != currentProcessIdentifier {
            let oldApp = currentApp
            currentApp = appName
            currentBundleIdentifier = frontApp.bundleIdentifier
            currentProcessIdentifier = frontApp.processIdentifier

            if !oldApp.isEmpty {
                delegate?.appFocusMonitor(self, didChangeFocusTo: appName)
            }
        }
    }
}
