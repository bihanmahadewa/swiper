import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import { SwiperEngine } from "../src/pipeline.js";
import { GraphQuery } from "../src/query.js";
import { createId } from "../src/util.js";

function makeEvent({
  timestamp,
  source,
  eventType,
  appName,
  appBundleId,
  windowTitle = null,
  url = null,
  documentPath = null,
}) {
  return {
    eventId: createId("evt", timestamp, source, eventType, appBundleId ?? appName ?? "unknown", url ?? "", documentPath ?? ""),
    timestampStart: timestamp,
    timestampEnd: timestamp,
    durationMs: 0,
    source,
    eventType,
    appBundleId,
    appName,
    windowTitle,
    url,
    documentPath,
    rawPayload: {},
    confidence: 0.95,
  };
}

function withTempDb(t) {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "swiper-test-"));
  const dbPath = path.join(directory, "swiper.db");
  t.after(() => fs.rmSync(directory, { recursive: true, force: true }));
  return dbPath;
}

test("builds distinct but related sessions across apps and websites", (t) => {
  const dbPath = withTempDb(t);
  const engine = new SwiperEngine({ dbPath, collector: { collect: async () => [] } });
  engine.init();

  const day = "2026-04-05";
  engine.ingestEvents([
    makeEvent({
      timestamp: `${day}T09:00:00.000Z`,
      source: "browser",
      eventType: "browser_navigation",
      appName: "Safari",
      appBundleId: "com.apple.Safari",
      windowTitle: "Researching tax nexus",
      url: "https://www.irs.gov/filing",
    }),
    makeEvent({
      timestamp: `${day}T09:02:00.000Z`,
      source: "browser",
      eventType: "browser_navigation",
      appName: "Safari",
      appBundleId: "com.apple.Safari",
      windowTitle: "Researching tax nexus in California",
      url: "https://www.irs.gov/payments",
    }),
    makeEvent({
      timestamp: `${day}T09:20:00.000Z`,
      source: "editor",
      eventType: "document_focus",
      appName: "Cursor",
      appBundleId: "com.todesktop.230313mzl4w4u92",
      windowTitle: "proposal.md - swiper",
      documentPath: "/Users/bm/Developer/swiper/proposal.md",
    }),
    makeEvent({
      timestamp: `${day}T09:45:00.000Z`,
      source: "macos",
      eventType: "app_focus",
      appName: "Slack",
      appBundleId: "com.tinyspeck.slackmacgap",
      windowTitle: "Alice Johnson (DM) - Slack",
    }),
  ]);

  const query = new GraphQuery(dbPath);
  const timeline = query.dailyTimeline(day);
  const summary = query.dailySummary(day);
  const personSessions = query.sessionsForEntity("Alice Johnson");

  assert.equal(timeline.length, 3);
  assert.deepEqual(
    timeline.map((session) => session.dominantAppName),
    ["Safari", "Cursor", "Slack"],
  );
  assert.ok(summary.some((item) => item.node_type === "Website" && item.label === "irs.gov"));
  assert.ok(summary.some((item) => item.node_type === "Project" && item.label === "swiper"));
  assert.equal(personSessions.length, 1);
  assert.ok(!summary.some((item) => item.node_type === "Person" && item.label === "Researching Tax"));
});

test("keeps rapid same-domain tab changes inside one session", (t) => {
  const dbPath = withTempDb(t);
  const engine = new SwiperEngine({ dbPath, collector: { collect: async () => [] } });
  engine.init();

  const day = "2026-04-05";
  engine.ingestEvents([
    makeEvent({
      timestamp: `${day}T10:00:00.000Z`,
      source: "browser",
      eventType: "browser_navigation",
      appName: "Safari",
      appBundleId: "com.apple.Safari",
      windowTitle: "OpenAI docs",
      url: "https://platform.openai.com/docs/overview",
    }),
    makeEvent({
      timestamp: `${day}T10:00:30.000Z`,
      source: "browser",
      eventType: "browser_navigation",
      appName: "Safari",
      appBundleId: "com.apple.Safari",
      windowTitle: "OpenAI docs API reference",
      url: "https://platform.openai.com/docs/api-reference",
    }),
    makeEvent({
      timestamp: `${day}T10:01:00.000Z`,
      source: "browser",
      eventType: "browser_navigation",
      appName: "Safari",
      appBundleId: "com.apple.Safari",
      windowTitle: "OpenAI docs guides",
      url: "https://platform.openai.com/docs/guides",
    }),
  ]);

  const query = new GraphQuery(dbPath);
  const timeline = query.dailyTimeline(day);
  assert.equal(timeline.length, 1);
  assert.equal(timeline[0].dominantUrl, "https://platform.openai.com/docs/overview");
});

