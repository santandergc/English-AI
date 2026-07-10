import CoreGraphics
import Foundation

struct SelectedTextCorrection: Codable, Identifiable {
    let id: UUID
    let original: String
    let replacement: String
    let category: String
    let explanation: String
    let memoryCue: String?

    init(
        id: UUID = UUID(),
        original: String,
        replacement: String,
        category: String,
        explanation: String,
        memoryCue: String? = nil
    ) {
        self.id = id
        self.original = original
        self.replacement = replacement
        self.category = category
        self.explanation = explanation
        self.memoryCue = memoryCue
    }

    private enum CodingKeys: String, CodingKey {
        case original
        case replacement
        case category
        case explanation
        case memoryCue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = UUID()
        self.original = try container.decode(String.self, forKey: .original)
        self.replacement = try container.decode(String.self, forKey: .replacement)
        self.category = try container.decode(String.self, forKey: .category)
        self.explanation = try container.decode(String.self, forKey: .explanation)
        self.memoryCue = try container.decodeIfPresent(String.self, forKey: .memoryCue)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(original, forKey: .original)
        try container.encode(replacement, forKey: .replacement)
        try container.encode(category, forKey: .category)
        try container.encode(explanation, forKey: .explanation)
        try container.encodeIfPresent(memoryCue, forKey: .memoryCue)
    }
}

struct SelectedTextProposal: Codable, Identifiable {
    let id: UUID
    let title: String
    let text: String
    let why: String

    init(id: UUID = UUID(), title: String, text: String, why: String) {
        self.id = id
        self.title = title
        self.text = text
        self.why = why
    }

    private enum CodingKeys: String, CodingKey {
        case title
        case text
        case why
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = UUID()
        self.title = try container.decode(String.self, forKey: .title)
        self.text = try container.decode(String.self, forKey: .text)
        self.why = try container.decode(String.self, forKey: .why)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encode(text, forKey: .text)
        try container.encode(why, forKey: .why)
    }
}

struct SelectedTextReview: Codable {
    let originalText: String
    let improvedText: String
    let detectedTone: String
    let overallAssessment: String
    let corrections: [SelectedTextCorrection]
    let proposals: [SelectedTextProposal]
    let reminders: [String]
    let confidence: Double
    let redactionCount: Int

    var hasCorrections: Bool {
        !corrections.isEmpty || improvedText.trimmingCharacters(in: .whitespacesAndNewlines) != originalText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    init(
        originalText: String,
        improvedText: String,
        detectedTone: String,
        overallAssessment: String,
        corrections: [SelectedTextCorrection],
        proposals: [SelectedTextProposal],
        reminders: [String],
        confidence: Double,
        redactionCount: Int = 0
    ) {
        self.originalText = originalText
        self.improvedText = improvedText
        self.detectedTone = detectedTone
        self.overallAssessment = overallAssessment
        self.corrections = corrections
        self.proposals = proposals
        self.reminders = reminders
        self.confidence = confidence
        self.redactionCount = redactionCount
    }

    private enum CodingKeys: String, CodingKey {
        case originalText
        case improvedText
        case detectedTone
        case overallAssessment
        case corrections
        case proposals
        case reminders
        case confidence
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        originalText = try container.decode(String.self, forKey: .originalText)
        improvedText = try container.decode(String.self, forKey: .improvedText)
        detectedTone = try container.decode(String.self, forKey: .detectedTone)
        overallAssessment = try container.decode(String.self, forKey: .overallAssessment)
        corrections = try container.decodeIfPresent([SelectedTextCorrection].self, forKey: .corrections) ?? []
        proposals = try container.decodeIfPresent([SelectedTextProposal].self, forKey: .proposals) ?? []
        reminders = try container.decodeIfPresent([String].self, forKey: .reminders) ?? []
        confidence = try container.decodeIfPresent(Double.self, forKey: .confidence) ?? 0.75
        redactionCount = 0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(originalText, forKey: .originalText)
        try container.encode(improvedText, forKey: .improvedText)
        try container.encode(detectedTone, forKey: .detectedTone)
        try container.encode(overallAssessment, forKey: .overallAssessment)
        try container.encode(corrections, forKey: .corrections)
        try container.encode(proposals, forKey: .proposals)
        try container.encode(reminders, forKey: .reminders)
        try container.encode(confidence, forKey: .confidence)
    }
}

struct SelectedTextCapture {
    let text: String
    let appName: String
    let bundleIdentifier: String?
    let processIdentifier: pid_t?
    let method: CaptureMethod
    let selectionFrame: CGRect?

    enum CaptureMethod: String {
        case accessibility = "Accessibility"
        case clipboardFallback = "Clipboard fallback"
    }
}
