import SwiftUI

struct InsightsView: View {
    let date: Date
    @StateObject private var viewModel = InsightsViewModel()
    @State private var isAnalyzing = false
    @State private var showSettings = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("AI Analysis")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                if viewModel.aiService.hasAPIKey {
                    Text("via \(viewModel.aiService.activeProviderName)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if !viewModel.aiService.hasAPIKey {
                    Button("Set API Key") {
                        showSettings = true
                    }
                    .buttonStyle(.bordered)
                }
                
                Button(action: {
                    Task {
                        await analyzeDay()
                    }
                }) {
                    HStack {
                        if isAnalyzing {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "sparkles")
                        }
                        Text(isAnalyzing ? "Analyzing..." : "Analyze")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isAnalyzing || !viewModel.aiService.hasAPIKey)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            if let error = viewModel.error {
                ErrorBannerView(message: error)
            }
            
            if let result = viewModel.currentResult {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Summary Card
                        SummaryCardView(result: result)
                        
                        // Grammar Issues
                        if !result.grammarIssues.isEmpty {
                            IssuesSectionView(
                                title: "Grammar Issues",
                                icon: "text.badge.xmark",
                                color: .red
                            ) {
                                ForEach(Array(result.grammarIssues.enumerated()), id: \.offset) { _, issue in
                                    GrammarIssueCard(issue: issue)
                                }
                            }
                        }
                        
                        // Phrasing Issues
                        if !result.phrasingIssues.isEmpty {
                            IssuesSectionView(
                                title: "Phrasing Suggestions",
                                icon: "text.quote",
                                color: .orange
                            ) {
                                ForEach(Array(result.phrasingIssues.enumerated()), id: \.offset) { _, issue in
                                    PhrasingIssueCard(issue: issue)
                                }
                            }
                        }
                        
                        // Vocabulary
                        if !result.vocabularyInsights.isEmpty {
                            IssuesSectionView(
                                title: "Vocabulary Notes",
                                icon: "book",
                                color: .blue
                            ) {
                                ForEach(Array(result.vocabularyInsights.enumerated()), id: \.offset) { _, insight in
                                    VocabularyCard(insight: insight)
                                }
                            }
                        }
                        
                        // Positives
                        if !result.positives.isEmpty {
                            IssuesSectionView(
                                title: "What You Did Well",
                                icon: "checkmark.circle",
                                color: .green
                            ) {
                                ForEach(result.positives, id: \.self) { positive in
                                    HStack(alignment: .top) {
                                        Image(systemName: "star.fill")
                                            .foregroundColor(.yellow)
                                            .font(.caption)
                                        Text(positive)
                                            .font(.body)
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        }
                    }
                    .padding()
                }
            } else if viewModel.insights.isEmpty {
                VStack {
                    Spacer()
                    Image(systemName: "sparkles")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No analysis yet for this day")
                        .font(.title3)
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                    Text("Click 'Analyze' to get AI feedback on your English")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                // Show historical insights
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(viewModel.insights) { insight in
                            InsightHistoryCard(insight: insight)
                        }
                    }
                    .padding()
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .onAppear {
            viewModel.loadInsights(for: date)
        }
        .onChange(of: date) { newDate in
            viewModel.loadInsights(for: newDate)
        }
    }
    
    private func analyzeDay() async {
        isAnalyzing = true
        await viewModel.analyzeDate(date)
        isAnalyzing = false
    }
}

// MARK: - View Model

class InsightsViewModel: ObservableObject {
    @Published var insights: [Insight] = []
    @Published var currentResult: AnalysisResult?
    @Published var error: String?
    
    let aiService = AIAnalysisService.shared
    private let database = DatabaseService.shared
    
    func loadInsights(for date: Date) {
        insights = database.fetchInsights(for: date)
        error = nil
        
        // Try to parse the most recent insight
        if let latestInsight = insights.first,
           let data = latestInsight.content.data(using: .utf8),
           let result = try? JSONDecoder().decode(AnalysisResult.self, from: data) {
            currentResult = result
        } else {
            currentResult = nil
        }
    }
    
    func analyzeDate(_ date: Date) async {
        do {
            let result = try await aiService.analyzeRecords(for: date)
            await MainActor.run {
                self.currentResult = result
                self.error = nil
                self.loadInsights(for: date)
            }
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
            }
        }
    }
}

// MARK: - Components

struct SummaryCardView: View {
    let result: AnalysisResult
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Summary")
                    .font(.headline)
                Spacer()
                ScoreBadge(score: result.overallScore)
            }
            
            Text(result.summary)
                .font(.body)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }
}

struct ScoreBadge: View {
    let score: Int
    
