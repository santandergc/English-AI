import Foundation
import AppKit
import ApplicationServices
import NaturalLanguage

struct CapturePrivacyContext {
    let source: RecordSource
    let appName: String
    let bundleIdentifier: String?
    let processIdentifier: pid_t?
}

enum CapturePrivacySkipReason: String {
    case sensitiveInput = "sensitive input"
    case excludedApp = "excluded app"
    case singleCharacter = "single character"
    case numbersOnly = "numbers only"
    case tooShort = "too short"
    case terminalCommand = "terminal command"
    case nonNaturalTerminalText = "non-natural terminal text"
    case tooManySpecialCharacters = "too many special characters"
    case insufficientVowels = "insufficient vowels"
    case spanish = "Spanish text"
}

enum CapturePrivacyDecision {
    case save(String)
    case skip(CapturePrivacySkipReason)
}

enum CapturePrivacySettings {
    static let protectSensitiveInputsKey = "privacy_protect_sensitive_inputs"
    static let ignoreSpanishTextKey = "privacy_ignore_spanish_text"
    static let excludeSensitiveAppsKey = "privacy_exclude_sensitive_apps"
    static let excludedAppNamesKey = "privacy_excluded_app_names"

    static let defaultExcludedAppNames = [
        "1Password",
        "Bitwarden",
        "Dashlane",
        "Keeper",
        "KeePass",
        "Keychain Access",
        "LastPass",
        "NordPass",
        "Proton Pass",
        "Secrets"
    ]

    static var protectSensitiveInputs: Bool {
        get { bool(forKey: protectSensitiveInputsKey, defaultValue: true) }
        set { UserDefaults.standard.set(newValue, forKey: protectSensitiveInputsKey) }
    }

    static var ignoreSpanishText: Bool {
        get { bool(forKey: ignoreSpanishTextKey, defaultValue: true) }
        set { UserDefaults.standard.set(newValue, forKey: ignoreSpanishTextKey) }
    }

    static var excludeSensitiveApps: Bool {
        get { bool(forKey: excludeSensitiveAppsKey, defaultValue: true) }
        set { UserDefaults.standard.set(newValue, forKey: excludeSensitiveAppsKey) }
    }

    static var excludedAppNamesText: String {
        get {
            if let saved = UserDefaults.standard.string(forKey: excludedAppNamesKey), !saved.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return saved
            }
            return defaultExcludedAppNames.joined(separator: "\n")
        }
        set { UserDefaults.standard.set(newValue, forKey: excludedAppNamesKey) }
    }

    static var excludedAppNames: [String] {
        excludedAppNamesText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func bool(forKey key: String, defaultValue: Bool) -> Bool {
        guard UserDefaults.standard.object(forKey: key) != nil else {
            return defaultValue
        }
        return UserDefaults.standard.bool(forKey: key)
    }
}

final class CapturePrivacyFilter {
    static let shared = CapturePrivacyFilter()

    private let sensitiveInputDetector = SensitiveInputDetector()

    private let sensitiveBundleIdentifiers: Set<String> = [
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.apple.keychainaccess",
        "com.bitwarden.desktop",
        "com.dashlane.dashlanephonefinal",
        "com.lastpass.LastPass",
        "com.lastpass.LastPassHelper",
        "com.keepersecurity.passwordmanager",
        "com.nordpass.NordPass",
        "ch.protonmail.protonpass"
    ]

    private init() {}

    func shouldSuppressInput(context: CapturePrivacyContext) -> Bool {
        if context.bundleIdentifier == Bundle.main.bundleIdentifier {
            return true
        }

        if CapturePrivacySettings.excludeSensitiveApps && isExcludedApp(context) {
            return true
        }

        if CapturePrivacySettings.protectSensitiveInputs && sensitiveInputDetector.isSensitiveInputActive(context: context) {
            return true
        }

        return false
    }

    func evaluate(_ rawContent: String, context: CapturePrivacyContext) -> CapturePrivacyDecision {
        let content = rawContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else {
            return .skip(.tooShort)
        }

        if shouldSuppressInput(context: context) {
            return .skip(isExcludedApp(context) ? .excludedApp : .sensitiveInput)
        }

        guard let languageFilteredContent = englishOnlyContent(from: content) else {
            return .skip(.spanish)
        }

        return evaluateNaturalLanguageFilters(languageFilteredContent, context: context)
    }

