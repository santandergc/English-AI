import Foundation
import NaturalLanguage

/// Owns the Focus Item lifecycle. This is the ONLY component that applies
/// queueAdvice and status transitions (single writer, no dual mastery logic).
///
/// Responsibilities:
/// - Local detection: lemma/phrase matching of new records against active
///   enrich-items -> pending sightings (correct_use, verified = 0)
/// - Applying the AI analysis extension in a fixed 6-step order with
///   forward-only date gating against language_profile.based_on_date
/// - The idempotent once-per-day trigger (ensureTodayPrepared) that makes
///   the Morning Brief appear without manual steps
final class FocusQueueService {
    static let shared = FocusQueueService()

    /// Hard cap: the active queue never exceeds 5 items. The cap IS the 20/80.
    static let maxActiveItems = 5

    /// Verified wild uses required to graduate an enrich-item
    static let adoptionThreshold = 3

    private let database = DatabaseService.shared
    private let stateQueue = DispatchQueue(label: "com.englishai.focusqueue")
    private let lastPreparedDayKey = "focus.lastPreparedDay"
    private var isPreparingToday = false

    private init() {}

    // MARK: - Local Detection (called from RecordManager on every saved record)

    /// Matches a freshly inserted record against active enrich-items and files
    /// pending sightings. Status does NOT change here: practicing -> spotted
    /// only fires on AI verification. Fix-items are excluded from local
    /// matching entirely (their evidence comes from the analysis pass).
    func processNewRecord(recordId: Int64, content: String, app: String) {
        stateQueue.async { [weak self] in
            guard let self = self else { return }

            let activeEnrichItems = self.database
                .getFocusItems(statuses: FocusItemStatus.activeStatuses)
                .filter { $0.kind == .enrich }

            guard !activeEnrichItems.isEmpty else { return }

            let normalizedText = Self.normalizeForMatching(content)
            let wordForms = Self.lemmasAndTokens(of: content)

            for item in activeEnrichItems {
                guard let itemId = item.id else { continue }

                let matched = item.matchForms.contains { form in
                    Self.formMatches(form, normalizedText: normalizedText, wordForms: wordForms)
                }
                guard matched else { continue }

                // A record can only ever produce one sighting per item
                if self.database.focusEvidenceExists(itemId: itemId, excerpt: content) {
                    continue
                }

                let sighting = FocusEvidence(
                    focusItemId: itemId,
                    recordId: recordId,
                    excerpt: content,
                    app: app,
                    evidenceType: .correctUse,
                    verified: false
                )
                self.database.insertFocusEvidence(sighting)
                print("[FocusQueue] 🎯 Pending sighting for '\(item.targetPhrase)' in \(app)")
            }
        }
    }

    // MARK: - Matching helpers

    /// Lowercased text with whitespace collapsed, padded so word-boundary
    /// checks work at string edges. Apostrophes preserved ("I'd rather").
    static func normalizeForMatching(_ text: String) -> String {
        let lowered = text.lowercased()
            .replacingOccurrences(of: "\u{2019}", with: "'") // curly -> straight apostrophe
        let collapsed = lowered
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return " " + collapsed + " "
    }

