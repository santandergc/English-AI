import SwiftUI
import AppKit

@MainActor
final class SelectedTextReviewWindowController {
    static let shared = SelectedTextReviewWindowController()

    private var panel: NSPanel?
    private let viewModel = SelectedTextReviewViewModel()
    private let minimumPanelWidth: CGFloat = 430
    private let maximumPanelWidth: CGFloat = 780
    private let panelGap: CGFloat = 24
    private var lastAnchorRect: CGRect?
    private var lastSelectedText = ""
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?

    private init() {
        viewModel.onStateChanged = { [weak self] state in
            self?.resizePanel(for: state)
        }
    }

    func reviewCurrentSelection() {
        viewModel.startCapture()

        Task { @MainActor in
            do {
                try? await Task.sleep(nanoseconds: 120_000_000)
                let capture = try await SelectedTextReader.shared.captureSelectedText()
                lastAnchorRect = capture.selectionFrame
                lastSelectedText = capture.text
                showPanel(
                    near: capture.selectionFrame,
                    metrics: PanelMetrics(text: capture.text, correctionCount: 0, phase: .loading)
                )
                viewModel.review(capture)
            } catch {
                lastAnchorRect = nil
                lastSelectedText = ""
                showPanel(near: nil, metrics: PanelMetrics(text: "", correctionCount: 0, phase: .error))
                viewModel.showError(error)
            }
        }
    }

