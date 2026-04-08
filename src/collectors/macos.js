import { execFileSync } from "node:child_process";
import { Collector } from "./base.js";
import { createId, normalizePath, toLocalTimestamp } from "../util.js";

const FRONTMOST_APP_SCRIPT = `
tell application "System Events"
  set frontApp to first application process whose frontmost is true
  set appName to name of frontApp
  set unixId to unix id of frontApp
  try
    set windowName to name of first window of frontApp
  on error
    set windowName to ""
  end try
  return appName & "||" & (unixId as text) & "||" & windowName
end tell
`;

export class MacOSCollector extends Collector {
  constructor(options = {}) {
    super();
    this.previousSnapshot = null;
    this.idleThresholdMs = options.idleThresholdMs ?? 5 * 60 * 1000;
  }

  async collect() {
    const snapshot = captureSnapshot(this.idleThresholdMs);
    const events = deriveEvents(this.previousSnapshot, snapshot);
    this.previousSnapshot = snapshot;
    return events;
  }
}

export function captureSnapshot(idleThresholdMs = 5 * 60 * 1000) {
  const timestamp = toLocalTimestamp();
  const frontmostResult = runAppleScript(FRONTMOST_APP_SCRIPT);
  const frontmost = parseFrontmostApp(frontmostResult.output);
  const browserContext = captureBrowserContext(frontmost.appName);
  const idleMs = readIdleMs();
  const isIdle = idleMs >= idleThresholdMs;
  const errors = [
    formatProbeError("frontmostApp", frontmostResult.error),
    formatProbeError("browserContext", browserContext.error),
  ].filter(Boolean);

  return {
    timestamp,
    idleMs,
    isIdle,
    appName: frontmost.appName,
    appBundleId: frontmost.appBundleId,
    windowTitle: frontmost.windowTitle || null,
    url: browserContext.url,
    pageTitle: browserContext.pageTitle,
    documentPath: browserContext.documentPath,
    rawPayload: {
      pageTitle: browserContext.pageTitle,
      idleMs,
      probeErrors: errors,
    },
  };
}

export function runDoctor() {
  const frontmostResult = runAppleScript(FRONTMOST_APP_SCRIPT);
  const frontmost = parseFrontmostApp(frontmostResult.output);
  const browserContext = captureBrowserContext(frontmost.appName);
  const idleMs = readIdleMs();

  return {
    timestamp: toLocalTimestamp(),
    frontmostApp: {
      appName: frontmost.appName,
      appBundleId: frontmost.appBundleId,
      windowTitle: frontmost.windowTitle,
      rawOutput: frontmostResult.output,
      error: frontmostResult.error,
    },
    browserContext,
    idle: {
      idleMs,
      isIdle: idleMs >= 5 * 60 * 1000,
    },
  };
}

export function deriveEvents(previousSnapshot, snapshot) {
  const events = [];
  const previous = previousSnapshot;

  if (!previous || previous.isIdle !== snapshot.isIdle) {
    events.push({
      eventId: createId("evt", snapshot.timestamp, "idle", String(snapshot.isIdle)),
      timestampStart: snapshot.timestamp,
      timestampEnd: snapshot.timestamp,
      durationMs: 0,
      source: "macos",
      eventType: snapshot.isIdle ? "idle_start" : "idle_end",
      appBundleId: snapshot.appBundleId,
      appName: snapshot.appName,
      windowTitle: snapshot.windowTitle,
      url: snapshot.url,
      documentPath: snapshot.documentPath,
      rawPayload: snapshot.rawPayload,
      confidence: 0.95,
    });
  }

  if (!previous || previous.appBundleId !== snapshot.appBundleId) {
    events.push({
      eventId: createId("evt", snapshot.timestamp, "app", snapshot.appBundleId ?? snapshot.appName ?? "unknown"),
      timestampStart: snapshot.timestamp,
      timestampEnd: snapshot.timestamp,
      durationMs: 0,
      source: "macos",
      eventType: "app_focus",
      appBundleId: snapshot.appBundleId,
      appName: snapshot.appName,
      windowTitle: snapshot.windowTitle,
      url: snapshot.url,
      documentPath: snapshot.documentPath,
      rawPayload: snapshot.rawPayload,
      confidence: 0.98,
    });
  }

  if (!previous || previous.windowTitle !== snapshot.windowTitle) {
    events.push({
      eventId: createId("evt", snapshot.timestamp, "window", snapshot.windowTitle ?? ""),
      timestampStart: snapshot.timestamp,
      timestampEnd: snapshot.timestamp,
      durationMs: 0,
      source: "macos",
      eventType: "window_focus",
      appBundleId: snapshot.appBundleId,
      appName: snapshot.appName,
      windowTitle: snapshot.windowTitle,
      url: snapshot.url,
      documentPath: snapshot.documentPath,
      rawPayload: snapshot.rawPayload,
      confidence: 0.9,
    });
  }

  if (!previous || previous.url !== snapshot.url) {
    events.push({
      eventId: createId("evt", snapshot.timestamp, "url", snapshot.url ?? ""),
      timestampStart: snapshot.timestamp,
      timestampEnd: snapshot.timestamp,
      durationMs: 0,
      source: "browser",
      eventType: "browser_navigation",
      appBundleId: snapshot.appBundleId,
      appName: snapshot.appName,
      windowTitle: snapshot.pageTitle ?? snapshot.windowTitle,
      url: snapshot.url,
      documentPath: snapshot.documentPath,
      rawPayload: snapshot.rawPayload,
      confidence: snapshot.url ? 0.92 : 0.5,
    });
  }

  if (!previous || previous.documentPath !== snapshot.documentPath) {
    events.push({
      eventId: createId("evt", snapshot.timestamp, "doc", snapshot.documentPath ?? ""),
      timestampStart: snapshot.timestamp,
      timestampEnd: snapshot.timestamp,
      durationMs: 0,
      source: "editor",
      eventType: "document_focus",
      appBundleId: snapshot.appBundleId,
      appName: snapshot.appName,
      windowTitle: snapshot.windowTitle,
      url: snapshot.url,
      documentPath: snapshot.documentPath,
      rawPayload: snapshot.rawPayload,
      confidence: snapshot.documentPath ? 0.88 : 0.4,
    });
  }

  return events;
}

