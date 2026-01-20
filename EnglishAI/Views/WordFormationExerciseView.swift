import SwiftUI

// MARK: - Word Formation Exercise View

struct WordFormationExerciseView: View {
    let content: WordFormationContent
    let onComplete: (Bool, String, Int) -> Void  // isCorrect, feedback, timeSpentSeconds

    @State private var userAnswer: String = ""
    @State private var isSubmitted: Bool = false
    @State private var isCorrect: Bool = false
    @State private var startTime: Date = Date()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Instruction section
                instructionSection

                // Sentence with blank and base word
                sentenceSection

                // Input section
                inputSection

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
            Text("Word Formation")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            Text("Complete the sentence using the correct form of the word in parentheses.")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    private var sentenceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Complete the sentence:")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            // Display sentence with blank and base word
            sentenceDisplay
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

    private var sentenceDisplay: some View {
        // Parse the sentence and create styled text with blank
        let parts = content.baseSentence.components(separatedBy: "___")

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 0) {
                ForEach(0..<parts.count, id: \.self) { index in
                    Text(parts[index])
                        .font(.title3)
                        .fontWeight(.medium)

                    if index < parts.count - 1 {
                        // Blank placeholder
                        Text(isSubmitted ? content.correctForm : "_______")
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(isSubmitted ? (isCorrect ? .green : .red) : .blue)
                            .underline(!isSubmitted)
                    }
                }
            }

            // Base word in parentheses
            Text("(\(content.targetWord.uppercased()))")
                .font(.headline)
                .foregroundColor(.orange)
                .padding(.top, 4)
        }
    }

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your Answer")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            HStack {
                TextField("Type the correct word form", text: $userAnswer)
                    .textFieldStyle(.roundedBorder)
                    .font(.body)
                    .disabled(isSubmitted)

                if !userAnswer.isEmpty && !isSubmitted {
                    Button(action: { userAnswer = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            if isSubmitted && !isCorrect {
                HStack(spacing: 4) {
                    Text("Your answer:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(userAnswer.isEmpty ? "(empty)" : userAnswer)
                        .font(.caption)
                        .foregroundColor(.red)
                        .strikethrough()
                }
            }
        }
    }

    private var actionButtonsSection: some View {
        HStack {
            Spacer()

            if !isSubmitted {
                Button(action: checkAnswer) {
                    HStack {
                        Image(systemName: "checkmark.circle")
                        Text("Check Answer")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(userAnswer.trimmingCharacters(in: .whitespaces).isEmpty)
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

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Result indicator
            HStack(spacing: 12) {
                Image(systemName: isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.title)
                    .foregroundColor(isCorrect ? .green : .red)

                VStack(alignment: .leading, spacing: 2) {
                    Text(isCorrect ? "Correct!" : "Incorrect")
                        .font(.headline)
                        .foregroundColor(isCorrect ? .green : .red)

                    if !isCorrect {
                        Text("The correct answer is: \(content.correctForm)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isCorrect ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
            .cornerRadius(12)

            // Word family section
            wordFamilySection
        }
    }

    private var wordFamilySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Word Family")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                Text("Related words from the same root:")
                    .font(.caption)
                    .foregroundColor(.secondary)

                FlexibleWordGrid(words: content.wordFamily, correctForm: content.correctForm)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
    }

    // MARK: - Actions

    private func checkAnswer() {
        let trimmedAnswer = userAnswer.trimmingCharacters(in: .whitespaces).lowercased()
        let correctAnswer = content.correctForm.lowercased()

        isCorrect = trimmedAnswer == correctAnswer
        isSubmitted = true
    }

    private func completeExercise() {
        let timeSpent = Int(Date().timeIntervalSince(startTime))
        let feedback = isCorrect
            ? "You correctly identified the word form '\(content.correctForm)'."
            : "The correct form was '\(content.correctForm)'. Remember the word family: \(content.wordFamily.joined(separator: ", "))."
        onComplete(isCorrect, feedback, timeSpent)
    }
}

// MARK: - Flexible Word Grid

struct FlexibleWordGrid: View {
    let words: [String]
    let correctForm: String

    var body: some View {
        LazyVGrid(columns: [
            GridItem(.adaptive(minimum: 100, maximum: 150), spacing: 8)
        ], alignment: .leading, spacing: 8) {
            ForEach(words, id: \.self) { word in
                HStack(spacing: 4) {
                    if word.lowercased() == correctForm.lowercased() {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                    Text(word)
                        .font(.subheadline)
                        .fontWeight(word.lowercased() == correctForm.lowercased() ? .bold : .regular)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    word.lowercased() == correctForm.lowercased()
                        ? Color.orange.opacity(0.2)
                        : Color.blue.opacity(0.1)
                )
                .cornerRadius(6)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    WordFormationExerciseView(
        content: WordFormationContent(
            baseSentence: "She is very ___ and always helps others.",
            targetWord: "beauty",
            correctForm: "beautiful",
            wordFamily: ["beauty", "beautiful", "beautifully", "beautify", "beautician"]
        ),
        onComplete: { isCorrect, feedback, timeSpent in
            print("Completed: \(isCorrect), Time: \(timeSpent)s")
            print("Feedback: \(feedback)")
        }
    )
    .frame(width: 600, height: 500)
}