test("starts a new session after idle and resolves repeated entities across the day", (t) => {
  const dbPath = withTempDb(t);
  const engine = new SwiperEngine({ dbPath, collector: { collect: async () => [] } });
  engine.init();

  const day = "2026-04-05";
  engine.ingestEvents([
    makeEvent({
      timestamp: `${day}T11:00:00.000Z`,
      source: "editor",
      eventType: "document_focus",
      appName: "Cursor",
      appBundleId: "com.todesktop.230313mzl4w4u92",
      windowTitle: "graph.js - swiper",
      documentPath: "/Users/bm/Developer/swiper/src/graph.js",
    }),
    makeEvent({
      timestamp: `${day}T11:20:00.000Z`,
      source: "macos",
      eventType: "idle_start",
      appName: "Cursor",
      appBundleId: "com.todesktop.230313mzl4w4u92",
      windowTitle: "graph.js - swiper",
      documentPath: "/Users/bm/Developer/swiper/src/graph.js",
    }),
    makeEvent({
      timestamp: `${day}T11:45:00.000Z`,
      source: "macos",
      eventType: "idle_end",
      appName: "Cursor",
      appBundleId: "com.todesktop.230313mzl4w4u92",
      windowTitle: "graph.js - swiper",
      documentPath: "/Users/bm/Developer/swiper/src/graph.js",
    }),
    makeEvent({
      timestamp: `${day}T11:46:00.000Z`,
      source: "editor",
      eventType: "document_focus",
      appName: "Cursor",
      appBundleId: "com.todesktop.230313mzl4w4u92",
      windowTitle: "graph.js - swiper",
      documentPath: "/Users/bm/Developer/swiper/src/graph.js",
    }),
  ]);

  const query = new GraphQuery(dbPath);
  const timeline = query.dailyTimeline(day);
  const entitySessions = query.sessionsForEntity("graph.js");

  assert.equal(timeline.length, 3);
  assert.equal(entitySessions.length, 3);
});

test("browser gaps still produce usable sessions from app and window metadata", (t) => {
  const dbPath = withTempDb(t);
  const engine = new SwiperEngine({ dbPath, collector: { collect: async () => [] } });
  engine.init();

  const day = "2026-04-05";
  engine.ingestEvents([
    makeEvent({
      timestamp: `${day}T12:00:00.000Z`,
      source: "macos",
      eventType: "app_focus",
      appName: "Safari",
      appBundleId: "com.apple.Safari",
      windowTitle: "Interesting article about supply chains",
    }),
  ]);

  const query = new GraphQuery(dbPath);
  const timeline = query.dailyTimeline(day);
  assert.equal(timeline.length, 1);
  assert.equal(timeline[0].taskLabel, "Interesting article about supply chains");
});

test("topics require repeated evidence or a hostname and do not turn arbitrary title pairs into people", (t) => {
  const dbPath = withTempDb(t);
  const engine = new SwiperEngine({ dbPath, collector: { collect: async () => [] } });
  engine.init();

  const day = "2026-04-05";
  engine.ingestEvents([
    makeEvent({
      timestamp: `${day}T13:00:00.000Z`,
      source: "browser",
      eventType: "browser_navigation",
      appName: "Safari",
      appBundleId: "com.apple.Safari",
      windowTitle: "This Determines My Future Relationship",
      url: "https://www.youtube.com/watch?v=123",
    }),
    makeEvent({
      timestamp: `${day}T13:00:05.000Z`,
      source: "browser",
      eventType: "window_focus",
      appName: "Safari",
      appBundleId: "com.apple.Safari",
      windowTitle: "This Determines My Future Relationship",
      url: "https://www.youtube.com/watch?v=123",
    }),
  ]);

  const query = new GraphQuery(dbPath);
  const summary = query.dailySummary(day);
  const youtubeSessions = query.sessionsForEntity("youtube.com");

  assert.equal(youtubeSessions.length, 1);
  assert.ok(summary.some((item) => item.node_type === "Website" && item.label === "youtube.com"));
  assert.ok(!summary.some((item) => item.node_type === "Person" && item.label === "This Determines"));
  assert.ok(!summary.some((item) => item.node_type === "Person" && item.label === "My Future"));
});

