import SwiftUI

// MARK: - Practice View

/// Main view for the Practice tab showing exercises and progress tracking
struct PracticeView: View {
    @StateObject private var viewModel = PracticeViewModel()
    @State private var showProgressSection = true
    @State private var showDailySection = true

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerSection

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Daily Practice Section
                    dailyPracticeSection

                    // Progress Section (collapsible)
                    progressSection
                }
                .padding()
            }
        }
        .onAppear {
            viewModel.loadData()
            // Check and generate daily exercises on app launch
            viewModel.checkAndGenerateDailyExercises()
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        HStack {
            Text("Practice")
                .font(.title2)
                .fontWeight(.semibold)

            Spacer()

            Button(action: {
                viewModel.loadData()
            }) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh")
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Progress Section

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header with collapse toggle
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showProgressSection.toggle()
                }
            }) {
                HStack {
                    Image(systemName: "chart.bar.fill")
                        .foregroundColor(.purple)
                    Text("Progress")
                        .font(.headline)
                        .foregroundColor(.primary)

                    Spacer()

                    Image(systemName: showProgressSection ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)

            if showProgressSection {
                VStack(alignment: .leading, spacing: 16) {
                    // Overall stats row
                    overallStatsRow

                    Divider()

                    // Weakness categories section
                    weaknessCategoriesSection
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }

    // MARK: - Overall Stats Row

    private var overallStatsRow: some View {
        HStack(spacing: 20) {
            // Total completed
            StatCard(
                title: "Completed",
                value: "\(viewModel.stats.totalCompleted)",
                icon: "checkmark.circle.fill",
                color: .green
            )

            // Accuracy percentage
            StatCard(
                title: "Accuracy",
                value: String(format: "%.0f%%", viewModel.stats.accuracyPercentage),
                icon: "target",
                color: .blue
            )

            // Current streak
            StatCard(
                title: "Streak",
                value: "\(viewModel.stats.currentStreak) days",
                icon: "flame.fill",
                color: .orange
            )
        }
    }

    // MARK: - Weakness Categories Section

    private var weaknessCategoriesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Weakness Categories")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            if viewModel.weaknessProgress.isEmpty {
                Text("No practice data yet. Complete some exercises to see your progress.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(viewModel.weaknessProgress, id: \.weaknessCategory) { progress in
                    WeaknessCategoryRow(progress: progress)
                }
            }
        }
    }

    // MARK: - Daily Practice Section

    private var dailyPracticeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header with collapse toggle
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showDailySection.toggle()
                }
            }) {
                HStack {
                    Image(systemName: "calendar.badge.clock")
                        .foregroundColor(.blue)
                    Text("Daily Practice")
                        .font(.headline)
                        .foregroundColor(.primary)

                    Spacer()

                    // Progress indicator
                    if !viewModel.dailyExercises.isEmpty {
                        Text("\(viewModel.completedDailyCount)/\(viewModel.dailyExercises.count)")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(4)
                    }

                    Image(systemName: showDailySection ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)

            if showDailySection {
                if viewModel.isGeneratingExercises {
                    // Generation in progress
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Generating your daily exercises...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text("This may take a moment")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
                } else if viewModel.dailyExercises.isEmpty {
                    // No exercises yet
                    VStack(spacing: 12) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        Text("No daily exercises yet")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        if viewModel.generationError != nil {
                            Text(viewModel.generationError!)
                                .font(.caption)
                                .foregroundColor(.red)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)

                            Button("Try Again") {
                                viewModel.generateDailyExercises()
                            }
                            .buttonStyle(.borderedProminent)
                            .padding(.top, 4)
                        } else {
                            Text("Complete some AI analysis first, or exercises will be generated automatically.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)

                            Button("Generate Now") {
                                viewModel.generateDailyExercises()
                            }
                            .buttonStyle(.borderedProminent)
                            .padding(.top, 4)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
                } else {
                    // Show exercises list
                    dailyExercisesList
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }

    // MARK: - Daily Exercises List

    private var dailyExercisesList: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(viewModel.dailyExercises, id: \.id) { exercise in
                DailyExerciseRow(
                    exercise: exercise,
                    isCompleted: viewModel.isExerciseCompleted(exercise.id)
                )
            }
        }
    }
}

// MARK: - Daily Exercise Row

private struct DailyExerciseRow: View {
    let exercise: Exercise
    let isCompleted: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Completion status
            Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isCompleted ? .green : .secondary)
                .font(.title3)

            // Type icon
            Image(systemName: exerciseTypeIcon)
                .foregroundColor(.blue)
                .frame(width: 24)

            // Content
            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.instruction)
                    .font(.subheadline)
                    .lineLimit(1)
                    .foregroundColor(isCompleted ? .secondary : .primary)

                HStack(spacing: 8) {
                    // Weakness category
                    Text(exercise.targetWeakness)
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    // Difficulty stars
                    HStack(spacing: 2) {
                        ForEach(0..<5, id: \.self) { index in
                            Image(systemName: index < exercise.difficulty ? "star.fill" : "star")
                                .font(.system(size: 8))
                                .foregroundColor(index < exercise.difficulty ? .yellow : .gray.opacity(0.3))
                        }
                    }
                }
            }

            Spacer()
        }
        .padding(10)
        .background(isCompleted ? Color.green.opacity(0.05) : Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }

    private var exerciseTypeIcon: String {
        switch exercise.type {
        case .singleChoice: return "checkmark.circle"
        case .multipleChoice: return "checklist"
        case .fillInBlank: return "text.cursor"
        case .freeResponse: return "text.alignleft"
        case .errorCorrection: return "exclamationmark.triangle"
        case .sentenceReorder: return "arrow.left.arrow.right"
        case .matching: return "link"
        case .wordFormation: return "textformat.abc"
        }
    }
}

