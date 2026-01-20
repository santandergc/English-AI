import SwiftUI

// MARK: - Free Response Exercise View

struct FreeResponseExerciseView: View {
    let content: FreeResponseContent
    let onComplete: (Bool, String, Int) -> Void  // isCorrect, feedback, timeSpentSeconds

    @State private var userResponse: String = ""
    @State private var isSubmitting: Bool = false
    @State private var evaluationResult: FreeResponseEvaluationResult?
    @State private var errorMessage: String?
    @State private var startTime: Date = Date()

    private let minCharacters = 10

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Prompt section
                promptSection

                // Response input section
                responseInputSection

                // Action buttons
                actionButtonsSection

                // Results section (shown after submission)
                if let result = evaluationResult {
                    resultsSection(result: result)
                }

                // Error message
                if let error = errorMessage {
                    errorSection(error: error)
                }
            }
            .padding()
        }
        .onAppear {
            startTime = Date()
        }
    }

    // MARK: - View Components

    private var promptSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Question")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            Text(content.prompt)
                .font(.title3)
                .fontWeight(.medium)
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

    private var responseInputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your Response")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            TextEditor(text: $userResponse)
                .font(.body)
                .frame(minHeight: 150)
                .padding(8)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
                .disabled(evaluationResult != nil)

            // Character count
            HStack {
                Spacer()
                Text("\(userResponse.count) characters")
                    .font(.caption)
                    .foregroundColor(userResponse.count >= minCharacters ? .secondary : .orange)
            }
        }
    }

    private var actionButtonsSection: some View {
        HStack {
            Spacer()

            if evaluationResult == nil {
                Button(action: submitResponse) {
                    HStack {
                        if isSubmitting {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 16, height: 16)
                        } else {
                            Image(systemName: "paperplane.fill")
                        }
                        Text(isSubmitting ? "Evaluating..." : "Submit")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(userResponse.count < minCharacters || isSubmitting)
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

    private func resultsSection(result: FreeResponseEvaluationResult) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Result indicator
            HStack(spacing: 12) {
                Image(systemName: result.isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.title)
                    .foregroundColor(result.isCorrect ? .green : .orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text(result.isCorrect ? "Well Done!" : "Needs Improvement")
                        .font(.headline)
                        .foregroundColor(result.isCorrect ? .green : .orange)

                    Text(result.feedback)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(result.isCorrect ? Color.green.opacity(0.1) : Color.orange.opacity(0.1))
            .cornerRadius(12)

            // Sample answer section
            VStack(alignment: .leading, spacing: 8) {
                Text("Sample Answer")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)

                Text(content.sampleAnswer)
                    .font(.body)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
            }

            // Key points section
            if !content.keyPoints.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Key Points")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)

                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(content.keyPoints, id: \.self) { point in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "checkmark.circle")
                                    .foregroundColor(.blue)
                                    .font(.caption)
                                Text(point)
                                    .font(.subheadline)
                            }
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                }
            }
        }
    }

    private func errorSection(error: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text(error)
                .font(.subheadline)
                .foregroundColor(.orange)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
    }

    // MARK: - Actions

    private func submitResponse() {
        guard !isSubmitting else { return }

        isSubmitting = true
        errorMessage = nil

        Task {
            do {
                let result = try await ExerciseGenerationService.shared.evaluateFreeResponse(
                    prompt: content.prompt,
                    userAnswer: userResponse,
                    keyPoints: content.keyPoints
                )

                await MainActor.run {
                    self.evaluationResult = result
                    self.isSubmitting = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isSubmitting = false
                }
            }
        }
    }

    private func completeExercise() {
        guard let result = evaluationResult else { return }

        let timeSpent = Int(Date().timeIntervalSince(startTime))
        onComplete(result.isCorrect, result.feedback, timeSpent)
    }
}

// MARK: - Preview

#Preview {
    FreeResponseExerciseView(
        content: FreeResponseContent(
            prompt: "Describe your ideal vacation destination and explain why you would like to visit there.",
            sampleAnswer: "My ideal vacation destination would be Japan. I've always been fascinated by the unique blend of ancient traditions and modern technology. I would love to visit historic temples in Kyoto, experience the bustling streets of Tokyo, and try authentic Japanese cuisine. The country's beautiful landscapes, from cherry blossoms to Mount Fuji, also make it incredibly appealing.",
            keyPoints: [
                "Names a specific destination",
                "Provides reasons for the choice",
                "Includes details about activities or experiences"
            ]
        ),
        onComplete: { isCorrect, feedback, timeSpent in
            print("Completed: \(isCorrect), Time: \(timeSpent)s")
        }
    )
    .frame(width: 600, height: 700)
}
