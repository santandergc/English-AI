import SwiftUI

// MARK: - Sidebar Selection
enum SidebarItem: Hashable {
    case date(Date)
    case weeklyProgress
    case allAnalyses
}

struct ContentView: View {
    @StateObject private var viewModel = RecordsViewModel()
    @State private var selectedItem: SidebarItem = .date(Date())
    @State private var selectedSource: RecordSource? = nil
    @State private var showSettings = false

    private var selectedDate: Date {
        if case .date(let date) = selectedItem {
            return date
        }
        return Date()
    }

    var body: some View {
        NavigationSplitView {
            // Sidebar
            VStack(spacing: 0) {
                // History Section
            VStack(alignment: .leading, spacing: 0) {
                Text("History")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 16)
                    .padding(.top, 12)
                        .padding(.bottom, 6)

                    List(selection: $selectedItem) {
                        ForEach(viewModel.availableDates, id: \.self) { date in
                            DateRowView(
                                date: date,
                                recordCount: viewModel.recordCount(for: date),
                                hasAnalysis: DatabaseService.shared.hasAnalysis(for: date)
                            )
                            .tag(SidebarItem.date(date))
                        }
                    }
                    .listStyle(.sidebar)
                }
                
                Divider()
                    .padding(.vertical, 4)
                
                // AI Insights Section
                VStack(alignment: .leading, spacing: 0) {
                    Text("AI Insights")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 6)
                    
                    List(selection: $selectedItem) {
                        Label("Weekly Progress", systemImage: "chart.line.uptrend.xyaxis")
                            .tag(SidebarItem.weeklyProgress)
                        
                        Label("All Analyses", systemImage: "sparkles")
                            .tag(SidebarItem.allAnalyses)
                }
                .listStyle(.sidebar)
                    .frame(height: 80)
                }
                
                Divider()
                
                // Profile Section (Bottom)
                ProfileSectionView(showSettings: $showSettings)
                    .padding(.vertical, 8)
            }
            .frame(minWidth: 220)
        } detail: {
            // Main content based on selection
            switch selectedItem {
            case .date(let date):
                DayDetailView(
                    date: date,
                    viewModel: viewModel,
                    selectedSource: $selectedSource
                )
            case .weeklyProgress:
                WeeklyProgressView()
            case .allAnalyses:
                AllAnalysesView()
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .onAppear {
            viewModel.refresh()
        }
        .onChange(of: selectedItem) { newItem in
            if case .date(let date) = newItem {
                viewModel.loadRecords(for: date)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }
}

// MARK: - Day Detail View

struct DayDetailView: View {
    let date: Date
    @ObservedObject var viewModel: RecordsViewModel
    @Binding var selectedSource: RecordSource?
    @State private var showAnalysisDetail = false
    @State private var isAnalyzing = false
    @StateObject private var analysisViewModel = DayAnalysisViewModel()
    
    private var filteredRecords: [Record] {
        viewModel.records(for: date).filter { record in
            selectedSource == nil || record.source == selectedSource
        }
    }
    
    private var totalCharacters: Int {
        filteredRecords.reduce(0) { $0 + $1.content.count }
    }
    
    var body: some View {
            VStack(spacing: 0) {
            // Header
                HStack {
                Text(formatDateHeader(date))
                        .font(.title2)
                        .fontWeight(.semibold)

                    Spacer()

                    // Filter
                Picker("", selection: $selectedSource) {
                        Text("All").tag(RecordSource?.none)
                        Text("Keyboard").tag(RecordSource?.some(.keyboard))
                        Text("Wispr").tag(RecordSource?.some(.wispr))
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)

                    Button(action: viewModel.refresh) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                .help("Refresh")
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))

                Divider()

            // Main content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // AI Analysis Card
                    DayAnalysisCard(
                        date: date,
                        viewModel: analysisViewModel,
                        isAnalyzing: $isAnalyzing,
                        showDetail: $showAnalysisDetail
                    )
                    .padding(.horizontal)
                    .padding(.top)
                    
                    // Records Section
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Records")
                                .font(.headline)
                            Spacer()
                            Text("\(filteredRecords.count) entries")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal)
                        
                if filteredRecords.isEmpty {
                            EmptyRecordsView()
                                .frame(minHeight: 200)
                        } else {
                            LazyVStack(alignment: .leading, spacing: 10) {
                                ForEach(filteredRecords) { record in
                                    RecordCardView(record: record)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }
                .padding(.bottom)
            }
            
            Divider()
            
            // Status bar
            StatusBarView(
                isRecording: viewModel.isRecording,
                recordCount: filteredRecords.count,
                characterCount: totalCharacters
            )
        }
        .onAppear {
            analysisViewModel.loadAnalysis(for: date)
        }
        .onChange(of: date) { newDate in
            // Force clear and reload when date changes
            analysisViewModel.loadAnalysis(for: newDate)
        }
        .id("\(date.timeIntervalSince1970)") // Force view refresh when date changes
        .sheet(isPresented: $showAnalysisDetail) {
            AnalysisDetailSheet(date: date, viewModel: analysisViewModel)
        }
    }
    
    private func formatDateHeader(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE, MMM d"
            return formatter.string(from: date)
        }
    }
}

