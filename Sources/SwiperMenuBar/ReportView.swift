import SwiftUI

struct ReportView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ZStack {
            Color(red: 0.11, green: 0.11, blue: 0.11)
                .ignoresSafeArea()

            if let selected = appState.selectedNoteItem {
                SessionDetailView(item: selected)
                    .environmentObject(appState)
            } else {
                VStack(alignment: .leading, spacing: 18) {
                    header

                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 22) {
                            if appState.noteSections.isEmpty {
                                emptyState
                            } else {
                                ForEach(appState.noteSections) { section in
                                    VStack(alignment: .leading, spacing: 12) {
                                        Text(section.title)
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(.secondary)

                                        ForEach(section.items) { item in
                                            noteRow(item)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.bottom, 24)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(minWidth: 760, minHeight: 620)
        .onAppear {
            appState.refreshSessionNotes()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Sessions")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.white)

                    Text("Granola-style summaries of your tracked sessions.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 16)

                quickSessionControls
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("OpenAI API Key")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    SecureField("Paste your OpenAI API key", text: $appState.openAIKeyInput)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(.white)

                    Button("Paste") {
                        appState.pasteOpenAIKeyFromClipboard()
                    }
                    .buttonStyle(.bordered)

                    Button("Save") {
                        appState.saveOpenAIKey()
                    }
                    .buttonStyle(.borderedProminent)
                }

                Text(appState.hasOpenAIKey() ? "OpenAI summaries enabled." : "Fallback titles are shown until a key is saved.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let error = appState.lastError {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(Color(red: 0.92, green: 0.72, blue: 0.72))
                    .fixedSize(horizontal: false, vertical: true)
            } else if appState.trackerStatus?.state == "watching" {
                Text("Tracking now: \(appState.elapsedTrackingText(now: appState.now))")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var quickSessionControls: some View {
        HStack(spacing: 8) {
            if appState.trackerStatus?.state == "watching" {
                Button("Pause") {
                    appState.pauseTracking()
                }
                .buttonStyle(.bordered)

                Button("End") {
                    appState.pauseTracking()
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button("Start Tracking") {
                    appState.startTracking()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No sessions yet")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.white)

            Text("Start the timer, switch through a few apps, then come back here to browse summarized sessions.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 32)
    }

    private func noteRow(_ item: SessionNoteItem) -> some View {
        Button {
            appState.openSessionDetail(item)
        } label: {
            HStack(alignment: .top, spacing: 14) {
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
                    .background(
                        RoundedRectangle(cornerRadius: 9)
                            .fill(Color.white.opacity(0.04))
                    )
                    .frame(width: 32, height: 32)
                    .overlay(
                        Image(systemName: "doc.text")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white.opacity(0.8))
                    )

                VStack(alignment: .leading, spacing: 6) {
                    Text(item.title)
                        .font(.system(size: 21, weight: .regular))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.leading)

                    Text(item.isSummarizing ? "Summarizing with OpenAI..." : item.subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)

                    if let startedAt = item.startedAt, let endedAt = item.endedAt {
                        Text("\(timeRange(startedAt: startedAt, endedAt: endedAt))")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary.opacity(0.9))
                    }
                }

                Spacer(minLength: 12)

                Text(item.timeLabel)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }

    private func timeRange(startedAt: Date, endedAt: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        formatter.timeZone = .current
        return "\(formatter.string(from: startedAt)) - \(formatter.string(from: endedAt))"
    }
}

struct SessionDetailView: View {
    @EnvironmentObject private var appState: AppState
    let item: SessionNoteItem

    var body: some View {
        ZStack {
            Color(red: 0.11, green: 0.11, blue: 0.11)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Button {
                            appState.closeSessionDetail()
                        } label: {
                            Label("Back", systemImage: "chevron.left")
                        }
                        .buttonStyle(.bordered)

                        Spacer()
                    }

                    Text(item.title)
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.white)

                    Text(item.subtitle)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)

                    if appState.isLoadingSelectedNoteDetail {
                        Text("Generating detailed summary...")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    } else {
                        Text(appState.selectedNoteDetailMarkdown)
                            .font(.system(size: 14))
                            .foregroundStyle(.white)
                            .textSelection(.enabled)
                    }

                    Button("Reveal Session JSON") {
                        appState.revealSessionFile(item)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 700, minHeight: 520)
    }
}
