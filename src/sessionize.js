import { createId, durationMs, hostnameFromUrl, mostFrequent, titleWords, toDay } from "./util.js";

const DEFAULTS = {
  idleGapMs: 5 * 60 * 1000,
  bounceWindowMs: 90 * 1000,
};

export class Sessionizer {
  constructor(options = {}) {
    this.options = {
      ...DEFAULTS,
      ...options,
    };
  }

  buildSessions(events) {
    if (!events.length) {
      return [];
    }

    const ordered = [...events].sort(
      (left, right) => new Date(left.timestampStart).getTime() - new Date(right.timestampStart).getTime(),
    );

    const groups = [];
    let current = [ordered[0]];

    for (let index = 1; index < ordered.length; index += 1) {
      const previous = ordered[index - 1];
      const event = ordered[index];
      if (shouldSplitSession(previous, event, this.options)) {
        groups.push(current);
        current = [event];
      } else {
        current.push(event);
      }
    }

    groups.push(current);

    return mergeBounces(groups, this.options.bounceWindowMs).map((group) => createSession(group));
  }
}

function shouldSplitSession(previous, next, options) {
  if (previous.eventType === "idle_start" || next.eventType === "idle_end") {
    return true;
  }

  const gapMs = new Date(next.timestampStart).getTime() - new Date(previous.timestampStart).getTime();
  if (gapMs > options.idleGapMs) {
    return true;
  }

  if (previous.appBundleId && next.appBundleId && previous.appBundleId !== next.appBundleId) {
    return true;
  }

  const previousHost = hostnameFromUrl(previous.url);
  const nextHost = hostnameFromUrl(next.url);
  if (previousHost && nextHost && previousHost !== nextHost) {
    return true;
  }

  if (previous.documentPath && next.documentPath && previous.documentPath !== next.documentPath) {
    return true;
  }

  return false;
}

function mergeBounces(groups, bounceWindowMs) {
  if (groups.length < 3) {
    return groups;
  }

  const merged = [groups[0]];

  for (let index = 1; index < groups.length; index += 1) {
    const current = groups[index];
    const previous = merged[merged.length - 1];
    const next = groups[index + 1];

    if (!next) {
      merged.push(current);
      continue;
    }

    const currentDuration = groupDuration(current);
    const previousKey = focusKey(previous[0]);
    const nextKey = focusKey(next[0]);
    const currentKey = focusKey(current[0]);

    if (
      currentDuration <= bounceWindowMs &&
      previousKey &&
      previousKey === nextKey &&
      currentKey !== previousKey
    ) {
      merged[merged.length - 1] = [...previous, ...current, ...next];
      index += 1;
      continue;
    }

    merged.push(current);
  }

  return merged;
}

function groupDuration(group) {
  return durationMs(group[0].timestampStart, group[group.length - 1].timestampStart);
}

function focusKey(event) {
  return event.documentPath ?? hostnameFromUrl(event.url) ?? event.appBundleId ?? event.appName ?? null;
}

function createSession(events) {
  const start = events[0].timestampStart;
  const end = events[events.length - 1].timestampStart;
  const dominantAppName = mostFrequent(events.map((event) => event.appName));
  const dominantAppBundleId = mostFrequent(events.map((event) => event.appBundleId));
  const dominantWindowTitle = mostFrequent(events.map((event) => event.windowTitle));
  const dominantUrl = mostFrequent(events.map((event) => event.url));
  const dominantDocumentPath = mostFrequent(events.map((event) => event.documentPath));
  const explanation = inferExplanation({
    dominantAppName,
    dominantWindowTitle,
    dominantUrl,
    dominantDocumentPath,
  });
  const semanticHints = deriveSemanticHints(events);

  return {
    sessionId: createId(
      "ses",
      start,
      end,
      dominantAppBundleId ?? dominantAppName ?? "unknown",
      ...events.map((event) => event.eventId),
    ),
    day: toDay(start),
    timestampStart: start,
    timestampEnd: end,
    durationMs: durationMs(start, end),
    dominantAppBundleId,
    dominantAppName,
    dominantWindowTitle,
    dominantUrl,
    dominantDocumentPath,
    taskLabel: explanation.label,
    explanation,
    rawEventIds: events.map((event) => event.eventId),
    topicHints: semanticHints.topicHints,
    personHints: semanticHints.personHints,
  };
}

function inferExplanation(context) {
  const reasons = [];

  if (context.dominantDocumentPath) {
    reasons.push(`document:${context.dominantDocumentPath}`);
  }

  const host = hostnameFromUrl(context.dominantUrl);
  if (host) {
    reasons.push(`website:${host}`);
  }

  if (context.dominantWindowTitle) {
    const keywords = titleWords(context.dominantWindowTitle).slice(0, 3);
    if (keywords.length) {
      reasons.push(`window:${keywords.join(",")}`);
    }
  }

  if (context.dominantAppName) {
    reasons.push(`app:${context.dominantAppName}`);
  }

  const label =
    context.dominantDocumentPath?.split("/").pop() ||
    host ||
    context.dominantWindowTitle ||
    context.dominantAppName ||
    "Unlabeled session";

  return {
    label,
    reasons,
    confidence: reasons.length >= 2 ? 0.8 : 0.6,
  };
}

function deriveSemanticHints(events) {
  const topicCounts = new Map();
  const personHints = new Set();

  for (const event of events) {
    const host = hostnameFromUrl(event.url);
    if (host) {
      for (const part of host.split(".")) {
        if (part.length >= 4 && !GENERIC_HOST_PARTS.has(part)) {
          topicCounts.set(part, (topicCounts.get(part) ?? 0) + 2);
        }
      }
    }

    for (const word of titleWords(event.windowTitle ?? "")) {
      topicCounts.set(word, (topicCounts.get(word) ?? 0) + 1);
    }

    const directPerson = extractDirectPersonHint(event.windowTitle ?? "");
    if (directPerson) {
      personHints.add(directPerson);
    }
  }

  return {
    topicHints: [...topicCounts.entries()]
      .filter(([, count]) => count >= 2)
      .sort((left, right) => right[1] - left[1] || left[0].localeCompare(right[0]))
      .map(([word]) => word)
      .slice(0, 5),
    personHints: [...personHints].slice(0, 5),
  };
}

function extractDirectPersonHint(windowTitle) {
  const dmMatch = windowTitle.match(/^(.+?) \((?:DM|Direct Message)\)(?: - .+)?$/i);
  if (dmMatch) {
    return dmMatch[1].trim();
  }

  for (const match of windowTitle.matchAll(/\b([a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,})\b/gi)) {
    return match[1].toLowerCase();
  }

  return null;
}

const GENERIC_HOST_PARTS = new Set(["www", "com", "app", "docs"]);
