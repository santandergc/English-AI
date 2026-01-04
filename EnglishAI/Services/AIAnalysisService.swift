import Foundation

enum AIProvider: String {
    case anthropic
    case openai
}

enum AIAnalysisError: Error, LocalizedError {
    case noAPIKey
    case insufficientData
    case networkError(Error)
    case invalidResponse
    case rateLimited
    
    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "No API key configured. Please set your API key in Settings."
        case .insufficientData:
            return "Not enough data to analyze. Keep writing and try again later."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from AI service."
        case .rateLimited:
            return "Rate limited. Please try again later."
        }
    }
}

final class AIAnalysisService {
    static let shared = AIAnalysisService()
    
    private let database = DatabaseService.shared
    private let minimumCharacters = 300
    
    private init() {}
    
    // MARK: - API Key Management
    
    var anthropicAPIKey: String? {
        get {
            let key = UserDefaults.standard.string(forKey: "anthropic_api_key")
            return key?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? key?.trimmingCharacters(in: .whitespacesAndNewlines) : nil
        }
        set {
            let trimmed = newValue?.trimmingCharacters(in: .whitespacesAndNewlines)
            UserDefaults.standard.set(trimmed?.isEmpty == false ? trimmed : nil, forKey: "anthropic_api_key")
            UserDefaults.standard.synchronize()
        }
    }
    
    var openAIAPIKey: String? {
        get {
            let key = UserDefaults.standard.string(forKey: "openai_api_key")
            return key?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? key?.trimmingCharacters(in: .whitespacesAndNewlines) : nil
        }
        set {
            let trimmed = newValue?.trimmingCharacters(in: .whitespacesAndNewlines)
            UserDefaults.standard.set(trimmed?.isEmpty == false ? trimmed : nil, forKey: "openai_api_key")
            UserDefaults.standard.synchronize()
        }
    }
    
    var hasAPIKey: Bool {
        return (anthropicAPIKey != nil && !anthropicAPIKey!.isEmpty) ||
               (openAIAPIKey != nil && !openAIAPIKey!.isEmpty)
    }
    
    var activeProvider: AIProvider? {
        if let key = anthropicAPIKey, !key.isEmpty {
            return .anthropic
        } else if let key = openAIAPIKey, !key.isEmpty {
            return .openai
        }
        return nil
    }
    
    var activeProviderName: String {
        switch activeProvider {
        case .anthropic: return "Claude (Anthropic)"
        case .openai: return "GPT (OpenAI)"
        case .none: return "None"
        }
    }
    
    // MARK: - Analysis
    
    func analyzeUnanalyzedRecords() async throws -> AnalysisResult {
        guard hasAPIKey else {
            throw AIAnalysisError.noAPIKey
        }
        
        let (records, dateRange) = database.fetchUnanalyzedRecords(minCharacters: minimumCharacters)
        
        guard !records.isEmpty, let range = dateRange else {
            throw AIAnalysisError.insufficientData
        }
        
        let totalCharacters = records.reduce(0) { $0 + $1.content.count }
        
        if totalCharacters < minimumCharacters {
            throw AIAnalysisError.insufficientData
        }
        
        let result = try await sendToAPI(records: records)
        
        // Save the analysis session
        let session = AnalysisSession(
            dateRangeStart: range.start,
            dateRangeEnd: range.end,
            recordsAnalyzed: records.count,
            charactersAnalyzed: totalCharacters
        )
        database.insertAnalysisSession(session)
        
        // Save insights
        let insightContent = try JSONEncoder().encode(result)
        let insight = Insight(
            dateRangeStart: range.start,
            dateRangeEnd: range.end,
            insightType: .grammar,
            content: String(data: insightContent, encoding: .utf8) ?? "{}",
            recordCount: records.count,
            characterCount: totalCharacters
        )
        database.insertInsight(insight)
        
        return result
    }
    
