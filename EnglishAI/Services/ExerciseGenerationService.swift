import Foundation

// MARK: - Free Response Evaluation Result

struct FreeResponseEvaluationResult: Codable {
    let isCorrect: Bool
    let feedback: String
}

// MARK: - Exercise Generation Service

final class ExerciseGenerationService {
    static let shared = ExerciseGenerationService()

    private init() {}

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
