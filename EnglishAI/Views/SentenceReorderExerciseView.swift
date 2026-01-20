import SwiftUI
import UniformTypeIdentifiers

// MARK: - Sentence Reorder Exercise View

struct SentenceReorderExerciseView: View {
    let content: SentenceReorderContent
    let onComplete: (Bool, String, Int, [Int]) -> Void  // isCorrect, feedback, timeSpentSeconds, userOrder

    @State private var currentOrder: [Int] = []  // Indices into shuffledWords representing current arrangement
    @State private var selectedIndex: Int? = nil  // For tap-to-reorder interaction
    @State private var draggingIndex: Int? = nil  // For drag visual feedback
    @State private var isSubmitted: Bool = false
    @State private var startTime: Date = Date()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Instruction section
                instructionSection

                // Word tiles area with drag-and-drop
                wordTilesSection

                // Current sentence preview
                sentencePreviewSection

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
            // Initialize current order to match the shuffled order (0, 1, 2, ...)
            currentOrder = Array(0..<content.shuffledWords.count)
        }
    }

    // MARK: - View Components

    private var instructionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Arrange the words in correct order")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            Text("Drag words to reorder them, or tap two words to swap their positions.")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    private var wordTilesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Words")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            // Reorderable word tiles using FlowLayout
            ReorderableFlowLayout(spacing: 10) {
                ForEach(Array(currentOrder.enumerated()), id: \.element) { position, wordIndex in
                    wordTile(wordIndex: wordIndex, position: position)
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

    private func wordTile(wordIndex: Int, position: Int) -> some View {
        let word = content.shuffledWords[wordIndex]
        let isSelected = selectedIndex == position
        let isDragging = draggingIndex == position

        // Determine background/border color based on state
        let backgroundColor: Color = {
            if isSubmitted {
                let correctWordIndex = content.correctOrder[position]
                return wordIndex == correctWordIndex ? Color.green.opacity(0.2) : Color.red.opacity(0.2)
            } else if isSelected {
                return Color.blue.opacity(0.2)
            } else {
                return Color(NSColor.controlColor)
            }
        }()

        let borderColor: Color = {
            if isSubmitted {
                let correctWordIndex = content.correctOrder[position]
                return wordIndex == correctWordIndex ? Color.green : Color.red
            } else if isSelected {
                return Color.blue
            } else {
                return Color.secondary.opacity(0.3)
            }
        }()

        return Text(word)
            .font(.body)
            .fontWeight(.medium)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(backgroundColor)
            .foregroundColor(.primary)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(borderColor, lineWidth: isSelected || isSubmitted ? 2 : 1)
            )
            .shadow(color: isDragging ? Color.black.opacity(0.3) : Color.clear, radius: isDragging ? 8 : 0)
            .scaleEffect(isDragging ? 1.05 : 1.0)
            .opacity(isDragging ? 0.9 : 1.0)
            .onTapGesture {
                guard !isSubmitted else { return }
                handleTap(at: position)
            }
            .onDrag {
                self.draggingIndex = position
                return NSItemProvider(object: String(position) as NSString)
            }
            .onDrop(of: [UTType.text], delegate: WordDropDelegate(
                position: position,
                currentOrder: $currentOrder,
                draggingIndex: $draggingIndex,
                isSubmitted: isSubmitted
            ))
            .animation(.easeInOut(duration: 0.2), value: isDragging)
    }

    private var sentencePreviewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Current Sentence")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            Text(currentSentence)
                .font(.body)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
        }
    }

    private var currentSentence: String {
        currentOrder.map { content.shuffledWords[$0] }.joined(separator: " ")
    }

    private var correctSentence: String {
        content.correctOrder.map { content.shuffledWords[$0] }.joined(separator: " ")
    }

    private var actionButtonsSection: some View {
        HStack {
            if !isSubmitted && selectedIndex != nil {
                Text("Tap another word to swap")
                    .font(.caption)
                    .foregroundColor(.blue)
            } else if !isSubmitted {
                Text("\(content.shuffledWords.count) words to arrange")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if !isSubmitted {
                Button(action: resetOrder) {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Reset")
                    }
                }
                .buttonStyle(.bordered)

                Button(action: submitOrder) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Check Answer")
                    }
                }
                .buttonStyle(.borderedProminent)
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
            // Overall result
            let isCorrect = checkAnswer()

            HStack(spacing: 12) {
                Image(systemName: isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.title)
                    .foregroundColor(isCorrect ? .green : .red)

                VStack(alignment: .leading, spacing: 2) {
                    Text(isCorrect ? "Correct!" : "Not Quite Right")
                        .font(.headline)
                        .foregroundColor(isCorrect ? .green : .red)

                    if !isCorrect {
                        Text("The words aren't in the right order yet.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isCorrect ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
            .cornerRadius(12)

            // Show correct answer if wrong
            if !isCorrect {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Correct Sentence")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)

                    Text(correctSentence)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.green)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(8)
                }
            }
        }
    }

    // MARK: - Helper Methods

    private func handleTap(at position: Int) {
        if let selected = selectedIndex {
            if selected == position {
                // Deselect if tapping the same word
                selectedIndex = nil
            } else {
                // Swap the two words
                swapWords(from: selected, to: position)
                selectedIndex = nil
            }
        } else {
            // Select this word
            selectedIndex = position
        }
    }

    private func swapWords(from: Int, to: Int) {
        guard from != to else { return }
        let temp = currentOrder[from]
        currentOrder[from] = currentOrder[to]
        currentOrder[to] = temp
    }

    private func resetOrder() {
        currentOrder = Array(0..<content.shuffledWords.count)
        selectedIndex = nil
    }

    private func checkAnswer() -> Bool {
        return currentOrder == content.correctOrder
    }

    private func submitOrder() {
        selectedIndex = nil
        isSubmitted = true
    }

    private func completeExercise() {
        let isCorrect = checkAnswer()

        let feedback: String
        if isCorrect {
            feedback = "Excellent! You arranged all the words correctly."
        } else {
            feedback = "The sentence order was incorrect. Review the correct arrangement above."
        }

        let timeSpent = Int(Date().timeIntervalSince(startTime))
        onComplete(isCorrect, feedback, timeSpent, currentOrder)
    }
}