    func analyzeRecords(for date: Date) async throws -> AnalysisResult {
        guard hasAPIKey else {
            throw AIAnalysisError.noAPIKey
        }
        
        let records = database.fetchRecords(for: date)
        
        guard !records.isEmpty else {
            throw AIAnalysisError.insufficientData
        }
        
        let totalCharacters = records.reduce(0) { $0 + $1.content.count }
        
        let result = try await sendToAPI(records: records)
        
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
        
        // Delete old analysis for this date (if re-analyzing)
        database.deleteInsights(for: date)
        
        // Save the analysis session
        let session = AnalysisSession(
            dateRangeStart: dayStart,
            dateRangeEnd: dayEnd,
            recordsAnalyzed: records.count,
            charactersAnalyzed: totalCharacters
        )
        database.insertAnalysisSession(session)
        
        // Save insights
        let insightContent = try JSONEncoder().encode(result)
        let insight = Insight(
            dateRangeStart: dayStart,
            dateRangeEnd: dayEnd,
            insightType: .grammar,
            content: String(data: insightContent, encoding: .utf8) ?? "{}",
            recordCount: records.count,
            characterCount: totalCharacters
        )
        database.insertInsight(insight)
        
        return result
    }
    
    // MARK: - Weekly Progress
    
    func generateWeeklyProgress() async throws -> String {
        guard hasAPIKey else {
            throw AIAnalysisError.noAPIKey
        }
        
        let insights = database.fetchAllInsights(limit: 7)
        
        guard !insights.isEmpty else {
            throw AIAnalysisError.insufficientData
        }
        
        return try await sendWeeklyProgressToAPI(insights: insights)
    }
    
    // MARK: - AI API Calls
    
    private func sendToAPI(records: [Record]) async throws -> AnalysisResult {
        guard let provider = activeProvider else {
            throw AIAnalysisError.noAPIKey
        }
        
        let keyboardRecords = records.filter { $0.source == .keyboard }
        let wisprRecords = records.filter { $0.source == .wispr }
        let prompt = buildAnalysisPrompt(keyboardRecords: keyboardRecords, wisprRecords: wisprRecords)
        
        let textContent: String
        
        switch provider {
        case .anthropic:
            textContent = try await callAnthropicAPI(prompt: prompt, maxTokens: 4096)
        case .openai:
            textContent = try await callOpenAIAPI(prompt: prompt, maxTokens: 4096)
        }
        
        return parseAnalysisResponse(textContent)
    }
    
    private func sendWeeklyProgressToAPI(insights: [Insight]) async throws -> String {
        guard let provider = activeProvider else {
            throw AIAnalysisError.noAPIKey
        }
        
        let prompt = buildWeeklyProgressPrompt(insights: insights)
        
        switch provider {
        case .anthropic:
            return try await callAnthropicAPI(prompt: prompt, maxTokens: 2048)
        case .openai:
            return try await callOpenAIAPI(prompt: prompt, maxTokens: 2048)
        }
    }
    
    // MARK: - Anthropic API
    
    private func callAnthropicAPI(prompt: String, maxTokens: Int) async throws -> String {
        guard let apiKey = anthropicAPIKey else {
            throw AIAnalysisError.noAPIKey
        }
        
        let requestBody: [String: Any] = [
            "model": "claude-sonnet-4-20250514",
            "max_tokens": maxTokens,
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
            print("Anthropic API Error: \(String(data: data, encoding: .utf8) ?? "Unknown")")
            throw AIAnalysisError.invalidResponse
        }
        
        let responseJSON = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let content = responseJSON?["content"] as? [[String: Any]],
              let textContent = content.first?["text"] as? String else {
            throw AIAnalysisError.invalidResponse
        }
        
        return textContent
    }
    
    // MARK: - OpenAI API
    
    private func callOpenAIAPI(prompt: String, maxTokens: Int) async throws -> String {
        guard let apiKey = openAIAPIKey, !apiKey.isEmpty else {
            print("⚠️ OpenAI API Key is missing or empty")
            throw AIAnalysisError.noAPIKey
        }
        
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            print("⚠️ OpenAI API Key is empty after trimming")
            throw AIAnalysisError.noAPIKey
        }
        
