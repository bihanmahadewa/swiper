import fs from "node:fs";
import path from "node:path";
import { MacOSCollector, runDoctor } from "./collectors/macos.js";
import { exportDailyJson } from "./exports.js";
import { SwiperEngine } from "./pipeline.js";
import { GraphQuery } from "./query.js";
import { clearTrackerStatus, createRuntimePaths, ensureRuntimeDirectories, writeTrackerStatus } from "./runtime.js";
import { SwiperStore } from "./store.js";

async function main() {
  const [, , command, ...args] = process.argv;

  switch (command) {
    case "init-db":
      return handleInitDb(args);
    case "run-once":
      return handleRunOnce(args);
    case "watch":
      return handleWatch(args);
    case "daemon":
      return handleDaemon(args);
    case "doctor":
      return handleDoctor();
    case "report-day":
      return handleReportDay(args);
    case "ingest-json":
      return handleIngestJson(args);
    default:
      printHelp();
      process.exitCode = 1;
  }
}

function handleInitDb(args) {
  const dbPath = resolveDbPath(args[0]);
  ensureParentDirectory(dbPath);
  const store = new SwiperStore(dbPath);
  store.init();
  console.log(`Initialized ${dbPath}`);
}

async function handleRunOnce(args) {
  const dbPath = resolveDbPath(args[0]);
  const engine = createLiveEngine(dbPath);
  const events = await engine.collectOnce();
  console.log(JSON.stringify({ storedEvents: events.length, dbPath }, null, 2));
}

async function handleWatch(args) {
  const dbPath = resolveDbPath(args[0]);
  const options = parseWatchOptions(args.slice(1));
  await runTracker({
    dbPath,
    options,
    mode: "watch",
  });
}

async function handleDaemon(args) {
  const dbPath = resolveDbPath(args[0]);
  const options = parseWatchOptions(args.slice(1));
  await runTracker({
    dbPath,
    options,
    mode: "daemon",
  });
}

function handleReportDay(args) {
  const dbPath = resolveDbPath(args[0]);
  const day = args[1] ?? new Date().toISOString().slice(0, 10);
  const query = new GraphQuery(dbPath);
  const report = query.dailyBehaviorReport(day);
  console.log(JSON.stringify(report, null, 2));
}

function handleDoctor() {
  console.log(JSON.stringify(runDoctor(), null, 2));
}

function handleIngestJson(args) {
  const dbPath = resolveDbPath(args[0]);
  const filePath = args[1];
  if (!filePath) {
    throw new Error("Expected JSON file path");
  }

  const absoluteFile = path.resolve(filePath);
  const engine = new SwiperEngine({
    dbPath,
    collector: { collect: async () => [] },
  });
  engine.init();
  const events = JSON.parse(fs.readFileSync(absoluteFile, "utf8"));
  engine.ingestEvents(events);
  console.log(JSON.stringify({ ingestedEvents: events.length, dbPath, filePath: absoluteFile }, null, 2));
}

function ensureParentDirectory(dbPath) {
  fs.mkdirSync(path.dirname(dbPath), { recursive: true });
}

function createLiveEngine(dbPath) {
  ensureParentDirectory(dbPath);
  const engine = new SwiperEngine({
    dbPath,
    collector: new MacOSCollector(),
  });
  engine.init();
  return engine;
}

