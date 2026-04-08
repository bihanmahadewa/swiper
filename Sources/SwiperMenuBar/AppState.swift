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
    @Published var lastError: String?
    @Published var now: Date = .init()
    @Published var doctorReport: DoctorReport?

    let repoURL: URL
    let dbURL: URL
    let statusURL: URL
    let dailyDirURL: URL
    let sessionsDirURL: URL

    private var process: Process?
    private var timer: Timer?

    init() {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        self.repoURL = cwd
        self.dbURL = cwd.appendingPathComponent("data/swiper-menubar.db")
        self.statusURL = cwd.appendingPathComponent("data/runtime/swiper-menubar-status.json")
        self.dailyDirURL = cwd.appendingPathComponent("data/daily")
        self.sessionsDirURL = cwd.appendingPathComponent("data/sessions")
    }

    func startPolling() {
        refreshStatus()
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
        let fileManager = FileManager.default
        guard let fileURLs = try? fileManager.contentsOfDirectory(
            at: sessionsDirURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        let jsonFiles = fileURLs.filter { $0.pathExtension.lowercased() == "json" }
        if jsonFiles.isEmpty {
            return nil
        }

        let sorted = jsonFiles.sorted { left, right in
            let leftDate = (try? left.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rightDate = (try? right.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast

            if leftDate != rightDate {
                return leftDate > rightDate
            }

            return left.lastPathComponent > right.lastPathComponent
        }

        return sorted.first
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
