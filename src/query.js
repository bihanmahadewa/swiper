import { querySql } from "./sqlite.js";
import { parseJson, sqlQuote } from "./util.js";

export class GraphQuery {
  constructor(dbPath) {
    this.dbPath = dbPath;
  }

  dailyTimeline(day) {
    return querySql(
      this.dbPath,
      `SELECT session_id, timestamp_start, timestamp_end, duration_ms, task_label,
              dominant_app_name, dominant_url, dominant_document_path, explanation
       FROM sessions
       WHERE day = ${sqlQuote(day)}
       ORDER BY timestamp_start ASC;`,
    ).map((row) => ({
      sessionId: row.session_id,
      timestampStart: row.timestamp_start,
      timestampEnd: row.timestamp_end,
      durationMs: row.duration_ms,
      taskLabel: row.task_label,
      dominantAppName: row.dominant_app_name,
      dominantUrl: row.dominant_url,
      dominantDocumentPath: row.dominant_document_path,
      explanation: parseJson(row.explanation, {}),
    }));
  }

  sessionsForEntity(label) {
    return querySql(
      this.dbPath,
      `SELECT gn.label AS entity_label, gn.node_type, ge.edge_type, ge.session_id
       FROM graph_nodes gn
       JOIN graph_edges ge ON ge.to_node_id = gn.node_id
       WHERE gn.label = ${sqlQuote(label)}
       ORDER BY ge.session_id ASC;`,
    );
  }

  dailySummary(day) {
    return querySql(
      this.dbPath,
      `SELECT gn.node_type, gn.label, COUNT(*) AS mentions
       FROM graph_nodes gn
       JOIN graph_edges ge ON ge.to_node_id = gn.node_id
       JOIN sessions s ON s.session_id = ge.session_id
       WHERE s.day = ${sqlQuote(day)}
         AND gn.node_type IN ('App', 'Website', 'Document', 'Project')
       GROUP BY gn.node_type, gn.label
       ORDER BY mentions DESC, gn.label ASC;`,
    );
  }

  appTimeline(day) {
    const timeline = querySql(
      this.dbPath,
      `SELECT session_id, timestamp_start, timestamp_end, duration_ms,
              dominant_app_name, dominant_url, dominant_document_path
       FROM sessions
       WHERE day = ${sqlQuote(day)}
       ORDER BY timestamp_start ASC;`,
    ).map((row) => ({
      sessionId: row.session_id,
      timestampStart: row.timestamp_start,
      timestampEnd: row.timestamp_end,
      durationMs: row.duration_ms,
      appName: row.dominant_app_name,
      url: row.dominant_url,
      domain: hostname(row.dominant_url),
      documentPath: row.dominant_document_path,
    }));

    return deriveBehaviorTimeline(timeline);
  }

  appUsage(day) {
    const usage = aggregateBy(this.appTimeline(day), (entry) => entry.appName ?? "Unknown");
    return usage.map(([app_name, values]) => ({
      app_name,
      total_duration_ms: values.totalDurationMs,
      session_count: values.sessionCount,
    }));
  }

  domainUsage(day) {
    const timeline = this.appTimeline(day).filter((entry) => entry.url);
    const usage = aggregateBy(timeline, (entry) => entry.url);
    return usage.map(([url, values]) => ({
      url,
      domain: hostname(url),
      totalDurationMs: values.totalDurationMs,
      sessionCount: values.sessionCount,
    }));
  }

  appSwitches(day) {
    const timeline = this.appTimeline(day);
    const switches = [];

    for (let index = 1; index < timeline.length; index += 1) {
      const previous = timeline[index - 1];
      const current = timeline[index];
      if (previous.appName === current.appName) {
        continue;
      }

      switches.push({
        timestamp: current.timestampStart,
        fromApp: previous.appName,
        toApp: current.appName,
        fromDomain: previous.domain,
        toDomain: current.domain,
      });
    }

    return switches;
  }

  dailyBehaviorReport(day) {
    return {
      day,
      appTimeline: this.appTimeline(day),
      appUsage: this.appUsage(day),
      domainUsage: this.domainUsage(day),
      appSwitches: this.appSwitches(day),
      rawTimeline: this.dailyTimeline(day),
      summary: this.dailySummary(day),
    };
  }
}

function hostname(value) {
  if (!value) {
    return null;
  }

  try {
    return new URL(value).hostname.toLowerCase().replace(/^www\./, "");
  } catch {
    return null;
  }
}

function deriveBehaviorTimeline(entries) {
  const normalized = [];

  for (const entry of entries) {
    const last = normalized.at(-1);
    if (last && sameState(last, entry)) {
      last.sessionIds.push(entry.sessionId);
      last.timestampEnd = laterTimestamp(last.timestampEnd, entry.timestampEnd);
      last.durationMs = Math.max(last.durationMs, entry.durationMs);
      continue;
    }

    normalized.push({
      ...entry,
      sessionIds: [entry.sessionId],
    });
  }

  for (let index = 0; index < normalized.length; index += 1) {
    const current = normalized[index];
    const next = normalized[index + 1];
    const observedDurationMs = durationBetween(current.timestampStart, current.timestampEnd);
    const closedDurationMs = next
      ? durationBetween(current.timestampStart, next.timestampStart)
      : observedDurationMs;

    const effectiveDurationMs = Math.max(current.durationMs, observedDurationMs, closedDurationMs);
    current.durationMs = effectiveDurationMs;
    current.timestampEnd = new Date(
      new Date(current.timestampStart).getTime() + effectiveDurationMs,
    ).toISOString();
  }

  return normalized;
}

function sameState(left, right) {
  return (
    (left.appName ?? null) === (right.appName ?? null) &&
    (left.url ?? null) === (right.url ?? null) &&
    (left.documentPath ?? null) === (right.documentPath ?? null)
  );
}

function laterTimestamp(left, right) {
  return new Date(left).getTime() >= new Date(right).getTime() ? left : right;
}

function durationBetween(start, end) {
  return Math.max(0, new Date(end).getTime() - new Date(start).getTime());
}

function aggregateBy(entries, keyFn) {
  const map = new Map();
  for (const entry of entries) {
    const key = keyFn(entry);
    const current = map.get(key) ?? { totalDurationMs: 0, sessionCount: 0 };
    current.totalDurationMs += entry.durationMs;
    current.sessionCount += 1;
    map.set(key, current);
  }

  return [...map.entries()].sort((left, right) => {
    if (right[1].totalDurationMs !== left[1].totalDurationMs) {
      return right[1].totalDurationMs - left[1].totalDurationMs;
    }
    if (right[1].sessionCount !== left[1].sessionCount) {
      return right[1].sessionCount - left[1].sessionCount;
    }
    return String(left[0]).localeCompare(String(right[0]));
  });
}
