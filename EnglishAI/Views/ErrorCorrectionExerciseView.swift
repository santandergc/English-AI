import SwiftUI

// MARK: - Error Correction Exercise View

struct ErrorCorrectionExerciseView: View {
    let content: ErrorCorrectionContent
    let onComplete: (Bool, String, Int) -> Void  // isCorrect, feedback, timeSpentSeconds

    @State private var selectedWordIndices: Set<Int> = []
    @State private var corrections: [Int: String] = [:]  // wordIndex -> user's correction
    @State private var isSubmitted: Bool = false
    @State private var startTime: Date = Date()

    private var words: [String] {
        content.incorrectSentence.components(separatedBy: " ")
    }

    // Build a map of word position to error item for quick lookup
    private var errorsByPosition: [Int: ErrorItem] {
        var map: [Int: ErrorItem] = [:]
        for error in content.errors {
            map[error.position] = error
        }
        return map
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Instruction section
                instructionSection

                // Sentence with tappable words
                sentenceSection

                // Corrections input section (shown when words are selected)
                if !selectedWordIndices.isEmpty && !isSubmitted {
                    correctionsInputSection
                }

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
            Text("Find and correct the error(s)")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            Text("Tap on the words that contain errors, then type your corrections below.")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    private var sentenceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sentence")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            // Word flow layout
            FlowLayout(spacing: 8) {
                ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                    wordButton(word: word, index: index)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
            )
        }
    }

    private func wordButton(word: String, index: Int) -> some View {
        let isSelected = selectedWordIndices.contains(index)
        let isError = errorsByPosition[index] != nil
        let userCorrection = corrections[index]

        // Determine background color based on state
        let backgroundColor: Color = {
            if isSubmitted {
                if isError && isSelected {
                    // User correctly identified an error
                    let correction = userCorrection ?? ""
                    let isCorrectCorrection = correction.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) ==
                        errorsByPosition[index]!.correctText.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                    return isCorrectCorrection ? Color.green.opacity(0.3) : Color.orange.opacity(0.3)
                } else if isError && !isSelected {
                    // Missed error
                    return Color.red.opacity(0.3)
                } else if !isError && isSelected {
                    // Incorrectly selected a correct word
                    return Color.orange.opacity(0.3)
                }
                return Color.clear
            } else {
                return isSelected ? Color.blue.opacity(0.2) : Color.clear
            }
        }()

        let borderColor: Color = {
            if isSubmitted {
                if isError && isSelected {
                    let correction = userCorrection ?? ""
                    let isCorrectCorrection = correction.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) ==
                        errorsByPosition[index]!.correctText.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                    return isCorrectCorrection ? Color.green : Color.orange
                } else if isError && !isSelected {
                    return Color.red
                } else if !isError && isSelected {
                    return Color.orange
                }
                return Color.clear
            } else {
                return isSelected ? Color.blue : Color.clear
            }
        }()

        return Button(action: {
            guard !isSubmitted else { return }
            toggleWordSelection(index: index)
        }) {
            VStack(spacing: 2) {
                Text(word)
                    .font(.body)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundColor(isSelected && !isSubmitted ? .blue : .primary)

                // Show correction preview below selected word
                if isSelected && userCorrection != nil && !userCorrection!.isEmpty {
                    Text(userCorrection!)
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(backgroundColor)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(borderColor, lineWidth: isSelected || (isSubmitted && isError) ? 2 : 0)
            )
        }
        .buttonStyle(.plain)
        .disabled(isSubmitted)
    }

    private var correctionsInputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your Corrections")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            ForEach(Array(selectedWordIndices.sorted()), id: \.self) { index in
                HStack(spacing: 12) {
                    Text("\"\(words[index])\"")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .frame(minWidth: 80, alignment: .leading)

                    Image(systemName: "arrow.right")
                        .foregroundColor(.secondary)

                    TextField("Type correction...", text: Binding(
                        get: { corrections[index] ?? "" },
                        set: { corrections[index] = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 200)

                    Button(action: {
                        selectedWordIndices.remove(index)
                        corrections.removeValue(forKey: index)
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    private var actionButtonsSection: some View {
        HStack {
            if !isSubmitted {
                Text("\(selectedWordIndices.count) word\(selectedWordIndices.count == 1 ? "" : "s") selected")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if !isSubmitted {
                Button(action: submitCorrections) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Check Answer")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedWordIndices.isEmpty || !allSelectionsHaveCorrections)
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

    private var allSelectionsHaveCorrections: Bool {
        for index in selectedWordIndices {
            guard let correction = corrections[index], !correction.isEmpty else {
                return false
            }
        }
        return true
    }

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Overall result
            let (correctCount, totalErrors, incorrectSelections) = calculateResults()
            let allCorrect = correctCount == totalErrors && incorrectSelections == 0

            HStack(spacing: 12) {
                Image(systemName: allCorrect ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .font(.title)
                    .foregroundColor(allCorrect ? .green : .orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text(allCorrect ? "Perfect!" : "Keep Practicing")
                        .font(.headline)
                        .foregroundColor(allCorrect ? .green : .orange)

                    Text("\(correctCount) of \(totalErrors) error\(totalErrors == 1 ? "" : "s") correctly identified and fixed")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    if incorrectSelections > 0 {
                        Text("\(incorrectSelections) word\(incorrectSelections == 1 ? "" : "s") incorrectly marked as errors")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(allCorrect ? Color.green.opacity(0.1) : Color.orange.opacity(0.1))
            .cornerRadius(12)

            // Detailed explanations for each error
            VStack(alignment: .leading, spacing: 12) {
                Text("Error Explanations")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)

                ForEach(content.errors, id: \.position) { error in
                    errorExplanationCard(error: error)
                }
            }
        }
    }

    private func errorExplanationCard(error: ErrorItem) -> some View {
        let wasSelected = selectedWordIndices.contains(error.position)
        let userCorrection = corrections[error.position] ?? ""
        let isCorrectCorrection = wasSelected && userCorrection.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) ==
            error.correctText.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: isCorrectCorrection ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(isCorrectCorrection ? .green : .red)

                Text("\"\(error.incorrectText)\"")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .strikethrough()
                    .foregroundColor(.red)

                Image(systemName: "arrow.right")
                    .foregroundColor(.secondary)

                Text("\"\(error.correctText)\"")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.green)

                Spacer()
            }

            if wasSelected && !isCorrectCorrection && !userCorrection.isEmpty {
                Text("Your answer: \"\(userCorrection)\"")
                    .font(.caption)
                    .foregroundColor(.orange)
            }

            if !wasSelected {
                Text("You missed this error")
                    .font(.caption)
                    .foregroundColor(.red)
            }

            Text(error.explanation)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - Helper Methods

    private func toggleWordSelection(index: Int) {
        if selectedWordIndices.contains(index) {
            selectedWordIndices.remove(index)
            corrections.removeValue(forKey: index)
        } else {
            selectedWordIndices.insert(index)
        }
    }

    private func calculateResults() -> (correctCount: Int, totalErrors: Int, incorrectSelections: Int) {
        var correctCount = 0
        var incorrectSelections = 0

        for index in selectedWordIndices {
            if let error = errorsByPosition[index] {
                let userCorrection = corrections[index] ?? ""
                if userCorrection.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) ==
                    error.correctText.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) {
                    correctCount += 1
                }
            } else {
                incorrectSelections += 1
            }
        }

        return (correctCount, content.errors.count, incorrectSelections)
    }

    private func submitCorrections() {
        isSubmitted = true
    }

    private func completeExercise() {
        let (correctCount, totalErrors, incorrectSelections) = calculateResults()
        let isCorrect = correctCount == totalErrors && incorrectSelections == 0
        let partialScore = totalErrors > 0 ? Double(correctCount) / Double(totalErrors) : 0.0

        let feedback: String
        if isCorrect {
            feedback = "Excellent! You found and corrected all errors."
        } else if correctCount > 0 {
            feedback = "You found \(correctCount) of \(totalErrors) errors. Keep practicing!"
        } else {
            feedback = "None of the errors were correctly identified. Review the explanations above."
        }

        let timeSpent = Int(Date().timeIntervalSince(startTime))
        onComplete(isCorrect, feedback, timeSpent)
    }
}

// MARK: - Flow Layout for Word Wrapping

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = computeLayout(proposal: proposal, subviews: subviews)

        for (index, subview) in subviews.enumerated() {
            let position = result.positions[index]
            subview.place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func computeLayout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxWidth: CGFloat = 0

        let maxContainerWidth = proposal.width ?? .infinity

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > maxContainerWidth && currentX > 0 {
                currentX = 0
                currentY += rowHeight + spacing
                rowHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))

            rowHeight = max(rowHeight, size.height)
            currentX += size.width + spacing
            maxWidth = max(maxWidth, currentX - spacing)
        }

        return (CGSize(width: maxWidth, height: currentY + rowHeight), positions)
    }
}

// MARK: - Preview

#Preview {
    ErrorCorrectionExerciseView(
        content: ErrorCorrectionContent(
            incorrectSentence: "She go to the store yesterday and buyed some milk.",
            errors: [
                ErrorItem(
                    position: 1,
                    incorrectText: "go",
                    correctText: "went",
                    explanation: "The verb should be in past tense to match 'yesterday'."
                ),
                ErrorItem(
                    position: 7,
                    incorrectText: "buyed",
                    correctText: "bought",
                    explanation: "'Buy' is an irregular verb. The past tense is 'bought', not 'buyed'."
                )
            ]
        ),
        onComplete: { isCorrect, feedback, timeSpent in
            print("Completed: \(isCorrect), Feedback: \(feedback), Time: \(timeSpent)s")
        }
    )
    .frame(width: 600, height: 700)
}
