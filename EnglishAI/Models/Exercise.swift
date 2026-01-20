import Foundation

// MARK: - Exercise Types

enum ExerciseType: String, Codable, CaseIterable {
    case singleChoice = "singleChoice"
    case multipleChoice = "multipleChoice"
    case fillInBlank = "fillInBlank"
    case freeResponse = "freeResponse"
    case errorCorrection = "errorCorrection"
    case sentenceReorder = "sentenceReorder"
    case matching = "matching"
    case wordFormation = "wordFormation"
}

// MARK: - Exercise Content Types

struct SingleChoiceContent: Codable {
    let question: String
    let options: [String]
    let correctIndex: Int
}

struct MultipleChoiceContent: Codable {
    let question: String
    let options: [String]
    let correctIndices: [Int]
}

struct BlankItem: Codable {
    let position: Int
    let correctAnswer: String
    let acceptableAlternatives: [String]
}

struct FillInBlankContent: Codable {
    let textWithBlanks: String  // Uses ___ as placeholder
    let blanks: [BlankItem]
}

struct FreeResponseContent: Codable {
    let prompt: String
    let sampleAnswer: String
    let keyPoints: [String]
}

struct ErrorItem: Codable {
    let position: Int
    let incorrectText: String
    let correctText: String
    let explanation: String
}

struct ErrorCorrectionContent: Codable {
    let incorrectSentence: String
    let errors: [ErrorItem]
}

struct SentenceReorderContent: Codable {
    let shuffledWords: [String]
    let correctOrder: [Int]
}

struct MatchPair: Codable {
    let leftIndex: Int
    let rightIndex: Int
}

struct MatchingContent: Codable {
    let leftItems: [String]
    let rightItems: [String]
    let correctPairs: [MatchPair]
}

struct WordFormationContent: Codable {
    let baseSentence: String
    let targetWord: String
    let correctForm: String
    let wordFamily: [String]
}

// MARK: - Exercise Content Enum

enum ExerciseContent: Codable {
    case singleChoice(SingleChoiceContent)
    case multipleChoice(MultipleChoiceContent)
    case fillInBlank(FillInBlankContent)
    case freeResponse(FreeResponseContent)
    case errorCorrection(ErrorCorrectionContent)
    case sentenceReorder(SentenceReorderContent)
    case matching(MatchingContent)
    case wordFormation(WordFormationContent)

    // Custom Codable implementation for enum with associated values
    private enum CodingKeys: String, CodingKey {
        case type
        case content
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ExerciseType.self, forKey: .type)

        switch type {
        case .singleChoice:
            let content = try container.decode(SingleChoiceContent.self, forKey: .content)
            self = .singleChoice(content)
        case .multipleChoice:
            let content = try container.decode(MultipleChoiceContent.self, forKey: .content)
            self = .multipleChoice(content)
        case .fillInBlank:
            let content = try container.decode(FillInBlankContent.self, forKey: .content)
            self = .fillInBlank(content)
        case .freeResponse:
            let content = try container.decode(FreeResponseContent.self, forKey: .content)
            self = .freeResponse(content)
        case .errorCorrection:
            let content = try container.decode(ErrorCorrectionContent.self, forKey: .content)
            self = .errorCorrection(content)
        case .sentenceReorder:
            let content = try container.decode(SentenceReorderContent.self, forKey: .content)
            self = .sentenceReorder(content)
        case .matching:
            let content = try container.decode(MatchingContent.self, forKey: .content)
            self = .matching(content)
        case .wordFormation:
            let content = try container.decode(WordFormationContent.self, forKey: .content)
            self = .wordFormation(content)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .singleChoice(let content):
            try container.encode(ExerciseType.singleChoice, forKey: .type)
            try container.encode(content, forKey: .content)
        case .multipleChoice(let content):
            try container.encode(ExerciseType.multipleChoice, forKey: .type)
            try container.encode(content, forKey: .content)
        case .fillInBlank(let content):
            try container.encode(ExerciseType.fillInBlank, forKey: .type)
            try container.encode(content, forKey: .content)
        case .freeResponse(let content):
            try container.encode(ExerciseType.freeResponse, forKey: .type)
            try container.encode(content, forKey: .content)
        case .errorCorrection(let content):
            try container.encode(ExerciseType.errorCorrection, forKey: .type)
            try container.encode(content, forKey: .content)
        case .sentenceReorder(let content):
            try container.encode(ExerciseType.sentenceReorder, forKey: .type)
            try container.encode(content, forKey: .content)
        case .matching(let content):
            try container.encode(ExerciseType.matching, forKey: .type)
            try container.encode(content, forKey: .content)
        case .wordFormation(let content):
            try container.encode(ExerciseType.wordFormation, forKey: .type)
            try container.encode(content, forKey: .content)
        }
    }
}

// MARK: - Exercise Model

struct Exercise: Identifiable, Codable {
    let id: Int64?
    let type: ExerciseType
    let instruction: String
    let content: ExerciseContent
    let difficulty: Int  // 1-5
    let targetWeakness: String
    let createdAt: Date
    let sourceAnalysisId: Int64?
    let dailySetDate: String?  // ISO8601 date string for daily grouping

    init(
        id: Int64? = nil,
        type: ExerciseType,
        instruction: String,
        content: ExerciseContent,
        difficulty: Int,
        targetWeakness: String,
        createdAt: Date = Date(),
        sourceAnalysisId: Int64? = nil,
        dailySetDate: String? = nil
    ) {
        self.id = id
        self.type = type
        self.instruction = instruction
        self.content = content
        self.difficulty = max(1, min(5, difficulty))  // Clamp 1-5
        self.targetWeakness = targetWeakness
        self.createdAt = createdAt
        self.sourceAnalysisId = sourceAnalysisId
        self.dailySetDate = dailySetDate
    }
}
