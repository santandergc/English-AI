import SwiftUI

// MARK: - Exercise Session View

/// A view that manages a practice session, showing exercises one at a time
/// with progress tracking and a summary at the end.
struct ExerciseSessionView: View {
    let exercises: [Exercise]
    let onDismiss: () -> Void

    @StateObject private var sessionState = ExerciseSessionState()
    @State private var showExitConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            if sessionState.isComplete {
                // Session complete - show summary
                SessionSummaryView(
                    results: sessionState.results,
                    totalTime: sessionState.totalTimeSpent,
                    onContinue: { onDismiss() },
                    onMorePractice: { restartSession() }
                )
            } else if let currentExercise = currentExercise {
                // Session in progress
                VStack(spacing: 0) {
                    // Header with progress
                    sessionHeader

                    Divider()

                    // Current exercise
                    ExerciseContainerView(
                        exercise: currentExercise,
                        onComplete: { attemptData in
                            handleExerciseComplete(attemptData: attemptData)
                        }
                    )
                }
            } else {
                // Fallback for empty exercises
                emptyStateView
            }
        }
        .alert("Exit Practice Session?", isPresented: $showExitConfirmation) {
            Button("Continue Practicing", role: .cancel) { }
            Button("Exit", role: .destructive) {
                onDismiss()
            }
        } message: {
            Text("Your progress will be saved, but you'll need to start a new session to continue.")
        }
        .onAppear {
            sessionState.startSession(with: exercises)
        }
    }

    // MARK: - Computed Properties

    private var currentExercise: Exercise? {
        guard sessionState.currentIndex < exercises.count else { return nil }
        return exercises[sessionState.currentIndex]
    }

    // MARK: - View Components

    private var sessionHeader: some View {
        VStack(spacing: 12) {
            HStack {
                // Exit button
                Button(action: {
                    showExitConfirmation = true
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark")
                        Text("Exit")
                    }
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)

                Spacer()

                // Progress indicator
                Text("\(sessionState.currentIndex + 1) of \(exercises.count)")
                    .font(.headline)
                    .foregroundColor(.primary)

                Spacer()

                // Timer display
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                    Text(formatTime(sessionState.elapsedTime))
                }
                .font(.subheadline)
                .foregroundColor(.secondary)
            }

            // Progress bar
            ProgressBar(
                current: sessionState.currentIndex + 1,
                total: exercises.count,
                correctCount: sessionState.correctCount
            )
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "tray")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("No exercises in this session")
                .font(.title2)
                .foregroundColor(.secondary)

            Button("Go Back") {
                onDismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func handleExerciseComplete(attemptData: ExerciseAttemptData) {
        // Save attempt to database
        attemptData.saveToDatabase()

        // Record result in session state
        sessionState.recordResult(
            exerciseId: attemptData.exerciseId,
            isCorrect: attemptData.isCorrect,
            timeSpent: attemptData.timeSpentSeconds
        )

        // Move to next exercise or complete session
        if sessionState.currentIndex < exercises.count - 1 {
            withAnimation(.easeInOut(duration: 0.3)) {
                sessionState.nextExercise()
            }
        } else {
            withAnimation(.easeInOut(duration: 0.3)) {
                sessionState.completeSession()
            }
        }
    }

    private func restartSession() {
        sessionState.reset()
        sessionState.startSession(with: exercises)
    }

    // MARK: - Helpers

    private func formatTime(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}

// MARK: - Exercise Session State

/// Observable state for tracking session progress
class ExerciseSessionState: ObservableObject {
    @Published var currentIndex: Int = 0
    @Published var results: [ExerciseResult] = []
    @Published var isComplete: Bool = false
    @Published var elapsedTime: Int = 0

    private var timer: Timer?
    private var sessionStartTime: Date?

    struct ExerciseResult {
        let exerciseId: Int64?
        let isCorrect: Bool
        let timeSpent: Int
    }

    var correctCount: Int {
        results.filter { $0.isCorrect }.count
    }

    var totalTimeSpent: Int {
        results.reduce(0) { $0 + $1.timeSpent }
    }

    var accuracyPercentage: Double {
        guard !results.isEmpty else { return 0 }
        return Double(correctCount) / Double(results.count) * 100
    }

    func startSession(with exercises: [Exercise]) {
        currentIndex = 0
        results = []
        isComplete = false
        sessionStartTime = Date()

        // Start elapsed time timer
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, let startTime = self.sessionStartTime else { return }
            DispatchQueue.main.async {
                self.elapsedTime = Int(Date().timeIntervalSince(startTime))
            }
        }
    }

    func recordResult(exerciseId: Int64?, isCorrect: Bool, timeSpent: Int) {
        results.append(ExerciseResult(
            exerciseId: exerciseId,
            isCorrect: isCorrect,
            timeSpent: timeSpent
        ))
    }

    func nextExercise() {
        currentIndex += 1
    }

    func completeSession() {
        timer?.invalidate()
        timer = nil
        isComplete = true
    }

    func reset() {
        timer?.invalidate()
        timer = nil
        currentIndex = 0
        results = []
        isComplete = false
        elapsedTime = 0
        sessionStartTime = nil
    }

    deinit {
        timer?.invalidate()
    }
}