    private func showPanel(near anchorRect: CGRect?, metrics: PanelMetrics) {
        let size = panelSize(near: anchorRect, metrics: metrics)

        if panel == nil {
            let rootView = SelectedTextReviewPanelView(
                viewModel: viewModel,
                onRetry: { [weak self] in self?.reviewCurrentSelection() },
                onClose: { [weak self] in self?.closePanel() }
            )

            let hostingView = NSHostingView(rootView: rootView)
            hostingView.wantsLayer = true
            hostingView.layer?.backgroundColor = NSColor.clear.cgColor

            let newPanel = CompactSelectedTextReviewPanel(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            newPanel.contentView = hostingView
            newPanel.isReleasedWhenClosed = false
            newPanel.isOpaque = false
            newPanel.backgroundColor = .clear
            newPanel.hasShadow = true
            newPanel.level = .floating
            newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
            newPanel.hidesOnDeactivate = false
            newPanel.isMovableByWindowBackground = true
            panel = newPanel
        }

        guard let panel else { return }
        panel.setFrame(NSRect(origin: panelOrigin(near: anchorRect, size: size), size: size), display: true)
        panel.orderFrontRegardless()
        startOutsideClickMonitoring()
    }

    private func resizePanel(for state: SelectedTextReviewViewModel.State) {
        guard let panel else { return }

        let metrics: PanelMetrics
        let anchorRect: CGRect?

        switch state {
        case .result(let capture, let review):
            anchorRect = capture.selectionFrame ?? lastAnchorRect
            metrics = PanelMetrics(
                text: review.originalText,
                correctionCount: review.corrections.count,
                phase: .result
            )
        case .loading:
            anchorRect = lastAnchorRect
            metrics = PanelMetrics(text: lastSelectedText, correctionCount: 0, phase: .loading)
        case .error:
            anchorRect = lastAnchorRect
            metrics = PanelMetrics(text: lastSelectedText, correctionCount: 0, phase: .error)
        case .idle:
            anchorRect = lastAnchorRect
            metrics = PanelMetrics(text: lastSelectedText, correctionCount: 0, phase: .loading)
        }

        let size = panelSize(near: anchorRect, metrics: metrics)
        panel.setFrame(NSRect(origin: panelOrigin(near: anchorRect, size: size), size: size), display: true, animate: true)
    }

    private func panelSize(near anchorRect: CGRect?, metrics: PanelMetrics) -> NSSize {
        let anchor = anchorRect ?? mouseAnchorRect()
        let screen = NSScreen.screens.first { $0.visibleFrame.intersects(anchor) || $0.visibleFrame.contains(anchor.center) } ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSScreen.screens.first?.visibleFrame ?? .zero

        let screenMaxWidth = max(280, visibleFrame.width - 24)
        let selectionBasedWidth = anchor.width + 92
        let style = TrustCenter.shared.selectedTextReviewPanelStyle
        let styleMinimumWidth: CGFloat = style == .beforeBetter ? 520 : minimumPanelWidth
        let textBasedWidth = min(maximumPanelWidth, CGFloat(min(metrics.text.count, 120)) * 6.7 + 130)
        let width = min(max(styleMinimumWidth, selectionBasedWidth, textBasedWidth), min(maximumPanelWidth, screenMaxWidth))

        let height: CGFloat
        switch metrics.phase {
        case .loading, .error:
            height = 126
        case .result:
            let availableTextWidth = max(260, width - 42)
            let estimatedCharactersPerRow = max(28, Int(availableTextWidth / 7.2))
            let hardLines = metrics.text.components(separatedBy: .newlines)
            let textRows = hardLines.reduce(0) { partial, line in
                partial + max(1, Int(ceil(Double(max(line.count, 1)) / Double(estimatedCharactersPerRow))))
            }
            switch style {
            case .beforeBetter:
                let rows = min(max(2, textRows), 4)
                let contentHeight = CGFloat(rows) * 36 + 92
                height = min(max(170, contentHeight), max(190, visibleFrame.height * 0.42))
            case .wordHover:
                let correctionRows = Int(ceil(Double(metrics.correctionCount) / 3.0))
                let diffRows = max(1, min(3, textRows + correctionRows))
                let contentHeight = CGFloat(diffRows) * 31 + 98
                height = min(max(138, contentHeight), max(170, visibleFrame.height * 0.34))
            }
        }

        return NSSize(width: width, height: height)
    }

    private func panelOrigin(near anchorRect: CGRect?, size: NSSize) -> NSPoint {
        let anchor = anchorRect ?? mouseAnchorRect()
        let screen = NSScreen.screens.first { $0.visibleFrame.intersects(anchor) || $0.visibleFrame.contains(anchor.center) } ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSScreen.screens.first?.visibleFrame ?? .zero

        var x = anchor.midX - size.width / 2
        var y = anchor.maxY + panelGap

        if y + size.height > visibleFrame.maxY {
            y = anchor.minY - size.height - panelGap
        }

        x = min(max(x, visibleFrame.minX + 8), visibleFrame.maxX - size.width - 8)
        y = min(max(y, visibleFrame.minY + 8), visibleFrame.maxY - size.height - 8)

        return NSPoint(x: x, y: y)
    }

    private func mouseAnchorRect() -> CGRect {
        let mouse = NSEvent.mouseLocation
        return CGRect(x: mouse.x - 4, y: mouse.y - 4, width: 8, height: 8)
    }

    private func startOutsideClickMonitoring() {
        guard globalMouseMonitor == nil, localMouseMonitor == nil else { return }

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            Task { @MainActor in
                self?.closePanelIfClickIsOutside(screenPoint: NSEvent.mouseLocation)
            }
        }

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            Task { @MainActor in
                guard let self else { return }
                if let panel = self.panel, event.window === panel { return }
                let screenPoint = event.window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
                self.closePanelIfClickIsOutside(screenPoint: screenPoint)
            }
            return event
        }
    }

    private func closePanelIfClickIsOutside(screenPoint: NSPoint) {
        guard let panel, panel.isVisible else { return }
        guard !panel.frame.contains(screenPoint) else { return }
        closePanel()
    }

    private func closePanel() {
        panel?.orderOut(nil)
        stopOutsideClickMonitoring()
    }

    private func stopOutsideClickMonitoring() {
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }

        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }
    }
}

private final class CompactSelectedTextReviewPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private struct PanelMetrics {
    let text: String
    let correctionCount: Int
    let phase: PanelPhase
}

private enum PanelPhase {
    case loading
    case result
    case error
}

@MainActor
final class SelectedTextReviewViewModel: ObservableObject {
    enum State {
        case idle
        case loading(String)
        case result(SelectedTextCapture, SelectedTextReview)
        case error(String)
    }

    @Published var state: State = .idle
    @Published var replacementStatus: String?
    @Published var isReplacing = false
    var onStateChanged: ((State) -> Void)?