// MARK: - Word Drop Delegate

struct WordDropDelegate: DropDelegate {
    let position: Int
    @Binding var currentOrder: [Int]
    @Binding var draggingIndex: Int?
    let isSubmitted: Bool

    func performDrop(info: DropInfo) -> Bool {
        draggingIndex = nil
        return true
    }

    func dropEntered(info: DropInfo) {
        guard !isSubmitted else { return }
        guard let fromIndex = draggingIndex, fromIndex != position else { return }

        withAnimation(.easeInOut(duration: 0.2)) {
            let fromValue = currentOrder[fromIndex]
            currentOrder.remove(at: fromIndex)
            currentOrder.insert(fromValue, at: position)
        }

        // Update dragging index to new position after swap
        draggingIndex = position
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }

    func validateDrop(info: DropInfo) -> Bool {
        return !isSubmitted
    }
}

// MARK: - Reorderable Flow Layout

struct ReorderableFlowLayout: Layout {
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
    SentenceReorderExerciseView(
        content: SentenceReorderContent(
            shuffledWords: ["morning", "I", "coffee", "every", "drink"],
            correctOrder: [1, 4, 2, 0, 3]  // "I drink coffee every morning"
        ),
        onComplete: { isCorrect, feedback, timeSpent, userOrder in
            print("Completed: \(isCorrect), Feedback: \(feedback), Time: \(timeSpent)s, Order: \(userOrder)")
        }
    )
    .frame(width: 600, height: 500)
}
