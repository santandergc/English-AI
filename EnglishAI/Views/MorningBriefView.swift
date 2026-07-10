import SwiftUI

/// The daily coach card. Rendered entirely from the local morning_briefs row
/// (zero API calls at open time). Fallbacks per design: no brief today ->
/// show the latest brief with an explicit date badge; no briefs at all ->
/// the card hides itself (the popover empty state covers first-run).
struct MorningBriefView: View {
    /// Launches a practice session targeting the brief's focus item
    var onPracticeFocus: (FocusItem) -> Void = { _ in }

    @State private var brief: MorningBrief?
    @State private var focusItem: FocusItem?
    @State private var isStale = false

    var body: some View {
        Group {
            if let brief = brief {
                card(for: brief)
            }
        }
        .onAppear(perform: load)
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("FocusQueueDidChange"))) { _ in
            load()
        }
    }

    private func load() {
        let db = DatabaseService.shared
        if let today = db.getMorningBrief(forDate: Date()) {
            brief = today
            isStale = false
        } else if let latest = db.getLatestMorningBrief() {
            brief = latest
            isStale = true
        } else {
            brief = nil
        }
        focusItem = brief.flatMap { db.getFocusItem(byId: $0.focusItemId) }
    }

    private func card(for brief: MorningBrief) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(brief.forDate, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                        .font(.caption)
                        .textCase(.uppercase)
                        .foregroundColor(.secondary)

                    if isStale {
                        Text("previous brief")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.15))
                            .foregroundColor(.orange)
                            .cornerRadius(4)
                    }
                    Spacer()
                    Image(systemName: "sun.max.fill")
                        .foregroundColor(.orange)
                }
                Text("One thing today, Cristóbal")
                    .font(.title3)
                    .fontWeight(.bold)
            }

            Divider()

            // Today's focus
            VStack(alignment: .leading, spacing: 6) {
                Text("TODAY'S FOCUS")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)

                Text(brief.headline)
                    .font(.headline)

                if let focusItem = focusItem {
                    HStack(spacing: 6) {
                        FocusKindChip(kind: focusItem.kind)
                        Text(focusItem.targetPhrase)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }

                    Text("Receipt: \(focusItem.rationale)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
                        .overlay(
                            Rectangle()
                                .fill(Color.secondary.opacity(0.5))
                                .frame(width: 3),
                            alignment: .leading
                        )
                }

                if !brief.mission.isEmpty {
                    Label(brief.mission, systemImage: "target")
                        .font(.subheadline)
                        .padding(.top, 2)
                }
            }

            // Yesterday's wins — quoting real sentences is the magic moment
            if !brief.wins.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text("YESTERDAY'S WINS")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)

                    ForEach(brief.wins, id: \.self) { win in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "checkmark")
                                .font(.caption)
                                .foregroundColor(.green)
                            Text(win)
                                .font(.caption)
                        }
                    }
                }
            }

            // CTA
            if let focusItem = focusItem, FocusItemStatus.activeStatuses.contains(focusItem.status) {
                Button {
                    onPracticeFocus(focusItem)
                } label: {
                    HStack {
                        Text("Practice today's focus")
                        Image(systemName: "arrow.right")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
}
