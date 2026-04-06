import crypto from "node:crypto";

export function createId(prefix, ...parts) {
  const hash = crypto
    .createHash("sha1")
    .update(parts.filter(Boolean).join("|"))
    .digest("hex")
    .slice(0, 16);
  return `${prefix}_${hash}`;
}

export function toIsoDate(input) {
  return new Date(input).toISOString();
}

export function toDay(input) {
  return toIsoDate(input).slice(0, 10);
}

export function durationMs(start, end) {
  return Math.max(0, new Date(end).getTime() - new Date(start).getTime());
}

export function hostnameFromUrl(value) {
  if (!value) {
    return null;
  }

  try {
    return new URL(value).hostname.toLowerCase().replace(/^www\./, "");
  } catch {
    return null;
  }
}

export function titleWords(value) {
  if (!value) {
    return [];
  }

  return value
    .toLowerCase()
    .replace(/[^a-z0-9\s/_-]+/g, " ")
    .split(/\s+/)
    .filter((word) => word.length >= 4)
    .filter((word) => !STOP_WORDS.has(word));
}

const STOP_WORDS = new Set([
  "https",
  "http",
  "www",
  "with",
  "from",
  "that",
  "this",
  "your",
  "about",
  "into",
  "while",
  "where",
  "when",
  "have",
  "will",
  "file",
  "edit",
  "view",
  "help",
  "slack",
  "safari",
  "cursor",
  "chrome",
]);

export function mostFrequent(items) {
  const counts = new Map();
  for (const item of items.filter(Boolean)) {
    counts.set(item, (counts.get(item) ?? 0) + 1);
  }

  let best = null;
  let bestCount = -1;
  for (const [item, count] of counts.entries()) {
    if (count > bestCount) {
      best = item;
      bestCount = count;
    }
  }

  return best;
}

export function json(value) {
  return JSON.stringify(value ?? {});
}

export function parseJson(value, fallback = {}) {
  if (!value) {
    return fallback;
  }

  try {
    return JSON.parse(value);
  } catch {
    return fallback;
  }
}

export function sqlQuote(value) {
  if (value === null || value === undefined) {
    return "NULL";
  }

  if (typeof value === "number") {
    return Number.isFinite(value) ? String(value) : "NULL";
  }

  const text = String(value).replaceAll("'", "''");
  return `'${text}'`;
}

export function normalizePath(value) {
  if (!value) {
    return null;
  }

  return value.replace(/^file:\/\//, "");
}
