import Foundation

// MARK: - Focus Item

enum FocusItemKind: String, Codable {
    case enrich = "enrich"
    case fix = "fix"
}

/// Lifecycle stages. Enrich-items pass through `spotted`; fix-items skip it.
/// `retired` = exit without graduation (from any active stage); `adopted` = graduated.
enum FocusItemStatus: String, Codable, CaseIterable {
    case candidate = "candidate"
    case queued = "queued"
    case practicing = "practicing"
    case spotted = "spotted"
    case adopted = "adopted"
    case retired = "retired"

    /// Statuses that occupy one of the 5 active queue slots
    static let activeStatuses: [FocusItemStatus] = [.queued, .practicing, .spotted]
}

/// One unit of learning: a word, expression, or error-pattern with a lifecycle.
/// Wild-use count is always COMPUTED from verified correct_use evidence rows (no stored counter).
struct FocusItem: Identifiable, Codable {
    let id: Int64?
    let kind: FocusItemKind
    var status: FocusItemStatus
    let targetPhrase: String
    let matchForms: [String]      // surface forms/lemmas matched locally against new records
    let rationale: String         // the receipt summary shown in UI
    var priority: Int             // rank among candidates; rewritten from queueAdvice each analysis
    let supersedesItemId: Int64?  // relapse re-nomination links back to the adopted original
    let createdAt: Date
    var updatedAt: Date

    init(
        id: Int64? = nil,
        kind: FocusItemKind,
        status: FocusItemStatus,
        targetPhrase: String,
        matchForms: [String],
        rationale: String,
        priority: Int = 0,
        supersedesItemId: Int64? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.status = status
        self.targetPhrase = targetPhrase
        self.matchForms = matchForms
        self.rationale = rationale
        self.priority = priority
        self.supersedesItemId = supersedesItemId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Normalized phrase used for cross-reference resolution (AI references items by phrase, never rowid)
    var normalizedPhrase: String {
        FocusItem.normalize(targetPhrase)
    }

    static func normalize(_ phrase: String) -> String {
        phrase.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Focus Evidence

enum FocusEvidenceType: String, Codable {
    case overuse = "overuse"           // crutch usage cited by the AI
    case mistake = "mistake"           // fix-item error occurrence
    case correctUse = "correct_use"    // target used correctly (wild sighting)
    case nearMiss = "near_miss"        // attempted but used incorrectly
    case practice = "practice"         // exercise-derived signal
}

/// A receipt: one piece of evidence tied to a focus item.
/// `verified == false` means a pending local sighting awaiting AI review.
struct FocusEvidence: Identifiable, Codable {
    let id: Int64?
    let focusItemId: Int64
    let recordId: Int64?              // nil for AI-cited/aggregated evidence
    let excerpt: String
    let app: String?                  // source context ("Slack")
    var evidenceType: FocusEvidenceType
    var verified: Bool                // false = pending AI review; true = AI has ruled
    let occurredAt: Date

    init(
        id: Int64? = nil,
        focusItemId: Int64,
        recordId: Int64? = nil,
        excerpt: String,
        app: String? = nil,
        evidenceType: FocusEvidenceType,
        verified: Bool = false,
        occurredAt: Date = Date()
    ) {
        self.id = id
        self.focusItemId = focusItemId
        self.recordId = recordId
        self.excerpt = excerpt
        self.app = app
        self.evidenceType = evidenceType
        self.verified = verified
        self.occurredAt = occurredAt
    }
}

// MARK: - Language Profile

/// One immutable version of the AI-maintained profile document.
/// Latest row is truth; history stays queryable.
struct LanguageProfileVersion {
    let id: Int64?
    let version: Int
    let content: String    // bounded JSON document the AI rewrites each analysis
    let basedOnDate: Date  // newest record date incorporated (forward-only ordering guard)
    let createdAt: Date
}

// MARK: - Morning Brief

/// The daily coach card, rendered entirely from local data (zero API calls at open time).
struct MorningBrief: Identifiable {
    let id: Int64?
    let forDate: Date          // the day this brief is FOR (unique per day, replace on re-run)
    let focusItemId: Int64
    let headline: String
    let mission: String
    let wins: [String]
    let createdAt: Date
}

// MARK: - AI Analysis Extension Payload

/// Typed form of the focus-related superset fields in the analysis response.
/// Cross-references: evidenceId/focusItemId are rowids echoed from the prompt payload;
/// queueAdvice/morningBrief reference items by normalized targetPhrase (same-response
/// candidates have no rowid yet).
struct FocusAnalysisExtension {
    struct SightingVerdict {
        let evidenceId: Int64
        let correct: Bool
        let note: String
    }

    struct NewErrorEvidence {
        let focusItemId: Int64
        let excerpt: String
        let app: String?
    }

    struct Candidate {
        let kind: FocusItemKind
        let targetPhrase: String
        let matchForms: [String]
        let rationale: String
        let excerpts: [String]
    }

    struct QueueAdvice {
        let promote: [String]              // targetPhrases
        let retire: [String]               // targetPhrases
        let candidatePriorities: [String]  // targetPhrases in rank order
        let reasoning: String
    }

    struct BriefPayload {
        let focusTargetPhrase: String
        let headline: String
        let mission: String
        let wins: [String]
    }

    let sightingVerdicts: [SightingVerdict]
    let newErrorEvidence: [NewErrorEvidence]
    let candidates: [Candidate]
    let queueAdvice: QueueAdvice?
    let profileUpdateJSON: String?   // re-serialized profile document
    let morningBrief: BriefPayload?
}
