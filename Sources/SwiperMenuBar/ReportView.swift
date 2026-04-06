import SwiftUI

struct ReportView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Daily Report")
                    .font(.title3)

                if let report = appState.dailyReport {
                    Text(report.day)
                        .font(.subheadline)

                    reportSection("App Usage") {
                        ForEach(report.appUsage) { entry in
                            reportRow(
                                title: entry.app_name,
                                detail: "\(appState.formatDuration(ms: entry.total_duration_ms))  \(entry.session_count) sessions"
                            )
                        }
                    }

                    reportSection("Domain Usage") {
                        if report.domainUsage.isEmpty {
                            Text("No browser domains recorded.")
                        } else {
                            ForEach(report.domainUsage) { entry in
                                reportRow(
                                    title: entry.domain ?? entry.url,
                                    detail: "\(appState.formatDuration(ms: entry.totalDurationMs))"
                                )
                            }
                        }
                    }

                    reportSection("App Switches") {
                        if report.appSwitches.isEmpty {
                            Text("No app switches recorded.")
                        } else {
                            ForEach(report.appSwitches) { entry in
                                reportRow(
                                    title: "\(entry.fromApp ?? "Unknown") -> \(entry.toApp ?? "Unknown")",
                                    detail: entry.timestamp
                                )
                            }
                        }
                    }

                    reportSection("Timeline") {
                        ForEach(report.appTimeline) { entry in
                            reportRow(
                                title: entry.appName ?? "Unknown",
                                detail: "\(entry.timestampStart)  \(appState.formatDuration(ms: entry.durationMs))"
                            )
                        }
                    }
                } else {
                    Text("No report loaded yet.")
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 620, minHeight: 520)
        .onAppear {
            appState.loadTodaysReport()
        }
    }

    private func reportSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            content()
        }
    }

    private func reportRow(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.body)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }
}
