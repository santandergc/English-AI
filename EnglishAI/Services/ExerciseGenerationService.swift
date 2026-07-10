import Foundation

// MARK: - Free Response Evaluation Result

struct FreeResponseEvaluationResult: Codable {
    let isCorrect: Bool
    let feedback: String
}

// MARK: - AI Generated Exercise Response

private struct AIGeneratedExercise: Codable {
    let type: String
    let instruction: String
    let difficulty: Int
    let targetWeakness: String
    let content: ExerciseContent
}

private struct AIExerciseResponse: Codable {
    let exercises: [AIGeneratedExercise]
}

// MARK: - Exercise Generation Service

final class ExerciseGenerationService {
    static let shared = ExerciseGenerationService()

    private init() {}

    // MARK: - Exercise Generation

    /// Generate exercises based on user's weaknesses using AI
    /// - Parameters:
    ///   - weaknesses: Array of weakness categories to target (for Focus Engine
    ///     targets this is the exact item targetPhrase, so attempts map back)
    ///   - count: Number of exercises to generate (default 8)
    ///   - types: Optional filter for specific exercise types (nil = all types)
    ///   - difficulty: Optional fixed difficulty (nil = random 1-5)
    ///   - focusContext: Optional Focus Engine block (item rationales, near
    ///     misses, production-weighting rules) appended to the prompt
    /// - Returns: Array of generated Exercise objects
    func generateExercises(
        weaknesses: [String],
        count: Int = 8,
        types: [ExerciseType]? = nil,
        difficulty: Int? = nil,
        focusContext: String? = nil
    ) async throws -> [Exercise] {
        let aiService = AIAnalysisService.shared

        guard aiService.hasAPIKey else {
            throw AIAnalysisError.noAPIKey
        }

        var prompt = buildGenerationPrompt(
            weaknesses: weaknesses,
            count: count,
            types: types,
            difficulty: difficulty
        )

        if let focusContext = focusContext {
            prompt += "\n\n" + focusContext
        }

        let response: String

        if let _ = aiService.anthropicAPIKey {
            response = try await callAnthropicForGeneration(prompt: prompt)
        } else if let _ = aiService.openAIAPIKey {
            response = try await callOpenAIForGeneration(prompt: prompt)
        } else {
            throw AIAnalysisError.noAPIKey
        }

        return parseGeneratedExercises(response, weaknesses: weaknesses)
    }

    // MARK: - Generation Prompt

    private static let exercisePromptTemplate = """
    You are an English language tutor creating practice exercises for a non-native speaker.

    Generate exactly {COUNT} exercises based on the student's weaknesses. Create practical, natural-sounding exercises (not textbook-like).

    STUDENT'S WEAKNESSES:
    {WEAKNESSES}

    EXERCISE TYPES TO USE:
    {TYPES}

    {DIFFICULTY_INSTRUCTION}

    EXERCISE TYPE SPECIFICATIONS:

    1. singleChoice: Multiple choice with one correct answer
       Content schema: {"question": "string", "options": ["string array, 4 options"], "correctIndex": 0-3}

    2. multipleChoice: Multiple choice with multiple correct answers
       Content schema: {"question": "string", "options": ["string array, 4-5 options"], "correctIndices": [array of correct indices]}

    3. fillInBlank: Complete sentences with missing words (use ___ as placeholder)
       Content schema: {"textWithBlanks": "sentence with ___ for blanks", "blanks": [{"position": 0, "correctAnswer": "string", "acceptableAlternatives": ["string array"]}]}

    4. freeResponse: Open-ended writing prompt
       Content schema: {"prompt": "string", "sampleAnswer": "string", "keyPoints": ["string array of key points to address"]}

    5. errorCorrection: Find and fix errors in a sentence
       Content schema: {"incorrectSentence": "string with errors", "errors": [{"position": word_index, "incorrectText": "wrong", "correctText": "correct", "explanation": "why"}]}

    6. sentenceReorder: Arrange scrambled words into correct order
       Content schema: {"shuffledWords": ["word", "array", "scrambled"], "correctOrder": [indices showing correct positions]}

    7. matching: Match items from two columns
       Content schema: {"leftItems": ["string array"], "rightItems": ["string array"], "correctPairs": [{"leftIndex": 0, "rightIndex": 0}]}

    8. wordFormation: Use the correct form of a word (use ___ as placeholder)
       Content schema: {"baseSentence": "She is very ___ (BEAUTY)", "targetWord": "BEAUTY", "correctForm": "beautiful", "wordFamily": ["beauty", "beautiful", "beautifully", "beautify"]}

    DIFFICULTY LEVELS (affects vocabulary complexity and sentence length):
    1 = Basic vocabulary, simple sentences
    2 = Elementary vocabulary, compound sentences
    3 = Intermediate vocabulary, complex sentences
    4 = Advanced vocabulary, sophisticated structures
    5 = Expert level, nuanced expressions

    RESPOND WITH ONLY A JSON OBJECT (no markdown, no explanation):
    {
        "exercises": [
            {
                "type": "exerciseType",
                "instruction": "Clear instruction for the student",
                "difficulty": 1-5,
                "targetWeakness": "The weakness this targets",
                "content": {content object matching the type schema}
            }
        ]
    }

    IMPORTANT:
    - Create practical, real-world scenarios
    - Vary the exercise types
    - Make instructions clear and concise
    - Target the specified weaknesses
    - Ensure all content schemas are valid
    """