function parseFrontmostApp(output) {
  const [appName = "Unknown", unixId = "", windowTitle = ""] = output.trim().split("||");
  return {
    appName: appName || null,
    appBundleId: unixId ? `pid:${unixId}` : null,
    windowTitle: windowTitle || null,
  };
}

function captureBrowserContext(appName) {
  switch (appName) {
    case "Safari":
      return readSafariContext();
    case "Google Chrome":
    case "Arc":
      return readChromeContext(appName);
    case "Cursor":
      return readCursorContext();
    default:
      return { url: null, pageTitle: null, documentPath: null, error: null };
  }
}

function readSafariContext() {
  const script = `
tell application "Safari"
  if (count of windows) = 0 then
    return "||"
  end if
  set currentTab to current tab of front window
  return (URL of currentTab as text) & "||" & (name of currentTab as text)
end tell
`;

  const result = runAppleScript(script);
  const [url = "", pageTitle = ""] = result.output.trim().split("||");
  return { url: url || null, pageTitle: pageTitle || null, documentPath: null, error: result.error };
}

function readChromeContext(appName) {
  const script = `
tell application "${appName}"
  if (count of windows) = 0 then
    return "||"
  end if
  set currentTab to active tab of front window
  return (URL of currentTab as text) & "||" & (title of currentTab as text)
end tell
`;

  const result = runAppleScript(script);
  const [url = "", pageTitle = ""] = result.output.trim().split("||");
  return { url: url || null, pageTitle: pageTitle || null, documentPath: null, error: result.error };
}

function readCursorContext() {
  const script = `
tell application "System Events"
  tell process "Cursor"
    try
      set currentWindow to first window
      return name of currentWindow
    on error
      return ""
    end try
  end tell
end tell
`;

  const result = runAppleScript(script);
  const title = result.output.trim();
  const documentPath = extractPathFromWindowTitle(title);
  return { url: null, pageTitle: title || null, documentPath, error: result.error };
}

function extractPathFromWindowTitle(title) {
  if (!title) {
    return null;
  }

  const match = title.match(/(\/[^ ]+\.[A-Za-z0-9]+)\b/);
  return normalizePath(match?.[1] ?? null);
}

function runAppleScript(script) {
  try {
    return {
      output: execFileSync("osascript", ["-e", script], {
        encoding: "utf8",
        stdio: "pipe",
      }),
      error: null,
    };
  } catch (error) {
    return {
      output: "",
      error: {
        message: error.stderr?.toString?.().trim?.() || error.message,
        status: error.status ?? null,
      },
    };
  }
}

function formatProbeError(source, error) {
  if (!error) {
    return null;
  }

  return {
    source,
    ...error,
  };
}

function readIdleMs() {
  try {
    const output = execFileSync("ioreg", ["-c", "IOHIDSystem"], {
      encoding: "utf8",
      stdio: "pipe",
    });
    const match = output.match(/"HIDIdleTime" = (\d+)/);
    if (!match) {
      return 0;
    }
    return Math.floor(Number(match[1]) / 1_000_000);
  } catch {
    return 0;
  }
}