    private func evaluateNaturalLanguageFilters(_ content: String, context: CapturePrivacyContext) -> CapturePrivacyDecision {
        if content.count <= 1 {
            return .skip(.singleCharacter)
        }

        let nonNumericCharacters = content.rangeOfCharacter(from: CharacterSet.decimalDigits.inverted)
        if nonNumericCharacters == nil {
            return .skip(.numbersOnly)
        }

        let nonSpaceCharacters = content.filter { !$0.isWhitespace }
        if nonSpaceCharacters.count < 5 {
            return .skip(.tooShort)
        }

        let isNaturalLanguage = hasEnoughVowels(content) && !hasTooManySpecialCharacters(content)

        if looksLikeTerminalCommand(content) {
            return .skip(.terminalCommand)
        }

        if isTerminalApp(context.appName) && !isNaturalLanguage {
            return .skip(.nonNaturalTerminalText)
        }

        if !isTerminalApp(context.appName) && hasTooManySpecialCharacters(content) {
            return .skip(.tooManySpecialCharacters)
        }

        if !isTerminalApp(context.appName) && !hasEnoughVowels(content) {
            return .skip(.insufficientVowels)
        }

        return .save(content)
    }

    private func isExcludedApp(_ context: CapturePrivacyContext) -> Bool {
        if let bundleIdentifier = context.bundleIdentifier,
           sensitiveBundleIdentifiers.contains(bundleIdentifier) {
            return true
        }

        return CapturePrivacySettings.excludedAppNames.contains { excluded in
            context.appName.localizedCaseInsensitiveContains(excluded)
        }
    }