    /// Both surface tokens and their lemmas, lowercased (on-device, free)
    static func lemmasAndTokens(of text: String) -> Set<String> {
        var forms = Set<String>()
        let tagger = NLTagger(tagSchemes: [.lemma])
        tagger.string = text
        let options: NLTagger.Options = [.omitPunctuation, .omitWhitespace]
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lemma, options: options) { tag, range in
            let token = String(text[range]).lowercased()
            if !token.isEmpty { forms.insert(token) }
            if let lemma = tag?.rawValue.lowercased(), !lemma.isEmpty { forms.insert(lemma) }
            return true
        }
        return forms
    }

    static func formMatches(_ form: String, normalizedText: String, wordForms: Set<String>) -> Bool {
        let normalizedForm = form.lowercased()
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedForm.isEmpty else { return false }

        if normalizedForm.contains(" ") {
            // Multi-word expression: word-boundary substring match. Boundary
            // characters cover the padding plus common punctuation.
            guard let range = normalizedText.range(of: normalizedForm) else { return false }
            let before = normalizedText[normalizedText.index(before: range.lowerBound)]
            let boundaries: Set<Character> = [" ", ".", ",", "!", "?", ";", ":", "(", ")", "\""]
            let afterIndex = range.upperBound
            let after = afterIndex < normalizedText.endIndex ? normalizedText[afterIndex] : " "
            return boundaries.contains(before) && boundaries.contains(after)
        } else {
            return wordForms.contains(normalizedForm)
        }
    }

    // MARK: - Daily Trigger

    /// Idempotent, at most once per calendar day. Wired from: app launch,
    /// didBecomeActive, popover open, machine wake, and day-rollover — any
    /// of them lands the Morning Brief for an always-running menu bar app.
    func ensureTodayPrepared() {
        stateQueue.async { [weak self] in
            guard let self = self, !self.isPreparingToday else { return }

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            let todayString = formatter.string(from: Date())

            guard UserDefaults.standard.string(forKey: self.lastPreparedDayKey) != todayString else { return }

            // Without an API key we can't analyze; don't mark the day done so
            // adding a key later the same day still triggers preparation.
            guard AIAnalysisService.shared.hasAPIKey else { return }

            let calendar = Calendar.current
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: Date())) else { return }

            // Nothing to analyze, or already analyzed: the day is prepared.
            let yesterdayRecords = self.database.getRecordCount(for: yesterday)
            let yesterdayRecordings = self.database.getRecordingsForDate(yesterday)
                .filter { $0.transcriptionStatus == .completed && $0.transcription != nil }
            if (yesterdayRecords == 0 && yesterdayRecordings.isEmpty) || self.database.hasAnalysis(for: yesterday) {
                UserDefaults.standard.set(todayString, forKey: self.lastPreparedDayKey)
                return
            }

            self.isPreparingToday = true
            print("[FocusQueue] ☀️ Preparing today: analyzing yesterday in background")

            Task {
                defer {
                    self.stateQueue.async { self.isPreparingToday = false }
                }
                do {
                    _ = try await AIAnalysisService.shared.analyzeRecords(for: yesterday)
                    UserDefaults.standard.set(todayString, forKey: self.lastPreparedDayKey)
                    print("[FocusQueue] ☀️ Morning brief prepared")
                } catch {
                    // Leave the day unmarked so the next trigger retries
                    print("[FocusQueue] ⚠️ Daily preparation failed: \(error)")
                }
            }
        }
    }

    // MARK: - Applying the AI Analysis Extension

    /// Fixed application order (design doc):
    /// 1) upsert candidates (+ excerpts as verified evidence rows)
    /// 2) resolve phrase references to rowids
    /// 3) apply sightingVerdicts + newErrorEvidence
    /// 4) apply queueAdvice + rewrite priorities
    /// 5) write profile version
    /// 6) write brief
    ///
    /// Verdicts and error evidence apply on EVERY run (they are idempotent).
    /// Everything that moves state forward (candidates, advice, priorities,
    /// profile, brief) applies ONLY when analyzedDate >= based_on_date of the
    /// latest profile — re-running an old day never mutates state backwards.
    func applyAnalysisExtension(_ ext: FocusAnalysisExtension, analyzedDate: Date) {
        stateQueue.sync { [weak self] in
            guard let self = self else { return }

            let calendar = Calendar.current
            let analyzedDay = calendar.startOfDay(for: analyzedDate)
            let latestProfile = self.database.getLatestProfileVersion()
            let forwardGateOpen: Bool
            if let profile = latestProfile {
                forwardGateOpen = analyzedDay >= calendar.startOfDay(for: profile.basedOnDate)
            } else {
                forwardGateOpen = true
            }

            // Step 3a (always): sighting verdicts — keyed on evidenceId, no-op when re-applied
            for verdict in ext.sightingVerdicts {
                let applied = self.database.applyEvidenceVerdict(evidenceId: verdict.evidenceId, correct: verdict.correct)
                if applied {
                    print("[FocusQueue] Verdict on evidence \(verdict.evidenceId): \(verdict.correct ? "✓ correct" : "✗ near miss") \(verdict.note)")
                }
            }

            // Step 3b (always): new error evidence for fix-items — dedup on (item, excerpt)
            for error in ext.newErrorEvidence {
                guard !self.database.focusEvidenceExists(itemId: error.focusItemId, excerpt: error.excerpt) else { continue }
                self.database.insertFocusEvidence(FocusEvidence(
                    focusItemId: error.focusItemId,
                    excerpt: error.excerpt,
                    app: error.app,
                    evidenceType: .mistake,
                    verified: true,
                    occurredAt: analyzedDate
                ))
            }

            // Recompute enrich statuses after verdicts (spotted / adopted / revert)
            self.recomputeEnrichStatuses()

            guard forwardGateOpen else {
                print("[FocusQueue] Forward gate closed (analyzed \(analyzedDay) < profile base) — evidence applied, state unchanged")
                return
            }

            // Step 1: upsert candidates, excerpts become verified evidence at nomination time
            for candidate in ext.candidates {
                self.upsertCandidate(candidate)
            }

            // Steps 2+4: queue advice, resolved by normalized phrase
            if let advice = ext.queueAdvice {
                for phrase in advice.retire {
                    if let item = self.database.getFocusItem(byPhrase: phrase), let id = item.id,
                       FocusItemStatus.activeStatuses.contains(item.status) || item.status == .candidate {
                        self.database.updateFocusItemStatus(id: id, status: .retired)
                        print("[FocusQueue] Retired '\(item.targetPhrase)': \(advice.reasoning)")
                    }
                }
                for phrase in advice.promote {
                    self.promoteIfSlotAvailable(phrase: phrase)
                }
                for (rank, phrase) in advice.candidatePriorities.enumerated() {
                    if let item = self.database.getFocusItem(byPhrase: phrase), let id = item.id, item.status == .candidate {
                        self.database.updateFocusItemPriority(id: id, priority: rank)
                    }
                }
            }

            // Slot refill: highest-priority candidates fill any open slots
            self.refillOpenSlots()

            // Step 5: profile version, guarded against telephone-game shrinkage
            if let profileJSON = ext.profileUpdateJSON {
                if self.profilePassesDriftGuard(newContent: profileJSON, previous: latestProfile) {
                    self.database.insertProfileVersion(content: profileJSON, basedOnDate: analyzedDate)
                } else {
                    print("[FocusQueue] ⚠️ Profile drift guard tripped: >30% of entries vanished without retirement — keeping previous version")
                }
            }

            // Step 6: the brief is FOR the morning after the analyzed day
            if let brief = ext.morningBrief,
               let item = self.database.getFocusItem(byPhrase: brief.focusTargetPhrase),
               let itemId = item.id,
               let briefDate = calendar.date(byAdding: .day, value: 1, to: analyzedDay) {
                self.database.upsertMorningBrief(
                    forDate: briefDate,
                    focusItemId: itemId,
                    headline: brief.headline,
                    mission: brief.mission,
                    wins: brief.wins
                )
            }
        }
    }

    // MARK: - Practice signal (queued -> practicing)

    /// Called when an exercise attempt lands for a focus-targeted exercise.
    /// First practice moves a queued item into practicing; the attempt itself
    /// is recorded as a practice evidence row (training signal, never verdict).
    func registerPracticeAttempt(targetPhrase: String, isCorrect: Bool) {
        stateQueue.async { [weak self] in
            guard let self = self,
                  let item = self.database.getFocusItem(byPhrase: targetPhrase),
                  let itemId = item.id else { return }

            self.database.insertFocusEvidence(FocusEvidence(
                focusItemId: itemId,
                excerpt: isCorrect ? "Practice: correct" : "Practice: incorrect",
                evidenceType: .practice,
                verified: true
            ))

            if item.status == .queued {
                self.database.updateFocusItemStatus(id: itemId, status: .practicing)
            }
        }
    }

    // MARK: - Queue state helpers (UI reads these)

    /// Active queue items with computed verified wild-use counts, for the popover
    func activeQueueSnapshot() -> [(item: FocusItem, verifiedUses: Int)] {
        let items = database.getFocusItems(statuses: FocusItemStatus.activeStatuses)
        return items.map { item in
            let uses = item.id.map { database.countVerifiedCorrectUses(forItem: $0) } ?? 0
            return (item: item, verifiedUses: uses)
        }
    }

    // MARK: - Private lifecycle mechanics

    /// spotted at >=1 verified use, adopted at threshold, revert if all uses
    /// were struck down. Fix-items skip `spotted` entirely; their adoption
    /// (error-rate fade vs frozen baseline) needs >=4 weeks of history and is
    /// intentionally not claimed in v1 — the UI shows raw weekly trends.
    private func recomputeEnrichStatuses() {
        let items = database.getFocusItems(statuses: FocusItemStatus.activeStatuses)
        for item in items where item.kind == .enrich {
            guard let itemId = item.id else { continue }
            let uses = database.countVerifiedCorrectUses(forItem: itemId)

            if uses >= Self.adoptionThreshold {
                database.updateFocusItemStatus(id: itemId, status: .adopted)
                print("[FocusQueue] 🏆 ADOPTED: '\(item.targetPhrase)' (\(uses) verified wild uses)")
            } else if uses >= 1 && (item.status == .practicing || item.status == .queued) {
                database.updateFocusItemStatus(id: itemId, status: .spotted)
            } else if uses == 0 && item.status == .spotted {
                database.updateFocusItemStatus(id: itemId, status: .practicing)
            }
        }
    }

    private func activeCount() -> Int {
        database.getFocusItems(statuses: FocusItemStatus.activeStatuses).count
    }

    private func promoteIfSlotAvailable(phrase: String) {
        guard activeCount() < Self.maxActiveItems else { return }
        if let item = database.getFocusItem(byPhrase: phrase), let id = item.id, item.status == .candidate {
            database.updateFocusItemStatus(id: id, status: .queued)
            print("[FocusQueue] ⬆️ Promoted to queue: '\(item.targetPhrase)'")
        }
    }

    private func refillOpenSlots() {
        var open = Self.maxActiveItems - activeCount()
        guard open > 0 else { return }

        let candidates = database.getFocusItems(statuses: [.candidate])  // already priority-ordered
        for candidate in candidates {
            guard open > 0, let id = candidate.id else { break }
            database.updateFocusItemStatus(id: id, status: .queued)
            print("[FocusQueue] ⬆️ Slot refill: '\(candidate.targetPhrase)'")
            open -= 1
        }
    }

    /// Upsert by normalized phrase. Nomination rules:
    /// - phrase already candidate/active: keep it (no duplicate)
    /// - phrase was adopted: this is a relapse re-nomination -> new item
    ///   linked via supersedes_item_id (no status reversals on adopted items)
    /// - phrase was retired or unknown: fresh item
    private func upsertCandidate(_ candidate: FocusAnalysisExtension.Candidate) {
        var supersedes: Int64?
        if let existing = database.getFocusItem(byPhrase: candidate.targetPhrase) {
            switch existing.status {
            case .candidate, .queued, .practicing, .spotted:
                return  // already tracked
            case .adopted:
                supersedes = existing.id
            case .retired:
                supersedes = nil
            }
        }

        let item = FocusItem(
            kind: candidate.kind,
            status: .candidate,
            targetPhrase: candidate.targetPhrase,
            matchForms: candidate.matchForms.isEmpty ? [candidate.targetPhrase] : candidate.matchForms,
            rationale: candidate.rationale,
            priority: Int.max / 2,  // unranked until candidatePriorities lands
            supersedesItemId: supersedes
        )

        guard let newId = database.insertFocusItem(item) else { return }

        // Receipts exist at nomination time: excerpts become verified evidence
        let evidenceType: FocusEvidenceType = candidate.kind == .enrich ? .overuse : .mistake
        for excerpt in candidate.excerpts where !excerpt.isEmpty {
            if !database.focusEvidenceExists(itemId: newId, excerpt: excerpt) {
                database.insertFocusEvidence(FocusEvidence(
                    focusItemId: newId,
                    excerpt: excerpt,
                    evidenceType: evidenceType,
                    verified: true
                ))
            }
        }
        print("[FocusQueue] 🆕 Candidate: '\(candidate.targetPhrase)' (\(candidate.kind.rawValue)) — \(candidate.rationale)")
    }

    /// Keep the previous profile when the rewrite silently drops >30% of
    /// entries without moving them to retired_entries (telephone-game decay).
    private func profilePassesDriftGuard(newContent: String, previous: LanguageProfileVersion?) -> Bool {
        guard let previous = previous else { return true }

        let oldCount = Self.profileEntryCount(previous.content)
        guard oldCount >= 5 else { return true }

        let newCount = Self.profileEntryCount(newContent) + Self.retiredEntryCount(newContent)
        return Double(newCount) >= Double(oldCount) * 0.7
    }

    static func profileEntryCount(_ json: String) -> Int {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return 0 }
        let listKeys = ["crutches", "error_patterns", "strengths", "vocab_notes", "style_notes"]
        return listKeys.reduce(0) { total, key in
            total + ((dict[key] as? [Any])?.count ?? 0)
        }
    }

    static func retiredEntryCount(_ json: String) -> Int {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return 0 }
        return (dict["retired_entries"] as? [Any])?.count ?? 0
    }
}