    private func buildGenerationPrompt(
        weaknesses: [String],
        count: Int,
        types: [ExerciseType]?,
        difficulty: Int?
    ) -> String {
        var prompt = Self.exercisePromptTemplate

        // Replace placeholders
        prompt = prompt.replacingOccurrences(of: "{COUNT}", with: "\(count)")

        let weaknessList = weaknesses.isEmpty
            ? "General English improvement"
            : weaknesses.map { "- \($0)" }.joined(separator: "\n")
        prompt = prompt.replacingOccurrences(of: "{WEAKNESSES}", with: weaknessList)

        let typesList: String
        if let types = types, !types.isEmpty {
            typesList = types.map { $0.rawValue }.joined(separator: ", ")
        } else {
            typesList = ExerciseType.allCases.map { $0.rawValue }.joined(separator: ", ")
        }
        prompt = prompt.replacingOccurrences(of: "{TYPES}", with: typesList)

        let difficultyInstruction: String
        if let diff = difficulty {
            difficultyInstruction = "Use difficulty level \(diff) for all exercises."
        } else {
            difficultyInstruction = "Randomize difficulty levels between 1-5 for variety."
        }
        prompt = prompt.replacingOccurrences(of: "{DIFFICULTY_INSTRUCTION}", with: difficultyInstruction)

        return prompt
    }

    private func callAnthropicForGeneration(prompt: String) async throws -> String {
        guard let apiKey = AIAnalysisService.shared.anthropicAPIKey else {
            throw AIAnalysisError.noAPIKey
        }

        let requestBody: [String: Any] = [
            "model": "claude-sonnet-4-20250514",
            "max_tokens": 4096,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIAnalysisError.invalidResponse
        }

        if httpResponse.statusCode == 429 {
            throw AIAnalysisError.rateLimited
        }

        guard httpResponse.statusCode == 200 else {
            throw AIAnalysisError.invalidResponse
        }

        let responseJSON = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let content = responseJSON?["content"] as? [[String: Any]],
              let textContent = content.first?["text"] as? String else {
            throw AIAnalysisError.invalidResponse
        }

        return textContent
    }

    private func callOpenAIForGeneration(prompt: String) async throws -> String {
        guard let apiKey = AIAnalysisService.shared.openAIAPIKey else {
            throw AIAnalysisError.noAPIKey
        }

        let requestBody: [String: Any] = [
            "model": "gpt-4o",
            "max_tokens": 4096,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIAnalysisError.invalidResponse
        }

        if httpResponse.statusCode == 429 {
            throw AIAnalysisError.rateLimited
        }

        guard httpResponse.statusCode == 200 else {
            throw AIAnalysisError.invalidResponse
        }

        let responseJSON = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let choices = responseJSON?["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let textContent = message["content"] as? String else {
            throw AIAnalysisError.invalidResponse
        }

        return textContent
    }