async function runTracker({ dbPath, options, mode }) {
  const engine = createLiveEngine(dbPath);
  const stopAt = options.durationMs ? Date.now() + options.durationMs : null;
  const startedAt = new Date().toISOString();
  const runtimePaths = createRuntimePaths(dbPath);
  ensureRuntimeDirectories(runtimePaths);

  let ticks = 0;
  let totalEvents = 0;
  let stopping = false;
  let timer = null;
  let lastTickAt = null;

  const updateStatus = (state) => {
    const reportDay = new Date().toISOString().slice(0, 10);
    writeTrackerStatus(runtimePaths.statusPath, {
      state,
      mode,
      dbPath,
      intervalMs: options.intervalMs,
      durationMs: options.durationMs,
      startedAt,
      lastTickAt,
      ticks,
      totalEvents,
      trackedDurationMs: Date.now() - new Date(startedAt).getTime(),
      reportDay,
      statusPath: runtimePaths.statusPath,
      dailyDir: runtimePaths.dailyDir,
      pid: process.pid,
    });
  };

  const shutdown = () => {
    if (stopping) {
      return;
    }

    stopping = true;
    if (timer) {
      clearTimeout(timer);
    }

    updateStatus("stopped");

    if (mode === "watch") {
      console.log(
        JSON.stringify(
          {
            status: "stopped",
            dbPath,
            ticks,
            totalEvents,
          },
          null,
          2,
        ),
      );
      clearTrackerStatus(runtimePaths.statusPath);
    }
  };

  process.on("SIGINT", shutdown);
  process.on("SIGTERM", shutdown);

  updateStatus("watching");

  if (mode === "watch") {
    console.log(
      JSON.stringify(
        {
          status: "watching",
          dbPath,
          intervalMs: options.intervalMs,
          durationMs: options.durationMs,
        },
        null,
        2,
      ),
    );
  }

  const tick = async () => {
    if (stopping) {
      return;
    }

    if (stopAt && Date.now() >= stopAt) {
      shutdown();
      return;
    }

    const events = await engine.collectOnce();
    ticks += 1;
    totalEvents += events.length;
    lastTickAt = new Date().toISOString();

    const day = new Date().toISOString().slice(0, 10);
    const report = new GraphQuery(dbPath).dailyBehaviorReport(day);
    const exportPath = exportDailyJson({ dbPath, day, report });

    updateStatus("watching");

    if (mode === "watch") {
      console.log(
        JSON.stringify(
          {
            status: "tick",
            tick: ticks,
            timestamp: lastTickAt,
            storedEvents: events.length,
            totalEvents,
            exportPath,
          },
          null,
          2,
        ),
      );
    }

    if (stopAt && Date.now() >= stopAt) {
      shutdown();
      return;
    }

    timer = setTimeout(() => {
      tick().catch((error) => {
        updateStatus("error");
        console.error(error.stack || error.message);
        process.exitCode = 1;
      });
    }, options.intervalMs);
  };

  await tick();
}

function resolveDbPath(value) {
  return path.resolve(value ?? "./data/swiper.db");
}

function parseWatchOptions(args) {
  const options = {
    intervalMs: 2_000,
    durationMs: null,
  };

  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    if (arg === "--interval" && args[index + 1]) {
      options.intervalMs = parseDurationToMs(args[index + 1]);
      index += 1;
      continue;
    }

    if (arg === "--duration" && args[index + 1]) {
      options.durationMs = parseDurationToMs(args[index + 1]);
      index += 1;
    }
  }

  return options;
}

function parseDurationToMs(value) {
  const match = String(value).trim().match(/^(\d+)(ms|s|m|h)?$/);
  if (!match) {
    throw new Error(`Invalid duration: ${value}`);
  }

  const amount = Number(match[1]);
  const unit = match[2] ?? "ms";
  switch (unit) {
    case "ms":
      return amount;
    case "s":
      return amount * 1_000;
    case "m":
      return amount * 60_000;
    case "h":
      return amount * 3_600_000;
    default:
      throw new Error(`Unsupported duration unit: ${unit}`);
  }
}

function printHelp() {
  console.log(`Usage:
  node src/cli.js init-db [dbPath]
  node src/cli.js run-once [dbPath]
  node src/cli.js watch [dbPath] [--interval 2s] [--duration 5m]
  node src/cli.js daemon [dbPath] [--interval 2s]
  node src/cli.js doctor
  node src/cli.js report-day [dbPath] [YYYY-MM-DD]
  node src/cli.js ingest-json [dbPath] [events.json]`);
}

main().catch((error) => {
  console.error(error.stack || error.message);
  process.exitCode = 1;
});