    private func englishOnlyContent(from content: String) -> String? {
        guard CapturePrivacySettings.ignoreSpanishText else {
            return content
        }

        let segments = sentenceLikeSegments(from: content)
        let keptSegments = segments.filter { segment in
            classifyLanguage(segment) != .spanish
        }

        let filtered = keptSegments
            .joined(separator: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return filtered.isEmpty ? nil : filtered
    }

    private func sentenceLikeSegments(from content: String) -> [String] {
        var segments: [String] = []
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = content

        tokenizer.enumerateTokens(in: content.startIndex..<content.endIndex) { range, _ in
            let segment = String(content[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !segment.isEmpty {
                segments.append(segment)
            }
            return true
        }

        if segments.isEmpty {
            segments = content
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }

        return segments.isEmpty ? [content] : segments
    }

    private enum LanguageClassification {
        case english
        case spanish
        case unknown
    }

    private func classifyLanguage(_ content: String) -> LanguageClassification {
        let letterCount = content.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
        guard letterCount >= 4 else {
            return .unknown
        }

        let lexicalScore = spanishLexicalScore(content)

        if letterCount < 18 {
            if lexicalScore.spanishScore >= max(2, lexicalScore.englishScore + 1) {
                return .spanish
            }
            return .unknown
        }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(content)
        let hypotheses = recognizer.languageHypotheses(withMaximum: 3)
        let spanishConfidence = hypotheses[.spanish] ?? 0
        let englishConfidence = hypotheses[.english] ?? 0

        if spanishConfidence >= 0.55 && spanishConfidence > englishConfidence + 0.12 {
            return .spanish
        }

        if lexicalScore.spanishScore >= lexicalScore.englishScore + 3 && spanishConfidence >= 0.35 {
            return .spanish
        }

        if englishConfidence >= 0.45 && englishConfidence >= spanishConfidence {
            return .english
        }

        if lexicalScore.spanishScore >= max(3, lexicalScore.englishScore + 2) {
            return .spanish
        }

        return .unknown
    }

    private func spanishLexicalScore(_ content: String) -> (spanishScore: Int, englishScore: Int) {
        let normalized = content
            .lowercased()
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_ES"))

        let tokens = normalized
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }

        let spanishWords: Set<String> = [
            "a", "al", "algo", "alla", "aqui", "ayer", "buenas", "buenos", "cada",
            "como", "con", "cuando", "de", "del", "desde", "donde", "el", "ella",
            "ellos", "en", "eres", "es", "esa", "ese", "eso", "esta", "estan",
            "estoy", "gracias", "hacer", "hacia", "hasta", "hay", "hola", "hoy",
            "la", "las", "le", "lo", "los", "mas", "menos", "mi", "muy", "necesito",
            "no", "nos", "nosotros", "para", "pero", "por", "porque", "puedo",
            "que", "quiero", "se", "si", "sin", "son", "soy", "su", "tambien",
            "te", "tengo", "tiene", "tienes", "tu", "una", "uno", "unos", "voy",
            "y", "ya", "yo", "ahora", "amigo", "amiga", "ayuda", "ayudar",
            "ayudarme", "bien", "casa", "cosa", "creo", "dia", "dias", "esto",
            "favor", "mal", "manana", "me", "mejor", "mismo", "mucha", "muchas",
            "mucho", "muchos", "nada", "quieres", "saber", "semana", "siempre",
            "solo", "tal", "todo", "todos", "tuve", "vamos", "ver"
        ]

        let englishWords: Set<String> = [
            "a", "about", "am", "an", "and", "are", "as", "at", "be", "because",
            "but", "can", "could", "do", "for", "from", "have", "he", "hello",
            "her", "his", "how", "i", "if", "in", "is", "it", "me", "my", "need",
            "not", "of", "on", "or", "our", "she", "so", "that", "the", "their",
            "there", "they", "this", "to", "today", "was", "we", "what", "when",
            "where", "will", "with", "would", "you", "your"
        ]

        let spanishTokenScore = tokens.filter { spanishWords.contains($0) }.count
        let englishTokenScore = tokens.filter { englishWords.contains($0) }.count
        let spanishPunctuationScore = content.contains("¿") || content.contains("¡") ? 2 : 0
        let spanishDiacriticScore = content.range(of: "[áéíóúÁÉÍÓÚñÑüÜ]", options: .regularExpression) == nil ? 0 : 1

        return (
            spanishScore: spanishTokenScore + spanishPunctuationScore + spanishDiacriticScore,
            englishScore: englishTokenScore
        )
    }

    private func isTerminalApp(_ appName: String) -> Bool {
        let terminalApps = [
            "Warp", "Terminal", "iTerm", "iTerm2", "Alacritty",
            "Hyper", "Kitty", "WezTerm", "Terminator"
        ]
        return terminalApps.contains { appName.localizedCaseInsensitiveContains($0) }
    }

    private func looksLikeTerminalCommand(_ content: String) -> Bool {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)

        let shellCommands = [
            "cd ", "ls ", "git ", "npm ", "yarn ", "python ", "node ",
            "sudo ", "brew ", "docker ", "kubectl ", "ssh ", "scp ",
            "mv ", "cp ", "rm ", "mkdir ", "touch ", "cat ", "grep ",
            "find ", "ps ", "kill ", "chmod ", "chown ", "tar ", "zip ",
            "unzip ", "curl ", "wget ", "ping ", "ifconfig ", "netstat "
        ]

        for command in shellCommands where trimmed.lowercased().hasPrefix(command.lowercased()) {
            return true
        }

        if !hasEnoughVowels(trimmed) {
            let words = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            if words.count >= 3 {
                let shortWords = words.filter { $0.count <= 2 }
                if shortWords.count >= words.count / 2 {
                    return true
                }
            }
        }

        if trimmed.hasPrefix("/") || trimmed.hasPrefix("./") || trimmed.hasPrefix("../") {
            return true
        }

        return trimmed.contains("|") || trimmed.contains("&&") || trimmed.contains("||") || trimmed.contains(";")
    }

    private func hasTooManySpecialCharacters(_ content: String) -> Bool {
        let codeSpecialChars = CharacterSet(charactersIn: "@#$%^&*()_+-=[]{}|;':\"/<>`~")
        let codeCharCount = content.unicodeScalars.filter { codeSpecialChars.contains($0) }.count
        let letterCount = content.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count

        if letterCount > 0 {
            return Double(codeCharCount) / Double(letterCount) > 0.25
        }

        return !content.isEmpty && Double(codeCharCount) / Double(content.count) > 0.20
    }

    private func hasEnoughVowels(_ content: String) -> Bool {
        let vowels = CharacterSet(charactersIn: "aeiouAEIOU")
        let vowelCount = content.unicodeScalars.filter { vowels.contains($0) }.count
        let letterCount = content.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count

        guard letterCount > 0 else {
            return false
        }

        return Double(vowelCount) / Double(letterCount) >= 0.20
    }
}

private final class SensitiveInputDetector {
    private var cachedContextKey: String?
    private var cachedResult: Bool = false
    private var cachedAt: Date = .distantPast
    private let cacheDuration: TimeInterval = 0.15

