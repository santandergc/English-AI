import SwiftUI

// MARK: - Focus Queue Section (native, lives inside PracticeView)

/// The 20/80 queue as a standard Practice section — same collapsible header,
/// card background, and corner radius as the existing sections. Up to 5 items,
/// each carrying its receipt and verified wild-use dots.
struct FocusQueueSection: View {
    @State private var queue: [(item: FocusItem, verifiedUses: Int)] = []
    @State private var selectedItem: FocusItem?
    @State private var isExpanded = true
    @State private var isAnalyzing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header with collapse toggle (mirrors the other sections)
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }) {
                HStack {
                    Image(systemName: "scope")
                        .foregroundColor(.green)
                    Text("Focus Queue")
                        .font(.headline)
                        .foregroundColor(.primary)

                    Spacer()

                    Text("\(queue.count)/\(FocusQueueService.maxActiveItems)")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(4)

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                if queue.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 8) {
                        ForEach(queue, id: \.item.id) { entry in
                            Button {
                                selectedItem = entry.item
                            } label: {
                                FocusQueueRow(item: entry.item, verifiedUses: entry.verifiedUses)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("FocusQueueDidChange"))) { _ in
            refresh()
        }
        .sheet(item: $selectedItem) { item in
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button("Done") { selectedItem = nil }
                        .keyboardShortcut(.defaultAction)
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)

                FocusItemDetailView(item: item)
            }
            .frame(width: 420, height: 480)
        }
    }

    private func refresh() {
        queue = FocusQueueService.shared.activeQueueSnapshot()
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "scope")
                .font(.system(size: 32))
                .foregroundColor(.secondary)
            Text("The coach is reading your writing.")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text("Your first focus queue arrives with the next analysis.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            if isAnalyzing {
                ProgressView()
                    .controlSize(.small)
                    .padding(.top, 4)
            } else {
                Button("Analyze Now") {
                    runAnalysisNow()
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private func runAnalysisNow() {
        isAnalyzing = true
        Task {
            let calendar = Calendar.current
            let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: Date())) ?? Date()
            // Seed from yesterday when it's still unanalyzed, otherwise today
            let target = AIAnalysisService.shared.hasAnalysis(for: yesterday) ? Date() : yesterday
            _ = try? await AIAnalysisService.shared.analyzeRecords(for: target)
            await MainActor.run {
                isAnalyzing = false
                refresh()
            }
        }
    }
}

// MARK: - Queue Row

struct FocusQueueRow: View {
    let item: FocusItem
    let verifiedUses: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(item.targetPhrase)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                Spacer()
                FocusKindChip(kind: item.kind)
            }

            HStack(spacing: 6) {
                Text(statusLine)
                    .font(.caption)
                    .foregroundColor(.secondary)
                if item.kind == .enrich {
                    WildUseDots(verified: verifiedUses)
                }
            }

            Text(item.rationale)
                .font(.caption2)
                .italic()
                .foregroundColor(Color.secondary.opacity(0.8))
                .lineLimit(1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
        .contentShape(Rectangle())
    }

    private var statusLine: String {
        switch item.status {
        case .queued: return "queued — practice to activate"
        case .practicing: return "practicing → in the wild"
        case .spotted: return verifiedUses >= 2 ? "in the wild — 1 more and it's yours" : "in the wild"
        default: return item.status.rawValue
        }
    }
}

// MARK: - Shared bits

struct FocusKindChip: View {
    let kind: FocusItemKind

    var body: some View {
        Text(kind == .enrich ? "ENRICH" : "FIX")
            .font(.system(size: 8, weight: .semibold))
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.secondary.opacity(0.6), lineWidth: 1))
            .foregroundColor(.secondary)
    }
}

/// Dots count VERIFIED wild uses only; pending sightings appear only in the
/// detail timeline (the design's honesty rule).
struct WildUseDots: View {
    let verified: Int

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<FocusQueueService.adoptionThreshold, id: \.self) { index in
                Circle()
                    .fill(index < verified ? Color.green : Color.secondary.opacity(0.25))
                    .frame(width: 6, height: 6)
            }
        }
    }
}
