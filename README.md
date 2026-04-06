# Swiper

Swiper is a macOS activity tracker focused on ground-truth behavioral data: app switches, browser domains, timestamps, durations, and daily reports. It does not rely on screenshots. Instead, it watches frontmost app changes, window changes, browser URL changes, and idle transitions, then turns those observations into a daily activity trace.

## What It Does

- A common raw event envelope for macOS, browser, editor, file, and idle signals
- A macOS collector that inspects the frontmost app, window title, browser URL/title when available, and idle transitions
- Sessionization that groups raw events into activity spans
- A SQLite-backed append-only event/session store plus a graph store for nodes and edges
- Behavior-first reports for app usage, domain usage, app switches, and normalized timelines
- Daily JSON exports for background tracking
- A native SwiftUI menu bar shell for start/pause/report controls
- Scenario-driven tests using Node's built-in test runner

## Project Status

Current strengths:

- Terminal tracking works on macOS when the host app has the right permissions
- Browser URL/domain capture works in Safari when automation access is available
- Reports are now behavior-first instead of keyword-first
- The menu bar app scaffold exists and controls a background tracker + report window

Current caveats:

- The collector is still polling-based rather than fully event-driven
- The menu bar app may require local Swift/Xcode toolchain cleanup depending on your machine
- Raw window titles can contain sensitive information, so privacy controls are still needed

## Requirements

- macOS
- Node.js 22+
- `sqlite3` available on the system
- Accessibility permission for the host app running Swiper
- Automation permission for `System Events`, and optionally Safari/Cursor/Chrome/Arc if you want richer context

## Quick Start

Initialize a database:

```bash
npm run init-db -- ./data/swiper.db
```

Capture one sample from the current macOS desktop and persist derived sessions and graph updates:

```bash
npm run run-once -- ./data/swiper.db
```

Run a short tracker session:

```bash
npm run watch -- ./data/swiper.db --interval 2s --duration 5m
```

Run until you stop it:

```bash
npm run watch -- ./data/swiper.db --interval 2s
```

Run the background tracker without a terminal progress stream:

```bash
npm run daemon -- ./data/swiper-menubar.db --interval 2s
```

Diagnose what the macOS collector can currently see:

```bash
node src/cli.js doctor
```

Generate a report for a day:

```bash
npm run report-day -- ./data/swiper.db 2026-04-05
```

## Report Shape

The day report is behavior-first. It includes:

- `appTimeline`: chronological app/domain/document spans
- `appUsage`: total time and session count by app
- `domainUsage`: total time and session count by browser URL/domain
- `appSwitches`: explicit transitions such as Safari to ChatGPT
- `rawTimeline` and `summary`: the lower-level session and graph views

This means the main questions Swiper answers today are:

- What apps did I switch between?
- When did I switch?
- How long did I spend in each app?
- Which browser domains/URLs were active?

## Menu Bar App

Swiper also includes a native macOS menu bar shell built with SwiftUI.

Build it:

```bash
npm run menu-build
```

Run it:

```bash
npm run menu-run
```

The menu bar app lets you:

- start tracking
- pause tracking
- check permissions
- quit the app
- see elapsed tracking time
- open a minimal report window
- open today's exported JSON
- open the daily JSON folder

Daily JSON exports are written to [data/daily](/Users/bm/Developer/swiper/data/daily) while tracking runs in the background.

## Permissions

The easiest permission smoke test is:

```bash
osascript -e 'tell application "System Events" to return name of first application process whose frontmost is true'
node src/cli.js doctor
```

If that works in Terminal, Swiper should also work from Terminal.

## Development

Run tests:

```bash
npm test
```

Useful files:

- [src/cli.js](/Users/bm/Developer/swiper/src/cli.js): tracker commands
- [src/collectors/macos.js](/Users/bm/Developer/swiper/src/collectors/macos.js): macOS collector and doctor probes
- [src/query.js](/Users/bm/Developer/swiper/src/query.js): behavior-first reporting
- [Sources/SwiperMenuBar](/Users/bm/Developer/swiper/Sources/SwiperMenuBar): SwiftUI menu bar app

## Notes

- v1 is macOS-only.
- Screenshots are intentionally excluded from the architecture.
- The default watch interval is `2s` because Swiper currently works best as a state-change collector rather than a minute-by-minute summarizer.