    func startCapture() {
        setState(.loading("Reading selection"))
        replacementStatus = nil
    }

    func review(_ capture: SelectedTextCapture) {
        setState(.loading("Checking \(capture.appName)"))
        replacementStatus = nil

        Task {
            do {
                let review = try await AIAnalysisService.shared.reviewSelectedText(capture)
                setState(.result(capture, review))
            } catch {
                showError(error)
            }
        }
    }

    func showError(_ error: Error) {
        setState(.error((error as? LocalizedError)?.errorDescription ?? error.localizedDescription))
    }

    private func setState(_ nextState: State) {
        state = nextState
        DispatchQueue.main.async { [weak self] in
            self?.onStateChanged?(nextState)
        }
    }

    func copyImprovedText(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        replacementStatus = "Copied"
    }

    func replaceSelection(capture: SelectedTextCapture, review: SelectedTextReview) {
        isReplacing = true
        replacementStatus = nil

        Task {
            do {
                try await SelectedTextReader.shared.replaceSelection(with: review.improvedText, target: capture)
                replacementStatus = "Replaced"
            } catch {
                replacementStatus = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            isReplacing = false
        }
    }

    func addRemindersToPractice(_ review: SelectedTextReview) {
        for correction in review.corrections {
            _ = DatabaseService.shared.getOrCreateWeaknessProgress(category: correction.category)
        }
        replacementStatus = review.corrections.isEmpty ? "Nothing to remember" : "Remembered"
    }
}

struct SelectedTextReviewPanelView: View {
    @ObservedObject var viewModel: SelectedTextReviewViewModel
    let onRetry: () -> Void
    let onClose: () -> Void

    var body: some View {
        ZStack {
            GlassBackground(material: .hudWindow, blendingMode: .behindWindow)

            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(0.08))

            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)

            VStack(spacing: 0) {
                header
                Divider().opacity(0.25)
                content
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        HStack(spacing: 9) {
            Image(systemName: "text.badge.checkmark")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.cyan)

            Text("Fix before send")
                .font(.system(size: 12, weight: .semibold))

            Spacer()

            compactIconButton("arrow.clockwise", help: "Review current selection again", action: onRetry)
            compactIconButton("xmark", help: "Close", action: onClose)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle:
            compactEmpty(
                icon: "selection.pin.in.out",
                title: "Select text",
                message: "Highlight text, then press Option+E twice."
            )
        case .loading(let message):
            VStack(spacing: 10) {
                ProgressView()
                    .scaleEffect(0.82)
                Text(message)
                    .font(.system(size: 13, weight: .semibold))
                Text("Grammar, clarity, tone, and your patterns.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .error(let message):
            compactEmpty(
                icon: "exclamationmark.triangle",
                title: "No text found",
                message: message
            )
        case .result(let capture, let review):
            resultContent(capture: capture, review: review)
        }
    }

    @ViewBuilder
    private func resultContent(capture: SelectedTextCapture, review: SelectedTextReview) -> some View {
        switch TrustCenter.shared.selectedTextReviewPanelStyle {
        case .beforeBetter:
            beforeBetterContent(capture: capture, review: review)
        case .wordHover:
            wordHoverContent(capture: capture, review: review)
        }
    }

    private func beforeBetterContent(capture: SelectedTextCapture, review: SelectedTextReview) -> some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text(capture.appName)
                    Text(review.detectedTone)
                    Spacer()
                    if !review.corrections.isEmpty {
                        Text("\(review.corrections.count) fix\(review.corrections.count == 1 ? "" : "es")")
                    }
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)

                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .trailing, spacing: 12) {
                        Text("Original")
                        Text("Better")
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 54, alignment: .trailing)

                    VStack(alignment: .leading, spacing: 9) {
                        MarkedOriginalLine(review: review, maxRows: 2)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        MarkedImprovedLine(review: review, maxRows: 2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .background(Color.white.opacity(0.065))
                .cornerRadius(11)

                explanationStrip(review: review)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider().opacity(0.25)
            actionBar(capture: capture, review: review)
        }
    }

