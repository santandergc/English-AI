import Foundation

/// Tracks a user's progress on a specific weakness category for spaced repetition
struct WeaknessProgress: Identifiable, Codable {
    let id: Int64?
    let weaknessCategory: String
    var totalAttempts: Int
    var correctAttempts: Int
    var lastPracticed: Date?
    var nextReviewDate: Date?
    var masteryLevel: Int  // 0-100

    /// Computed accuracy percentage (0-100)
    var accuracyPercentage: Double {
        guard totalAttempts > 0 else { return 0 }
        return Double(correctAttempts) / Double(totalAttempts) * 100
    }

    init(
        id: Int64? = nil,
        weaknessCategory: String,
        totalAttempts: Int = 0,
        correctAttempts: Int = 0,
        lastPracticed: Date? = nil,
        nextReviewDate: Date? = nil,
        masteryLevel: Int = 0
    ) {
        self.id = id
        self.weaknessCategory = weaknessCategory
        self.totalAttempts = totalAttempts
        self.correctAttempts = correctAttempts
        self.lastPracticed = lastPracticed
        self.nextReviewDate = nextReviewDate
        self.masteryLevel = max(0, min(100, masteryLevel))
    }
}

// MARK: - Spaced Repetition Intervals

extension WeaknessProgress {
    /// Review intervals in days based on consecutive correct answers
    /// Follows a modified SM-2 pattern: 1 -> 3 -> 7 -> 14 -> 30 days
    static let reviewIntervals: [Int] = [1, 3, 7, 14, 30]

    /// Calculates the next review date based on whether the answer was correct
    /// - Parameters:
    ///   - isCorrect: Whether the user answered correctly
    ///   - currentInterval: The current interval index (0-4)
    /// - Returns: A tuple of (next review date, new interval index)
    static func calculateNextReview(isCorrect: Bool, currentInterval: Int) -> (Date, Int) {
        let calendar = Calendar.current
        let newInterval: Int
        let days: Int

        if isCorrect {
            // Move to next interval (max out at last interval)
            newInterval = min(currentInterval + 1, reviewIntervals.count - 1)
            days = reviewIntervals[newInterval]
        } else {
            // Reset to first interval on incorrect
            newInterval = 0
            days = reviewIntervals[0]
        }

        let nextDate = calendar.date(byAdding: .day, value: days, to: Date()) ?? Date()
        return (nextDate, newInterval)
    }
}
