import fs from "node:fs";
import path from "node:path";

export function createRuntimePaths(dbPath) {
  const dbName = path.basename(dbPath, path.extname(dbPath));
  const baseDir = path.resolve(path.dirname(dbPath));
  const runtimeDir = path.join(baseDir, "runtime");
  const dailyDir = path.join(baseDir, "daily");
  const sessionsDir = path.join(baseDir, "sessions");

  return {
    baseDir,
    runtimeDir,
    dailyDir,
    sessionsDir,
    statusPath: path.join(runtimeDir, `${dbName}-status.json`),
  };
}

export function ensureRuntimeDirectories(paths) {
  fs.mkdirSync(paths.runtimeDir, { recursive: true });
  fs.mkdirSync(paths.dailyDir, { recursive: true });
  fs.mkdirSync(paths.sessionsDir, { recursive: true });
}

export function writeJsonFile(filePath, value) {
  fs.writeFileSync(filePath, JSON.stringify(value, null, 2));
}

export function writeTrackerStatus(statusPath, value) {
  writeJsonFile(statusPath, value);
}

export function clearTrackerStatus(statusPath) {
  if (fs.existsSync(statusPath)) {
    fs.unlinkSync(statusPath);
  }
}