// MARK: - Stat Card

private struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

// MARK: - Weakness Category Row

private struct WeaknessCategoryRow: View {
    let progress: WeaknessProgress

    private var isDueForReview: Bool {
        guard let nextReviewDate = progress.nextReviewDate else { return false }
        return nextReviewDate <= Date()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(progress.weaknessCategory)
                    .font(.subheadline)
                    .fontWeight(.medium)

                if isDueForReview {
                    Text("Due for review")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange)
                        .cornerRadius(4)
                }

                Spacer()

                Text("\(progress.masteryLevel)%")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(masteryColor)
            }

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background track
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 8)

                    // Progress fill
                    RoundedRectangle(cornerRadius: 4)
                        .fill(masteryColor)
                        .frame(width: geometry.size.width * CGFloat(progress.masteryLevel) / 100, height: 8)
                }
            }
            .frame(height: 8)

            // Details row
            HStack {
                Text("\(progress.totalAttempts) attempts")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Text("•")
                    .foregroundColor(.secondary)

                Text(String(format: "%.0f%% accuracy", progress.accuracyPercentage))
                    .font(.caption2)
                    .foregroundColor(.secondary)

                if let lastPracticed = progress.lastPracticed {
                    Text("•")
                        .foregroundColor(.secondary)
                    Text("Last: \(formatRelativeDate(lastPracticed))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }

    private var masteryColor: Color {
        switch progress.masteryLevel {
        case 80...100: return .green
        case 60..<80: return .blue
        case 40..<60: return .yellow
        case 20..<40: return .orange
        default: return .red
        }
    }

    private func formatRelativeDate(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "today"
        } else if calendar.isDateInYesterday(date) {
            return "yesterday"
        } else {
            let days = calendar.dateComponents([.day], from: date, to: Date()).day ?? 0
            return "\(days)d ago"
        }
    }
}

// MARK: - Practice View Model

class PracticeViewModel: ObservableObject {
    @Published var stats = PracticeStats()
    @Published var weaknessProgress: [WeaknessProgress] = []
    @Published var dailyExercises: [Exercise] = []
    @Published var completedExerciseIds: Set<Int64> = []
    @Published var isGeneratingExercises = false
    @Published var generationError: String?

    private let database = DatabaseService.shared
    private let exerciseService = ExerciseGenerationService.shared
    private var hasCheckedDailyExercises = false

    struct PracticeStats {
        var totalCompleted: Int = 0
        var accuracyPercentage: Double = 0
        var currentStreak: Int = 0
    }

    var completedDailyCount: Int {
        dailyExercises.filter { exercise in
            guard let id = exercise.id else { return false }
            return completedExerciseIds.contains(id)
        }.count
    }

    func loadData() {
        // Load weakness progress (sorted by mastery level, lowest first)
        weaknessProgress = database.getAllWeaknessProgress()

        // Load daily exercises for today
        loadDailyExercises()

        // Calculate overall stats
        calculateStats()
    }

    private func loadDailyExercises() {
        dailyExercises = database.getExercisesForDate(Date())

        // Check which exercises are completed
        completedExerciseIds = []
        for exercise in dailyExercises {
            if let id = exercise.id, database.isExerciseCompleted(id) {
                completedExerciseIds.insert(id)
            }
        }
    }

    func isExerciseCompleted(_ id: Int64?) -> Bool {
        guard let id = id else { return false }
        return completedExerciseIds.contains(id)
    }

    private func calculateStats() {
        // Get exercise statistics from database
        let exerciseStats = database.getExerciseStatistics()

        stats.totalCompleted = exerciseStats.totalAttempts
        stats.accuracyPercentage = exerciseStats.accuracyPercentage
        stats.currentStreak = exerciseStats.currentStreak
    }

    // MARK: - Daily Exercise Generation

    /// Check if daily exercises exist for today, generate if not
    func checkAndGenerateDailyExercises() {
        // Only check once per session
        guard !hasCheckedDailyExercises else { return }
        hasCheckedDailyExercises = true

        // Check if daily exercises already exist for today
        if database.hasDailyExercisesForToday() {
            print("[PracticeViewModel] Daily exercises already exist for today")
            return
        }

        // No daily exercises yet - generate them
        generateDailyExercises()
    }

    /// Generate daily exercises using AI
    func generateDailyExercises() {
        guard !isGeneratingExercises else { return }

        isGeneratingExercises = true
        generationError = nil

        Task {
            do {
                // Get weaknesses from recent analysis and existing progress
                var weaknesses = database.getWeaknessesFromRecentInsights(days: 7)

                // Prioritize weaknesses due for review (spaced repetition)
                let dueForReview = database.getWeaknessesDueForReview()
                for progress in dueForReview {
                    // Add to front of list if not already present
                    if !weaknesses.contains(progress.weaknessCategory) {
                        weaknesses.insert(progress.weaknessCategory, at: 0)
                    } else {
                        // Move to front
                        weaknesses.removeAll { $0 == progress.weaknessCategory }
                        weaknesses.insert(progress.weaknessCategory, at: 0)
                    }
                }

                // If no weaknesses found, use general defaults
                if weaknesses.isEmpty {
                    weaknesses = [
                        "Grammar: General",
                        "Vocabulary: Word choice",
                        "Phrasing: Natural expressions"
                    ]
                }

                // Limit to top 5 weaknesses for focused practice
                let targetWeaknesses = Array(weaknesses.prefix(5))

                print("[PracticeViewModel] Generating daily exercises for weaknesses: \(targetWeaknesses)")

                // Generate 5-10 exercises with random difficulty
                let exerciseCount = Int.random(in: 5...10)
                let exercises = try await exerciseService.generateExercises(
                    weaknesses: targetWeaknesses,
                    count: exerciseCount,
                    types: nil,  // All types
                    difficulty: nil  // Random difficulty
                )

                // Get today's date string for dailySetDate
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd"
                let todayStr = dateFormatter.string(from: Date())

                // Save exercises to database with today's date
                var savedCount = 0
                for exercise in exercises {
                    let exerciseWithDate = Exercise(
                        type: exercise.type,
                        instruction: exercise.instruction,
                        content: exercise.content,
                        difficulty: exercise.difficulty,
                        targetWeakness: exercise.targetWeakness,
                        createdAt: Date(),
                        sourceAnalysisId: nil,
                        dailySetDate: todayStr
                    )

                    if database.createExercise(exerciseWithDate) != nil {
                        savedCount += 1
                    }
                }

                print("[PracticeViewModel] Saved \(savedCount) daily exercises")

                // Update UI on main thread
                await MainActor.run {
                    self.isGeneratingExercises = false
                    self.loadDailyExercises()
                }

            } catch AIAnalysisError.noAPIKey {
                await MainActor.run {
                    self.isGeneratingExercises = false
                    self.generationError = "No API key configured. Please add an Anthropic or OpenAI API key in Settings."
                }
            } catch AIAnalysisError.rateLimited {
                await MainActor.run {
                    self.isGeneratingExercises = false
                    self.generationError = "API rate limited. Please try again in a moment."
                }
            } catch {
                print("[PracticeViewModel] Error generating exercises: \(error)")
                await MainActor.run {
                    self.isGeneratingExercises = false
                    self.generationError = "Failed to generate exercises: \(error.localizedDescription)"
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    PracticeView()
}