// MARK: - Day Analysis Card

class DayAnalysisViewModel: ObservableObject {
    @Published var analysisResult: AnalysisResult?
    @Published var hasAnalysis: Bool = false
    @Published var error: String?
    
    private let database = DatabaseService.shared
    private let aiService = AIAnalysisService.shared
    
    func loadAnalysis(for date: Date) {
        // Clear previous results first
        analysisResult = nil
        hasAnalysis = false
        error = nil
        
        // Check if analysis exists for this specific date
        hasAnalysis = database.hasAnalysis(for: date)
        
        if hasAnalysis {
            let insights = database.fetchInsights(for: date)
            if let latestInsight = insights.first,
               let data = latestInsight.content.data(using: .utf8),
               let result = try? JSONDecoder().decode(AnalysisResult.self, from: data) {
                analysisResult = result
            } else {
                // If we can't decode, clear the flag
                hasAnalysis = false
                analysisResult = nil
            }
        }
    }
    
    func runAnalysis(for date: Date) async {
        do {
            let result = try await aiService.analyzeRecords(for: date)
            await MainActor.run {
                self.analysisResult = result
                self.hasAnalysis = true
                self.error = nil
                // Reload to ensure UI is updated
                self.loadAnalysis(for: date)
            }
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
            }
        }
    }
}

struct DayAnalysisCard: View {
    let date: Date
    @ObservedObject var viewModel: DayAnalysisViewModel
    @Binding var isAnalyzing: Bool
    @Binding var showDetail: Bool
    
