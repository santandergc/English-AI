import SwiftUI

/// The receipts view: one focus item's life story. Practice is a modest line;
/// wild uses are the headlines. This is why mastery feels earned, not gamified.
struct FocusItemDetailView: View {
    let item: FocusItem

    @State private var evidence: [FocusEvidence] = []
    @State private var verifiedUses = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            lifecycleStrip
            Divider()
            timeline
        }
        .frame(minWidth: 340, maxWidth: .infinity)
        .onAppear(perform: load)
    }

    private func load() {
        guard let itemId = item.id else { return }
        evidence = DatabaseService.shared.getFocusEvidence(forItem: itemId)
        verifiedUses = DatabaseService.shared.countVerifiedCorrectUses(forItem: itemId)
    }

    private var header: some View {
        HStack {
            Text(item.targetPhrase)
                .font(.headline)
                .lineLimit(2)
            Spacer()
            FocusKindChip(kind: item.kind)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: Lifecycle strip

    private var stages: [FocusItemStatus] {
        // Fix-items skip `spotted`: there is no single "use" to spot
        item.kind == .enrich
            ? [.candidate, .queued, .practicing, .spotted, .adopted]
            : [.candidate, .queued, .practicing, .adopted]
    }

    private var lifecycleStrip: some View {
        HStack(spacing: 4) {
            ForEach(stages, id: \.self) { stage in
                Text(stageLabel(stage))
                    .font(.system(size: 9))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(stage == item.status ? Color.primary : Color.clear)
                    .foregroundColor(stage == item.status ? Color(NSColor.windowBackgroundColor) : stageColor(stage))
                    .overlay(Capsule().stroke(Color.secondary.opacity(0.4), lineWidth: stage == item.status ? 0 : 1))
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func stageLabel(_ stage: FocusItemStatus) -> String {
        if stage == .spotted && item.kind == .enrich {
            return "in the wild \(verifiedUses)/\(FocusQueueService.adoptionThreshold)"
        }
        return stage.rawValue
    }

    private func stageColor(_ stage: FocusItemStatus) -> Color {
        let currentIndex = stages.firstIndex(of: item.status) ?? 0
        let stageIndex = stages.firstIndex(of: stage) ?? 0
        return stageIndex < currentIndex ? .primary : .secondary
    }

    // MARK: Timeline

    private var timeline: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                TimelineEntry(
                    when: item.createdAt,
                    title: "Entered as candidate.",
                    detail: item.rationale,
                    icon: "sparkle"
                )

                ForEach(evidence) { row in
                    TimelineEntry(
                        when: row.occurredAt,
                        title: evidenceTitle(row),
                        detail: evidenceDetail(row),
                        icon: evidenceIcon(row)
                    )
                }

                if item.kind == .enrich && FocusItemStatus.activeStatuses.contains(item.status) {
                    let remaining = max(0, FocusQueueService.adoptionThreshold - verifiedUses)
                    TimelineEntry(
                        when: nil,
                        title: remaining == 0 ? "Adoption pending next check" : "\(remaining) more verified use\(remaining == 1 ? "" : "s") → adopted",
                        detail: "A slot opens when this graduates.",
                        icon: "flag.checkered"
                    )
                }
            }
            .padding(.vertical, 6)
        }
        .frame(maxHeight: 320)
    }

    private func evidenceTitle(_ row: FocusEvidence) -> String {
        switch row.evidenceType {
        case .overuse: return "Receipt: the pattern in your own words"
        case .mistake: return "Error occurrence" + (row.app.map { " — \($0)" } ?? "")
        case .correctUse:
            return row.verified
                ? "Wild use ✓ verified" + (row.app.map { " — \($0)" } ?? "")
                : "Sighting (pending review)" + (row.app.map { " — \($0)" } ?? "")
        case .nearMiss: return "Near miss — attempted, not quite right"
        case .practice: return "Practice"
        }
    }

    private func evidenceDetail(_ row: FocusEvidence) -> String {
        row.evidenceType == .practice ? row.excerpt : "\u{201C}\(row.excerpt.prefix(140))\u{201D}"
    }

    private func evidenceIcon(_ row: FocusEvidence) -> String {
        switch row.evidenceType {
        case .overuse: return "repeat"
        case .mistake: return "exclamationmark.triangle"
        case .correctUse: return row.verified ? "checkmark.seal.fill" : "eye"
        case .nearMiss: return "arrow.uturn.left"
        case .practice: return "dumbbell"
        }
    }
}

private struct TimelineEntry: View {
    let when: Date?
    let title: String
    let detail: String
    let icon: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(title)
                        .font(.caption)
                        .fontWeight(.medium)
                    Spacer()
                    if let when = when {
                        Text(when, format: .dateTime.month(.abbreviated).day())
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                Text(detail)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }
}
