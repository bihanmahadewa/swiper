import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Swiper")
                .font(.headline)

            statusView

            Divider()

            HStack {
                Button(appState.trackerStatus?.state == "watching" ? "Pause Tracking" : "Start Tracking") {
                    if appState.trackerStatus?.state == "watching" {
                        appState.pauseTracking()
                    } else {
                        appState.startTracking()
                    }
                }

                Button("Quit Swiper") {
                    appState.handleAppTermination()
                    NSApplication.shared.terminate(nil)
                }
            }

            Divider()

            Button("Get Report") {
                appState.showReportWindow()
            }

            Divider()

            Button("Open Today's JSON") {
                appState.openTodaysJSON()
            }

            Button("Open Daily JSON Folder") {
                appState.openDailyJSONFolder()
            }

            Button("Open Database Folder") {
                appState.openDatabaseFolder()
            }

            if let error = appState.lastError {
                Divider()
                Text(error)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .onAppear {
            NSApplication.shared.setActivationPolicy(.accessory)
            appState.startPolling()
        }
    }

    @ViewBuilder
    private var statusView: some View {
        if let status = appState.trackerStatus, status.state == "watching" {
            VStack(alignment: .leading, spacing: 6) {
                Text("Tracking On")
                    .font(.subheadline.weight(.semibold))

                Text("Elapsed: \(appState.elapsedTrackingText(now: appState.now))")
                    .font(.system(.body, design: .monospaced))

                Text("Events: \(status.totalEvents)  Ticks: \(status.ticks)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let lastTickAt = status.lastTickAt {
                    Text("Last tick: \(lastTickAt)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("Tracking Off")
                    .font(.subheadline.weight(.semibold))
                Text("Start tracking to write daily JSON snapshots in the background.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Start Tracking will ask for macOS permissions the first time if needed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
