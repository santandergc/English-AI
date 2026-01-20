import SwiftUI

// MARK: - Matching Exercise View

struct MatchingExerciseView: View {
    let content: MatchingContent
    let onComplete: (Bool, String, Int, [Int: Int]) -> Void  // isCorrect, feedback, timeSpentSeconds, userMatches

    @State private var selectedLeftIndex: Int? = nil
    @State private var userMatches: [Int: Int] = [:]  // leftIndex -> rightIndex
    @State private var isSubmitted: Bool = false
    @State private var startTime: Date = Date()

    // Color palette for matched pairs
    private let matchColors: [Color] = [
        .blue, .purple, .orange, .pink, .cyan, .indigo, .mint, .teal
    ]

    // Build reverse lookup for right items
    private var rightToLeftMatches: [Int: Int] {
        var result: [Int: Int] = [:]
        for (left, right) in userMatches {
            result[right] = left
        }
        return result
    }

    // Build correct pairs lookup for validation
    private var correctPairsMap: [Int: Int] {
        var result: [Int: Int] = [:]
        for pair in content.correctPairs {
            result[pair.leftIndex] = pair.rightIndex
        }
        return result
    }

    private var allItemsMatched: Bool {
        userMatches.count == content.leftItems.count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Instruction section
                instructionSection

                // Matching columns
                matchingColumnsSection

                // Action buttons
                actionButtonsSection

                // Results section (shown after submission)
                if isSubmitted {
                    resultsSection
                }
            }
            .padding()
        }
        .onAppear {
            startTime = Date()
        }
    }

    // MARK: - View Components

    private var instructionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Match the items")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            Text("Tap an item on the left, then tap the matching item on the right. Tap a matched pair to remove it.")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    private var matchingColumnsSection: some View {
        HStack(alignment: .top, spacing: 40) {
            // Left column
            VStack(spacing: 12) {
                Text("Items")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)

                ForEach(0..<content.leftItems.count, id: \.self) { index in
                    leftItemButton(item: content.leftItems[index], index: index)
                }
            }
            .frame(maxWidth: .infinity)

            // Right column
            VStack(spacing: 12) {
                Text("Matches")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)

                ForEach(0..<content.rightItems.count, id: \.self) { index in
                    rightItemButton(item: content.rightItems[index], index: index)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
        )
    }

    private func leftItemButton(item: String, index: Int) -> some View {
        let isSelected = selectedLeftIndex == index
        let isMatched = userMatches[index] != nil
        let matchColorIndex = isMatched ? index % matchColors.count : 0

        // Determine result state after submission
        let resultState: MatchResultState = {
            if !isSubmitted { return .none }
            guard let userRightIndex = userMatches[index] else { return .missed }
            let correctRightIndex = correctPairsMap[index]
            return userRightIndex == correctRightIndex ? .correct : .incorrect
        }()

        let backgroundColor: Color = {
            if isSubmitted {
                switch resultState {
                case .correct: return Color.green.opacity(0.2)
                case .incorrect: return Color.red.opacity(0.2)
                case .missed: return Color.orange.opacity(0.2)
                case .none: return Color.clear
                }
            } else if isMatched {
                return matchColors[matchColorIndex].opacity(0.2)
            } else if isSelected {
                return Color.blue.opacity(0.2)
            }
            return Color(NSColor.textBackgroundColor)
        }()

        let borderColor: Color = {
            if isSubmitted {
                switch resultState {
                case .correct: return Color.green
                case .incorrect: return Color.red
                case .missed: return Color.orange
                case .none: return Color.secondary.opacity(0.3)
                }
            } else if isMatched {
                return matchColors[matchColorIndex]
            } else if isSelected {
                return Color.blue
            }
            return Color.secondary.opacity(0.3)
        }()

        return Button(action: {
            guard !isSubmitted else { return }
            handleLeftTap(index: index)
        }) {
            HStack {
                // Match indicator badge
                if isMatched {
                    Circle()
                        .fill(isSubmitted ? (resultState == .correct ? Color.green : Color.red) : matchColors[matchColorIndex])
                        .frame(width: 12, height: 12)
                }

                Text(item)
                    .font(.body)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)

                Spacer()

                // Selection indicator
                if isSelected && !isMatched {
                    Image(systemName: "arrow.right.circle.fill")
                        .foregroundColor(.blue)
                }

                // Result indicator
                if isSubmitted {
                    Image(systemName: resultState == .correct ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(resultState == .correct ? .green : .red)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(backgroundColor)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(borderColor, lineWidth: isSelected || isMatched || isSubmitted ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isSubmitted)
    }

    private func rightItemButton(item: String, index: Int) -> some View {
        let matchedLeftIndex = rightToLeftMatches[index]
        let isMatched = matchedLeftIndex != nil
        let matchColorIndex = isMatched ? matchedLeftIndex! % matchColors.count : 0

        // Determine result state after submission
        let resultState: MatchResultState = {
            if !isSubmitted { return .none }
            guard let leftIndex = matchedLeftIndex else { return .none }
            let correctRightIndex = correctPairsMap[leftIndex]
            return index == correctRightIndex ? .correct : .incorrect
        }()

        let backgroundColor: Color = {
            if isSubmitted && isMatched {
                return resultState == .correct ? Color.green.opacity(0.2) : Color.red.opacity(0.2)
            } else if isMatched {
                return matchColors[matchColorIndex].opacity(0.2)
            }
            return Color(NSColor.textBackgroundColor)
        }()

        let borderColor: Color = {
            if isSubmitted && isMatched {
                return resultState == .correct ? Color.green : Color.red
            } else if isMatched {
                return matchColors[matchColorIndex]
            }
            return Color.secondary.opacity(0.3)
        }()

        return Button(action: {
            guard !isSubmitted else { return }
            handleRightTap(index: index)
        }) {
            HStack {
                // Match indicator badge
                if isMatched {
                    Circle()
                        .fill(isSubmitted ? (resultState == .correct ? Color.green : Color.red) : matchColors[matchColorIndex])
                        .frame(width: 12, height: 12)
                }

                Text(item)
                    .font(.body)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)

                Spacer()

                // Result indicator
                if isSubmitted && isMatched {
                    Image(systemName: resultState == .correct ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(resultState == .correct ? .green : .red)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(backgroundColor)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(borderColor, lineWidth: isMatched || isSubmitted ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isSubmitted)
    }

    private var actionButtonsSection: some View {
        HStack {
            if !isSubmitted {
                Text("\(userMatches.count) of \(content.leftItems.count) matched")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                // Clear all button
                if !userMatches.isEmpty {
                    Button(action: clearAllMatches) {
                        HStack {
                            Image(systemName: "arrow.counterclockwise")
                            Text("Clear All")
                        }
                    }
                    .buttonStyle(.bordered)
                }

                Button(action: submitMatches) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Check Answer")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!allItemsMatched)
            } else {
                Spacer()

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

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Overall result
            let correctCount = calculateCorrectCount()
            let totalPairs = content.correctPairs.count
            let allCorrect = correctCount == totalPairs

            HStack(spacing: 12) {
                Image(systemName: allCorrect ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .font(.title)
                    .foregroundColor(allCorrect ? .green : .orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text(allCorrect ? "Perfect!" : "Keep Practicing")
                        .font(.headline)
                        .foregroundColor(allCorrect ? .green : .orange)

                    Text("\(correctCount) of \(totalPairs) pair\(totalPairs == 1 ? "" : "s") correctly matched")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(allCorrect ? Color.green.opacity(0.1) : Color.orange.opacity(0.1))
            .cornerRadius(12)

            // Show correct answers if there were mistakes
            if correctCount < totalPairs {
                correctAnswersSection
            }
        }
    }

    private var correctAnswersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Correct Matches")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            ForEach(content.correctPairs, id: \.leftIndex) { pair in
                let userRightIndex = userMatches[pair.leftIndex]
                let isCorrect = userRightIndex == pair.rightIndex

                HStack(spacing: 12) {
                    Image(systemName: isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(isCorrect ? .green : .red)

                    Text(content.leftItems[pair.leftIndex])
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Image(systemName: "arrow.right")
                        .foregroundColor(.secondary)

                    Text(content.rightItems[pair.rightIndex])
                        .font(.subheadline)
                        .foregroundColor(isCorrect ? .primary : .green)
                        .fontWeight(isCorrect ? .regular : .semibold)

                    if !isCorrect, let userRight = userRightIndex {
                        Text("(You: \(content.rightItems[userRight]))")
                            .font(.caption)
                            .foregroundColor(.red)
                    }

                    Spacer()
                }
                .padding(.vertical, 4)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - Helper Methods

    private func handleLeftTap(index: Int) {
        // If this left item is already matched, remove the match
        if userMatches[index] != nil {
            userMatches.removeValue(forKey: index)
            selectedLeftIndex = nil
            return
        }

        // Select this left item
        selectedLeftIndex = index
    }

    private func handleRightTap(index: Int) {
        // If this right item is already matched, remove that match
        if let leftIndex = rightToLeftMatches[index] {
            userMatches.removeValue(forKey: leftIndex)
            selectedLeftIndex = nil
            return
        }

        // If no left item is selected, do nothing
        guard let leftIndex = selectedLeftIndex else { return }

        // Create the match
        userMatches[leftIndex] = index
        selectedLeftIndex = nil
    }

    private func clearAllMatches() {
        userMatches.removeAll()
        selectedLeftIndex = nil
    }

    private func calculateCorrectCount() -> Int {
        var correct = 0
        for pair in content.correctPairs {
            if userMatches[pair.leftIndex] == pair.rightIndex {
                correct += 1
            }
        }
        return correct
    }

    private func submitMatches() {
        isSubmitted = true
    }

    private func completeExercise() {
        let correctCount = calculateCorrectCount()
        let totalPairs = content.correctPairs.count
        let isCorrect = correctCount == totalPairs

        let feedback: String
        if isCorrect {
            feedback = "Excellent! All matches are correct."
        } else if correctCount > 0 {
            feedback = "You matched \(correctCount) of \(totalPairs) pairs correctly. Keep practicing!"
        } else {
            feedback = "None of the matches were correct. Review the correct answers above."
        }

        let timeSpent = Int(Date().timeIntervalSince(startTime))
        onComplete(isCorrect, feedback, timeSpent, userMatches)
    }
}

// MARK: - Match Result State

private enum MatchResultState {
    case none
    case correct
    case incorrect
    case missed
}

// MARK: - Preview

#Preview {
    MatchingExerciseView(
        content: MatchingContent(
            leftItems: ["Happy", "Sad", "Fast", "Slow"],
            rightItems: ["Quick", "Unhappy", "Joyful", "Sluggish"],
            correctPairs: [
                MatchPair(leftIndex: 0, rightIndex: 2),  // Happy -> Joyful
                MatchPair(leftIndex: 1, rightIndex: 1),  // Sad -> Unhappy
                MatchPair(leftIndex: 2, rightIndex: 0),  // Fast -> Quick
                MatchPair(leftIndex: 3, rightIndex: 3)   // Slow -> Sluggish
            ]
        ),
        onComplete: { isCorrect, feedback, timeSpent, userMatches in
            print("Completed: \(isCorrect), Feedback: \(feedback), Time: \(timeSpent)s, Matches: \(userMatches)")
        }
    )
    .frame(width: 600, height: 700)
}
