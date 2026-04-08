import Foundation
import SwiftUI
import AppKit
import Darwin
import ApplicationServices

struct TrackerStatus: Decodable {
    let state: String
    let mode: String
    let sessionId: String?
    let dbPath: String
    let intervalMs: Int
    let durationMs: Int?
    let startedAt: String
    let lastTickAt: String?
    let ticks: Int
    let totalEvents: Int
    let trackedDurationMs: Int
    let reportDay: String
    let statusPath: String
    let dailyDir: String
    let sessionsDir: String?
    let latestSessionPath: String?
    let pid: Int32
}

struct DoctorReport: Decodable {
    struct FrontmostApp: Decodable {
        struct DoctorError: Decodable {
            let message: String
            let status: Int?
        }

        let appName: String?
        let appBundleId: String?
        let windowTitle: String?
        let rawOutput: String
        let error: DoctorError?
    }

    struct BrowserContext: Decodable {
        struct DoctorError: Decodable {
            let message: String
            let status: Int?
        }

        let url: String?
        let pageTitle: String?
        let documentPath: String?
        let error: DoctorError?
    }

    let timestamp: String
    let frontmostApp: FrontmostApp
    let browserContext: BrowserContext
}

struct DailyReport: Decodable {
    let day: String
    let appTimeline: [BehaviorEntry]
    let appUsage: [AppUsageEntry]
    let domainUsage: [DomainUsageEntry]
    let appSwitches: [AppSwitchEntry]
    let rawTimeline: [RawTimelineEntry]
}

struct BehaviorEntry: Decodable, Identifiable {
    let sessionId: String
    let timestampStart: String
    let timestampEnd: String
    let durationMs: Int
    let appName: String?
    let url: String?
    let domain: String?
    let documentPath: String?

    var id: String { sessionId }
}

struct AppUsageEntry: Decodable, Identifiable {
    let app_name: String
    let total_duration_ms: Int
    let session_count: Int

    var id: String { app_name }
}

struct DomainUsageEntry: Decodable, Identifiable {
    let url: String
    let domain: String?
    let totalDurationMs: Int
    let sessionCount: Int

    var id: String { url }
}

struct AppSwitchEntry: Decodable, Identifiable {
    let timestamp: String
    let fromApp: String?
    let toApp: String?
    let fromDomain: String?
    let toDomain: String?

    var id: String { "\(timestamp)-\(fromApp ?? "")-\(toApp ?? "")" }
}

struct RawTimelineEntry: Decodable, Identifiable {
    let sessionId: String
    let timestampStart: String
    let timestampEnd: String
    let durationMs: Int
    let taskLabel: String
    let dominantAppName: String?
    let dominantUrl: String?
    let dominantDocumentPath: String?

    var id: String { sessionId }
}

@MainActor
final class AppState: ObservableObject {
    @Published var trackerStatus: TrackerStatus?
    @Published var dailyReport: DailyReport?
    @Published var noteSections: [SessionDaySection] = []
    @Published var openAIKeyInput: String = ""
    @Published var selectedNoteItem: SessionNoteItem?
    @Published var selectedNoteDetailMarkdown: String = ""
    @Published var isLoadingSelectedNoteDetail = false
    @Published var lastError: String?
    @Published var now: Date = .init()
    @Published var doctorReport: DoctorReport?

    let repoURL: URL
    let dbURL: URL
    let statusURL: URL
    let dailyDirURL: URL
    let sessionsDirURL: URL
    let summariesDirURL: URL
    let detailSummariesDirURL: URL

    private var process: Process?
    private var timer: Timer?
    private var summarizationTask: Task<Void, Never>?
    private let openAIKeyDefaultsKey = "swiper.openai_api_key"

