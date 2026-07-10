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

        // Fetch voice recordings for all days in the date range
        var voiceRecordings: [VoiceRecording] = []
        let calendar = Calendar.current
        var currentDate = calendar.startOfDay(for: range.start)
        let endDate = calendar.startOfDay(for: range.end)

        while currentDate <= endDate {
            let dayRecordings = database.getRecordingsForDate(currentDate)
            voiceRecordings.append(contentsOf: dayRecordings)
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? endDate
        }

        let totalCharacters = records.reduce(0) { $0 + $1.content.count }

        if totalCharacters < minimumCharacters {
            throw AIAnalysisError.insufficientData
        }

        let (result, _) = try await sendToAPI(records: records, recordings: voiceRecordings)

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

        // Fetch voice recordings for this date (only completed ones with transcriptions)
        let voiceRecordings = database.getRecordingsForDate(date)

        guard !records.isEmpty || !voiceRecordings.filter({ $0.transcriptionStatus == .completed && $0.transcription != nil }).isEmpty else {
            throw AIAnalysisError.insufficientData
        }

        let totalCharacters = records.reduce(0) { $0 + $1.content.count }

        let (result, focusExtension) = try await sendToAPI(records: records, recordings: voiceRecordings)

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

        // Feed the Focus Engine. On schema failure focusExtension is nil and
        // the legacy analysis above still landed — never lose a day.
        if let focusExtension = focusExtension {
            FocusQueueService.shared.applyAnalysisExtension(focusExtension, analyzedDate: dayStart)
        }

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

    // MARK: - Selected Text Review

    func reviewSelectedText(_ capture: SelectedTextCapture) async throws -> SelectedTextReview {
        guard let provider = activeProvider else {
            throw AIAnalysisError.noAPIKey
        }

        let redaction = TrustCenter.shared.prepareTextForAI(capture.text)
        let prompt = buildSelectedTextReviewPrompt(
            originalText: redaction.text,
            appName: capture.appName,
            redactionCount: redaction.redactionCount
        )

        let textContent: String
        switch provider {
        case .anthropic:
            textContent = try await callAnthropicAPI(
                prompt: prompt,
                maxTokens: 900,
                model: "claude-haiku-4-5-20251001"
            )
        case .openai:
            textContent = try await callOpenAIResponsesAPI(
                prompt: prompt,
                model: "gpt-5.4-nano",
                maxOutputTokens: 900
            )
        }

        return parseSelectedTextReviewResponse(
            textContent,
            originalText: capture.text,
            redaction: redaction
        )
    }

    // MARK: - AI API Calls

    private func sendToAPI(records: [Record], recordings: [VoiceRecording] = []) async throws -> (AnalysisResult, FocusAnalysisExtension?) {
        guard let provider = activeProvider else {
            throw AIAnalysisError.noAPIKey
        }

        let keyboardRecords = records.filter { $0.source == .keyboard }
        let wisprRecords = records.filter { $0.source == .wispr }

        // Filter to only completed transcriptions
        let completedRecordings = recordings.filter { $0.transcriptionStatus == .completed && $0.transcription != nil }

        let prompt = buildAnalysisPrompt(keyboardRecords: keyboardRecords, wisprRecords: wisprRecords, voiceRecordings: completedRecordings)

        let textContent: String

        // 8192, not 4096: the superset response (legacy fields + verdicts +
        // candidates + full profile rewrite + brief) does not reliably fit in
        // 4096 — truncated JSON would trip the fallback path every day and the
        // profile would never update.
        switch provider {
        case .anthropic:
            textContent = try await callAnthropicAPI(prompt: prompt, maxTokens: 8192)
        case .openai:
            textContent = try await callOpenAIAPI(prompt: prompt, maxTokens: 8192)
        }

        let result = parseAnalysisResponse(textContent)
        let focusExtension = parseFocusExtension(textContent)
        return (result, focusExtension)
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
    
    private func callAnthropicAPI(
        prompt: String,
        maxTokens: Int,
        model: String = "claude-sonnet-4-20250514"
    ) async throws -> String {
        guard let apiKey = anthropicAPIKey else {
            throw AIAnalysisError.noAPIKey
        }

        let requestBody: [String: Any] = [
            "model": model,
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

    private func callOpenAIResponsesAPI(prompt: String, model: String, maxOutputTokens: Int) async throws -> String {
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
            "model": model,
            "input": prompt,
            "max_output_tokens": maxOutputTokens
        ]

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
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
            print("OpenAI Responses API Error: \(String(data: data, encoding: .utf8) ?? "Unknown")")
            throw AIAnalysisError.invalidResponse
        }

        let responseJSON = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        if let outputText = responseJSON?["output_text"] as? String {
            return outputText
        }

        if let output = responseJSON?["output"] as? [[String: Any]] {
            let texts = output.flatMap { item -> [String] in
                guard let content = item["content"] as? [[String: Any]] else { return [] }
                return content.compactMap { contentItem in
                    if let text = contentItem["text"] as? String {
                        return text
                    }
                    if let text = contentItem["output_text"] as? String {
                        return text
                    }
                    return nil
                }
            }

            if !texts.isEmpty {
                return texts.joined(separator: "\n")
            }
        }

        throw AIAnalysisError.invalidResponse
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
    
    private func buildAnalysisPrompt(keyboardRecords: [Record], wisprRecords: [Record], voiceRecordings: [VoiceRecording] = []) -> String {
        var prompt = """
        You are an English tutor helping a Chilean native Spanish speaker improve their English.
        Analyze the following text they wrote (keyboard), spoke via Wispr Flow dictation, and recorded voice transcriptions today.

        Be encouraging but precise. Focus on patterns, not every single typo.

        """

        if !keyboardRecords.isEmpty {
            prompt += "\n--- KEYBOARD (typed text) ---\n"
            for record in keyboardRecords {
                let redactedContent = TrustCenter.shared.prepareTextForAI(record.content).text
                prompt += "[\(record.activeApp)] \(redactedContent)\n"
            }
        }

        if !wisprRecords.isEmpty {
            prompt += "\n--- WISPR (spoken text via dictation) ---\n"
            for record in wisprRecords {
                let redactedContent = TrustCenter.shared.prepareTextForAI(record.content).text
                prompt += "[\(record.activeApp)] \(redactedContent)\n"
            }
        }

        if !voiceRecordings.isEmpty {
            prompt += "\n--- VOICE RECORDING TRANSCRIPTIONS ---\n"
            let timeFormatter = DateFormatter()
            timeFormatter.dateFormat = "HH:mm"
            for recording in voiceRecordings {
                let timestamp = timeFormatter.string(from: recording.startTime)
                let durationMinutes = Int(recording.duration / 60)
                let durationSeconds = Int(recording.duration) % 60
                if let transcription = recording.transcription {
                    let redactedTranscription = TrustCenter.shared.prepareTextForAI(transcription).text
                    prompt += "[\(timestamp), \(durationMinutes)m\(durationSeconds)s] \(redactedTranscription)\n"
                }
            }
        }

        prompt += buildFocusContextSection()

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
            "summary": "One paragraph summary of their English today, encouraging tone, specific advice",
            "sightingVerdicts": [
                {"evidenceId": 123, "correct": true, "note": "natural, correct use"}
            ],
            "newErrorEvidence": [
                {"focusItemId": 4, "excerpt": "exact quote from today's text containing the error", "app": "Slack"}
            ],
            "candidates": [
                {"kind": "enrich", "targetPhrase": "crucial / vital / decisive",
                 "matchForms": ["crucial", "vital", "decisive"],
                 "rationale": "you wrote 'very important' repeatedly — one precise word beats two vague ones",
                 "excerpts": ["exact quotes from the user's own text proving the pattern"]}
            ],
            "queueAdvice": {"promote": ["targetPhrase"], "retire": [], "candidatePriorities": ["targetPhrase in rank order"], "reasoning": "one line"},
            "profileUpdate": {"crutches": [], "error_patterns": [], "strengths": [], "vocab_notes": [], "style_notes": [], "retired_entries": []},
            "morningBrief": {"focusTargetPhrase": "targetPhrase of ONE active queue item", "headline": "Retire 'very important.'", "mission": "Use crucial, vital or decisive in one real message today.", "wins": ["quote a real sentence from yesterday and celebrate it"]}
        }

        Important:
        - Focus on the 3-5 most important grammar issues, not every typo
        - Note patterns common to Spanish speakers (articles, prepositions, verb tenses)
        - If comparing keyboard vs voice, note if errors differ between modalities
        - For voice recording transcriptions, pay attention to spoken English patterns like filler words, sentence structure, and natural speech flow
        - overallScore is 1-10 (7 = good, 5 = needs work, 9 = excellent)
        - Be encouraging and constructive

        FOCUS ENGINE RULES (the fields after "summary"):
        - sightingVerdicts: rule on EVERY pending sighting listed above by its evidenceId. correct=true only if the target was used correctly and naturally.
        - newErrorEvidence: for each active FIX item, cite exact quotes from today's text where the error pattern occurred (empty array if none). Use the item's focusItemId.
        - candidates: nominate 0-3 new focus items MAX, only when today's text shows a real pattern. Every candidate MUST include exact-quote excerpts from the user's own text as receipts. No evidence, no nomination. matchForms must enumerate surface forms including contractions and inflections (e.g. "I'd rather", "I would rather", "rather than").
        - queueAdvice: reference items ONLY by their exact targetPhrase. Promote candidates only if an active slot is free (max 5 active). Retire active items only when clearly superseded.
        - profileUpdate: REWRITE the full profile document. Carry forward EVERY existing entry unless you explicitly move it to retired_entries with a reason. Max 15 entries per list, keep the whole document under 2KB.
        - morningBrief: focusTargetPhrase must be an ACTIVE queue item (after your promotions). ONE focus. Mission = one concrete real-world action for today. Wins = quote the user's actual sentences from today's records (verified sightings, error-free streaks). Speak directly to Cristobal, warm but precise.
        """

        return prompt
    }

    /// The Focus Engine context injected into every daily analysis: latest
    /// profile, active queue, pending sightings and the candidate pool. Rowids
    /// are included so the model can echo them back (evidenceId/focusItemId);
    /// candidates nominated in the same response are referenced by phrase.
    private func buildFocusContextSection() -> String {
        let db = DatabaseService.shared
        var section = "\n\n--- YOUR PERSISTENT KNOWLEDGE OF THIS USER (Focus Engine) ---\n"

        if let profile = db.getLatestProfileVersion() {
            section += "\nLANGUAGE PROFILE (version \(profile.version), yours to rewrite in profileUpdate):\n\(profile.content)\n"
        } else {
            section += "\nLANGUAGE PROFILE: none yet — this is the first run. Create it in profileUpdate from today's evidence.\n"
        }

        let activeItems = db.getFocusItems(statuses: FocusItemStatus.activeStatuses)
        if activeItems.isEmpty {
            section += "\nACTIVE FOCUS QUEUE: empty (max 5 slots). Nominate candidates and promote the best."
        } else {
            section += "\nACTIVE FOCUS QUEUE (max 5 slots):\n"
            for item in activeItems {
                let uses = item.id.map { db.countVerifiedCorrectUses(forItem: $0) } ?? 0
                section += "- focusItemId \(item.id ?? -1) [\(item.kind.rawValue)] \"\(item.targetPhrase)\" status=\(item.status.rawValue) verifiedWildUses=\(uses) — \(item.rationale)\n"
            }
        }

        let pending = db.getPendingFocusEvidence()
        if pending.isEmpty {
            section += "\nPENDING SIGHTINGS: none.\n"
        } else {
            section += "\nPENDING SIGHTINGS (locally matched, awaiting your verdict — rule on ALL of them):\n"
            for sighting in pending {
                let phrase = db.getFocusItem(byId: sighting.focusItemId)?.targetPhrase ?? "?"
                section += "- evidenceId \(sighting.id ?? -1) target=\"\(phrase)\" app=\(sighting.app ?? "?") excerpt: \"\(sighting.excerpt.prefix(200))\"\n"
            }
        }

        let candidates = db.getFocusItems(statuses: [.candidate])
        if !candidates.isEmpty {
            section += "\nCANDIDATE POOL (not yet queued — re-rank via candidatePriorities, promote via promote):\n"
            for candidate in candidates {
                section += "- [\(candidate.kind.rawValue)] \"\(candidate.targetPhrase)\" priority=\(candidate.priority) — \(candidate.rationale)\n"
            }
        }

        section += "\n--- END FOCUS ENGINE CONTEXT ---\n"
        return section
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

    /// Strict parse of the Focus Engine superset fields. Returns nil when the
    /// response carries none of them (or is malformed) — callers then proceed
    /// legacy-only and keep the previous profile version. Never loses a day.
    private func parseFocusExtension(_ response: String) -> FocusAnalysisExtension? {
        var jsonString = response.trimmingCharacters(in: .whitespacesAndNewlines)
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
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let hasAnyFocusField = json["sightingVerdicts"] != nil || json["candidates"] != nil
            || json["profileUpdate"] != nil || json["morningBrief"] != nil || json["queueAdvice"] != nil
        guard hasAnyFocusField else { return nil }

        var verdicts: [FocusAnalysisExtension.SightingVerdict] = []
        for dict in (json["sightingVerdicts"] as? [[String: Any]]) ?? [] {
            guard let evidenceId = (dict["evidenceId"] as? NSNumber)?.int64Value,
                  let correct = dict["correct"] as? Bool else { continue }
            verdicts.append(.init(evidenceId: evidenceId, correct: correct, note: dict["note"] as? String ?? ""))
        }

        var errorEvidence: [FocusAnalysisExtension.NewErrorEvidence] = []
        for dict in (json["newErrorEvidence"] as? [[String: Any]]) ?? [] {
            guard let itemId = (dict["focusItemId"] as? NSNumber)?.int64Value,
                  let excerpt = dict["excerpt"] as? String, !excerpt.isEmpty else { continue }
            errorEvidence.append(.init(focusItemId: itemId, excerpt: excerpt, app: dict["app"] as? String))
        }

        var candidates: [FocusAnalysisExtension.Candidate] = []
        for dict in (json["candidates"] as? [[String: Any]]) ?? [] {
            guard let kindRaw = dict["kind"] as? String,
                  let kind = FocusItemKind(rawValue: kindRaw),
                  let phrase = dict["targetPhrase"] as? String, !phrase.isEmpty else { continue }
            let excerpts = (dict["excerpts"] as? [String]) ?? []
            // No evidence, no slot: candidates without receipts are dropped here
            guard !excerpts.filter({ !$0.isEmpty }).isEmpty else { continue }
            candidates.append(.init(
                kind: kind,
                targetPhrase: phrase,
                matchForms: (dict["matchForms"] as? [String]) ?? [],
                rationale: dict["rationale"] as? String ?? "",
                excerpts: excerpts
            ))
        }

        var advice: FocusAnalysisExtension.QueueAdvice?
        if let adviceDict = json["queueAdvice"] as? [String: Any] {
            advice = .init(
                promote: (adviceDict["promote"] as? [String]) ?? [],
                retire: (adviceDict["retire"] as? [String]) ?? [],
                candidatePriorities: (adviceDict["candidatePriorities"] as? [String]) ?? [],
                reasoning: adviceDict["reasoning"] as? String ?? ""
            )
        }

        var profileJSON: String?
        if let profileDict = json["profileUpdate"] as? [String: Any],
           let profileData = try? JSONSerialization.data(withJSONObject: profileDict),
           let profileString = String(data: profileData, encoding: .utf8) {
            profileJSON = profileString
        }

        var brief: FocusAnalysisExtension.BriefPayload?
        if let briefDict = json["morningBrief"] as? [String: Any],
           let phrase = briefDict["focusTargetPhrase"] as? String,
           let headline = briefDict["headline"] as? String {
            brief = .init(
                focusTargetPhrase: phrase,
                headline: headline,
                mission: briefDict["mission"] as? String ?? "",
                wins: (briefDict["wins"] as? [String]) ?? []
            )
        }

        return FocusAnalysisExtension(
            sightingVerdicts: verdicts,
            newErrorEvidence: errorEvidence,
            candidates: candidates,
            queueAdvice: advice,
            profileUpdateJSON: profileJSON,
            morningBrief: brief
        )
    }

    // MARK: - Selected Text Review (prompt + parsing)

    private func buildSelectedTextReviewPrompt(originalText: String, appName: String, redactionCount: Int) -> String {
        let redactionNote = redactionCount > 0
            ? "Keep placeholders like [EMAIL_1] exactly as written."
            : ""

        return """
        Fast English correction for selected text from \(appName).
        Fix grammar, spelling, clarity, and naturalness. Preserve meaning. \(redactionNote)

        Text:
        \(originalText)

        Return ONLY compact valid JSON:
        {
          "originalText": "repeat the selected text exactly",
          "improvedText": "best corrected version",
          "detectedTone": "1-3 word tone",
          "overallAssessment": "max 10 words",
          "corrections": [
            {
              "original": "exact original word/phrase",
              "replacement": "corrected word/phrase",
              "category": "short category",
              "explanation": "max 12 words",
              "memoryCue": "max 10 words"
            }
          ],
          "proposals": [],
          "reminders": ["max 8 words"],
          "confidence": 0.8
        }

        Rules:
        - Max 4 corrections.
        - Keep explanations short for tooltips.
        - If good already, corrections=[] and improvedText almost identical.
        - Do not invent facts or add new commitments.
        """
    }

    private func parseSelectedTextReviewResponse(_ response: String, originalText: String, redaction: RedactionResult) -> SelectedTextReview {
        let jsonString = cleanedJSONString(response)

        guard let data = jsonString.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(SelectedTextReview.self, from: data) else {
            return SelectedTextReview(
                originalText: originalText,
                improvedText: originalText,
                detectedTone: "Needs review",
                overallAssessment: "The AI response could not be parsed, so the original text was preserved.",
                corrections: [],
                proposals: [],
                reminders: [],
                confidence: 0,
                redactionCount: redaction.redactionCount
            )
        }

        let restoredImproved = redaction.restorePlaceholders(in: decoded.improvedText)
        let restoredCorrections = decoded.corrections.map { correction in
            SelectedTextCorrection(
                original: redaction.restorePlaceholders(in: correction.original),
                replacement: redaction.restorePlaceholders(in: correction.replacement),
                category: correction.category,
                explanation: correction.explanation,
                memoryCue: correction.memoryCue
            )
        }
        let restoredProposals = decoded.proposals.map { proposal in
            SelectedTextProposal(
                title: proposal.title,
                text: redaction.restorePlaceholders(in: proposal.text),
                why: proposal.why
            )
        }

        return SelectedTextReview(
            originalText: originalText,
            improvedText: restoredImproved,
            detectedTone: decoded.detectedTone,
            overallAssessment: decoded.overallAssessment,
            corrections: restoredCorrections,
            proposals: restoredProposals,
            reminders: decoded.reminders,
            confidence: decoded.confidence,
            redactionCount: redaction.redactionCount
        )
    }

    private func cleanedJSONString(_ response: String) -> String {
        var jsonString = response.trimmingCharacters(in: .whitespacesAndNewlines)

        if jsonString.hasPrefix("```json") {
            jsonString = String(jsonString.dropFirst(7))
        } else if jsonString.hasPrefix("```") {
            jsonString = String(jsonString.dropFirst(3))
        }

        if jsonString.hasSuffix("```") {
            jsonString = String(jsonString.dropLast(3))
        }

        return jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Convenience Methods

extension AIAnalysisService {
    func hasAnalysis(for date: Date) -> Bool {
        return DatabaseService.shared.hasAnalysis(for: date)
    }
}
