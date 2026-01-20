import SwiftUI

// MARK: - Exercise Container View

/// A container view that renders the appropriate exercise view based on exercise type.
/// Takes an Exercise object and routes to the correct specialized view.
struct ExerciseContainerView: View {
    let exercise: Exercise
    let onComplete: (ExerciseAttemptData) -> Void

    var body: some View {
        switch exercise.content {
        case .singleChoice(let content):
            SingleChoiceExerciseView(
                content: content,
                onComplete: { isCorrect, feedback, timeSpent, selectedIndex in
                    onComplete(ExerciseAttemptData(
                        exerciseId: exercise.id,
                        isCorrect: isCorrect,
                        partialScore: nil,
                        feedback: feedback,
                        timeSpentSeconds: timeSpent,
                        userAnswer: .singleChoice(selectedIndex)
                    ))
                }
            )
        case .multipleChoice(let content):
            MultipleChoiceExerciseView(
                content: content,
                onComplete: { isCorrect, feedback, timeSpent, partialScore, selectedIndices in
                    onComplete(ExerciseAttemptData(
                        exerciseId: exercise.id,
                        isCorrect: isCorrect,
                        partialScore: partialScore,
                        feedback: feedback,
                        timeSpentSeconds: timeSpent,
                        userAnswer: .multipleChoice(selectedIndices)
                    ))
                }
            )
        case .fillInBlank(let content):
            FillInBlankExerciseView(
                content: content,
                onComplete: { isCorrect, feedback, timeSpent, partialScore, userAnswers in
                    onComplete(ExerciseAttemptData(
                        exerciseId: exercise.id,
                        isCorrect: isCorrect,
                        partialScore: partialScore,
                        feedback: feedback,
                        timeSpentSeconds: timeSpent,
                        userAnswer: .fillInBlank(userAnswers)
                    ))
                }
            )
        case .freeResponse(let content):
            FreeResponseExerciseView(
                content: content,
                onComplete: { isCorrect, feedback, timeSpent, userResponse in
                    onComplete(ExerciseAttemptData(
                        exerciseId: exercise.id,
                        isCorrect: isCorrect,
                        partialScore: nil,
                        feedback: feedback,
                        timeSpentSeconds: timeSpent,
                        userAnswer: .freeResponse(userResponse)
                    ))
                }
            )
        case .errorCorrection(let content):
            ErrorCorrectionExerciseView(
                content: content,
                onComplete: { isCorrect, feedback, timeSpent, corrections in
                    onComplete(ExerciseAttemptData(
                        exerciseId: exercise.id,
                        isCorrect: isCorrect,
                        partialScore: nil,
                        feedback: feedback,
                        timeSpentSeconds: timeSpent,
                        userAnswer: .errorCorrection(corrections)
                    ))
                }
            )
        case .sentenceReorder(let content):
            SentenceReorderExerciseView(
                content: content,
                onComplete: { isCorrect, feedback, timeSpent, userOrder in
                    onComplete(ExerciseAttemptData(
                        exerciseId: exercise.id,
                        isCorrect: isCorrect,
                        partialScore: nil,
                        feedback: feedback,
                        timeSpentSeconds: timeSpent,
                        userAnswer: .sentenceReorder(userOrder)
                    ))
                }
            )
        case .matching(let content):
            MatchingExerciseView(
                content: content,
                onComplete: { isCorrect, feedback, timeSpent, userMatches in
                    onComplete(ExerciseAttemptData(
                        exerciseId: exercise.id,
                        isCorrect: isCorrect,
                        partialScore: nil,
                        feedback: feedback,
                        timeSpentSeconds: timeSpent,
                        userAnswer: .matching(userMatches)
                    ))
                }
            )
        case .wordFormation(let content):
            WordFormationExerciseView(
                content: content,
                onComplete: { isCorrect, feedback, timeSpent, userAnswer in
                    onComplete(ExerciseAttemptData(
                        exerciseId: exercise.id,
                        isCorrect: isCorrect,
                        partialScore: nil,
                        feedback: feedback,
                        timeSpentSeconds: timeSpent,
                        userAnswer: .wordFormation(userAnswer)
                    ))
                }
            )
        }
    }
}