    var body: some View {
        HStack(spacing: 4) {
            Text("\(score)")
                .font(.title2)
                .fontWeight(.bold)
            Text("/10")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(scoreColor.opacity(0.2))
        .cornerRadius(8)
    }
    
    private var scoreColor: Color {
        switch score {
        case 8...10: return .green
        case 6...7: return .yellow
        default: return .orange
        }
    }
}

struct IssuesSectionView<Content: View>: View {
    let title: String
    let icon: String
    let color: Color
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(title)
                    .font(.headline)
            }
            
            content
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }
}

struct GrammarIssueCard: View {
    let issue: GrammarIssue
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text(issue.original)
                    .strikethrough()
                    .foregroundColor(.red)
                Image(systemName: "arrow.right")
                    .foregroundColor(.secondary)
                Text(issue.corrected)
                    .foregroundColor(.green)
            }
            .font(.body)
            
            Text(issue.explanation)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(8)
    }
}

struct PhrasingIssueCard: View {
    let issue: PhrasingIssue
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text(issue.original)
                    .foregroundColor(.orange)
                Image(systemName: "arrow.right")
                    .foregroundColor(.secondary)
                Text(issue.natural)
                    .foregroundColor(.green)
            }
            .font(.body)
            
            Text(issue.context)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(8)
    }
}

struct VocabularyCard: View {
    let insight: VocabularyInsight
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(insight.word)
                    .font(.body)
                    .fontWeight(.medium)
                if let suggestion = insight.suggestion {
                    Image(systemName: "arrow.right")
                        .foregroundColor(.secondary)
                    Text(suggestion)
                        .foregroundColor(.blue)
                }
            }
            
            Text(insight.note)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(8)
    }
}

struct ErrorBannerView: View {
    let message: String
    
    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle")
            Text(message)
            Spacer()
        }
        .foregroundColor(.white)
        .padding()
        .background(Color.red)
    }
}

struct InsightHistoryCard: View {
    let insight: Insight
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(formatDate(insight.createdAt))
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(insight.recordCount) records")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if let data = insight.content.data(using: .utf8),
               let result = try? JSONDecoder().decode(AnalysisResult.self, from: data) {
                Text(result.summary)
                    .font(.body)
                    .lineLimit(3)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var anthropicKey: String = ""
    @State private var openAIKey: String = ""
    
    private var activeProvider: String {
        if !anthropicKey.isEmpty {
            return "Anthropic (Claude)"
        } else if !openAIKey.isEmpty {
            return "OpenAI (GPT)"
        }
        return "None"
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Settings")
                .font(.title2)
                .fontWeight(.semibold)
            
            // Active Provider Indicator
            HStack {
                Text("Active Provider:")
                    .foregroundColor(.secondary)
                Text(activeProvider)
                    .fontWeight(.medium)
                    .foregroundColor(activeProvider == "None" ? .red : .green)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            
            Divider()
            
            // Anthropic API Key
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Anthropic API Key")
                        .font(.headline)
                    if !anthropicKey.isEmpty {
                        Text("(Priority)")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
                
                SecureField("sk-ant-...", text: $anthropicKey)
                    .textFieldStyle(.roundedBorder)
                
                Text("Get your API key from console.anthropic.com")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // OpenAI API Key
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("OpenAI API Key")
                        .font(.headline)
                    if anthropicKey.isEmpty && !openAIKey.isEmpty {
                        Text("(Active)")
                            .font(.caption)
                            .foregroundColor(.blue)
                    } else if !openAIKey.isEmpty {
                        Text("(Fallback)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                SecureField("sk-...", text: $openAIKey)
                    .textFieldStyle(.roundedBorder)
                
                Text("Get your API key from platform.openai.com")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Text("If both keys are saved, Anthropic will be used. OpenAI is used as fallback.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Spacer()
            
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                
                Button("Save") {
                    let trimmedAnthropic = anthropicKey.trimmingCharacters(in: .whitespacesAndNewlines)
                    let trimmedOpenAI = openAIKey.trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    AIAnalysisService.shared.anthropicAPIKey = trimmedAnthropic.isEmpty ? nil : trimmedAnthropic
                    AIAnalysisService.shared.openAIAPIKey = trimmedOpenAI.isEmpty ? nil : trimmedOpenAI
                    
                    // Verify the keys were saved
                    print("✅ Saved Anthropic key: \(AIAnalysisService.shared.anthropicAPIKey != nil ? "Yes (\(AIAnalysisService.shared.anthropicAPIKey!.prefix(10))...)" : "No")")
                    print("✅ Saved OpenAI key: \(AIAnalysisService.shared.openAIAPIKey != nil ? "Yes (\(AIAnalysisService.shared.openAIAPIKey!.prefix(10))...)" : "No")")
                    
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(30)
        .frame(width: 450, height: 420)
        .onAppear {
            anthropicKey = AIAnalysisService.shared.anthropicAPIKey ?? ""
            openAIKey = AIAnalysisService.shared.openAIAPIKey ?? ""
        }
    }
}

#Preview {
    InsightsView(date: Date())
}
