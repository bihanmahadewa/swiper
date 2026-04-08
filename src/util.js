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
  return toLocalTimestamp(input);
}

export function toDay(input) {
  return toLocalTimestamp(input).slice(0, 10);
}

export function toLocalTimestamp(input = new Date()) {
  const date = input instanceof Date ? input : new Date(input);
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  const hours = String(date.getHours()).padStart(2, "0");
  const minutes = String(date.getMinutes()).padStart(2, "0");
  const seconds = String(date.getSeconds()).padStart(2, "0");
  const milliseconds = String(date.getMilliseconds()).padStart(3, "0");
  const offsetMinutes = -date.getTimezoneOffset();
  const sign = offsetMinutes >= 0 ? "+" : "-";
  const absOffsetMinutes = Math.abs(offsetMinutes);
  const offsetHours = String(Math.floor(absOffsetMinutes / 60)).padStart(2, "0");
  const offsetRemainder = String(absOffsetMinutes % 60).padStart(2, "0");

  return `${year}-${month}-${day}T${hours}:${minutes}:${seconds}.${milliseconds}${sign}${offsetHours}:${offsetRemainder}`;
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
