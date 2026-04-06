import Foundation
import SwiftUI
import AppKit
import Darwin

struct TrackerStatus: Decodable {
    let state: String
    let mode: String
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
    @Published var doctorReport: DoctorReport?

    let repoURL: URL
    let dbURL: URL
    let statusURL: URL
    let dailyDirURL: URL

    private var process: Process?
    private var timer: Timer?

    init() {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        self.repoURL = cwd
        self.dbURL = cwd.appendingPathComponent("data/swiper-menubar.db")
        self.statusURL = cwd.appendingPathComponent("data/runtime/swiper-menubar-status.json")
        self.dailyDirURL = cwd.appendingPathComponent("data/daily")
    }

    func startPolling() {
        refreshStatus()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
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

        guard ensurePermissions() else {
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
    func ensurePermissions() -> Bool {
        guard let report = runDoctor() else {
            lastError = "Could not run the Swiper doctor check."
            return false
        }

        doctorReport = report

        if let error = report.frontmostApp.error {
            lastError = "Tracking needs macOS permissions before it can start. \(error.message)"
            openAccessibilitySettings()
            return false
        }

        lastError = nil
        return true
    }

    func elapsedTrackingText(now: Date = Date()) -> String {
        guard let status = trackerStatus,
              status.state == "watching",
              let started = ISO8601DateFormatter().date(from: status.startedAt) else {
            return "Not tracking"
        }

        return format(duration: Int(now.timeIntervalSince(started)))
    }

    func openDailyJSONFolder() {
        NSWorkspace.shared.open(dailyDirURL)
    }

    func openDatabaseFolder() {
        NSWorkspace.shared.open(dbURL.deletingLastPathComponent())
    }

    func openTodaysJSON() {
        let filename = "\(localDayString()).json"
        let fileURL = dailyDirURL.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            NSWorkspace.shared.open(fileURL)
        } else {
            NSWorkspace.shared.open(dailyDirURL)
        }
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
}
