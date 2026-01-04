import Foundation

enum InsightType: String, Codable, CaseIterable {
    case grammar = "grammar"
    case phrasing = "phrasing"
    case vocabulary = "vocabulary"
    case pattern = "pattern"
    case progress = "progress"
    case positive = "positive"
}

struct GrammarIssue: Codable {
    let original: String
    let corrected: String
    let explanation: String
}

struct PhrasingIssue: Codable {
    let original: String
    let natural: String
    let context: String
}

struct VocabularyInsight: Codable {
    let word: String
    let suggestion: String?
    let note: String
}

struct AnalysisResult: Codable {
    let grammarIssues: [GrammarIssue]
    let phrasingIssues: [PhrasingIssue]
    let vocabularyInsights: [VocabularyInsight]
    let positives: [String]
    let overallScore: Int // 1-10
    let summary: String
}

struct Insight: Identifiable, Codable {
    let id: Int64?
    let dateRangeStart: Date
    let dateRangeEnd: Date
    let insightType: InsightType
    let content: String // JSON encoded AnalysisResult or specific insight
    let recordCount: Int
    let characterCount: Int
    let createdAt: Date
    
    init(id: Int64? = nil, dateRangeStart: Date, dateRangeEnd: Date, insightType: InsightType, content: String, recordCount: Int, characterCount: Int, createdAt: Date = Date()) {
        self.id = id
        self.dateRangeStart = dateRangeStart
        self.dateRangeEnd = dateRangeEnd
        self.insightType = insightType
        self.content = content
        self.recordCount = recordCount
        self.characterCount = characterCount
        self.createdAt = createdAt
    }
}

struct AnalysisSession: Identifiable, Codable {
    let id: Int64?
    let analyzedAt: Date
    let dateRangeStart: Date
    let dateRangeEnd: Date
    let recordsAnalyzed: Int
    let charactersAnalyzed: Int
    
    init(id: Int64? = nil, analyzedAt: Date = Date(), dateRangeStart: Date, dateRangeEnd: Date, recordsAnalyzed: Int, charactersAnalyzed: Int) {
        self.id = id
        self.analyzedAt = analyzedAt
        self.dateRangeStart = dateRangeStart
        self.dateRangeEnd = dateRangeEnd
        self.recordsAnalyzed = recordsAnalyzed
        self.charactersAnalyzed = charactersAnalyzed
    }
}
