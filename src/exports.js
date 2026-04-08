import path from "node:path";
import { createRuntimePaths, ensureRuntimeDirectories, writeJsonFile } from "./runtime.js";

export function exportDailyJson({ dbPath, day, report }) {
  const paths = createRuntimePaths(dbPath);
  ensureRuntimeDirectories(paths);
  const exportPath = path.join(paths.dailyDir, `${day}.json`);
  writeJsonFile(exportPath, report);
  return exportPath;
}

export function exportSessionJson({ dbPath, sessionId, sessionStartedAt, report }) {
  const paths = createRuntimePaths(dbPath);
  ensureRuntimeDirectories(paths);
  const exportPath = path.join(paths.sessionsDir, `${sessionId}.json`);
  writeJsonFile(exportPath, sessionScopedReport(report, sessionStartedAt));
  return exportPath;
}

function sessionScopedReport(report, sessionStartedAt) {
  const appTimeline = report.appTimeline.filter((entry) => entry.timestampStart >= sessionStartedAt);
  const rawTimeline = report.rawTimeline.filter((entry) => entry.timestampStart >= sessionStartedAt);
  const appSwitches = report.appSwitches.filter((entry) => entry.timestamp >= sessionStartedAt);

  return {
    ...report,
    appTimeline,
    appUsage: aggregateUsage(appTimeline, (entry) => entry.appName ?? "Unknown", "app_name", "total_duration_ms"),
    domainUsage: aggregateUsage(
      appTimeline.filter((entry) => entry.url),
      (entry) => entry.url,
      "url",
      "totalDurationMs",
      (entry) => ({ domain: entry.domain ?? null }),
    ),
    appSwitches,
    rawTimeline,
    summary: [],
  };
}

function aggregateUsage(entries, keyFn, labelKey, durationKey, extrasFn = null) {
  const map = new Map();

  for (const entry of entries) {
    const key = keyFn(entry);
    if (!key) {
      continue;
    }

    const current = map.get(key) ?? { totalDurationMs: 0, sessionCount: 0 };
    current.totalDurationMs += entry.durationMs;
    current.sessionCount += 1;
    map.set(key, current);
  }

  return [...map.entries()]
    .sort((left, right) => right[1].totalDurationMs - left[1].totalDurationMs || String(left[0]).localeCompare(String(right[0])))
    .map(([key, value]) => ({
      [labelKey]: key,
      ...(extrasFn ? extrasFn(entries.find((entry) => keyFn(entry) === key)) : {}),
      [durationKey]: value.totalDurationMs,
      sessionCount: value.sessionCount,
      ...(labelKey === "app_name" ? { session_count: value.sessionCount } : {}),
    }))
    .map((item) => {
      if (labelKey === "app_name") {
        const { sessionCount, ...rest } = item;
        return rest;
      }
      return item;
    });
}