    init() {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        self.repoURL = cwd
        self.dbURL = cwd.appendingPathComponent("data/swiper-menubar.db")
        self.statusURL = cwd.appendingPathComponent("data/runtime/swiper-menubar-status.json")
        self.dailyDirURL = cwd.appendingPathComponent("data/daily")
        self.sessionsDirURL = cwd.appendingPathComponent("data/sessions")
        self.summariesDirURL = cwd.appendingPathComponent("data/session-summaries")
        self.detailSummariesDirURL = cwd.appendingPathComponent("data/session-detail-summaries")
        self.openAIKeyInput = UserDefaults.standard.string(forKey: openAIKeyDefaultsKey)
            ?? ProcessInfo.processInfo.environment["OPENAI_API_KEY"]
            ?? ""
    }

    func startPolling() {
        refreshStatus()
        refreshSessionNotes()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.now = Date()
                self?.refreshStatus()
            }
        }
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
        summarizationTask?.cancel()
        summarizationTask = nil
    }

    func startTracking() {
        if process != nil || trackerStatus?.state == "watching" {
            return
        }

        guard ensurePermissions(prompt: true) else {
            return
        }

        do {
            try FileManager.default.createDirectory(
                at: repoURL.appendingPathComponent("data/runtime"),
                withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(
                at: repoURL.appendingPathComponent("data/daily"),
                withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(
                at: repoURL.appendingPathComponent("data/sessions"),
                withIntermediateDirectories: true
            )
        } catch {
            lastError = error.localizedDescription
        }

        let process = Process()
        process.currentDirectoryURL = repoURL
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["node", "src/cli.js", "daemon", dbURL.path, "--interval", "2s"]

        process.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                self?.process = nil
                self?.refreshStatus()
            }
        }

        do {
            try process.run()
            self.process = process
            lastError = nil
            refreshStatus()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func pauseTracking() {
        if let process {
            process.terminate()
            self.process = nil
            refreshStatus()
            return
        }

        if let pid = trackerStatus?.pid, trackerStatus?.state == "watching" {
            kill(pid, SIGTERM)
        }

        refreshStatus()
    }

    func refreshStatus() {
        guard let data = try? Data(contentsOf: statusURL) else {
            trackerStatus = nil
            return
        }

        do {
            trackerStatus = try JSONDecoder().decode(TrackerStatus.self, from: data)
        } catch {
            lastError = error.localizedDescription
        }
    }

    @discardableResult
    func ensurePermissions(prompt: Bool = false) -> Bool {
        if !ensureAccessibility(prompt: prompt) {
            lastError = "Swiper needs Accessibility access before tracking can start."
            return false
        }

        guard let report = runDoctor() else {
            lastError = "Could not run the Swiper doctor check."
            return false
        }

        doctorReport = report

        if let error = report.frontmostApp.error {
            lastError = "Swiper needs Automation permission for System Events before tracking can start. \(error.message)"
            return false
        }

        lastError = nil
        return true
    }

    func elapsedTrackingText(now: Date = Date()) -> String {
        guard let status = trackerStatus,
              status.state == "watching" else {
            return "Not tracking"
        }

        if let started = iso8601Formatter.date(from: status.startedAt) {
            return format(duration: Int(now.timeIntervalSince(started)))
        }

        return format(duration: status.trackedDurationMs / 1000)
    }

    func loadTodaysReport() {
        let fileURL = dailyDirURL.appendingPathComponent("\(localDayString()).json")
        guard let data = try? Data(contentsOf: fileURL) else {
            dailyReport = nil
            lastError = "No daily JSON found for today yet."
            return
        }

        do {
            dailyReport = try JSONDecoder().decode(DailyReport.self, from: data)
            lastError = nil
        } catch {
            dailyReport = nil
            lastError = error.localizedDescription
        }
    }

    func refreshSessionNotes() {
        do {
            try FileManager.default.createDirectory(at: summariesDirURL, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: detailSummariesDirURL, withIntermediateDirectories: true)
        } catch {
            lastError = error.localizedDescription
        }

        let files = latestSessionFileURLs()
        let items = SessionNoteBuilder.buildItems(from: files, summariesDirURL: summariesDirURL)
        noteSections = SessionNoteBuilder.sections(from: items)

        guard currentOpenAIKey() != nil else {
            return
        }

        summarizeMissingNotesIfNeeded()
    }

    func hasOpenAIKey() -> Bool {
        currentOpenAIKey() != nil
    }

    func saveOpenAIKey() {
        let trimmed = openAIKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            UserDefaults.standard.removeObject(forKey: openAIKeyDefaultsKey)
            lastError = "Removed saved OpenAI API key."
        } else {
            UserDefaults.standard.set(trimmed, forKey: openAIKeyDefaultsKey)
            lastError = "Saved OpenAI API key locally for Swiper."
        }

        summarizationTask?.cancel()
        summarizationTask = nil
        refreshSessionNotes()
    }

    func pasteOpenAIKeyFromClipboard() {
        let pasteboard = NSPasteboard.general
        guard let value = pasteboard.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            lastError = "Clipboard does not contain a text API key."
            return
        }

        openAIKeyInput = value
        lastError = "Pasted API key from clipboard."
    }

    func handleAppTermination() {
        pauseTracking()
        stopPolling()
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    func sendTodaysStatsToChatGPT() {
        refreshStatus()

        guard let fileURL = latestSessionFileURL() else {
            lastError = "No tracked session found yet."
            return
        }

        guard let url = URL(string: "https://chatgpt.com/") else {
            lastError = "Could not open ChatGPT."
            return
        }

        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
        lastError = "Opened ChatGPT and revealed the latest session JSON in Finder so you can attach the exact file."
        openChatGPT(url)
    }

    func revealSessionFile(_ item: SessionNoteItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.fileURL])
    }

    func openSessionDetail(_ item: SessionNoteItem) {
        selectedNoteItem = item
        selectedNoteDetailMarkdown = ""
        isLoadingSelectedNoteDetail = true

        if let cached = readDetailSummaryCache(for: item.fileURL) {
            selectedNoteDetailMarkdown = cached.markdown
            isLoadingSelectedNoteDetail = false
            return
        }

        Task { @MainActor in
            defer { self.isLoadingSelectedNoteDetail = false }

            guard let markdown = try? await generateDetailedSummary(for: item.fileURL) else {
                self.selectedNoteDetailMarkdown = fallbackDetailMarkdown(for: item)
                return
            }

            let cache = SessionDetailSummaryCache(
                markdown: markdown,
                generatedAt: iso8601Formatter.string(from: Date()),
                model: ProcessInfo.processInfo.environment["SWIPER_OPENAI_MODEL"] ?? "gpt-4.1-mini"
            )
            writeDetailSummaryCache(cache, for: item.fileURL)
            self.selectedNoteDetailMarkdown = markdown
        }
    }

    func closeSessionDetail() {
        selectedNoteItem = nil
        selectedNoteDetailMarkdown = ""
        isLoadingSelectedNoteDetail = false
    }

    private func localDayString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter.string(from: Date())
    }

    private func format(duration seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let remainingSeconds = seconds % 60

        if hours > 0 {
            return String(format: "%02dh %02dm %02ds", hours, minutes, remainingSeconds)
        }

        return String(format: "%02dm %02ds", minutes, remainingSeconds)
    }

    func formatDuration(ms: Int) -> String {
        format(duration: ms / 1000)
    }

    func menuBarTitle() -> String {
        guard trackerStatus?.state == "watching" else {
            return "Swiper"
        }

        return "Swiper \(elapsedTrackingText(now: now))"
    }

    private func runDoctor() -> DoctorReport? {
        let process = Process()
        process.currentDirectoryURL = repoURL
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["node", "src/cli.js", "doctor"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if process.terminationStatus != 0 {
                lastError = String(data: data, encoding: .utf8) ?? "Doctor failed."
                return nil
            }

            return try JSONDecoder().decode(DoctorReport.self, from: data)
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    private func ensureAccessibility(prompt: Bool) -> Bool {
        let key = "AXTrustedCheckOptionPrompt"
        let options = [key: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    private var iso8601Formatter: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    private func latestSessionFileURL() -> URL? {
        latestSessionFileURLs().first
    }

    private func latestSessionFileURLs() -> [URL] {
        let fileManager = FileManager.default
        guard let fileURLs = try? fileManager.contentsOfDirectory(
            at: sessionsDirURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let jsonFiles = fileURLs.filter { $0.pathExtension.lowercased() == "json" }
        if jsonFiles.isEmpty {
            return []
        }

        return jsonFiles.sorted { left, right in
            let leftDate = (try? left.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rightDate = (try? right.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast

            if leftDate != rightDate {
                return leftDate > rightDate
            }

            return left.lastPathComponent > right.lastPathComponent
        }
    }

    private func summarizeMissingNotesIfNeeded() {
        guard summarizationTask == nil else { return }

        let pendingItems = noteSections
            .flatMap(\.items)
            .filter { $0.summaryTitle == nil && !$0.isSummarizing }

        guard !pendingItems.isEmpty else { return }

        for pending in pendingItems {
            setSummarizing(true, for: pending.id)
        }

        summarizationTask = Task { [weak self] in
            guard let self else { return }
            defer {
                Task { @MainActor in
                    self.summarizationTask = nil
                }
            }

            for item in pendingItems.prefix(24) {
                if Task.isCancelled { return }

                do {
                    guard let summary = try await self.generateSummary(for: item.fileURL) else {
                        await MainActor.run {
                            self.setSummarizing(false, for: item.id)
                        }
                        continue
                    }

                    let cache = SessionNoteSummaryCache(
                        title: summary.title,
                        subtitle: summary.subtitle,
                        generatedAt: iso8601Formatter.string(from: Date()),
                        model: ProcessInfo.processInfo.environment["SWIPER_OPENAI_MODEL"] ?? "gpt-4.1-mini"
                    )

                    SessionNoteBuilder.writeSummaryCache(cache, for: item.fileURL, summariesDirURL: self.summariesDirURL)

                    await MainActor.run {
                        self.applySummary(cache, to: item.id)
                    }
                } catch {
                    await MainActor.run {
                        self.setSummarizing(false, for: item.id)
                        self.lastError = error.localizedDescription
                    }
                }
            }
        }
    }

    private func setSummarizing(_ value: Bool, for itemId: String) {
        noteSections = noteSections.map { section in
            let items = section.items.map { item -> SessionNoteItem in
                guard item.id == itemId else { return item }
                var copy = item
                copy.isSummarizing = value
                return copy
            }
            return SessionDaySection(id: section.id, day: section.day, title: section.title, items: items)
        }
    }

    private func applySummary(_ summary: SessionNoteSummaryCache, to itemId: String) {
        noteSections = noteSections.map { section in
            let items = section.items.map { item -> SessionNoteItem in
                guard item.id == itemId else { return item }
                var copy = item
                copy.summaryTitle = summary.title
                copy.summarySubtitle = summary.subtitle
                copy.isSummarizing = false
                return copy
            }
            return SessionDaySection(id: section.id, day: section.day, title: section.title, items: items)
        }
    }

    private func generateSummary(for fileURL: URL) async throws -> (title: String, subtitle: String)? {
        guard let apiKey = currentOpenAIKey() else {
            return nil
        }

        guard let prompt = SessionNoteBuilder.prompt(for: fileURL) else {
            return nil
        }

        let requestBody = OpenAIResponsesRequest(
            model: ProcessInfo.processInfo.environment["SWIPER_OPENAI_MODEL"] ?? "gpt-4.1-mini",
            input: [
                .init(role: "system", content: [.init(type: "input_text", text: "You turn personal activity timelines into short note titles and micro-summaries. Be concrete and calm. Do not mention that this came from telemetry.")]),
                .init(role: "user", content: [.init(type: "input_text", text: prompt)])
            ]
        )

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "SwiperOpenAI", code: -1, userInfo: [NSLocalizedDescriptionKey: "No HTTP response from OpenAI."])
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "OpenAI request failed."
            throw NSError(domain: "SwiperOpenAI", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: message])
        }

        let decoded = try JSONDecoder().decode(OpenAIResponsesResponse.self, from: data)
        guard let text = SessionNoteBuilder.extractOutputText(from: decoded),
              let parsed = SessionNoteBuilder.parseSummary(text: text) else {
            return nil
        }

        return parsed
    }

    private func currentOpenAIKey() -> String? {
        let saved = UserDefaults.standard.string(forKey: openAIKeyDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let saved, !saved.isEmpty {
            return saved
        }

        let env = ProcessInfo.processInfo.environment["OPENAI_API_KEY"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let env, !env.isEmpty {
            return env
        }

        return nil
    }

    private func detailSummaryCacheURL(for fileURL: URL) -> URL {
        detailSummariesDirURL.appendingPathComponent(fileURL.deletingPathExtension().lastPathComponent + ".json")
    }

    private func readDetailSummaryCache(for fileURL: URL) -> SessionDetailSummaryCache? {
        let cacheURL = detailSummaryCacheURL(for: fileURL)
        guard let data = try? Data(contentsOf: cacheURL) else {
            return nil
        }
        return try? JSONDecoder().decode(SessionDetailSummaryCache.self, from: data)
    }

    private func writeDetailSummaryCache(_ cache: SessionDetailSummaryCache, for fileURL: URL) {
        let cacheURL = detailSummaryCacheURL(for: fileURL)
        guard let data = try? JSONEncoder().encode(cache) else {
            return
        }
        try? FileManager.default.createDirectory(at: detailSummariesDirURL, withIntermediateDirectories: true)
        try? data.write(to: cacheURL)
    }

    private func generateDetailedSummary(for fileURL: URL) async throws -> String {
        guard let apiKey = currentOpenAIKey() else {
            return fallbackDetailMarkdown(forFileURL: fileURL)
        }

        guard let prompt = SessionNoteBuilder.prompt(for: fileURL) else {
            return fallbackDetailMarkdown(forFileURL: fileURL)
        }

        let requestBody = OpenAIResponsesRequest(
            model: ProcessInfo.processInfo.environment["SWIPER_OPENAI_MODEL"] ?? "gpt-4.1-mini",
            input: [
                .init(role: "system", content: [.init(type: "input_text", text: "Write a clear session note in markdown with these sections: Summary, What happened, Signals, Follow-ups. Be concrete and concise.")]),
                .init(role: "user", content: [.init(type: "input_text", text: prompt)])
            ]
        )

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            return fallbackDetailMarkdown(forFileURL: fileURL)
        }

        let decoded = try JSONDecoder().decode(OpenAIResponsesResponse.self, from: data)
        return SessionNoteBuilder.extractOutputText(from: decoded) ?? fallbackDetailMarkdown(forFileURL: fileURL)
    }

    private func fallbackDetailMarkdown(for item: SessionNoteItem) -> String {
        """
        # \(item.title)

        \(item.subtitle)
        """
    }

    private func fallbackDetailMarkdown(forFileURL fileURL: URL) -> String {
        guard let data = try? Data(contentsOf: fileURL),
              let report = try? JSONDecoder().decode(DailyReport.self, from: data) else {
            return "No session details available."
        }

        let lines = report.appTimeline.map { entry in
            let app = entry.appName ?? "Unknown"
            let domain = entry.domain ?? ""
            let suffix = domain.isEmpty ? "" : " (\(domain))"
            return "- \(entry.timestampStart): \(app)\(suffix)"
        }.joined(separator: "\n")

        let title = report.appUsage.first?.app_name ?? "Session"
        return """
        # \(title)

        ## Timeline
        \(lines)
        """
    }

    private func openChatGPT(_ url: URL) {
        if let chatGPTURL = URL(string: "chatgpt://"),
           NSWorkspace.shared.open(chatGPTURL) {
            return
        }

        openInSafari(url)
    }

    private func openInSafari(_ url: URL) {
        let safariURL = URL(fileURLWithPath: "/Applications/Safari.app")
        let configuration = NSWorkspace.OpenConfiguration()

        if FileManager.default.fileExists(atPath: safariURL.path) {
            NSWorkspace.shared.open([url], withApplicationAt: safariURL, configuration: configuration) { _, error in
                Task { @MainActor in
                    if let error {
                        self.lastError = "Could not open Safari: \(error.localizedDescription)"
                    }
                }
            }
        } else {
            NSWorkspace.shared.open(url)
        }
    }
}
