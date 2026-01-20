import SwiftUI

// MARK: - Free Response Evaluation Result

struct FreeResponseEvaluationResult {
    let isCorrect: Bool
    let feedback: String
}

// MARK: - Free Response Exercise View

struct FreeResponseExerciseView: View {
    let content: FreeResponseContent
    let onComplete: (Bool, String, Int) -> Void  // isCorrect, feedback, timeSpentSeconds

    @State private var userResponse: String = ""
    @State private var isSubmitting: Bool = false
    @State private var evaluationResult: FreeResponseEvaluationResult?
    @State private var errorMessage: String?
    @State private var startTime: Date = Date()

    private let minCharacters = 10

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Prompt section
                promptSection

                // Response input section
                responseInputSection

                // Action buttons
                actionButtonsSection

                // Results section (shown after submission)
                if let result = evaluationResult {
                    resultsSection(result: result)
                }

                // Error message
                if let error = errorMessage {
                    errorSection(error: error)
                }
            }
            .padding()
        }
        .onAppear {
            startTime = Date()
        }
    }

    // MARK: - View Components

    private var promptSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Question")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            Text(content.prompt)
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

    private var responseInputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your Response")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            TextEditor(text: $userResponse)
                .font(.body)
                .frame(minHeight: 150)
                .padding(8)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
                .disabled(evaluationResult != nil)

            // Character count
            HStack {
                Spacer()
                Text("\(userResponse.count) characters")
                    .font(.caption)
                    .foregroundColor(userResponse.count >= minCharacters ? .secondary : .orange)
            }
        }
    }

    private var actionButtonsSection: some View {
        HStack {
            Spacer()

            if evaluationResult == nil {
                Button(action: submitResponse) {
                    HStack {
                        if isSubmitting {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 16, height: 16)
                        } else {
                            Image(systemName: "paperplane.fill")
                        }
                        Text(isSubmitting ? "Evaluating..." : "Submit")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(userResponse.count < minCharacters || isSubmitting)
            } else {
                Button(action: completeExercise) {
                    HStack {
                        Image(systemName: "arrow.right")
                        Text("Next")
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func resultsSection(result: FreeResponseEvaluationResult) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Result indicator
            HStack(spacing: 12) {
                Image(systemName: result.isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.title)
                    .foregroundColor(result.isCorrect ? .green : .orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text(result.isCorrect ? "Well Done!" : "Needs Improvement")
                        .font(.headline)
                        .foregroundColor(result.isCorrect ? .green : .orange)

                    Text(result.feedback)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(result.isCorrect ? Color.green.opacity(0.1) : Color.orange.opacity(0.1))
            .cornerRadius(12)

            // Sample answer section
            VStack(alignment: .leading, spacing: 8) {
                Text("Sample Answer")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)

                Text(content.sampleAnswer)
                    .font(.body)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
            }

            // Key points section
            if !content.keyPoints.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Key Points")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)

                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(content.keyPoints, id: \.self) { point in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "checkmark.circle")
                                    .foregroundColor(.blue)
                                    .font(.caption)
                                Text(point)
                                    .font(.subheadline)
                            }
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                }
            }
        }
    }

    private func errorSection(error: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text(error)
                .font(.subheadline)
                .foregroundColor(.orange)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
    }

    // MARK: - Actions

    private func submitResponse() {
        guard !isSubmitting else { return }

        isSubmitting = true
        errorMessage = nil

        Task {
            do {
                let result = try await evaluateFreeResponse(
                    prompt: content.prompt,
                    userAnswer: userResponse,
                    keyPoints: content.keyPoints
                )

                await MainActor.run {
                    self.evaluationResult = result
                    self.isSubmitting = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isSubmitting = false
                }
            }
        }
    }

    private func completeExercise() {
        guard let result = evaluationResult else { return }

        let timeSpent = Int(Date().timeIntervalSince(startTime))
        onComplete(result.isCorrect, result.feedback, timeSpent)
    }

    // MARK: - AI Evaluation

    private func evaluateFreeResponse(prompt: String, userAnswer: String, keyPoints: [String]) async throws -> FreeResponseEvaluationResult {
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

// MARK: - Preview

#Preview {
    FreeResponseExerciseView(
        content: FreeResponseContent(
            prompt: "Describe your ideal vacation destination and explain why you would like to visit there.",
            sampleAnswer: "My ideal vacation destination would be Japan. I've always been fascinated by the unique blend of ancient traditions and modern technology. I would love to visit historic temples in Kyoto, experience the bustling streets of Tokyo, and try authentic Japanese cuisine. The country's beautiful landscapes, from cherry blossoms to Mount Fuji, also make it incredibly appealing.",
            keyPoints: [
                "Names a specific destination",
                "Provides reasons for the choice",
                "Includes details about activities or experiences"
            ]
        ),
        onComplete: { isCorrect, feedback, timeSpent in
            print("Completed: \(isCorrect), Time: \(timeSpent)s")
        }
    )
    .frame(width: 600, height: 700)
}
