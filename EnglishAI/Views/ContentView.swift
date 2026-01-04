import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = RecordsViewModel()
    @State private var selectedDate: Date = Date()
    @State private var selectedSource: RecordSource? = nil
    @State private var searchText: String = ""

    var body: some View {
        NavigationSplitView {
            // Sidebar with dates
            VStack(alignment: .leading, spacing: 0) {
                Text("History")
                    .font(.headline)
                    .padding(.horizontal)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                List(viewModel.availableDates, id: \.self, selection: $selectedDate) { date in
                    DateRowView(date: date, recordCount: viewModel.recordCount(for: date))
                        .tag(date)
                }
                .listStyle(.sidebar)
            }
            .frame(minWidth: 200)
        } detail: {
            // Main content area
            VStack(spacing: 0) {
                // Toolbar
                HStack {
                    Text(formatDateHeader(selectedDate))
                        .font(.title2)
                        .fontWeight(.semibold)

                    Spacer()

                    // Search
                    TextField("Search...", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)

                    // Filter
                    Picker("Source", selection: $selectedSource) {
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
                    .help("Refresh records")
                    
                    Button(action: viewModel.removeDuplicates) {
                        Image(systemName: "trash.slash")
                    }
                    .buttonStyle(.borderless)
                    .help("Remove duplicate records")
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))

                Divider()

                // Records list
                if filteredRecords.isEmpty {
                    VStack {
                        Spacer()
                        Image(systemName: "doc.text")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("No records for this day")
                            .font(.title3)
                            .foregroundColor(.secondary)
                            .padding(.top, 8)
                        Spacer()
                    }
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(filteredRecords) { record in
                                RecordCardView(record: record)
                            }
                        }
                        .padding()
                    }
                }

                Divider()

                // Status bar
                HStack {
                    Circle()
                        .fill(viewModel.isRecording ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(viewModel.isRecording ? "Recording" : "Paused")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    Text("\(filteredRecords.count) records")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("•")
                        .foregroundColor(.secondary)

                    Text("\(totalCharacters) characters")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(NSColor.controlBackgroundColor))
            }
        }
        .frame(minWidth: 800, minHeight: 500)
        .onAppear {
            viewModel.refresh()
        }
        .onChange(of: selectedDate) { newDate in
            viewModel.loadRecords(for: newDate)
        }
    }

    private var filteredRecords: [Record] {
        viewModel.records(for: selectedDate).filter { record in
            let matchesSearch = searchText.isEmpty ||
                record.content.localizedCaseInsensitiveContains(searchText) ||
                record.activeApp.localizedCaseInsensitiveContains(searchText)

            let matchesSource = selectedSource == nil || record.source == selectedSource

            return matchesSearch && matchesSource
        }
    }

    private var totalCharacters: Int {
        filteredRecords.reduce(0) { $0 + $1.content.count }
    }

    private func formatDateHeader(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .full
            return formatter.string(from: date)
        }
    }
}

struct DateRowView: View {
    let date: Date
    let recordCount: Int

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(dayString)
                    .font(.headline)
                Text(dateString)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Text("\(recordCount)")
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.2))
                .cornerRadius(10)
        }
        .padding(.vertical, 4)
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
                HStack(spacing: 4) {
                    Image(systemName: "app")
                    Text(record.activeApp)
                }
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
        // Listen for database changes
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("DatabaseDidChange"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }
    }

    func refresh() {
        loadAllDates()
        isRecording = !(RecordManager.shared.isPaused)
    }
    
    func removeDuplicates() {
        database.removeDuplicateRecords()
        // Wait a moment for the cleanup to complete, then refresh
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.refresh()
        }
    }

    func loadAllDates() {
        let allRecords = database.fetchRecords(limit: 10000)
        let calendar = Calendar.current

        var dateSet = Set<Date>()
        var grouped: [Date: [Record]] = [:]

        for record in allRecords {
            let dayStart = calendar.startOfDay(for: record.timestamp)
            dateSet.insert(dayStart)

            if grouped[dayStart] == nil {
                grouped[dayStart] = []
            }
            grouped[dayStart]?.append(record)
        }

        recordsByDate = grouped
        availableDates = dateSet.sorted(by: >)

        // Ensure today is always in the list
        let today = calendar.startOfDay(for: Date())
        if !availableDates.contains(today) {
            availableDates.insert(today, at: 0)
        }
    }

    func loadRecords(for date: Date) {
        // Records are already loaded in loadAllDates
    }

    func records(for date: Date) -> [Record] {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        return recordsByDate[dayStart] ?? []
    }

    func recordCount(for date: Date) -> Int {
        records(for: date).count
    }
}

#Preview {
    ContentView()
}