test("behavior report emphasizes app usage, domains, and app switches", (t) => {
  const dbPath = withTempDb(t);
  const engine = new SwiperEngine({ dbPath, collector: { collect: async () => [] } });
  engine.init();

  const day = "2026-04-05";
  engine.ingestEvents([
    makeEvent({
      timestamp: `${day}T09:00:00.000Z`,
      source: "macos",
      eventType: "app_focus",
      appName: "Codex",
      appBundleId: "app.codex",
      windowTitle: "Codex",
    }),
    makeEvent({
      timestamp: `${day}T09:00:05.000Z`,
      source: "browser",
      eventType: "browser_navigation",
      appName: "Safari",
      appBundleId: "com.apple.Safari",
      windowTitle: "ChatGPT",
      url: "https://chatgpt.com/",
    }),
    makeEvent({
      timestamp: `${day}T09:00:15.000Z`,
      source: "browser",
      eventType: "browser_navigation",
      appName: "Safari",
      appBundleId: "com.apple.Safari",
      windowTitle: "ChatGPT pricing",
      url: "https://chatgpt.com/pricing",
    }),
    makeEvent({
      timestamp: `${day}T09:00:25.000Z`,
      source: "editor",
      eventType: "document_focus",
      appName: "Cursor",
      appBundleId: "com.cursor",
      windowTitle: "index.js - swiper",
      documentPath: "/Users/bm/Developer/swiper/index.js",
    }),
  ]);

  const query = new GraphQuery(dbPath);
  const report = query.dailyBehaviorReport(day);

  assert.equal(report.appTimeline.length, 3);
  assert.equal(report.appUsage[0].app_name, "Safari");
  assert.equal(report.appUsage[0].total_duration_ms, 20000);
  assert.ok(report.domainUsage.some((entry) => entry.domain === "chatgpt.com"));
  assert.deepEqual(
    report.appSwitches.map((entry) => [entry.fromApp, entry.toApp]),
    [
      ["Codex", "Safari"],
      ["Safari", "Cursor"],
    ],
  );
});

test("behavior timeline closes the previous app at the next observed transition and collapses duplicates", (t) => {
  const dbPath = withTempDb(t);
  const engine = new SwiperEngine({ dbPath, collector: { collect: async () => [] } });
  engine.init();

  const day = "2026-04-05";
  engine.ingestEvents([
    makeEvent({
      timestamp: `${day}T09:00:00.000Z`,
      source: "macos",
      eventType: "app_focus",
      appName: "Codex",
      appBundleId: "app.codex",
      windowTitle: "Codex",
    }),
    makeEvent({
      timestamp: `${day}T09:00:00.000Z`,
      source: "macos",
      eventType: "window_focus",
      appName: "Codex",
      appBundleId: "app.codex",
      windowTitle: "Codex",
    }),
    makeEvent({
      timestamp: `${day}T09:00:10.000Z`,
      source: "macos",
      eventType: "app_focus",
      appName: "Discord",
      appBundleId: "app.discord",
      windowTitle: "Discord",
    }),
    makeEvent({
      timestamp: `${day}T09:00:20.000Z`,
      source: "macos",
      eventType: "app_focus",
      appName: "Safari",
      appBundleId: "com.apple.Safari",
      windowTitle: "Example",
    }),
  ]);

  const report = new GraphQuery(dbPath).dailyBehaviorReport(day);

  assert.equal(report.appTimeline.length, 3);
  assert.deepEqual(
    report.appTimeline.map((entry) => [entry.appName, entry.durationMs]),
    [
      ["Codex", 10000],
      ["Discord", 10000],
      ["Safari", 0],
    ],
  );
});