    private func parseGeneratedExercises(_ response: String, weaknesses: [String]) -> [Exercise] {
        var jsonString = response.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove markdown code blocks if present
        if jsonString.hasPrefix("```json") {
            jsonString = String(jsonString.dropFirst(7))
        } else if jsonString.hasPrefix("```") {
            jsonString = String(jsonString.dropFirst(3))
        }
        if jsonString.hasSuffix("```") {
            jsonString = String(jsonString.dropLast(3))
        }
        jsonString = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = jsonString.data(using: .utf8) else {
            print("[ExerciseGenerationService] Failed to convert response to data")
            return []
        }

        // Try to parse using JSONSerialization first for more flexibility
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exercisesArray = json["exercises"] as? [[String: Any]] else {
            print("[ExerciseGenerationService] Failed to parse exercises JSON")
            return []
        }

        var exercises: [Exercise] = []
        let defaultWeakness = weaknesses.first ?? "General English"

        for exerciseDict in exercisesArray {
            guard let typeStr = exerciseDict["type"] as? String,
                  let exerciseType = ExerciseType(rawValue: typeStr),
                  let instruction = exerciseDict["instruction"] as? String,
                  let contentDict = exerciseDict["content"] else {
                continue
            }

            let difficulty = (exerciseDict["difficulty"] as? Int) ?? Int.random(in: 1...5)
            let targetWeakness = (exerciseDict["targetWeakness"] as? String) ?? defaultWeakness

            // Parse content based on type
            guard let content = parseExerciseContent(type: exerciseType, from: contentDict) else {
                continue
            }

            let exercise = Exercise(
                type: exerciseType,
                instruction: instruction,
                content: content,
                difficulty: difficulty,
                targetWeakness: targetWeakness
            )
            exercises.append(exercise)
        }

        return exercises
    }

    private func parseExerciseContent(type: ExerciseType, from dict: Any) -> ExerciseContent? {
        guard let contentDict = dict as? [String: Any] else { return nil }

        // Convert back to JSON data for Codable parsing
        guard let jsonData = try? JSONSerialization.data(withJSONObject: contentDict) else {
            return nil
        }

        let decoder = JSONDecoder()

        do {
            switch type {
            case .singleChoice:
                let content = try decoder.decode(SingleChoiceContent.self, from: jsonData)
                return .singleChoice(content)
            case .multipleChoice:
                let content = try decoder.decode(MultipleChoiceContent.self, from: jsonData)
                return .multipleChoice(content)
            case .fillInBlank:
                let content = try decoder.decode(FillInBlankContent.self, from: jsonData)
                return .fillInBlank(content)
            case .freeResponse:
                let content = try decoder.decode(FreeResponseContent.self, from: jsonData)
                return .freeResponse(content)
            case .errorCorrection:
                let content = try decoder.decode(ErrorCorrectionContent.self, from: jsonData)
                return .errorCorrection(content)
            case .sentenceReorder:
                let content = try decoder.decode(SentenceReorderContent.self, from: jsonData)
                return .sentenceReorder(content)
            case .matching:
                let content = try decoder.decode(MatchingContent.self, from: jsonData)
                return .matching(content)
            case .wordFormation:
                let content = try decoder.decode(WordFormationContent.self, from: jsonData)
                return .wordFormation(content)
            }
        } catch {
            print("[ExerciseGenerationService] Failed to parse \(type.rawValue) content: \(error)")
            return nil
        }
    }

    // MARK: - Free Response Evaluation