// MARK: - Exercise Attempt Data

/// Data structure for passing attempt results from exercise views
struct ExerciseAttemptData {
    let exerciseId: Int64?
    let isCorrect: Bool
    let partialScore: Double?
    let feedback: String
    let timeSpentSeconds: Int
    let userAnswer: UserAnswer

    /// Records this attempt to the database and updates weakness progress
    /// - Returns: The ID of the created attempt, or nil if the exercise ID was nil or save failed
    @discardableResult
    func saveToDatabase() -> Int64? {
        guard let exerciseId = exerciseId else {
            print("[ExerciseAttemptData] Cannot save attempt: exerciseId is nil")
            return nil
        }

        // Save the attempt to database
        let attemptId = DatabaseService.shared.createAttempt(
            exerciseId: exerciseId,
            userAnswer: userAnswer,
            isCorrect: isCorrect,
            partialScore: partialScore,
            feedback: feedback,
            timeSpentSeconds: timeSpentSeconds
        )

        // Update weakness progress with spaced repetition
        if attemptId != nil {
            DatabaseService.shared.updateWeaknessAfterAttempt(
                exerciseId: exerciseId,
                isCorrect: isCorrect
            )
        }

        return attemptId
    }
}

// MARK: - User Answer Types

/// Enum representing different user answer formats for each exercise type
enum UserAnswer: Codable {
    case singleChoice(Int?)
    case multipleChoice([Int])
    case fillInBlank([String])
    case freeResponse(String)
    case errorCorrection([Int: String])  // position -> correction
    case sentenceReorder([Int])
    case matching([Int: Int])  // leftIndex -> rightIndex
    case wordFormation(String)

    // Custom Codable implementation
    private enum CodingKeys: String, CodingKey {
        case type
        case value
    }

    private enum AnswerType: String, Codable {
        case singleChoice, multipleChoice, fillInBlank, freeResponse
        case errorCorrection, sentenceReorder, matching, wordFormation
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(AnswerType.self, forKey: .type)

        switch type {
        case .singleChoice:
            let value = try container.decodeIfPresent(Int.self, forKey: .value)
            self = .singleChoice(value)
        case .multipleChoice:
            let value = try container.decode([Int].self, forKey: .value)
            self = .multipleChoice(value)
        case .fillInBlank:
            let value = try container.decode([String].self, forKey: .value)
            self = .fillInBlank(value)
        case .freeResponse:
            let value = try container.decode(String.self, forKey: .value)
            self = .freeResponse(value)
        case .errorCorrection:
            let stringKeyedDict = try container.decode([String: String].self, forKey: .value)
            var intKeyedDict: [Int: String] = [:]
            for (key, value) in stringKeyedDict {
                if let intKey = Int(key) {
                    intKeyedDict[intKey] = value
                }
            }
            self = .errorCorrection(intKeyedDict)
        case .sentenceReorder:
            let value = try container.decode([Int].self, forKey: .value)
            self = .sentenceReorder(value)
        case .matching:
            let stringKeyedDict = try container.decode([String: Int].self, forKey: .value)
            var intKeyedDict: [Int: Int] = [:]
            for (key, value) in stringKeyedDict {
                if let intKey = Int(key) {
                    intKeyedDict[intKey] = value
                }
            }
            self = .matching(intKeyedDict)
        case .wordFormation:
            let value = try container.decode(String.self, forKey: .value)
            self = .wordFormation(value)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .singleChoice(let value):
            try container.encode(AnswerType.singleChoice, forKey: .type)
            try container.encodeIfPresent(value, forKey: .value)
        case .multipleChoice(let value):
            try container.encode(AnswerType.multipleChoice, forKey: .type)
            try container.encode(value, forKey: .value)
        case .fillInBlank(let value):
            try container.encode(AnswerType.fillInBlank, forKey: .type)
            try container.encode(value, forKey: .value)
        case .freeResponse(let value):
            try container.encode(AnswerType.freeResponse, forKey: .type)
            try container.encode(value, forKey: .value)
        case .errorCorrection(let value):
            try container.encode(AnswerType.errorCorrection, forKey: .type)
            let stringKeyedDict = Dictionary(uniqueKeysWithValues: value.map { (String($0.key), $0.value) })
            try container.encode(stringKeyedDict, forKey: .value)
        case .sentenceReorder(let value):
            try container.encode(AnswerType.sentenceReorder, forKey: .type)
            try container.encode(value, forKey: .value)
        case .matching(let value):
            try container.encode(AnswerType.matching, forKey: .type)
            let stringKeyedDict = Dictionary(uniqueKeysWithValues: value.map { (String($0.key), $0.value) })
            try container.encode(stringKeyedDict, forKey: .value)
        case .wordFormation(let value):
            try container.encode(AnswerType.wordFormation, forKey: .type)
            try container.encode(value, forKey: .value)
        }
    }
}