    private func wordHoverContent(capture: SelectedTextCapture, review: SelectedTextReview) -> some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text(capture.appName)
                    Text("fast check")
                    Spacer()
                    Text(review.corrections.isEmpty ? "clean" : "\(review.corrections.count) fix\(review.corrections.count == 1 ? "" : "es")")
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)

                InlineOriginalDiffText(review: review, maxRows: 3, popoverExplanations: true)
                    .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .background(Color.white.opacity(0.07))
                    .cornerRadius(11)

                HStack(spacing: 7) {
                    explanationStrip(review: review)
                    Spacer(minLength: 4)
                    inlineActionButtons(capture: capture, review: review)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private func explanationStrip(review: SelectedTextReview) -> some View {
        if review.corrections.isEmpty {
            Label("No major correction needed", systemImage: "checkmark.circle.fill")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.green)
        } else {
            HStack(spacing: 7) {
                ForEach(Array(review.corrections.prefix(3))) { correction in
                    Text(correction.category)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.055))
                        .cornerRadius(8)
                        .help(tooltip(for: correction))
                }

                if review.corrections.count > 3 {
                    Text("+\(review.corrections.count - 3)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.055))
                        .cornerRadius(8)
                }

                Spacer(minLength: 0)
            }
        }
    }

    private func actionBar(capture: SelectedTextCapture, review: SelectedTextReview) -> some View {
        HStack(spacing: 8) {
            if let replacementStatus = viewModel.replacementStatus {
                Text(replacementStatus)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Button(action: { viewModel.addRemindersToPractice(review) }) {
                Image(systemName: "pin")
            }
            .help("Remember")

            Button(action: { viewModel.copyImprovedText(review.improvedText) }) {
                Image(systemName: "doc.on.doc")
            }
            .help("Copy")

            Button(action: { viewModel.replaceSelection(capture: capture, review: review) }) {
                if viewModel.isReplacing {
                    ProgressView()
                        .scaleEffect(0.58)
                        .frame(width: 13, height: 13)
                } else {
                    Image(systemName: "arrow.down.doc")
                }
            }
            .help("Replace selection")
            .disabled(viewModel.isReplacing)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private func inlineActionButtons(capture: SelectedTextCapture, review: SelectedTextReview) -> some View {
        HStack(spacing: 7) {
            if let replacementStatus = viewModel.replacementStatus {
                Text(replacementStatus)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Button(action: { viewModel.addRemindersToPractice(review) }) {
                Image(systemName: "pin")
            }
            .help("Remember")

            Button(action: { viewModel.copyImprovedText(review.improvedText) }) {
                Image(systemName: "doc.on.doc")
            }
            .help("Copy")

            Button(action: { viewModel.replaceSelection(capture: capture, review: review) }) {
                if viewModel.isReplacing {
                    ProgressView()
                        .scaleEffect(0.58)
                        .frame(width: 13, height: 13)
                } else {
                    Image(systemName: "arrow.down.doc")
                }
            }
            .help("Replace selection")
            .disabled(viewModel.isReplacing)
        }
        .buttonStyle(.borderless)
    }

    private func compactEmpty(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 30, weight: .medium))
                .foregroundColor(.secondary)
            Text(title)
                .font(.system(size: 14, weight: .semibold))
            Text(message)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(22)
    }

    private func compactIconButton(_ systemName: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundColor(.secondary)
        .help(help)
    }

    private func tooltip(for correction: SelectedTextCorrection) -> String {
        [correction.explanation, correction.memoryCue]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}

private struct InlineOriginalDiffText: View {
    let review: SelectedTextReview
    let maxRows: Int
    var popoverExplanations = false

    var body: some View {
        WrappingInlineLayout(horizontalSpacing: 2, verticalSpacing: 3, maxRows: maxRows) {
            ForEach(InlineDiffBuilder.originalSegments(for: review)) { segment in
                switch segment.kind {
                case .plain:
                    Text(segment.text)
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                case .correction(let correction):
                    InlineCorrectionToken(correction: correction, popoverExplanations: popoverExplanations)
                }
            }
        }
    }
}

private struct InlineCorrectionToken: View {
    let correction: SelectedTextCorrection
    let popoverExplanations: Bool
    @State private var showingExplanation = false

    var body: some View {
        HStack(spacing: 4) {
            Text(correction.original)
                .strikethrough()
                .foregroundColor(.red.opacity(0.92))
                .lineLimit(1)
            Image(systemName: "arrow.right")
                .font(.system(size: 8, weight: .semibold))
                .foregroundColor(.secondary)
            Text(correction.replacement)
                .foregroundColor(.green)
                .lineLimit(1)
        }
        .font(.system(size: 13, weight: .semibold, design: .rounded))
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(Color.white.opacity(showingExplanation ? 0.13 : 0.075))
        .cornerRadius(7)
        .help(tooltip)
        .onHover { hovering in
            guard popoverExplanations else { return }
            showingExplanation = hovering
        }
        .popover(isPresented: $showingExplanation, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Why")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                Text(correction.explanation)
                    .font(.system(size: 12, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)

                if let memoryCue = correction.memoryCue, !memoryCue.isEmpty {
                    Text("Remember: \(memoryCue)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .frame(width: 260, alignment: .leading)
        }
    }

    private var tooltip: String {
        [correction.explanation, correction.memoryCue]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}

private struct MarkedOriginalLine: View {
    let review: SelectedTextReview
    let maxRows: Int

    var body: some View {
        WrappingInlineLayout(horizontalSpacing: 2, verticalSpacing: 3, maxRows: maxRows) {
            ForEach(InlineDiffBuilder.originalSegments(for: review)) { segment in
                switch segment.kind {
                case .plain:
                    Text(segment.text)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(.primary.opacity(0.86))
                        .lineLimit(1)
                case .correction(let correction):
                    Text(segment.text.isEmpty ? correction.original : segment.text)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.red.opacity(0.95))
                        .underline(true, color: .red.opacity(0.95))
                        .lineLimit(1)
                        .help(correction.explanation)
                }
            }
        }
    }
}

private struct MarkedImprovedLine: View {
    let review: SelectedTextReview
    let maxRows: Int

    var body: some View {
        WrappingInlineLayout(horizontalSpacing: 2, verticalSpacing: 3, maxRows: maxRows) {
            ForEach(InlineDiffBuilder.improvedSegments(for: review)) { segment in
                switch segment.kind {
                case .plain:
                    Text(segment.text)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(.primary.opacity(0.9))
                        .lineLimit(1)
                case .correction(let correction):
                    Text(segment.text.isEmpty ? correction.replacement : segment.text)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.green)
                        .lineLimit(1)
                        .help(correction.explanation)
                }
            }
        }
    }
}

private enum InlineDiffBuilder {
    static func originalSegments(for review: SelectedTextReview) -> [InlineDiffSegment] {
        correctionSegments(in: review.originalText, corrections: review.corrections, useReplacementText: false)
    }

    static func improvedSegments(for review: SelectedTextReview) -> [InlineDiffSegment] {
        let segments = correctionSegments(in: review.improvedText, corrections: review.corrections, useReplacementText: true)
        guard segments.contains(where: { $0.isCorrection }) else {
            return tokenize(review.improvedText).map { InlineDiffSegment(text: $0, kind: .plain) }
        }
        return segments
    }

    private static func correctionSegments(
        in text: String,
        corrections: [SelectedTextCorrection],
        useReplacementText: Bool
    ) -> [InlineDiffSegment] {
        let validCorrections = corrections
            .filter {
                !$0.original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                !$0.replacement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            .sorted {
                let lhs = useReplacementText ? $0.replacement.count : $0.original.count
                let rhs = useReplacementText ? $1.replacement.count : $1.original.count
                return lhs > rhs
            }

        guard !text.isEmpty, !validCorrections.isEmpty else {
            return tokenize(text).map { InlineDiffSegment(text: $0, kind: .plain) }
        }

        var output: [InlineDiffSegment] = []
        var cursor = text.startIndex

        while cursor < text.endIndex {
            var best: (range: Range<String.Index>, correction: SelectedTextCorrection)?

            for correction in validCorrections {
                let needle = useReplacementText ? correction.replacement : correction.original
                guard let range = text.range(
                    of: needle,
                    options: [.caseInsensitive],
                    range: cursor..<text.endIndex
                ) else { continue }

                if best == nil || range.lowerBound < best!.range.lowerBound {
                    best = (range, correction)
                }
            }

            guard let match = best else {
                output.append(contentsOf: tokenize(String(text[cursor..<text.endIndex])).map {
                    InlineDiffSegment(text: $0, kind: .plain)
                })
                break
            }

            if cursor < match.range.lowerBound {
                output.append(contentsOf: tokenize(String(text[cursor..<match.range.lowerBound])).map {
                    InlineDiffSegment(text: $0, kind: .plain)
                })
            }

            output.append(InlineDiffSegment(text: String(text[match.range]), kind: .correction(match.correction)))
            cursor = match.range.upperBound
        }

        if output.contains(where: { $0.isCorrection }) {
            return output
        }

        if useReplacementText {
            return tokenize(text).map { InlineDiffSegment(text: $0, kind: .plain) }
        }

        var fallback = tokenize(text).map { InlineDiffSegment(text: $0, kind: .plain) }
        fallback.append(InlineDiffSegment(text: " ", kind: .plain))
        fallback.append(contentsOf: validCorrections.prefix(3).map { correction in
            InlineDiffSegment(text: correction.original, kind: .correction(correction))
        })

        return fallback.isEmpty ? [InlineDiffSegment(text: text, kind: .plain)] : fallback
    }

    private static func tokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var currentIsWhitespace: Bool?

        for scalar in text.unicodeScalars {
            let isWhitespace = CharacterSet.whitespacesAndNewlines.contains(scalar)
            if let currentIsWhitespace, currentIsWhitespace != isWhitespace {
                tokens.append(current)
                current = ""
            }
            current.append(Character(scalar))
            currentIsWhitespace = isWhitespace
        }

        if !current.isEmpty {
            tokens.append(current)
        }

        return tokens
    }
}

private struct InlineDiffSegment: Identifiable {
    let id = UUID()
    let text: String
    let kind: InlineDiffKind

    var isCorrection: Bool {
        if case .correction = kind {
            return true
        }
        return false
    }
}

private enum InlineDiffKind {
    case plain
    case correction(SelectedTextCorrection)
}

private struct WrappingInlineLayout: Layout {
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat
    let maxRows: Int

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 520
        let rows = arrangedRows(maxWidth: maxWidth, subviews: subviews)
        let height = rows.reduce(CGFloat.zero) { partial, row in
            partial + row.height
        } + CGFloat(max(rows.count - 1, 0)) * verticalSpacing
        return CGSize(width: maxWidth, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrangedRows(maxWidth: bounds.width, subviews: subviews)
        var y = bounds.minY

        for row in rows {
            var x = bounds.minX
            for item in row.items {
                item.subview.place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(item.size)
                )
                x += item.size.width + horizontalSpacing
            }
            y += row.height + verticalSpacing
        }
    }

    private func arrangedRows(maxWidth: CGFloat, subviews: Subviews) -> [InlineRow] {
        var rows: [InlineRow] = []
        var currentItems: [InlineItem] = []
        var currentWidth: CGFloat = 0
        var currentHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let nextWidth = currentItems.isEmpty ? size.width : currentWidth + horizontalSpacing + size.width

            if !currentItems.isEmpty, nextWidth > maxWidth, rows.count < maxRows - 1 {
                rows.append(InlineRow(items: currentItems, height: currentHeight))
                currentItems = [InlineItem(subview: subview, size: size)]
                currentWidth = size.width
                currentHeight = size.height
            } else if rows.count >= maxRows - 1, nextWidth > maxWidth {
                break
            } else {
                currentItems.append(InlineItem(subview: subview, size: size))
                currentWidth = nextWidth
                currentHeight = max(currentHeight, size.height)
            }
        }

        if !currentItems.isEmpty, rows.count < maxRows {
            rows.append(InlineRow(items: currentItems, height: currentHeight))
        }

        return rows
    }
}

private struct InlineRow {
    let items: [InlineItem]
    let height: CGFloat
}

private struct InlineItem {
    let subview: LayoutSubview
    let size: CGSize
}

struct GlassBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = .active
    }
}

private extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}