        let requestBody: [String: Any] = [
            "model": "gpt-4o",
            "max_tokens": maxTokens,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]
        
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIAnalysisError.invalidResponse
        }
        
        if httpResponse.statusCode == 429 {
            throw AIAnalysisError.rateLimited
        }
        
        guard httpResponse.statusCode == 200 else {
            print("OpenAI API Error: \(String(data: data, encoding: .utf8) ?? "Unknown")")
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
    
    // MARK: - Prompts
    
    private func buildAnalysisPrompt(keyboardRecords: [Record], wisprRecords: [Record]) -> String {
        var prompt = """
        You are an English tutor helping a Chilean native Spanish speaker improve their English.
        Analyze the following text they wrote (keyboard) and spoke (voice via Wispr Flow) today.
        
        Be encouraging but precise. Focus on patterns, not every single typo.
        
        """
        
        if !keyboardRecords.isEmpty {
            prompt += "\n--- KEYBOARD (typed text) ---\n"
            for record in keyboardRecords {
                prompt += "[\(record.activeApp)] \(record.content)\n"
            }
        }
        
        if !wisprRecords.isEmpty {
            prompt += "\n--- WISPR (spoken text) ---\n"
            for record in wisprRecords {
                prompt += "[\(record.activeApp)] \(record.content)\n"
            }
        }
        
        prompt += """
        
        Analyze and respond with a JSON object (and ONLY the JSON, no markdown):
        {
            "grammarIssues": [
                {"original": "text with error", "corrected": "corrected text", "explanation": "brief explanation"}
            ],
            "phrasingIssues": [
                {"original": "awkward phrase", "natural": "natural way to say it", "context": "when to use this"}
            ],
            "vocabularyInsights": [
                {"word": "word used", "suggestion": "better alternative or null", "note": "usage tip"}
            ],
            "positives": ["thing they did well 1", "thing they did well 2"],
            "overallScore": 7,
            "summary": "One paragraph summary of their English today, encouraging tone, specific advice"
        }
        
        Important:
        - Focus on the 3-5 most important grammar issues, not every typo
        - Note patterns common to Spanish speakers (articles, prepositions, verb tenses)
        - If comparing keyboard vs voice, note if errors differ between modalities
        - overallScore is 1-10 (7 = good, 5 = needs work, 9 = excellent)
        - Be encouraging and constructive
        """
        
        return prompt
    }
    
    private func buildWeeklyProgressPrompt(insights: [Insight]) -> String {
        var prompt = """
        You are reviewing a week of English learning progress for a Chilean native Spanish speaker.
        Below are the daily analysis results. Identify patterns, improvements, and recurring issues.
        
        """
        
        for insight in insights {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            let dateStr = formatter.string(from: insight.dateRangeStart)
            prompt += "\n--- \(dateStr) ---\n"
            prompt += insight.content
            prompt += "\n"
        }
        
        prompt += """
        
        Provide a weekly progress report in a friendly, encouraging tone:
        1. Top 3 recurring mistakes to focus on
        2. Notable improvements or strengths
        3. Specific practice recommendations for next week
        4. Overall progress assessment
        
        Keep it concise but actionable.
        """
        
        return prompt
    }
    
    // MARK: - Response Parsing
    
    private func parseAnalysisResponse(_ response: String) -> AnalysisResult {
        // Try to extract JSON from the response
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
              let result = try? JSONDecoder().decode(AnalysisResult.self, from: data) else {
            // Return a default result if parsing fails
            return AnalysisResult(
                grammarIssues: [],
                phrasingIssues: [],
                vocabularyInsights: [],
                positives: ["Analysis completed but parsing failed. Raw response saved."],
                overallScore: 5,
                summary: response
            )
        }
        
        return result
    }
}

// MARK: - Convenience Methods

extension AIAnalysisService {
    func hasAnalysis(for date: Date) -> Bool {
        return DatabaseService.shared.hasAnalysis(for: date)
    }
}