    /// Evaluates a free-form text response using AI
    /// - Parameters:
    ///   - prompt: The exercise prompt/question
    ///   - userAnswer: The user's written response
    ///   - keyPoints: Key points the answer should address
    /// - Returns: Evaluation result with isCorrect flag and feedback
    func evaluateFreeResponse(prompt: String, userAnswer: String, keyPoints: [String]) async throws -> FreeResponseEvaluationResult {
        let aiService = AIAnalysisService.shared

        guard aiService.hasAPIKey else {
            throw AIAnalysisError.noAPIKey
        }

        let evaluationPrompt = buildEvaluationPrompt(
            prompt: prompt,
            userAnswer: userAnswer,
            keyPoints: keyPoints
        )

        let response: String

        if let _ = aiService.anthropicAPIKey {
            response = try await callAnthropicForEvaluation(prompt: evaluationPrompt)
        } else if let _ = aiService.openAIAPIKey {
            response = try await callOpenAIForEvaluation(prompt: evaluationPrompt)
        } else {
            throw AIAnalysisError.noAPIKey
        }

        return parseEvaluationResponse(response)
    }

    // MARK: - Private Methods

    private func buildEvaluationPrompt(prompt: String, userAnswer: String, keyPoints: [String]) -> String {
        let keyPointsList = keyPoints.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")

        return """
        You are an English language tutor evaluating a student's free response answer.

        EXERCISE PROMPT:
        \(prompt)

        KEY POINTS THE ANSWER SHOULD ADDRESS:
        \(keyPointsList)

        STUDENT'S ANSWER:
        \(userAnswer)

        Evaluate the student's answer and respond with ONLY a JSON object (no markdown):
        {
            "isCorrect": true/false,
            "feedback": "Brief 1-2 sentence feedback"
        }

        Evaluation criteria:
        - Mark as correct if the student addresses most key points adequately
        - Focus on content and meaning, not perfect grammar (unless severely incorrect)
        - Be encouraging but honest
        - Feedback should be constructive and specific
        """
    }

    private func callAnthropicForEvaluation(prompt: String) async throws -> String {
        guard let apiKey = AIAnalysisService.shared.anthropicAPIKey else {
            throw AIAnalysisError.noAPIKey
        }

        let requestBody: [String: Any] = [
            "model": "claude-sonnet-4-20250514",
            "max_tokens": 256,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIAnalysisError.invalidResponse
        }

        if httpResponse.statusCode == 429 {
            throw AIAnalysisError.rateLimited
        }

        guard httpResponse.statusCode == 200 else {
            throw AIAnalysisError.invalidResponse
        }

        let responseJSON = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let content = responseJSON?["content"] as? [[String: Any]],
              let textContent = content.first?["text"] as? String else {
            throw AIAnalysisError.invalidResponse
        }

        return textContent
    }

    private func callOpenAIForEvaluation(prompt: String) async throws -> String {
        guard let apiKey = AIAnalysisService.shared.openAIAPIKey else {
            throw AIAnalysisError.noAPIKey
        }

        let requestBody: [String: Any] = [
            "model": "gpt-4o",
            "max_tokens": 256,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIAnalysisError.invalidResponse
        }

        if httpResponse.statusCode == 429 {
            throw AIAnalysisError.rateLimited
        }

        guard httpResponse.statusCode == 200 else {
            throw AIAnalysisError.invalidResponse
        }

        let responseJSON = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let choices = responseJSON?["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let textContent = message["content"] as? String else {
            throw AIAnalysisError.invalidResponse
        }

        return textContent
    }

    private func parseEvaluationResponse(_ response: String) -> FreeResponseEvaluationResult {
        var jsonString = response.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove markdown code blocks if present
        if jsonString.hasPrefix("```json") {
            jsonString = String(jsonString.dropFirst(7))
        } else if jsonString.hasPrefix("```") {
            jsonString = String(jsonString.dropFirst(3))
        }
        if jsonString.hasSuffix("```") {
            jsonString = String(jsonString.dropLast(3))
        }
        jsonString = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let isCorrect = json["isCorrect"] as? Bool,
              let feedback = json["feedback"] as? String else {
            // Default response if parsing fails
            return FreeResponseEvaluationResult(
                isCorrect: false,
                feedback: "Unable to evaluate response. Please try again."
            )
        }

        return FreeResponseEvaluationResult(isCorrect: isCorrect, feedback: feedback)
    }
}
