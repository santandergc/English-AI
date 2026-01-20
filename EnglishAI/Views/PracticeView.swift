import SwiftUI

// MARK: - Practice View

/// Main view for the Practice tab showing exercises and progress tracking
struct PracticeView: View {
    @StateObject private var viewModel = PracticeViewModel()
    @State private var showProgressSection = true

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerSection

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Progress Section (collapsible)
                    progressSection

                    // Exercises would go here (from US-014, US-015, US-029, US-030)
                    // Placeholder for now
                    exercisesPlaceholder
                }
                .padding()
            }
        }
        .onAppear {
            viewModel.loadData()
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

    // MARK: - Exercises Placeholder

    private var exercisesPlaceholder: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "book.fill")
                    .foregroundColor(.blue)
                Text("Exercises")
                    .font(.headline)
            }

            VStack {
                Image(systemName: "doc.text")
                    .font(.system(size: 40))
                    .foregroundColor(.secondary)
                Text("No exercises available")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
                Text("Generate exercises from the AI Analysis to start practicing")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
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

    private let database = DatabaseService.shared

    struct PracticeStats {
        var totalCompleted: Int = 0
        var accuracyPercentage: Double = 0
        var currentStreak: Int = 0
    }

    func loadData() {
        // Load weakness progress (sorted by mastery level, lowest first)
        weaknessProgress = database.getAllWeaknessProgress()

        // Calculate overall stats
        calculateStats()
    }

    private func calculateStats() {
        // Get exercise statistics from database
        let exerciseStats = database.getExerciseStatistics()

        stats.totalCompleted = exerciseStats.totalAttempts
        stats.accuracyPercentage = exerciseStats.accuracyPercentage
        stats.currentStreak = exerciseStats.currentStreak
    }
}

// MARK: - Preview

#Preview {
    PracticeView()
}