// MARK: - Progress Bar

/// A visual progress bar showing session progress with correct/incorrect indicators
private struct ProgressBar: View {
    let current: Int
    let total: Int
    let correctCount: Int

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background track
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 8)

                // Progress fill
                RoundedRectangle(cornerRadius: 4)
                    .fill(progressGradient)
                    .frame(width: geometry.size.width * progressFraction, height: 8)
            }
        }
        .frame(height: 8)
    }

    private var progressFraction: CGFloat {
        guard total > 0 else { return 0 }
        return CGFloat(current - 1) / CGFloat(total)  // -1 because current is 1-indexed
    }

    private var progressGradient: LinearGradient {
        LinearGradient(
            gradient: Gradient(colors: [.blue, .blue.opacity(0.7)]),
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

// MARK: - Session Summary View

/// View displayed when a practice session is complete
struct SessionSummaryView: View {
    let results: [ExerciseSessionState.ExerciseResult]
    let totalTime: Int
    let onContinue: () -> Void
    let onMorePractice: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                // Celebration header
                celebrationHeader

                // Stats cards
                statsSection

                // Results breakdown
                resultsBreakdown

                // Action buttons
                actionButtons
            }
            .padding(32)
        }
    }

    // MARK: - Computed Properties

    private var correctCount: Int {
        results.filter { $0.isCorrect }.count
    }

    private var accuracy: Double {
        guard !results.isEmpty else { return 0 }
        return Double(correctCount) / Double(results.count) * 100
    }

    private var performanceMessage: String {
        switch accuracy {
        case 90...100:
            return "Outstanding work!"
        case 75..<90:
            return "Great job!"
        case 50..<75:
            return "Good effort!"
        default:
            return "Keep practicing!"
        }
    }

    private var celebrationIcon: String {
        switch accuracy {
        case 90...100:
            return "star.circle.fill"
        case 75..<90:
            return "hand.thumbsup.circle.fill"
        case 50..<75:
            return "checkmark.circle.fill"
        default:
            return "arrow.up.circle.fill"
        }
    }

    private var celebrationColor: Color {
        switch accuracy {
        case 90...100:
            return .yellow
        case 75..<90:
            return .green
        case 50..<75:
            return .blue
        default:
            return .orange
        }
    }

    // MARK: - View Components

    private var celebrationHeader: some View {
        VStack(spacing: 16) {
            Image(systemName: celebrationIcon)
                .font(.system(size: 80))
                .foregroundColor(celebrationColor)

            Text("Session Complete!")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text(performanceMessage)
                .font(.title2)
                .foregroundColor(.secondary)
        }
    }

    private var statsSection: some View {
        HStack(spacing: 20) {
            // Completed count
            SummaryStatCard(
                icon: "checkmark.circle.fill",
                value: "\(results.count)",
                label: "Completed",
                color: .blue
            )

            // Accuracy
            SummaryStatCard(
                icon: "target",
                value: String(format: "%.0f%%", accuracy),
                label: "Accuracy",
                color: accuracy >= 70 ? .green : .orange
            )

            // Time spent
            SummaryStatCard(
                icon: "clock.fill",
                value: formatTime(totalTime),
                label: "Time",
                color: .purple
            )
        }
    }

    private var resultsBreakdown: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Results Breakdown")
                .font(.headline)
                .foregroundColor(.secondary)

            VStack(spacing: 8) {
                // Correct row
                HStack {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 12, height: 12)
                    Text("Correct")
                        .font(.subheadline)
                    Spacer()
                    Text("\(correctCount)")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.green)
                }

                // Incorrect row
                HStack {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 12, height: 12)
                    Text("Incorrect")
                        .font(.subheadline)
                    Spacer()
                    Text("\(results.count - correctCount)")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.red)
                }

                Divider()

                // Average time per exercise
                HStack {
                    Image(systemName: "timer")
                        .foregroundColor(.secondary)
                        .frame(width: 12)
                    Text("Avg. time per exercise")
                        .font(.subheadline)
                    Spacer()
                    Text(formatTime(results.isEmpty ? 0 : totalTime / results.count))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
        }
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button(action: onContinue) {
                HStack {
                    Image(systemName: "checkmark")
                    Text("Finish")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button(action: onMorePractice) {
                HStack {
                    Image(systemName: "arrow.counterclockwise")
                    Text("Practice More")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    // MARK: - Helpers

    private func formatTime(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let secs = seconds % 60
        if minutes > 0 {
            return String(format: "%dm %ds", minutes, secs)
        } else {
            return String(format: "%ds", secs)
        }
    }
}

// MARK: - Summary Stat Card

private struct SummaryStatCard: View {
    let icon: String
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title)
                .foregroundColor(color)

            Text(value)
                .font(.title)
                .fontWeight(.bold)

            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
}

// MARK: - Preview

#Preview("Session View") {
    ExerciseSessionView(
        exercises: [
            Exercise(
                type: .singleChoice,
                instruction: "Choose the correct word",
                content: .singleChoice(SingleChoiceContent(
                    question: "Which word is spelled correctly?",
                    options: ["Recieve", "Receive", "Recieve", "Recive"],
                    correctIndex: 1
                )),
                difficulty: 2,
                targetWeakness: "Spelling"
            ),
            Exercise(
                type: .fillInBlank,
                instruction: "Complete the sentence",
                content: .fillInBlank(FillInBlankContent(
                    textWithBlanks: "She ___ to the store yesterday.",
                    blanks: [BlankItem(position: 0, correctAnswer: "went", acceptableAlternatives: [])]
                )),
                difficulty: 3,
                targetWeakness: "Grammar: Past tense"
            )
        ],
        onDismiss: { print("Dismissed") }
    )
    .frame(width: 600, height: 700)
}

#Preview("Summary View") {
    SessionSummaryView(
        results: [
            ExerciseSessionState.ExerciseResult(exerciseId: 1, isCorrect: true, timeSpent: 15),
            ExerciseSessionState.ExerciseResult(exerciseId: 2, isCorrect: true, timeSpent: 20),
            ExerciseSessionState.ExerciseResult(exerciseId: 3, isCorrect: false, timeSpent: 30),
            ExerciseSessionState.ExerciseResult(exerciseId: 4, isCorrect: true, timeSpent: 25),
            ExerciseSessionState.ExerciseResult(exerciseId: 5, isCorrect: true, timeSpent: 18)
        ],
        totalTime: 108,
        onContinue: { print("Continue") },
        onMorePractice: { print("More practice") }
    )
    .frame(width: 600, height: 700)
}
