import SwiftUI

struct RecordingsView: View {
    @State private var selectedDate: Date = Date()
    @State private var recordings: [VoiceRecording] = []

    private let database = DatabaseService.shared

    var body: some View {
        VStack(spacing: 0) {
            // Header with date navigation
            HStack {
                // Previous day button
                Button(action: { navigateDay(by: -1) }) {
                    Image(systemName: "chevron.left")
                        .font(.title3)
                }
                .buttonStyle(.borderless)
                .help("Previous day")

                Spacer()

                // Date display with picker
                VStack(spacing: 2) {
                    Text(formatDateHeader(selectedDate))
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text(formatDateSubtitle(selectedDate))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Next day button
                Button(action: { navigateDay(by: 1) }) {
                    Image(systemName: "chevron.right")
                        .font(.title3)
                }
                .buttonStyle(.borderless)
                .disabled(Calendar.current.isDateInToday(selectedDate))
                .help("Next day")

                // Date picker
                DatePicker("", selection: $selectedDate, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .frame(width: 30)
                    .onChange(of: selectedDate) { _ in
                        loadRecordings()
                    }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Placeholder content for recording controls - will be expanded in US-009
            VStack {
                Spacer()
                Image(systemName: "mic.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)
                Text("Voice Recordings")
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
                Text("Record your voice and get transcriptions")
                    .font(.caption)
                    .foregroundColor(.secondary)

                // Recordings count for selected date
                if !recordings.isEmpty {
                    Text("\(recordings.count) recording\(recordings.count == 1 ? "" : "s") for this day")
                        .font(.caption)
                        .foregroundColor(.blue)
                        .padding(.top, 16)
                }

                Spacer()
            }
        }
        .onAppear {
            loadRecordings()
        }
    }

    // MARK: - Date Navigation

    private func navigateDay(by offset: Int) {
        if let newDate = Calendar.current.date(byAdding: .day, value: offset, to: selectedDate) {
            selectedDate = newDate
            loadRecordings()
        }
    }

    private func loadRecordings() {
        let dayStart = Calendar.current.startOfDay(for: selectedDate)
        DispatchQueue.global(qos: .userInitiated).async {
            let fetchedRecordings = database.getRecordingsForDate(dayStart)
            DispatchQueue.main.async {
                self.recordings = fetchedRecordings
            }
        }
    }

    // MARK: - Date Formatting

    private func formatDateHeader(_ date: Date) -> String {
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

    private func formatDateSubtitle(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }
}

#Preview {
    RecordingsView()
}
