import Foundation

struct SessionNoteSummaryCache: Codable {
    let title: String
    let subtitle: String
    let generatedAt: String
    let model: String
}

struct SessionDetailSummaryCache: Codable {
    let markdown: String
    let generatedAt: String
    let model: String
}

struct SessionNoteItem: Identifiable, Hashable {
    let id: String
    let fileURL: URL
    let day: String
    let startedAt: Date?
    let endedAt: Date?
    let timeLabel: String
    let fallbackTitle: String
    let fallbackSubtitle: String
    var summaryTitle: String?
    var summarySubtitle: String?
    var isSummarizing: Bool

    var title: String { summaryTitle ?? fallbackTitle }
    var subtitle: String { summarySubtitle ?? fallbackSubtitle }
}

struct SessionDaySection: Identifiable {
    let id: String
    let day: String
    let title: String
    let items: [SessionNoteItem]
}

struct OpenAIResponsesRequest: Encodable {
    struct InputMessage: Encodable {
        struct InputContent: Encodable {
            let type: String
            let text: String
        }

        let role: String
        let content: [InputContent]
    }

    let model: String
    let input: [InputMessage]
}

struct OpenAIResponsesResponse: Decodable {
    struct OutputItem: Decodable {
        struct OutputContent: Decodable {
            let type: String
            let text: String?
        }

        let type: String
        let content: [OutputContent]?
    }

    let output: [OutputItem]?
}

enum SessionNoteBuilder {
    static func buildItems(from files: [URL], summariesDirURL: URL) -> [SessionNoteItem] {
        files.compactMap { fileURL in
            guard let data = try? Data(contentsOf: fileURL),
                  let report = try? JSONDecoder().decode(DailyReport.self, from: data) else {
                return nil
            }

            let fallbackTitle = makeFallbackTitle(report: report)
            let fallbackSubtitle = makeFallbackSubtitle(report: report)
            let cache = readSummaryCache(for: fileURL, summariesDirURL: summariesDirURL)

            return SessionNoteItem(
                id: fileURL.lastPathComponent,
                fileURL: fileURL,
                day: report.day,
                startedAt: parseDate(report.appTimeline.first?.timestampStart ?? report.rawTimeline.first?.timestampStart),
                endedAt: parseDate(report.appTimeline.last?.timestampEnd ?? report.rawTimeline.last?.timestampEnd),
                timeLabel: makeTimeLabel(report: report),
                fallbackTitle: fallbackTitle,
                fallbackSubtitle: fallbackSubtitle,
                summaryTitle: cache?.title,
                summarySubtitle: cache?.subtitle,
                isSummarizing: false
            )
        }
    }

    static func sections(from items: [SessionNoteItem]) -> [SessionDaySection] {
        let grouped = Dictionary(grouping: items) { $0.day }
        return grouped.keys.sorted(by: >).map { day in
            let dayItems = grouped[day, default: []].sorted {
                ($0.startedAt ?? .distantPast) > ($1.startedAt ?? .distantPast)
            }

            return SessionDaySection(
                id: day,
                day: day,
                title: sectionTitle(for: day),
                items: dayItems
            )
        }
    }

    static func readSummaryCache(for fileURL: URL, summariesDirURL: URL) -> SessionNoteSummaryCache? {
        let cacheURL = summariesDirURL.appendingPathComponent(fileURL.deletingPathExtension().lastPathComponent + ".json")
        guard let data = try? Data(contentsOf: cacheURL) else {
            return nil
        }

        return try? JSONDecoder().decode(SessionNoteSummaryCache.self, from: data)
    }

    static func writeSummaryCache(_ cache: SessionNoteSummaryCache, for fileURL: URL, summariesDirURL: URL) {
        let cacheURL = summariesDirURL.appendingPathComponent(fileURL.deletingPathExtension().lastPathComponent + ".json")
        guard let data = try? JSONEncoder().encode(cache) else {
            return
        }

        try? FileManager.default.createDirectory(at: summariesDirURL, withIntermediateDirectories: true)
        try? data.write(to: cacheURL)
    }

    static func prompt(for fileURL: URL) -> String? {
        guard let data = try? Data(contentsOf: fileURL),
              let report = try? JSONDecoder().decode(DailyReport.self, from: data) else {
            return nil
        }

        let metrics = computeMetrics(report: report)
        let lines = report.appTimeline.prefix(18).map { entry in
            let app = entry.appName ?? "Unknown"
            let domain = entry.domain ?? ""
            let suffix = domain.isEmpty ? "" : " (\(domain))"
            return "- \(entry.timestampStart) to \(entry.timestampEnd): \(app)\(suffix)"
        }

        let topApps = report.appUsage.prefix(5).map {
            "\($0.app_name): \(minutesString($0.total_duration_ms)) (\(shareString(part: $0.total_duration_ms, total: metrics.totalDurationMs)))"
        }.joined(separator: ", ")
        let topDomains = report.domainUsage.prefix(5).map {
            "\($0.domain ?? $0.url): \(minutesString($0.totalDurationMs))"
        }.joined(separator: ", ")
        let rawLabels = report.rawTimeline.prefix(10).map(\.taskLabel).joined(separator: ", ")
        let switches = report.appSwitches.prefix(12).map {
            "\($0.fromApp ?? "Unknown") -> \($0.toApp ?? "Unknown")"
        }.joined(separator: ", ")

        return """
        Write a concise session note for this digital activity timeline.
        Respond with exactly two lines:
        title: <short note title, under 80 chars>
        subtitle: <micro-summary, under 140 chars>

        Day: \(report.day)
        Session summary:
        - total duration: \(minutesString(metrics.totalDurationMs))
        - app switches: \(metrics.appSwitchCount)
        - distinct apps: \(metrics.distinctAppCount)
        - browser ratio: \(percentString(metrics.browserRatio))
        - longest focus block: \(minutesString(metrics.longestFocusBlockMs))
        - switch rate: \(String(format: "%.1f", metrics.switchesPer10Minutes)) per 10 minutes
        - short switches: \(metrics.shortSwitchCount)
        - dominant app share: \(percentString(metrics.topAppShare))
        - dominant domain: \(metrics.dominantDomain ?? "None")
        Top apps: \(topApps.isEmpty ? "None" : topApps)
        Top domains: \(topDomains.isEmpty ? "None" : topDomains)
        Raw labels: \(rawLabels)
        App switches: \(switches.isEmpty ? "None" : switches)
        Timeline:
        \(lines.joined(separator: "\n"))
        """
    }

