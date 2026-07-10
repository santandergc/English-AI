import SwiftUI
import AppKit

@MainActor
final class TrustCenterWindowController {
    static let shared = TrustCenterWindowController()

    private var window: NSWindow?

    private init() {}

    func show(initialAppName: String? = nil) {
        let appName = initialAppName ?? TrustCenter.shared.frontmostAppName
        let root = TrustCenterView(initialAppName: appName, onClose: { [weak self] in self?.window?.close() })
        let hosting = NSHostingView(rootView: root)

        if window == nil {
            let trustWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 760, height: 680),
                styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            trustWindow.contentView = hosting
            trustWindow.title = "Trust Center"
            trustWindow.titlebarAppearsTransparent = true
            trustWindow.titleVisibility = .hidden
            trustWindow.isMovableByWindowBackground = true
            trustWindow.minSize = NSSize(width: 640, height: 540)
            window = trustWindow
        } else {
            window?.contentView = hosting
        }

        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct TrustCenterView: View {
    @ObservedObject private var trustCenter = TrustCenter.shared
    @State private var newBlockedApp = ""
    @State private var currentAppName: String
    @State private var lastAction: String?

    let onClose: () -> Void

    init(initialAppName: String, onClose: @escaping () -> Void) {
        _currentAppName = State(initialValue: initialAppName)
        self.onClose = onClose
    }

    var body: some View {
        ZStack {
            GlassBackground(material: .sidebar, blendingMode: .behindWindow)

            VStack(spacing: 0) {
                header
                Divider().opacity(0.35)

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        trustStatusCard
                        controlsCard
                        currentAppCard
                        blockedAppsCard
                        dataCard
                    }
                    .padding(22)
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.green.opacity(0.16))
                    .frame(width: 40, height: 40)
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.green)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Trust Center")
                    .font(.title3)
                    .fontWeight(.semibold)
                Text("Control what EnglishAI captures, blocks, and sends to AI.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: { currentAppName = trustCenter.frontmostAppName }) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh current app")

            Button(action: onClose) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
    }

    private var trustStatusCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: trustCenter.captureEnabled ? "checkmark.shield.fill" : "pause.circle.fill")
                .font(.title2)
                .foregroundColor(trustCenter.captureEnabled ? .green : .orange)

            VStack(alignment: .leading, spacing: 6) {
                Text(trustCenter.captureEnabled ? "Capture is on" : "Capture is paused")
                    .font(.headline)
                Text(statusDescription)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let lastAction {
                    Text(lastAction)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 2)
                }
            }

            Spacer()
        }
        .padding()
        .trustCard()
    }

    private var controlsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Controls", systemImage: "slider.horizontal.3")
                .font(.headline)

            Toggle("Capture typing and Wispr text", isOn: $trustCenter.captureEnabled)
            Toggle("Enable Option+E, Option+E selected-text review", isOn: $trustCenter.selectedTextShortcutEnabled)
            Toggle("Redact sensitive text before AI", isOn: $trustCenter.redactSensitiveTextBeforeAI)
            Toggle("Auto-block private apps", isOn: $trustCenter.blockPrivateAppsAutomatically)

            Text("Redaction replaces emails, phone numbers, cards, API keys, and long tokens with placeholders before AI calls.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .trustCard()
    }

    private var currentAppCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Current app", systemImage: "macwindow")
                .font(.headline)

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(currentAppName)
                        .font(.title3)
                        .fontWeight(.semibold)
                    Text(trustCenter.isBlocked(appName: currentAppName) ? "Blocked from capture and selected-text AI" : "Allowed")
                        .font(.caption)
                        .foregroundColor(trustCenter.isBlocked(appName: currentAppName) ? .orange : .green)
                }

                Spacer()

                if trustCenter.isBlocked(appName: currentAppName) {
                    Button("Allow app") {
                        trustCenter.removeBlockedApp(currentAppName)
                        lastAction = "\(currentAppName) is allowed."
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button("Block app") {
                        trustCenter.addBlockedApp(currentAppName)
                        lastAction = "\(currentAppName) is blocked."
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding()
        .trustCard()
    }

    private var blockedAppsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Blocked apps", systemImage: "hand.raised.fill")
                .font(.headline)

            HStack {
                TextField("App name, e.g. Slack", text: $newBlockedApp)
                    .textFieldStyle(.roundedBorder)
                Button("Add") {
                    trustCenter.addBlockedApp(newBlockedApp)
                    lastAction = "\(newBlockedApp) is blocked."
                    newBlockedApp = ""
                }
                .buttonStyle(.bordered)
                .disabled(newBlockedApp.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if trustCenter.blockedApps.isEmpty {
                Text("No custom blocked apps yet.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(trustCenter.blockedApps, id: \.self) { app in
                        HStack {
                            Image(systemName: "lock.fill")
                                .foregroundColor(.secondary)
                            Text(app)
                            Spacer()
                            Button("Remove") {
                                trustCenter.removeBlockedApp(app)
                                lastAction = "\(app) was removed from blocked apps."
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(10)
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(8)
                    }
                }
            }
        }
        .padding()
        .trustCard()
    }

    private var dataCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Data controls", systemImage: "externaldrive.badge.xmark")
                .font(.headline)

            Text("Delete captured text from apps you no longer trust, or clear all captured records. Exercise progress and settings are kept.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Delete blocked-app records") {
                    confirmDeleteBlockedAppRecords()
                }
                .buttonStyle(.bordered)
                .disabled(trustCenter.blockedApps.isEmpty)

                Button("Delete all captured records") {
                    confirmDeleteAllRecords()
                }
                .buttonStyle(.bordered)
                .foregroundColor(.red)

                Spacer()

                Button("Accessibility settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .trustCard()
    }

    private var statusDescription: String {
        if !trustCenter.captureEnabled {
            return "EnglishAI will keep running, but new typing and Wispr text will not be saved."
        }
        if trustCenter.redactSensitiveTextBeforeAI {
            return "Captured text is saved locally. Sensitive patterns are redacted before analysis requests."
        }
        return "Captured text is saved locally. AI requests may include selected or captured text exactly as written."
    }

    private func confirmDeleteBlockedAppRecords() {
        let alert = NSAlert()
        alert.messageText = "Delete records from blocked apps?"
        alert.informativeText = "This removes captured text whose app name exactly matches your blocked app list. This cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let deleted = DatabaseService.shared.deleteRecords(forApps: trustCenter.blockedApps)
        lastAction = "Deleted \(deleted) captured record\(deleted == 1 ? "" : "s") from blocked apps."
    }

    private func confirmDeleteAllRecords() {
        let alert = NSAlert()
        alert.messageText = "Delete all captured records?"
        alert.informativeText = "This clears typing and Wispr records from the local database. This cannot be undone."
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Delete All")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        DatabaseService.shared.deleteAllRecords()
        lastAction = "All captured records were deleted."
    }
}

private extension View {
    func trustCard() -> some View {
        self
            .background(Color.white.opacity(0.055))
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.white.opacity(0.13), lineWidth: 1)
            )
    }
}
