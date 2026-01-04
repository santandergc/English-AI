import AppKit
import SwiftUI

class RecordsWindowController: NSWindowController {
    convenience init(records: [Record]) {
        let contentView = RecordsView(records: records)
        let hostingController = NSHostingController(rootView: contentView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 500),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        window.title = "EnglishAI - History"
        window.contentViewController = hostingController
        window.center()
        window.setFrameAutosaveName("RecordsWindow")

        self.init(window: window)
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct RecordsView: View {
    let records: [Record]
    @State private var searchText: String = ""
    @State private var selectedSource: RecordSource? = nil

    private var filteredRecords: [Record] {
        records.filter { record in
            let matchesSearch = searchText.isEmpty ||
                record.content.localizedCaseInsensitiveContains(searchText) ||
                record.activeApp.localizedCaseInsensitiveContains(searchText)

            let matchesSource = selectedSource == nil || record.source == selectedSource

            return matchesSearch && matchesSource
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                TextField("Search...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 200)

                Picker("Source", selection: $selectedSource) {
                    Text("All").tag(RecordSource?.none)
                    Text("Keyboard").tag(RecordSource?.some(.keyboard))
                    Text("Wispr").tag(RecordSource?.some(.wispr))
                }
                .pickerStyle(.segmented)
                .frame(width: 200)

                Spacer()

                Text("\(filteredRecords.count) records")
                    .foregroundColor(.secondary)
            }
            .padding()

            Divider()

            // Records list
            if filteredRecords.isEmpty {
                VStack {
                    Spacer()
                    Text("No records found")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                List(filteredRecords) { record in
                    RecordRowView(record: record)
                }
            }
        }
        .frame(minWidth: 500, minHeight: 300)
    }
}

struct RecordRowView: View {
    let record: Record

    private var sourceIcon: String {
        switch record.source {
        case .keyboard:
            return "keyboard"
        case .wispr:
            return "mic.fill"
        }
    }

    private var sourceColor: Color {
        switch record.source {
        case .keyboard:
            return .blue
        case .wispr:
            return .green
        }
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter.string(from: record.timestamp)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: sourceIcon)
                    .foregroundColor(sourceColor)

                Text(record.source.rawValue.capitalized)
                    .font(.caption)
                    .foregroundColor(sourceColor)

                Spacer()

                Text(record.activeApp)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(formattedDate)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text(record.content)
                .font(.body)
                .lineLimit(3)
        }
        .padding(.vertical, 4)
    }
}