    static func parseSummary(text: String) -> (title: String, subtitle: String)? {
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard lines.count >= 2 else {
            return nil
        }

        let title = lines[0].replacingOccurrences(of: "title:", with: "", options: [.caseInsensitive]).trimmingCharacters(in: .whitespacesAndNewlines)
        let subtitle = lines[1].replacingOccurrences(of: "subtitle:", with: "", options: [.caseInsensitive]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !subtitle.isEmpty else {
            return nil
        }

        return (title, subtitle)
    }

    static func extractOutputText(from response: OpenAIResponsesResponse) -> String? {
        let parts = (response.output ?? []).flatMap { item in
            (item.content ?? []).compactMap { content in
                content.text
            }
        }

        let text = parts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private static func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractionalFormatter.date(from: value)
            ?? ISO8601DateFormatter().date(from: value)
    }

    private static func makeTimeLabel(report: DailyReport) -> String {
        let timestamp = report.appTimeline.first?.timestampStart ?? report.rawTimeline.first?.timestampStart
        guard let date = parseDate(timestamp) else { return "" }
        return sessionTimeFormatter.string(from: date)
    }

    private static func makeFallbackTitle(report: DailyReport) -> String {
        let primary = report.appUsage.first?.app_name ?? report.appTimeline.first?.appName ?? "Activity session"
        let secondary = report.domainUsage.first?.domain ?? report.appUsage.dropFirst().first?.app_name

        if let secondary, !secondary.isEmpty {
            return "\(primary) with \(secondary)"
        }

        return primary
    }

    private static func makeFallbackSubtitle(report: DailyReport) -> String {
        let metrics = computeMetrics(report: report)
        let appNames = report.appUsage.prefix(3).map(\.app_name).joined(separator: ", ")
        return "\(minutesString(metrics.totalDurationMs)) across \(metrics.distinctAppCount) apps: \(appNames)"
    }

    private static func computeMetrics(report: DailyReport) -> SessionPromptMetrics {
        let totalDurationMs = report.appTimeline.reduce(0) { $0 + max(0, $1.durationMs) }
        let distinctAppCount = Set(report.appUsage.map(\.app_name)).count
        let appSwitchCount = report.appSwitches.count
        let browserDurationMs = report.appTimeline
            .filter { $0.domain != nil && !($0.domain?.isEmpty ?? true) }
            .reduce(0) { $0 + max(0, $1.durationMs) }
        let browserRatio = totalDurationMs > 0 ? Double(browserDurationMs) / Double(totalDurationMs) : 0
        let longestFocusBlockMs = report.appTimeline.map(\.durationMs).max() ?? 0
        let shortSwitchCount = report.appTimeline.filter { $0.durationMs > 0 && $0.durationMs <= 30_000 }.count
        let topAppShare = {
            guard let top = report.appUsage.first?.total_duration_ms, totalDurationMs > 0 else { return 0.0 }
            return Double(top) / Double(totalDurationMs)
        }()
        let dominantDomain = report.domainUsage.first?.domain
        let switchesPer10Minutes = totalDurationMs > 0
            ? (Double(appSwitchCount) / (Double(totalDurationMs) / 600_000.0))
            : 0

        return SessionPromptMetrics(
            totalDurationMs: totalDurationMs,
            appSwitchCount: appSwitchCount,
            distinctAppCount: distinctAppCount,
            browserRatio: browserRatio,
            longestFocusBlockMs: longestFocusBlockMs,
            shortSwitchCount: shortSwitchCount,
            topAppShare: topAppShare,
            dominantDomain: dominantDomain,
            switchesPer10Minutes: switchesPer10Minutes
        )
    }

    private static func minutesString(_ durationMs: Int) -> String {
        let minutes = max(1, durationMs / 60_000)
        return "\(minutes)m"
    }

    private static func shareString(part: Int, total: Int) -> String {
        guard total > 0 else { return "0%" }
        return percentString(Double(part) / Double(total))
    }

    private static func percentString(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private static func sectionTitle(for day: String) -> String {
        guard let date = dayFormatter.date(from: day) else { return day }
        if Calendar.current.isDateInToday(date) {
            return "Today"
        }
        if Calendar.current.isDateInYesterday(date) {
            return "Yesterday"
        }
        return visibleDayFormatter.string(from: date)
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter
    }()

    private static let visibleDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        formatter.timeZone = .current
        return formatter
    }()

    private static let sessionTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        formatter.timeZone = .current
        return formatter
    }()
}

private struct SessionPromptMetrics {
    let totalDurationMs: Int
    let appSwitchCount: Int
    let distinctAppCount: Int
    let browserRatio: Double
    let longestFocusBlockMs: Int
    let shortSwitchCount: Int
    let topAppShare: Double
    let dominantDomain: String?
    let switchesPer10Minutes: Double
}
