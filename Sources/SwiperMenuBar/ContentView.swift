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
                Button(appState.trackerStatus?.state == "watching" ? "Stop Timer" : "Start Timer") {
                    if appState.trackerStatus?.state == "watching" {
                        appState.pauseTracking()
                    } else {
                        appState.startTracking()
                    }
                }

                Button("Get Stats") {
                    appState.sendTodaysStatsToChatGPT()
                }
            }

            Button("Open Swiper") {
                appState.refreshSessionNotes()
                NSApplication.shared.activate(ignoringOtherApps: true)
                for window in NSApplication.shared.windows where window.title == "Swiper" {
                    window.makeKeyAndOrderFront(nil)
                }
            }

            if let error = appState.lastError {
                Divider()
                Text(error)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            Button("Quit Swiper") {
                appState.handleAppTermination()
                NSApplication.shared.terminate(nil)
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
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("Tracking Off")
                    .font(.subheadline.weight(.semibold))
                Text("Start timer to track app switches and write today's JSON in the background.")
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