// MARK: - Single Choice Exercise View

struct SingleChoiceExerciseView: View {
    let content: SingleChoiceContent
    let onComplete: (Bool, String, Int, Int?) -> Void  // isCorrect, feedback, timeSpentSeconds, selectedIndex

    @State private var selectedIndex: Int? = nil
    @State private var isSubmitted: Bool = false
    @State private var startTime: Date = Date()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Question section
                questionSection

                // Options section
                optionsSection

                // Action buttons
                actionButtonsSection

                // Results section (shown after submission)
                if isSubmitted {
                    resultsSection
                }
            }
            .padding()
        }
        .onAppear {
            startTime = Date()
        }
    }

    // MARK: - View Components

    private var questionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Question")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            Text(content.question)
                .font(.title3)
                .fontWeight(.medium)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                )
        }
    }

    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Select one answer")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            VStack(spacing: 10) {
                ForEach(0..<content.options.count, id: \.self) { index in
                    optionCard(index: index, option: content.options[index])
                }
            }
        }
    }

    private func optionCard(index: Int, option: String) -> some View {
        Button(action: {
            if !isSubmitted {
                selectedIndex = index
            }
        }) {
            HStack(spacing: 12) {
                // Radio button indicator
                ZStack {
                    Circle()
                        .stroke(borderColor(for: index), lineWidth: 2)
                        .frame(width: 20, height: 20)

                    if selectedIndex == index || (isSubmitted && index == content.correctIndex) {
                        Circle()
                            .fill(fillColor(for: index))
                            .frame(width: 12, height: 12)
                    }
                }

                Text(option)
                    .font(.body)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)

                Spacer()

                // Result icons
                if isSubmitted {
                    if index == content.correctIndex {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    } else if selectedIndex == index {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                    }
                }
            }
            .padding()
            .background(backgroundColor(for: index))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(borderColor(for: index), lineWidth: selectedIndex == index && !isSubmitted ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isSubmitted)
    }

    private func borderColor(for index: Int) -> Color {
        if isSubmitted {
            if index == content.correctIndex {
                return .green
            } else if selectedIndex == index {
                return .red
            }
        } else if selectedIndex == index {
            return .blue
        }
        return Color.gray.opacity(0.3)
    }

    private func fillColor(for index: Int) -> Color {
        if isSubmitted {
            if index == content.correctIndex {
                return .green
            } else if selectedIndex == index {
                return .red
            }
        }
        return .blue
    }

    private func backgroundColor(for index: Int) -> Color {
        if isSubmitted {
            if index == content.correctIndex {
                return Color.green.opacity(0.1)
            } else if selectedIndex == index {
                return Color.red.opacity(0.1)
            }
        } else if selectedIndex == index {
            return Color.blue.opacity(0.05)
        }
        return Color(NSColor.controlBackgroundColor)
    }

    private var actionButtonsSection: some View {
        HStack {
            Spacer()

            if !isSubmitted {
                Button("Check Answer") {
                    submitAnswer()
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedIndex == nil)
            } else {
                Button("Next") {
                    let timeSpent = Int(Date().timeIntervalSince(startTime))
                    let isCorrect = selectedIndex == content.correctIndex
                    let feedback = isCorrect
                        ? "Correct! Well done."
                        : "Incorrect. The correct answer is: \(content.options[content.correctIndex])"
                    onComplete(isCorrect, feedback, timeSpent, selectedIndex)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            let isCorrect = selectedIndex == content.correctIndex

            HStack {
                Image(systemName: isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(isCorrect ? .green : .red)
                Text(isCorrect ? "Correct!" : "Incorrect")
                    .font(.headline)
                    .foregroundColor(isCorrect ? .green : .red)
            }

            if !isCorrect {
                Text("The correct answer is: \(content.options[content.correctIndex])")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }

    // MARK: - Actions

    private func submitAnswer() {
        isSubmitted = true
    }
}

// MARK: - Multiple Choice Exercise View

struct MultipleChoiceExerciseView: View {
    let content: MultipleChoiceContent
    let onComplete: (Bool, String, Int, Double?, [Int]) -> Void  // isCorrect, feedback, timeSpentSeconds, partialScore, selectedIndices

    @State private var selectedIndices: Set<Int> = []
    @State private var isSubmitted: Bool = false
    @State private var startTime: Date = Date()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Question section
                questionSection

                // Options section
                optionsSection

                // Action buttons
                actionButtonsSection

                // Results section (shown after submission)
                if isSubmitted {
                    resultsSection
                }
            }
            .padding()
        }
        .onAppear {
            startTime = Date()
        }
    }

    // MARK: - View Components

    private var questionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Question")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            Text(content.question)
                .font(.title3)
                .fontWeight(.medium)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                )
        }
    }

    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Select all that apply")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            VStack(spacing: 10) {
                ForEach(0..<content.options.count, id: \.self) { index in
                    optionCard(index: index, option: content.options[index])
                }
            }
        }
    }

    private func optionCard(index: Int, option: String) -> some View {
        let isSelected = selectedIndices.contains(index)
        let isCorrectOption = content.correctIndices.contains(index)

        return Button(action: {
            if !isSubmitted {
                if isSelected {
                    selectedIndices.remove(index)
                } else {
                    selectedIndices.insert(index)
                }
            }
        }) {
            HStack(spacing: 12) {
                // Checkbox indicator
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(checkboxBorderColor(index: index, isSelected: isSelected, isCorrectOption: isCorrectOption), lineWidth: 2)
                        .frame(width: 20, height: 20)

                    if isSelected || (isSubmitted && isCorrectOption) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(checkboxFillColor(index: index, isSelected: isSelected, isCorrectOption: isCorrectOption))
                    }
                }

                Text(option)
                    .font(.body)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)

                Spacer()

                // Result icons
                if isSubmitted {
                    if isCorrectOption && isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    } else if isCorrectOption && !isSelected {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundColor(.orange)
                    } else if !isCorrectOption && isSelected {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                    }
                }
            }
            .padding()
            .background(checkboxBackgroundColor(index: index, isSelected: isSelected, isCorrectOption: isCorrectOption))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(checkboxBorderColor(index: index, isSelected: isSelected, isCorrectOption: isCorrectOption), lineWidth: isSelected && !isSubmitted ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isSubmitted)
    }

    private func checkboxBorderColor(index: Int, isSelected: Bool, isCorrectOption: Bool) -> Color {
        if isSubmitted {
            if isCorrectOption && isSelected {
                return .green
            } else if isCorrectOption && !isSelected {
                return .orange
            } else if !isCorrectOption && isSelected {
                return .red
            }
        } else if isSelected {
            return .blue
        }
        return Color.gray.opacity(0.3)
    }

    private func checkboxFillColor(index: Int, isSelected: Bool, isCorrectOption: Bool) -> Color {
        if isSubmitted {
            if isCorrectOption {
                return isSelected ? .green : .orange
            } else if isSelected {
                return .red
            }
        }
        return .blue
    }

    private func checkboxBackgroundColor(index: Int, isSelected: Bool, isCorrectOption: Bool) -> Color {
        if isSubmitted {
            if isCorrectOption && isSelected {
                return Color.green.opacity(0.1)
            } else if isCorrectOption && !isSelected {
                return Color.orange.opacity(0.1)
            } else if !isCorrectOption && isSelected {
                return Color.red.opacity(0.1)
            }
        } else if isSelected {
            return Color.blue.opacity(0.05)
        }
        return Color(NSColor.controlBackgroundColor)
    }

    private var actionButtonsSection: some View {
        HStack {
            Spacer()

            if !isSubmitted {
                Button("Check Answer") {
                    submitAnswer()
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedIndices.isEmpty)
            } else {
                Button("Next") {
                    let timeSpent = Int(Date().timeIntervalSince(startTime))
                    let (isCorrect, partialScore, feedback) = calculateResult()
                    onComplete(isCorrect, feedback, timeSpent, partialScore, Array(selectedIndices).sorted())
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var resultsSection: some View {
        let (isCorrect, partialScore, _) = calculateResult()
        let correctCount = selectedIndices.intersection(Set(content.correctIndices)).count
        let totalCorrect = content.correctIndices.count

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(isCorrect ? .green : (partialScore ?? 0 > 0 ? .orange : .red))
                Text(isCorrect ? "Correct!" : "Partially Correct")
                    .font(.headline)
                    .foregroundColor(isCorrect ? .green : (partialScore ?? 0 > 0 ? .orange : .red))
            }

            Text("\(correctCount) of \(totalCorrect) correct answers selected")
                .font(.subheadline)
                .foregroundColor(.secondary)

            if !isCorrect {
                Text("Correct answers: \(content.correctIndices.map { content.options[$0] }.joined(separator: ", "))")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }

    // MARK: - Actions

    private func submitAnswer() {
        isSubmitted = true
    }

    private func calculateResult() -> (Bool, Double?, String) {
        let correctSet = Set(content.correctIndices)
        let selectedCorrect = selectedIndices.intersection(correctSet).count
        let selectedIncorrect = selectedIndices.subtracting(correctSet).count
        let missedCorrect = correctSet.subtracting(selectedIndices).count

        let isCorrect = selectedIndices == correctSet
        let partialScore = max(0, Double(selectedCorrect) - Double(selectedIncorrect)) / Double(correctSet.count)

        let feedback: String
        if isCorrect {
            feedback = "Correct! You selected all the right answers."
        } else if selectedCorrect == 0 {
            feedback = "Incorrect. None of your selections were correct."
        } else {
            feedback = "Partially correct. \(selectedCorrect) of \(correctSet.count) correct, \(selectedIncorrect) incorrect, \(missedCorrect) missed."
        }

        return (isCorrect, partialScore, feedback)
    }
}

// MARK: - Fill In Blank Exercise View

struct FillInBlankExerciseView: View {
    let content: FillInBlankContent
    let onComplete: (Bool, String, Int, Double?, [String]) -> Void  // isCorrect, feedback, timeSpentSeconds, partialScore, userAnswers

    @State private var userAnswers: [String]
    @State private var isSubmitted: Bool = false
    @State private var results: [Bool] = []
    @State private var startTime: Date = Date()
    @FocusState private var focusedBlankIndex: Int?

    init(content: FillInBlankContent, onComplete: @escaping (Bool, String, Int, Double?, [String]) -> Void) {
        self.content = content
        self.onComplete = onComplete
        _userAnswers = State(initialValue: Array(repeating: "", count: content.blanks.count))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Instruction section
                instructionSection

                // Sentence with blanks section
                sentenceSection

                // Action buttons
                actionButtonsSection

                // Results section (shown after submission)
                if isSubmitted {
                    resultsSection
                }
            }
            .padding()
        }
        .onAppear {
            startTime = Date()
        }
    }

    // MARK: - View Components

    private var instructionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Fill in the Blanks")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            Text("Complete the sentence by filling in the missing words.")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    private var sentenceSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Parse and display sentence with blanks
            let parts = content.textWithBlanks.components(separatedBy: "___")

            VStack(alignment: .leading, spacing: 12) {
                ForEach(0..<content.blanks.count, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 6) {
                        // Context text
                        if index < parts.count {
                            Text(parts[index].trimmingCharacters(in: .whitespaces))
                                .font(.body)
                        }

                        // Blank input
                        HStack(spacing: 8) {
                            Text("Blank \(index + 1):")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            TextField("Type your answer", text: $userAnswers[index])
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 200)
                                .focused($focusedBlankIndex, equals: index)
                                .disabled(isSubmitted)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5)
                                        .stroke(blankBorderColor(for: index), lineWidth: isSubmitted ? 2 : 0)
                                )

                            // Result indicator
                            if isSubmitted && index < results.count {
                                if results[index] {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                } else {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.red)
                                }
                            }
                        }

                        // Show correct answer if wrong
                        if isSubmitted && index < results.count && !results[index] {
                            Text("Correct: \(content.blanks[index].correctAnswer)")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }
                }

                // Show remaining text after last blank
                if parts.count > content.blanks.count {
                    Text(parts.last?.trimmingCharacters(in: .whitespaces) ?? "")
                        .font(.body)
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
        }
    }

    private func blankBorderColor(for index: Int) -> Color {
        guard isSubmitted, index < results.count else { return .clear }
        return results[index] ? .green : .red
    }

    private var actionButtonsSection: some View {
        HStack {
            Spacer()

            if !isSubmitted {
                Button("Check Answer") {
                    submitAnswer()
                }
                .buttonStyle(.borderedProminent)
                .disabled(userAnswers.contains { $0.trimmingCharacters(in: .whitespaces).isEmpty })
            } else {
                Button("Next") {
                    let timeSpent = Int(Date().timeIntervalSince(startTime))
                    let (isCorrect, partialScore, feedback) = calculateResult()
                    onComplete(isCorrect, feedback, timeSpent, partialScore, userAnswers)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var resultsSection: some View {
        let (isCorrect, _, _) = calculateResult()
        let correctCount = results.filter { $0 }.count
        let totalBlanks = content.blanks.count

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(isCorrect ? .green : (correctCount > 0 ? .orange : .red))
                Text(isCorrect ? "All Correct!" : "Some answers need correction")
                    .font(.headline)
                    .foregroundColor(isCorrect ? .green : (correctCount > 0 ? .orange : .red))
            }

            Text("\(correctCount) of \(totalBlanks) blanks filled correctly")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }

    // MARK: - Actions

    private func submitAnswer() {
        results = content.blanks.enumerated().map { index, blank in
            let userAnswer = userAnswers[index].trimmingCharacters(in: .whitespaces).lowercased()
            let correctAnswer = blank.correctAnswer.lowercased()
            let alternatives = blank.acceptableAlternatives.map { $0.lowercased() }

            return userAnswer == correctAnswer || alternatives.contains(userAnswer)
        }
        isSubmitted = true
    }

    private func calculateResult() -> (Bool, Double?, String) {
        let correctCount = results.filter { $0 }.count
        let totalBlanks = content.blanks.count
        let isCorrect = correctCount == totalBlanks
        let partialScore = Double(correctCount) / Double(totalBlanks)

        let feedback: String
        if isCorrect {
            feedback = "Correct! All blanks filled correctly."
        } else if correctCount == 0 {
            feedback = "Incorrect. None of the blanks were filled correctly."
        } else {
            feedback = "\(correctCount) of \(totalBlanks) blanks correct."
        }

        return (isCorrect, partialScore, feedback)
    }
}