    func isSensitiveInputActive(context: CapturePrivacyContext) -> Bool {
        let contextKey = "\(context.processIdentifier ?? -1):\(context.bundleIdentifier ?? "")"
        let now = Date()
        if cachedResult && cachedContextKey == contextKey && now.timeIntervalSince(cachedAt) < cacheDuration {
            return cachedResult
        }

        let result = detectSensitiveInput(context: context)
        cachedContextKey = contextKey
        cachedResult = result
        cachedAt = now
        return result
    }

    private func detectSensitiveInput(context: CapturePrivacyContext) -> Bool {
        guard let processIdentifier = context.processIdentifier else {
            return false
        }

        let appElement = AXUIElementCreateApplication(processIdentifier)
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedValue) == .success,
              let focusedValue,
              CFGetTypeID(focusedValue) == AXUIElementGetTypeID() else {
            return false
        }

        let focusedElement = focusedValue as! AXUIElement
        return elementOrParentsAreSensitive(focusedElement)
    }

    private func elementOrParentsAreSensitive(_ element: AXUIElement) -> Bool {
        var currentElement: AXUIElement? = element

        for _ in 0..<3 {
            guard let element = currentElement else {
                return false
            }

            if elementIsSensitive(element) {
                return true
            }

            currentElement = parent(of: element)
        }

        return false
    }

    private func elementIsSensitive(_ element: AXUIElement) -> Bool {
        let role = stringAttribute(element, kAXRoleAttribute as CFString) ?? ""
        let subrole = stringAttribute(element, kAXSubroleAttribute as CFString) ?? ""

        if subrole == "AXSecureTextField" {
            return true
        }

        let metadata = [
            role,
            subrole,
            stringAttribute(element, kAXRoleDescriptionAttribute as CFString),
            stringAttribute(element, kAXTitleAttribute as CFString),
            stringAttribute(element, kAXDescriptionAttribute as CFString),
            stringAttribute(element, kAXHelpAttribute as CFString),
            stringAttribute(element, kAXPlaceholderValueAttribute as CFString),
            stringAttribute(element, kAXLabelValueAttribute as CFString),
            stringAttribute(element, "AXDOMIdentifier" as CFString),
            stringAttribute(element, "AXDOMClassList" as CFString)
        ]
            .compactMap { $0 }
            .joined(separator: " ")

        guard containsSensitiveKeyword(metadata) else {
            return false
        }

        return isTextInput(role: role, subrole: subrole) || !role.localizedCaseInsensitiveContains("Button")
    }

    private func isTextInput(role: String, subrole: String) -> Bool {
        let textRoles = ["AXTextField", "AXTextArea", "AXComboBox"]
        let textSubroles = ["AXSecureTextField", "AXSearchField"]

        return textRoles.contains(role) || textSubroles.contains(subrole)
    }

    private func containsSensitiveKeyword(_ metadata: String) -> Bool {
        let normalized = metadata
            .lowercased()
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_ES"))

        let keywords = [
            "api key",
            "auth code",
            "authentication code",
            "backup code",
            "card number",
            "clave",
            "codigo de seguridad",
            "contrasena",
            "credit card",
            "cvc",
            "cvv",
            "mfa",
            "one time",
            "one-time",
            "otp",
            "passcode",
            "pass phrase",
            "passphrase",
            "password",
            "pin",
            "private key",
            "recovery code",
            "secret",
            "security code",
            "social security",
            "ssn",
            "token",
            "verification code"
        ]

        return keywords.contains { normalized.contains($0) }
    }

    private func parent(of element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }

        return (value as! AXUIElement)
    }

    private func stringAttribute(_ element: AXUIElement, _ attribute: CFString) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let value else {
            return nil
        }

        if let stringValue = value as? String {
            return stringValue
        }

        if let arrayValue = value as? [String] {
            return arrayValue.joined(separator: " ")
        }

        return nil
    }
}
