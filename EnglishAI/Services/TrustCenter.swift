import Foundation
import AppKit

extension Notification.Name {
    static let trustCenterSettingsChanged = Notification.Name("TrustCenter.settingsChanged")
}

enum SelectedTextReviewPanelStyle: String, CaseIterable, Identifiable {
    case beforeBetter = "before_better"
    case wordHover = "word_hover"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .beforeBetter:
            return "Before / Better"
        case .wordHover:
            return "Word hover"
        }
    }

    var description: String {
        switch self {
        case .beforeBetter:
            return "Two rows: original and improved text, with changes highlighted."
        case .wordHover:
            return "One compact line with word-level replacements and hover explanations."
        }
    }
}

struct RedactionResult {
    let text: String
    let replacements: [String: String]

    var redactionCount: Int {
        replacements.count
    }

    func restorePlaceholders(in value: String) -> String {
        replacements.reduce(value) { partial, item in
            partial.replacingOccurrences(of: item.key, with: item.value)
        }
    }
}

final class TrustCenter: ObservableObject {
    static let shared = TrustCenter()

    @Published var captureEnabled: Bool {
        didSet { saveBool(captureEnabled, key: Keys.captureEnabled) }
    }

    @Published var selectedTextShortcutEnabled: Bool {
        didSet { saveBool(selectedTextShortcutEnabled, key: Keys.selectedTextShortcutEnabled) }
    }

    @Published var redactSensitiveTextBeforeAI: Bool {
        didSet { saveBool(redactSensitiveTextBeforeAI, key: Keys.redactSensitiveTextBeforeAI) }
    }

    @Published var blockPrivateAppsAutomatically: Bool {
        didSet { saveBool(blockPrivateAppsAutomatically, key: Keys.blockPrivateAppsAutomatically) }
    }

    @Published var selectedTextReviewPanelStyle: SelectedTextReviewPanelStyle {
        didSet { saveString(selectedTextReviewPanelStyle.rawValue, key: Keys.selectedTextReviewPanelStyle) }
    }

    @Published private(set) var blockedApps: [String] {
        didSet { saveBlockedApps() }
    }

    private enum Keys {
        static let captureEnabled = "trust_capture_enabled"
        static let selectedTextShortcutEnabled = "trust_selected_text_shortcut_enabled"
        static let redactSensitiveTextBeforeAI = "trust_redact_sensitive_text_before_ai"
        static let blockPrivateAppsAutomatically = "trust_block_private_apps_automatically"
        static let selectedTextReviewPanelStyle = "trust_selected_text_review_panel_style"
        static let blockedApps = "trust_blocked_apps"
    }

    private let privateAppNames = [
        "1Password",
        "Bitwarden",
        "Dashlane",
        "Keychain Access",
        "KeePassXC",
        "LastPass",
        "NordPass",
        "Passwords",
        "System Settings"
    ]

    private init() {
        let defaults = UserDefaults.standard
        captureEnabled = defaults.object(forKey: Keys.captureEnabled) as? Bool ?? true
        selectedTextShortcutEnabled = defaults.object(forKey: Keys.selectedTextShortcutEnabled) as? Bool ?? true
        redactSensitiveTextBeforeAI = defaults.object(forKey: Keys.redactSensitiveTextBeforeAI) as? Bool ?? true
        blockPrivateAppsAutomatically = defaults.object(forKey: Keys.blockPrivateAppsAutomatically) as? Bool ?? true
        let savedStyle = defaults.string(forKey: Keys.selectedTextReviewPanelStyle)
        selectedTextReviewPanelStyle = SelectedTextReviewPanelStyle(rawValue: savedStyle ?? "") ?? .beforeBetter
        blockedApps = defaults.stringArray(forKey: Keys.blockedApps) ?? []
    }

    var frontmostAppName: String {
        NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown"
    }

    func shouldCapture(appName: String) -> Bool {
        captureEnabled && !isBlocked(appName: appName)
    }

    func canAnalyzeSelectedText(from appName: String) -> Bool {
        !isBlocked(appName: appName)
    }

    func isBlocked(appName: String) -> Bool {
        let normalized = normalizedAppName(appName)
        if blockedApps.contains(where: { normalizedAppName($0) == normalized }) {
            return true
        }

        guard blockPrivateAppsAutomatically else { return false }
        return privateAppNames.contains { privateName in
            normalized.contains(normalizedAppName(privateName))
        }
    }

    func addBlockedApp(_ appName: String) {
        let trimmed = appName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !blockedApps.contains(where: { normalizedAppName($0) == normalizedAppName(trimmed) }) else { return }
        blockedApps.append(trimmed)
        publishSettingsChanged()
    }

    func removeBlockedApp(_ appName: String) {
        blockedApps.removeAll { normalizedAppName($0) == normalizedAppName(appName) }
        publishSettingsChanged()
    }

    func prepareTextForAI(_ text: String) -> RedactionResult {
        guard redactSensitiveTextBeforeAI else {
            return RedactionResult(text: text, replacements: [:])
        }

        var redacted = text
        var replacements: [String: String] = [:]
        var counters: [String: Int] = [:]

        func apply(pattern: String, label: String, options: NSRegularExpression.Options = [.caseInsensitive]) {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return }
            let range = NSRange(redacted.startIndex..<redacted.endIndex, in: redacted)
            let matches = regex.matches(in: redacted, options: [], range: range)

            for match in matches.reversed() {
                guard let swiftRange = Range(match.range, in: redacted) else { continue }
                let original = String(redacted[swiftRange])
                guard !original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }

                counters[label, default: 0] += 1
                let placeholder = "[\(label)_\(counters[label] ?? 1)]"
                replacements[placeholder] = original
                redacted.replaceSubrange(swiftRange, with: placeholder)
            }
        }

        apply(pattern: #"\bsk-ant-[A-Za-z0-9_-]{16,}\b"#, label: "API_KEY")
        apply(pattern: #"\bsk-[A-Za-z0-9_-]{16,}\b"#, label: "API_KEY")
        apply(pattern: #"\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b"#, label: "EMAIL")
        apply(pattern: #"\b(?:\d[ -]*?){13,16}\b"#, label: "CARD")
        apply(pattern: #"\+?\d[\d\s().-]{7,}\d"#, label: "PHONE")
        apply(pattern: #"\b[A-Za-z0-9_-]{32,}\b"#, label: "TOKEN")

        return RedactionResult(text: redacted, replacements: replacements)
    }

    func publishSettingsChanged() {
        objectWillChange.send()
        NotificationCenter.default.post(name: .trustCenterSettingsChanged, object: self)
    }

    private func saveBool(_ value: Bool, key: String) {
        UserDefaults.standard.set(value, forKey: key)
        publishSettingsChanged()
    }

    private func saveString(_ value: String, key: String) {
        UserDefaults.standard.set(value, forKey: key)
        publishSettingsChanged()
    }

    private func saveBlockedApps() {
        UserDefaults.standard.set(blockedApps, forKey: Keys.blockedApps)
    }

    private func normalizedAppName(_ appName: String) -> String {
        appName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