    private var aiService: AIAnalysisService { AIAnalysisService.shared }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "sparkles")
                    .foregroundColor(.purple)
                Text("AI Analysis")
                    .font(.headline)
                
                Spacer()
                
                if viewModel.hasAnalysis {
                    HStack(spacing: 8) {
                        Button(action: {
                            Task {
                                isAnalyzing = true
                                await viewModel.runAnalysis(for: date)
                                isAnalyzing = false
                            }
                        }) {
                            HStack(spacing: 4) {
                                if isAnalyzing {
                                    ProgressView()
                                        .scaleEffect(0.6)
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                }
                                Text(isAnalyzing ? "Re-analyzing..." : "Re-analyze")
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(isAnalyzing)
                        
                        Button("View Details") {
                            showDetail = true
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
            
            if let error = viewModel.error {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            } else if let result = viewModel.analysisResult {
                // Show analysis summary
                HStack(spacing: 16) {
                    // Score
                    VStack {
                        Text("\(result.overallScore)")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(scoreColor(result.overallScore))
                        Text("Score")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .frame(width: 60)
                    
                    Divider()
                        .frame(height: 40)
                    
                    // Summary
                    VStack(alignment: .leading, spacing: 4) {
                        Text(result.summary)
                            .font(.subheadline)
                            .lineLimit(2)
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 12) {
                            if !result.grammarIssues.isEmpty {
                                Label("\(result.grammarIssues.count) grammar", systemImage: "text.badge.xmark")
                                    .font(.caption2)
                                    .foregroundColor(.red)
                            }
                            if !result.phrasingIssues.isEmpty {
                                Label("\(result.phrasingIssues.count) phrasing", systemImage: "text.quote")
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                            }
                            if !result.positives.isEmpty {
                                Label("\(result.positives.count) positives", systemImage: "checkmark.circle")
                                    .font(.caption2)
                                    .foregroundColor(.green)
                            }
                        }
                    }
                }
            } else if !aiService.hasAPIKey {
                // No API key
                HStack {
                    Image(systemName: "key")
                        .foregroundColor(.orange)
                    Text("Configure your API key in Settings to enable AI analysis")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                // Not analyzed yet
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("No analysis yet")
                            .font(.subheadline)
                        Text("Analyze your English writing and speaking for this day")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        Task {
                            isAnalyzing = true
                            await viewModel.runAnalysis(for: date)
                            isAnalyzing = false
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
                    .disabled(isAnalyzing)
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(viewModel.hasAnalysis ? Color.purple.opacity(0.3) : Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }
    
    private func scoreColor(_ score: Int) -> Color {
        switch score {
        case 8...10: return .green
        case 6...7: return .yellow
        default: return .orange
        }
    }
}

// MARK: - Analysis Detail Sheet

struct AnalysisDetailSheet: View {
    let date: Date
    @ObservedObject var viewModel: DayAnalysisViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("AI Analysis Details")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            if let result = viewModel.analysisResult {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Summary
                        AnalysisSectionCard(title: "Summary", icon: "doc.text", color: .blue) {
                            Text(result.summary)
                                .font(.body)
                        }
                        
                        // Grammar Issues
                        if !result.grammarIssues.isEmpty {
                            AnalysisSectionCard(title: "Grammar Issues", icon: "text.badge.xmark", color: .red) {
                                ForEach(Array(result.grammarIssues.enumerated()), id: \.offset) { _, issue in
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(issue.original)
                                                .strikethrough()
                                                .foregroundColor(.red)
                                            Image(systemName: "arrow.right")
                                                .foregroundColor(.secondary)
                                            Text(issue.corrected)
                                                .foregroundColor(.green)
                                        }
                                        Text(issue.explanation)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        }
                        
                        // Phrasing Issues
                        if !result.phrasingIssues.isEmpty {
                            AnalysisSectionCard(title: "Phrasing Suggestions", icon: "text.quote", color: .orange) {
                                ForEach(Array(result.phrasingIssues.enumerated()), id: \.offset) { _, issue in
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(issue.original)
                                                .foregroundColor(.orange)
                                            Image(systemName: "arrow.right")
                                                .foregroundColor(.secondary)
                                            Text(issue.natural)
                                                .foregroundColor(.green)
                                        }
                                        Text(issue.context)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        }
                        
                        // Positives
                        if !result.positives.isEmpty {
                            AnalysisSectionCard(title: "What You Did Well", icon: "checkmark.circle", color: .green) {
                                ForEach(result.positives, id: \.self) { positive in
                                    HStack(alignment: .top) {
                                        Image(systemName: "star.fill")
                                            .foregroundColor(.yellow)
                                            .font(.caption)
                                        Text(positive)
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .frame(minWidth: 600, minHeight: 500)
    }
}

struct AnalysisSectionCard<Content: View>: View {
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
}

// MARK: - Weekly Progress View

struct WeeklyProgressView: View {
    @StateObject private var viewModel = WeeklyProgressViewModel()
    @State private var isGenerating = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Weekly Progress")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                        Spacer()
                
                Button(action: {
                    Task {
                        isGenerating = true
                        await viewModel.generateReport()
                        isGenerating = false
                    }
                }) {
                    HStack {
                        if isGenerating {
                            ProgressView()
                                .scaleEffect(0.7)
                } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text(isGenerating ? "Generating..." : "Generate Report")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isGenerating || !AIAnalysisService.shared.hasAPIKey)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
                    ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Statistics
                    WeeklyStatsCard(stats: viewModel.stats)
                    
                    // Report
                    if let report = viewModel.report {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "doc.text.magnifyingglass")
                                    .foregroundColor(.purple)
                                Text("Weekly Report")
                                    .font(.headline)
                            }
                            Text(report)
                                .font(.body)
                                .textSelection(.enabled)
                        }
                        .padding()
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(12)
                    } else if !AIAnalysisService.shared.hasAPIKey {
                        NoAPIKeyCard()
                    } else {
                        VStack {
                            Image(systemName: "chart.bar.doc.horizontal")
                                .font(.system(size: 48))
                                .foregroundColor(.secondary)
                            Text("Generate a report to see your weekly progress")
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    }
                    
                    // Recent Analyses List
                    if !viewModel.recentInsights.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Recent Analyses")
                                .font(.headline)
                            
                            ForEach(viewModel.recentInsights) { insight in
                                RecentAnalysisRow(insight: insight)
                            }
                        }
                        .padding()
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(12)
                    }
                }
                .padding()
            }
        }
        .onAppear {
            viewModel.loadData()
        }
    }
}

class WeeklyProgressViewModel: ObservableObject {
    @Published var stats = WeeklyStats()
    @Published var report: String?
    @Published var recentInsights: [Insight] = []
    @Published var error: String?
    
    struct WeeklyStats {
        var daysAnalyzed: Int = 0
        var totalRecords: Int = 0
        var totalCharacters: Int = 0
        var averageScore: Double = 0
    }
    
    private let database = DatabaseService.shared
    private let aiService = AIAnalysisService.shared
    
    func loadData() {
        recentInsights = database.fetchAllInsights(limit: 7)
        calculateStats()
    }
    
    private func calculateStats() {
        stats.daysAnalyzed = recentInsights.count
        stats.totalRecords = recentInsights.reduce(0) { $0 + $1.recordCount }
        stats.totalCharacters = recentInsights.reduce(0) { $0 + $1.characterCount }
        
        var scores: [Int] = []
        for insight in recentInsights {
            if let data = insight.content.data(using: .utf8),
               let result = try? JSONDecoder().decode(AnalysisResult.self, from: data) {
                scores.append(result.overallScore)
            }
        }
        if !scores.isEmpty {
            stats.averageScore = Double(scores.reduce(0, +)) / Double(scores.count)
        }
    }
    
    func generateReport() async {
        do {
            let generatedReport = try await aiService.generateWeeklyProgress()
            await MainActor.run {
                self.report = generatedReport
                self.error = nil
            }
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
            }
        }
    }
}

struct WeeklyStatsCard: View {
    let stats: WeeklyProgressViewModel.WeeklyStats
    
    var body: some View {
        HStack(spacing: 20) {
            StatItem(title: "Days", value: "\(stats.daysAnalyzed)", icon: "calendar")
            StatItem(title: "Records", value: "\(stats.totalRecords)", icon: "doc.text")
            StatItem(title: "Characters", value: formatNumber(stats.totalCharacters), icon: "character.cursor.ibeam")
            if stats.averageScore > 0 {
                StatItem(title: "Avg Score", value: String(format: "%.1f", stats.averageScore), icon: "star.fill")
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
    
    private func formatNumber(_ num: Int) -> String {
        if num >= 1000 {
            return String(format: "%.1fK", Double(num) / 1000)
        }
        return "\(num)"
    }
}

struct StatItem: View {
    let title: String
    let value: String
    let icon: String
    
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.blue)
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct RecentAnalysisRow: View {
    let insight: Insight
    
    private var score: Int? {
        guard let data = insight.content.data(using: .utf8),
              let result = try? JSONDecoder().decode(AnalysisResult.self, from: data) else {
            return nil
        }
        return result.overallScore
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(formatDate(insight.dateRangeStart))
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("\(insight.recordCount) records")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if let s = score {
                Text("\(s)/10")
                    .font(.caption)
                    .fontWeight(.bold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(scoreColor(s).opacity(0.2))
                    .cornerRadius(6)
            }
        }
        .padding(.vertical, 4)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
    
    private func scoreColor(_ score: Int) -> Color {
        switch score {
        case 8...10: return .green
        case 6...7: return .yellow
        default: return .orange
        }
    }
}

// MARK: - All Analyses View

struct AllAnalysesView: View {
    @State private var insights: [Insight] = []
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("All Analyses")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Text("\(insights.count) analyses")
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

                Divider()

            if insights.isEmpty {
                VStack {
                    Spacer()
                    Image(systemName: "sparkles")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No analyses yet")
                        .font(.title3)
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                    Text("Analyze your daily records to see them here")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                List(insights) { insight in
                    AnalysisHistoryRow(insight: insight)
                }
                .listStyle(.plain)
            }
        }
        .onAppear {
            insights = DatabaseService.shared.fetchAllInsights(limit: 100)
        }
    }
}

struct AnalysisHistoryRow: View {
    let insight: Insight
    @State private var isExpanded = false
    
    private var analysisResult: AnalysisResult? {
        guard let data = insight.content.data(using: .utf8),
              let result = try? JSONDecoder().decode(AnalysisResult.self, from: data) else {
            return nil
        }
        return result
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
                HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(formatDate(insight.dateRangeStart))
                        .font(.headline)
                    Text("\(insight.recordCount) records • \(insight.characterCount) chars")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if let result = analysisResult {
                    HStack(spacing: 4) {
                        Text("\(result.overallScore)")
                            .font(.title3)
                            .fontWeight(.bold)
                        Text("/10")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Button(action: { isExpanded.toggle() }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                }
                .buttonStyle(.borderless)
            }
            
            if isExpanded, let result = analysisResult {
                Divider()
                Text(result.summary)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                if !result.grammarIssues.isEmpty {
                    Text("\(result.grammarIssues.count) grammar issues")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d, yyyy"
        return formatter.string(from: date)
    }
}

// MARK: - Helper Views

struct NoAPIKeyCard: View {
    var body: some View {
        HStack {
            Image(systemName: "key")
                .font(.title2)
                .foregroundColor(.orange)
            VStack(alignment: .leading) {
                Text("API Key Required")
                    .font(.headline)
                Text("Configure your Anthropic or OpenAI API key in Settings")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
    }
}

struct EmptyRecordsView: View {
    var body: some View {
        VStack {
            Spacer()
            Image(systemName: "doc.text")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("No records for this day")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.top, 8)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

struct StatusBarView: View {
    let isRecording: Bool
    let recordCount: Int
    let characterCount: Int
    
    var body: some View {
                HStack {
                    Circle()
                .fill(isRecording ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
            Text(isRecording ? "Recording" : "Paused")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

            Text("\(recordCount) records")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("•")
                        .foregroundColor(.secondary)

            Text("\(characterCount) characters")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(NSColor.controlBackgroundColor))
            }
        }

// MARK: - Profile Section

struct ProfileSectionView: View {
    @Binding var showSettings: Bool
    
    private var aiService: AIAnalysisService {
        AIAnalysisService.shared
    }
    
    var body: some View {
        Button(action: {
            showSettings = true
        }) {
            HStack {
                Image(systemName: "person.circle.fill")
                    .font(.title2)
                    .foregroundColor(.blue)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Settings")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    if aiService.hasAPIKey {
                        Text(aiService.activeProviderName)
                            .font(.caption2)
                            .foregroundColor(.green)
                    } else {
                        Text("No API key")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
        .padding(.horizontal, 8)
    }
}

// MARK: - Date Row View

struct DateRowView: View {
    let date: Date
    let recordCount: Int
    var hasAnalysis: Bool = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                Text(dayString)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    if hasAnalysis {
                        Image(systemName: "sparkles")
                            .font(.caption2)
                            .foregroundColor(.purple)
                    }
                }
                Text(dateString)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Text("\(recordCount)")
                .font(.caption)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.2))
                .cornerRadius(8)
        }
        .padding(.vertical, 2)
    }

    private var dayString: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE"
            return formatter.string(from: date)
        }
    }

    private var dateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }
}

// MARK: - Record Card View

struct RecordCardView: View {
    let record: Record

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // Source badge
                HStack(spacing: 4) {
                    Image(systemName: sourceIcon)
                    Text(record.source.rawValue.capitalized)
                }
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(sourceColor)
                .cornerRadius(6)

                // App name
                    Text(record.activeApp)
                .font(.caption)
                .foregroundColor(.secondary)

                Spacer()

                // Time
                Text(timeString)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Content
            Text(record.content)
                .font(.body)
                .textSelection(.enabled)
                .lineLimit(nil)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }

    private var sourceIcon: String {
        switch record.source {
        case .keyboard: return "keyboard"
        case .wispr: return "mic.fill"
        }
    }

    private var sourceColor: Color {
        switch record.source {
        case .keyboard: return .blue
        case .wispr: return .green
        }
    }

    private var timeString: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: record.timestamp)
    }
}

// MARK: - ViewModel

class RecordsViewModel: ObservableObject {
    @Published private var recordsByDate: [Date: [Record]] = [:]
    @Published var availableDates: [Date] = []
    @Published var isRecording: Bool = true

    private let database = DatabaseService.shared
    
    init() {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("DatabaseDidChange"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async {
                self?.refresh()
            }
        }
    }

    func refresh() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.loadAllDates()
            self.isRecording = !(RecordManager.shared.isPaused)
        }
    }
    
    func removeDuplicates() {
        database.removeDuplicateRecords()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.refresh()
        }
    }

    func loadAllDates() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let calendar = Calendar.current
            let uniqueDates = self.database.fetchAllUniqueDates()
            
            DispatchQueue.main.async {
                self.availableDates = uniqueDates.sorted(by: >)
                let today = calendar.startOfDay(for: Date())
                if !self.availableDates.contains(where: { calendar.isDate($0, inSameDayAs: today) }) {
                    self.availableDates.insert(today, at: 0)
                }
            }
        }
    }

    func loadRecords(for date: Date) {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let records = self.database.fetchRecords(for: dayStart)
            
            DispatchQueue.main.async {
                self.recordsByDate[dayStart] = records
            }
        }
    }

    func records(for date: Date) -> [Record] {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        
        if recordsByDate[dayStart] == nil {
            loadRecords(for: dayStart)
        }
        
        return recordsByDate[dayStart] ?? []
    }

    func recordCount(for date: Date) -> Int {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        return database.getRecordCount(for: dayStart)
    }
}

#Preview {
    ContentView()
}
